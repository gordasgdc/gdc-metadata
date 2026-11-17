import AppKit
import CryptoKit
import Foundation

/// Real update without a browser: downloads the DMG, verifies size + SHA-256 against the signed manifest, mounts it, checks the app inside
/// (bundle ID, announced version, Developer ID team, Gatekeeper), swaps it in place and relaunches after this process exits.
/// The native administrator prompt appears only if the app's folder is not writable.
@MainActor
enum SelfUpdater {
    struct UpdateError: LocalizedError { let message: String; var errorDescription: String? { message } }
    private static var loc: Loc { Loc.shared }

    static func downloadAndInstall(_ a: UpdateChecker.Available) async {
        let progress = UpdateProgressWindow()
        progress.show(loc.f("upd.progress.download", a.version))
        do {
            let dmg = try await download(a)
            progress.update(loc.t("upd.progress.verify"))
            let staged = try await Task.detached { try stage(dmg: dmg, a: a) }.value
            progress.update(loc.t("upd.progress.install"))
            let target = installedLocation()
            try await Task.detached { try replace(target, with: staged) }.value
            DiagnosticLog.write("update", "installed \(a.version) at \(target.path); relaunching")
            progress.update(loc.t("upd.progress.done"))
            relaunchAfterExit(target)
            NSApp.terminate(nil)
        } catch {
            progress.close()
            DiagnosticLog.write("update", "update \(a.version) failed: \(error.localizedDescription)")
            let al = NSAlert(); al.alertStyle = .warning; al.messageText = loc.t("upd.fail.install")
            al.informativeText = error.localizedDescription + "\n\n" + loc.t("upd.fail.unchanged"); al.addButton(withTitle: "OK"); al.runModal()
        }
    }

    private static func download(_ a: UpdateChecker.Available) async throws -> URL {
        let (tmp, response) = try await URLSession.shared.download(from: a.url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError(message: loc.f("upd.err.status", http.statusCode)) }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("GDCMetadata/Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("GDCMetadata-\(a.version).dmg")
        try? FileManager.default.removeItem(at: dest); try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    nonisolated private static func sha256(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    nonisolated private static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self)
        guard p.terminationStatus == 0 else { throw UpdateError(message: "\((tool as NSString).lastPathComponent): \(out.trimmingCharacters(in: .whitespacesAndNewlines))") }
        return out
    }

    nonisolated private static func stage(dmg: URL, a: UpdateChecker.Available) throws -> URL {
        let size = (try FileManager.default.attributesOfItem(atPath: dmg.path)[.size] as? Int) ?? -1
        guard size == a.size, try sha256(of: dmg) == a.sha256 else { throw UpdateError(message: Loc.shared.t("upd.err.hash")) }
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("GDCMetadata-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"]) }
        let apps = (try? FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)) ?? []
        guard let app = apps.first(where: { $0.pathExtension == "app" && (NSDictionary(contentsOf: $0.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String) == AppVersion.bundleID }),
              let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")), let found = info["CFBundleShortVersionString"] as? String
        else { throw UpdateError(message: Loc.shared.t("upd.err.noapp")) }
        guard found == a.version else { throw UpdateError(message: Loc.shared.f("upd.err.version", found, a.version)) }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        let details = try run("/usr/bin/codesign", ["-dvv", app.path])
        guard details.contains("TeamIdentifier=\(AppVersion.teamID)"), details.contains("Authority=Developer ID Application") else { throw UpdateError(message: Loc.shared.t("upd.err.sign")) }
        let gk = (try? run("/usr/sbin/spctl", ["-a", "-vv", "-t", "exec", app.path])) ?? ""
        guard gk.contains("Notarized Developer ID") else { throw UpdateError(message: Loc.shared.t("upd.err.gatekeeper")) }
        let staged = dmg.deletingLastPathComponent().appendingPathComponent("GDC Metadata \(a.version).app")
        try? FileManager.default.removeItem(at: staged)
        try run("/usr/bin/ditto", [app.path, staged.path])
        return staged
    }

    private static func installedLocation() -> URL {
        let current = Bundle.main.bundleURL
        if current.path.contains("/AppTranslocation/") { return URL(fileURLWithPath: "/Applications").appendingPathComponent(AppVersion.appName) }
        return current
    }

    nonisolated private static func replace(_ target: URL, with staged: URL) throws {
        let fm = FileManager.default
        let parent = target.deletingLastPathComponent()
        if fm.isWritableFile(atPath: parent.path) {
            let old = parent.appendingPathComponent(".\(target.lastPathComponent).old")
            try? fm.removeItem(at: old)
            if fm.fileExists(atPath: target.path) { try fm.moveItem(at: target, to: old) }
            do { try fm.moveItem(at: staged, to: target) } catch { if fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: target) }; throw error }
            try? fm.removeItem(at: old); return
        }
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let cmd = "/bin/rm -rf \(q(target.path)).old; if [ -e \(q(target.path)) ]; then /bin/mv \(q(target.path)) \(q(target.path)).old; fi; /usr/bin/ditto \(q(staged.path)) \(q(target.path)) && /bin/rm -rf \(q(target.path)).old || { [ -e \(q(target.path)).old ] && /bin/mv \(q(target.path)).old \(q(target.path)); exit 1; }"
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        try run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
        try? fm.removeItem(at: staged)
    }

    /// Relaunch after this process has exited (an `open` while it still runs would just re-activate the old instance).
    private static func relaunchAfterExit(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"", app.path]
        try? p.run()
    }
}

@MainActor
final class UpdateProgressWindow {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 90), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "GDC Metadata"
        let spinner = NSProgressIndicator(); spinner.style = .spinning; spinner.isIndeterminate = true; spinner.startAnimation(nil)
        label.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [spinner, label]); stack.orientation = .horizontal; stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20); panel.contentView = stack
    }
    func show(_ text: String) { label.stringValue = text; panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func update(_ text: String) { label.stringValue = text }
    func close() { panel.orderOut(nil) }
}
