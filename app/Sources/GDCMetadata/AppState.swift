import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var clips: [Clip] = []
    @Published var selection: Clip.ID?
    @Published var query = ""
    var openIDs: Set<String> = []
    @Published var found = 0
    @Published var scanning = false
    @Published var summary = ""
    @Published var rootPath: String?
    @Published var demo = false
    @Published var toast: String?
    @Published var showResolve = false
    @Published var resolveRows: [ResolveRow] = []
    @Published var resolveProject: String?
    @Published var resolveError: String?
    @Published var resolveLoading = false
    /// path -> resolve key -> current value (what Resolve reports)
    @Published var resolveCurrent: [String: [String: String]] = [:]
    @Published var lastApplied = false
    @Published var expandAll = false

    static let resolveKeyFor: [String: String] = ["make": "Camera Manufacturer", "camera_model": "Camera Type", "lens": "Lens Type", "focal_length": "Focal Point (mm)", "iso": "ISO", "wb_temp": "White Point (Kelvin)", "curve": "Gamma Notes", "gamut": "Color Space Notes"]

    var selected: Clip? { clips.first { $0.id == selection } }

    func filtered(_ q: String) -> [Clip] {
        let s = q.trimmingCharacters(in: .whitespaces).lowercased()
        if s.isEmpty { return clips }
        return clips.filter { c in
            c.id == selection || c.name.lowercased().contains(s) || c.fields.contains { ($0.value ?? "").lowercased().contains(s) || $0.id.contains(s) || ([$0.primary].compactMap { $0 } + $0.alternates).contains { $0.label.lowercased().contains(s) || ($0.printed ?? $0.raw.text).lowercased().contains(s) } } || c.tags.contains { $0.name.lowercased().contains(s) || $0.shown.lowercased().contains(s) }
        }
    }

    func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = true; p.allowsMultipleSelection = false
        p.prompt = "OK"
        if p.runModal() == .OK, let u = p.url { Task { await scan(u.path) } }
    }

    func scan(_ path: String) async {
        demo = false; clips = []; selection = nil; scanning = true; found = 0; rootPath = path; summary = ""
        resolveRows = []; resolveCurrent = [:]
        do {
            try await Core.scan(path) { [weak self] line in
                Task { @MainActor in
                    guard let self else { return }
                    switch line.event {
                    case "found": self.found = line.count ?? 0
                    case "clip": if let c = line.clip { self.clips.append(c); if self.selection == nil { self.selection = c.id } }
                    case "done": self.scanning = false; self.summary = "\(line.clips ?? 0)|\(line.errors ?? 0)|\(line.ms ?? 0)"
                    default: break
                    }
                }
            }
        } catch { summary = "0|1|0" }
        scanning = false
    }

    func loadDemo() {
        demo = true; rootPath = "/Demo"
        guard let u = Bundle.main.url(forResource: "demo_clips", withExtension: "ndjson") ?? URL(fileURLWithPath: (ProcessInfo.processInfo.environment["GDC_DEV_RES"] ?? "") + "/demo_clips.ndjson") as URL?,
              let text = try? String(contentsOf: u, encoding: .utf8) else { return }
        let dec = JSONDecoder()
        clips = text.split(separator: "\n").compactMap { try? dec.decode(Clip.self, from: Data($0.utf8)) }
        selection = clips.first?.id
        summary = "\(clips.count)|0|182"
        // canned Resolve state for the demo
        resolveProject = "Demo_Wedding_Reel"
        resolveCurrent = ["/Demo/CAM_A/C0001.mov": ["White Point (Kelvin)": "5700", "Camera Type": "Aurora Cine C1"]]
        resolveRows = demoRows()
    }

    func demoRows() -> [ResolveRow] {
        func rowsFor(_ c: Clip, match: String, folder: String?) -> ResolveRow {
            let cur = resolveCurrent[c.path] ?? [:]
            let fs: [ResolveField] = Self.resolveKeyFor.compactMap { (fid, key) in
                guard let f = c.field(fid), let v = f.value, f.status != "unavailable" else { return nil }
                let n = key == "ISO" || key == "Focal Point (mm)" || key == "White Point (Kelvin)" ? String(v.filter { $0.isNumber || $0 == "." }) : v
                let have = cur[key] ?? ""
                return ResolveField(key: key, new: n, current: have, action: have == n ? "same" : (have.isEmpty ? "write" : "keep"))
            }.sorted { $0.key < $1.key }
            return ResolveRow(path: c.path, match: match, folder: folder, fields: match == "exact" ? fs : [])
        }
        return clips.prefix(6).enumerated().map { i, c in
            if c.name == "A001.mov" { return rowsFor(c, match: "ambiguous", folder: "Master, Selects") }
            if i == 4 { return rowsFor(c, match: "none", folder: nil) }
            return rowsFor(c, match: "exact", folder: "Master")
        }
    }

    // MARK: Resolve
    func loadResolvePlan() async {
        resolveLoading = true; resolveError = nil; lastApplied = false
        defer { resolveLoading = false }
        if demo { resolveRows = demoRows(); return }
        guard let root = rootPath else { return }
        let (code, out) = await Core.run(["resolve-plan", root])
        guard code == 0, let data = out.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { resolveError = "core"; return }
        let reply = await Core.resolve(["action": "plan", "items": arr.map { ["path": $0["path"] as Any, "values": $0["values"] as Any] }])
        if !reply.ok { resolveError = reply.error ?? "resolve_unavailable"; resolveRows = []; return }
        resolveProject = reply.project; resolveRows = reply.results ?? []
        var cur: [String: [String: String]] = [:]
        for r in resolveRows { cur[r.path] = Dictionary(uniqueKeysWithValues: r.fields.map { ($0.key, $0.current) }) }
        resolveCurrent = cur
    }

    func applyResolve() async {
        guard !demo, let root = rootPath else { toast = "Demo"; return }
        resolveLoading = true; defer { resolveLoading = false }
        let (_, out) = await Core.run(["resolve-plan", root])
        guard let data = out.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let reply = await Core.resolve(["action": "apply", "items": arr.map { ["path": $0["path"] as Any, "values": $0["values"] as Any] }])
        if reply.ok { resolveRows = reply.results ?? []; lastApplied = true } else { resolveError = reply.error }
    }

    func saveCSV() async {
        guard let root = rootPath, !demo else { return }
        let sp = NSSavePanel(); sp.nameFieldStringValue = "GDC-Metadata-Resolve.csv"
        if sp.runModal() == .OK, let u = sp.url { _ = await Core.run(["resolve-csv", root, "--out", u.path]); toast = u.lastPathComponent }
    }

    func exportSidecars(share: Bool, chooseDir: Bool) async -> String? {
        guard let root = rootPath, !demo else { return nil }
        var args = ["export", root]
        var dest: URL?
        let rootURL = URL(fileURLWithPath: root)
        let dirForWrite = rootURL.hasDirectoryPath ? root : rootURL.deletingLastPathComponent().path
        if chooseDir || !FileManager.default.isWritableFile(atPath: dirForWrite) {
            let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
            if p.runModal() == .OK, let u = p.url { dest = u } else { return nil }
        }
        if let d = dest { args += ["--out-dir", d.path] }
        if share { args.append("--share") }
        let (_, out) = await Core.run(args)
        let n = out.split(separator: "\n").filter { $0.contains("Written") }.count
        return String(n)
    }
}
