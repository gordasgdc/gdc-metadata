import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var clips: [Clip] = []
    @Published var selection: Set<Clip.ID> = []
    /// Fields as read from the file, kept for every clip whose curve/gamut the user confirmed (confirmation is reversible).
    @Published var confirmedBase: [Clip.ID: [Field]] = [:]
    @Published var busy = false
    @Published var opMessage: String?
    @Published var opErrors: [String] = []
    @Published var query = ""
    var openIDs: Set<String> = []
    @Published var found = 0
    @Published var scanning = false
    @Published var summary = ""
    @Published var roots: [String] = []
    /// Outcome of the latest import batch (clips added, duplicates skipped, files refused with a reason).
    @Published var importInfo: ImportInfo?
    @Published var showImportInfo = false
    struct Rejected: Hashable, Identifiable { var path: String; var reason: String; var id: String { path + reason } }
    struct ImportInfo: Equatable { var imported = 0; var duplicates = 0; var rejected: [Rejected] = [] }
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
    /// Input colour space (separate, explicit action): rows, whether the project uses colour management, confirmation state.
    @Published var inputRows: [ResolveRow] = []
    @Published var inputManaged: Bool?
    @Published var inputApplied = false
    @Published var confirmInput = false
    @Published var expandAll = false

    static let resolveKeyFor: [String: String] = ["make": "Camera Manufacturer", "camera_model": "Camera Type", "lens": "Lens Type", "focal_length": "Focal Point (mm)", "iso": "ISO", "wb_temp": "White Point (Kelvin)", "curve": "Gamma Notes", "gamut": "Color Space Notes"]

    /// The clip shown in the inspector: only when exactly one is selected.
    var selected: Clip? { selection.count == 1 ? clips.first { $0.id == selection.first } : nil }
    /// Exactly what export / send act on: the selected clips, in list order, whatever the filter shows.
    var selectedClips: [Clip] { clips.filter { selection.contains($0.id) } }
    var targetPaths: [String] { selectedClips.map(\.path) }
    func hiddenByFilter(_ q: String) -> Int { let vis = Set(filtered(q).map(\.id)); return selection.filter { !vis.contains($0) }.count }

    // MARK: curve / gamut pairs
    enum PairState { case confirmed, read, inferred, partial, differ, none }
    struct Pair { var curve: String?; var gamut: String?; var state: PairState; var complete: Bool { curve != nil && gamut != nil } }
    static let knownPairs: [(gamut: String, curve: String)] = [
        ("S-Gamut3.Cine", "S-Log3"), ("S-Gamut3", "S-Log3"), ("S-Gamut", "S-Log2"),
        ("Cinema Gamut", "Canon Log 2"), ("Cinema Gamut", "Canon Log 3"),
        ("V-Gamut", "V-Log"), ("Rec.2020", "N-Log")]
    func pair(_ c: Clip) -> Pair {
        let cf = c.field("curve"), gf = c.field("gamut")
        let cv = cf?.value, gv = gf?.value
        if confirmedBase[c.id] != nil { return Pair(curve: cv, gamut: gv, state: .confirmed) }
        if cf?.status == "sources_differ" || gf?.status == "sources_differ" { return Pair(curve: cv, gamut: gv, state: .differ) }
        if cv == nil && gv == nil { return Pair(curve: nil, gamut: nil, state: .none) }
        if cv == nil || gv == nil { return Pair(curve: cv, gamut: gv, state: .partial) }
        let soft = [cf, gf].contains { $0?.status == "computed" || $0?.note == "viewing_metadata" || $0?.note == "maker_hint" }
        return Pair(curve: cv, gamut: gv, state: soft ? .inferred : .read)
    }
    private func setConfirmed(_ i: Int, curve: String, gamut: String) {
        let id = clips[i].id
        if confirmedBase[id] == nil { confirmedBase[id] = clips[i].fields }
        for (fid, v) in [("curve", curve), ("gamut", gamut)] {
            guard let k = clips[i].fields.firstIndex(where: { $0.id == fid }) else { continue }
            var f = clips[i].fields[k]
            if let p = f.primary { f.alternates.insert(p, at: 0) }
            f.value = v; f.status = "confirmed"; f.note = "user_confirmed"
            f.primary = SourceRef(source: "user", group: "", tag: fid, raw: .string(v), printed: nil, kind: "user")
            clips[i].fields[k] = f
        }
    }
    /// Accepts each selected clip's own detected pair. Clips without a complete pair stay as they are; returns how many were skipped.
    @discardableResult func acceptDetected(_ ids: Set<Clip.ID>) -> Int {
        var skipped = 0
        for i in clips.indices where ids.contains(clips[i].id) {
            let p = pair(clips[i])
            if p.state == .confirmed { continue }
            if let c = p.curve, let g = p.gamut, p.state != .differ { setConfirmed(i, curve: c, gamut: g) } else { skipped += 1 }
        }
        return skipped
    }
    func acceptManual(_ ids: Set<Clip.ID>, curve: String, gamut: String) {
        for i in clips.indices where ids.contains(clips[i].id) { setConfirmed(i, curve: curve, gamut: gamut) }
    }
    func revoke(_ ids: Set<Clip.ID>) {
        for i in clips.indices where ids.contains(clips[i].id) {
            if let base = confirmedBase[clips[i].id] { clips[i].fields = base; confirmedBase[clips[i].id] = nil }
        }
    }
    /// Temporary JSON handed to the core so exports carry the confirmed pairs with their provenance.
    func confirmFile() -> String? {
        var m: [String: [String: String]] = [:]
        for c in selectedClips where confirmedBase[c.id] != nil { if let cv = c.value("curve"), let gv = c.value("gamut") { m[c.path] = ["curve": cv, "gamut": gv] } }
        guard !m.isEmpty, let d = try? JSONSerialization.data(withJSONObject: m) else { return nil }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("gdc-confirm-\(UUID().uuidString).json")
        return (try? d.write(to: u)) != nil ? u.path : nil
    }
    func coreArgs(_ cmd: String) -> [String] { [cmd] + targetPaths + (confirmFile().map { ["--confirm", $0] } ?? []) }
    func removeSelected() {
        let ids = selection
        for id in ids { confirmedBase[id] = nil }
        clips.removeAll { ids.contains($0.id) }
        selection = []
        resolveRows = []; resolveCurrent = [:]; inputRows = []
        if clips.isEmpty { clearList() }
        else { let ms = summary.split(separator: "|").compactMap { Int($0) }.last ?? 0; summary = "\(clips.count)|\(clips.filter { !$0.ok }.count)|\(ms)" }
    }

    func filtered(_ q: String) -> [Clip] {
        let s = q.trimmingCharacters(in: .whitespaces).lowercased()
        if s.isEmpty { return clips }
        return clips.filter { c in
            c.name.lowercased().contains(s) || c.fields.contains { ($0.value ?? "").lowercased().contains(s) || $0.id.contains(s) || ([$0.primary].compactMap { $0 } + $0.alternates).contains { $0.label.lowercased().contains(s) || ($0.printed ?? $0.raw.text).lowercased().contains(s) } } || c.tags.contains { $0.name.lowercased().contains(s) || $0.shown.lowercased().contains(s) }
        }
    }

    func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = true; p.allowsMultipleSelection = true
        p.prompt = "OK"
        if p.runModal() == .OK, !p.urls.isEmpty { let paths = p.urls.map(\.path); Task { await scan(paths) } }
    }

    func clearList() {
        clips = []; selection = []; confirmedBase = [:]; opMessage = nil; opErrors = []; roots = []; summary = ""; importInfo = nil; resolveRows = []; resolveCurrent = [:]; found = 0
    }

    /// Adds files and/or folders to the current list (a second batch never replaces the first). Clips with the same name in different folders stay separate (identity = full path).
    func scan(_ path: String) async { await scan([path]) }
    func scan(_ paths: [String]) async {
        if demo { clearList(); demo = false }
        let fresh = paths.filter { !roots.contains($0) }
        roots += fresh
        scanning = true; found = 0; resolveRows = []; resolveCurrent = [:]
        var info = ImportInfo(); let before = clips.count
        var known = Set(clips.map(\.id))
        var errors = 0
        do {
            try await Core.scan(paths) { [weak self] line in
                Task { @MainActor in
                    guard let self else { return }
                    switch line.event {
                    case "found": self.found = line.count ?? 0
                    case "rejected": info.rejected.append(Rejected(path: line.path ?? "", reason: line.reason ?? ""))
                    case "clip": if let c = line.clip {
                        if known.contains(c.id) { info.duplicates += 1 } else { known.insert(c.id); self.clips.append(c); info.imported += 1; if !c.ok { errors += 1 }; if self.selection.isEmpty && self.clips.count == 1 { self.selection = [c.id] } }
                    }
                    case "done": self.summary = "\(self.clips.count)|\(errors)|\(line.ms ?? 0)"
                    default: break
                    }
                }
            }
        } catch { info.rejected.append(Rejected(path: paths.first ?? "", reason: "core_missing")) }
        // let the last streamed events land before publishing the outcome
        try? await Task.sleep(nanoseconds: 150_000_000)
        scanning = false
        if clips.count == before && info.rejected.isEmpty && info.duplicates == 0 { info.imported = 0 }
        importInfo = info
        if !info.rejected.isEmpty { showImportInfo = true }
    }

    func loadDemo(batch: Bool = false) {
        demo = true; roots = ["/Demo"]
        let resName = batch ? "demo_batch" : "demo_clips"
        guard let u = Bundle.main.url(forResource: resName, withExtension: "ndjson") ?? URL(fileURLWithPath: (ProcessInfo.processInfo.environment["GDC_DEV_RES"] ?? "") + "/" + resName + ".ndjson") as URL?,
              let text = try? String(contentsOf: u, encoding: .utf8) else { return }
        let dec = JSONDecoder()
        clips = text.split(separator: "\n").compactMap { try? dec.decode(Clip.self, from: Data($0.utf8)) }
        selection = clips.first.map { [$0.id] } ?? []
        summary = "\(clips.count)|0|182"
        // canned Resolve state for the demo
        resolveProject = "Demo_Wedding_Reel"
        resolveCurrent = ["/Demo/CAM_A/C0001.mov": ["Camera Type": "Aurora Cine C1"], "/Demo/CAM_A/C0002.mov": ["White Point (Kelvin)": "5700"]]
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
        guard !targetPaths.isEmpty else { resolveRows = []; return }
        let (code, out) = await Core.run(coreArgs("resolve-plan"))
        guard code == 0, let data = out.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { resolveError = "core"; return }
        let reply = await Core.resolve(["action": "plan", "items": arr.map { ["path": $0["path"] as Any, "values": $0["values"] as Any] }])
        if !reply.ok { resolveError = reply.error ?? "resolve_unavailable"; resolveRows = []; return }
        resolveProject = reply.project; resolveRows = reply.results ?? []
        var cur: [String: [String: String]] = [:]
        for r in resolveRows { cur[r.path] = Dictionary(uniqueKeysWithValues: r.fields.map { ($0.key, $0.current) }) }
        resolveCurrent = cur
        await loadInputPlan()
    }

    func inputItems() async -> [[String: Any]]? {
        let (code, out) = await Core.run(coreArgs("resolve-plan"))
        guard code == 0, let data = out.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return arr.compactMap { it in (it["input"] as? [String: Any]).map { ["path": it["path"] as Any, "input": $0] } }
    }
    func loadInputPlan() async {
        guard !demo, !targetPaths.isEmpty, let items = await inputItems() else { inputRows = []; return }
        inputApplied = false
        let reply = await Core.resolve(["action": "input_plan", "items": items])
        if reply.ok { inputRows = reply.results ?? []; inputManaged = reply.managed } else { inputRows = []; inputManaged = nil }
    }
    func applyInput() async {
        guard !demo, !targetPaths.isEmpty, let items = await inputItems() else { return }
        resolveLoading = true; defer { resolveLoading = false }
        let reply = await Core.resolve(["action": "input_apply", "confirm": true, "items": items])
        if reply.ok { inputRows = reply.results ?? []; inputManaged = reply.managed; inputApplied = true }
    }

    func applyResolve() async {
        guard !demo, !targetPaths.isEmpty else { toast = "Demo"; return }
        resolveLoading = true; defer { resolveLoading = false }
        let (_, out) = await Core.run(coreArgs("resolve-plan"))
        guard let data = out.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let reply = await Core.resolve(["action": "apply", "items": arr.map { ["path": $0["path"] as Any, "values": $0["values"] as Any] }])
        if reply.ok { resolveRows = reply.results ?? []; lastApplied = true } else { resolveError = reply.error }
    }

    func saveCSV() async {
        guard !targetPaths.isEmpty, !demo else { return }
        let sp = NSSavePanel(); sp.nameFieldStringValue = "GDC-Metadata-Resolve.csv"
        if sp.runModal() == .OK, let u = sp.url { _ = await Core.run(coreArgs("resolve-csv") + ["--out", u.path]); toast = u.lastPathComponent }
    }

    /// Writes one sidecar per SELECTED clip. Returns (written, per-clip problems); nil = cancelled.
    func exportSidecars(share: Bool, chooseDir: Bool) async -> (Int, [String])? {
        guard !targetPaths.isEmpty, !demo else { return nil }
        var args = coreArgs("export")
        var dest: URL?
        let allWritable = Set(selectedClips.map(\.dir)).allSatisfy { FileManager.default.isWritableFile(atPath: $0) }
        if chooseDir || !allWritable {
            let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
            if p.runModal() == .OK, let u = p.url { dest = u } else { return nil }
        }
        if let d = dest { args += ["--out-dir", d.path] }
        if share { args.append("--share") }
        busy = true; defer { busy = false }
        let (_, out) = await Core.run(args)
        var ok = 0; var bad: [String] = []
        for line in out.split(separator: "\n") {
            guard let d = line.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let r = o["result"] as? String else { continue }
            let name = URL(fileURLWithPath: (o["clip"] as? String) ?? "").lastPathComponent
            if r.hasPrefix("Written") { ok += 1 } else { bad.append("\(name): \(r.hasPrefix("RefusedForeign") ? "foreign" : "error")") }
        }
        return (ok, bad)
    }
}
