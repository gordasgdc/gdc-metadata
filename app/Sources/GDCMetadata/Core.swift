import Foundation

enum CoreError: Error { case missing }

enum Core {
    static var binary: URL? {
        let fm = FileManager.default
        if let e = ProcessInfo.processInfo.environment["GDC_CORE"], fm.isExecutableFile(atPath: e) { return URL(fileURLWithPath: e) }
        if let r = Bundle.main.resourceURL?.appendingPathComponent("gdc-metadata-core"), fm.isExecutableFile(atPath: r.path) { return r }
        let dev = (ProcessInfo.processInfo.environment["GDC_DEV_CORE_DIR"] ?? "") + "/gdc-metadata-core"
        return fm.isExecutableFile(atPath: dev) ? URL(fileURLWithPath: dev) : nil
    }
    static var bridge: URL? {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("resolve_bridge.py"), FileManager.default.fileExists(atPath: r.path) { return r }
        let dev = (ProcessInfo.processInfo.environment["GDC_DEV_BRIDGE"] ?? "")
        return FileManager.default.fileExists(atPath: dev) ? URL(fileURLWithPath: dev) : nil
    }

    /// Streams NDJSON events from `scan`.
    static func scan(_ path: String, onLine: @escaping (ScanLine) -> Void) async throws {
        guard let bin = binary else { throw CoreError.missing }
        let p = Process(); p.executableURL = bin; p.arguments = ["scan", path]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run()
        let dec = JSONDecoder()
        for try await line in pipe.fileHandleForReading.bytes.lines {
            if let d = line.data(using: .utf8), let s = try? dec.decode(ScanLine.self, from: d) { onLine(s) }
        }
        p.waitUntilExit()
    }

    static func run(_ args: [String]) async -> (Int32, String) {
        guard let bin = binary else { return (127, "core missing") }
        return await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process(); p.executableURL = bin; p.arguments = args
                let o = Pipe(); p.standardOutput = o; p.standardError = FileHandle.nullDevice
                do { try p.run() } catch { cont.resume(returning: (126, "\(error)")); return }
                let data = o.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
                cont.resume(returning: (p.terminationStatus, String(data: data, encoding: .utf8) ?? ""))
            }
        }
    }

    static func python() -> URL? {
        for c in ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"] where FileManager.default.isExecutableFile(atPath: c) {
            // /usr/bin/python3 is a shim that prompts for Command Line Tools when absent; only use it when they exist
            if c == "/usr/bin/python3", !FileManager.default.fileExists(atPath: "/Library/Developer/CommandLineTools/usr/bin/python3"),
               !FileManager.default.fileExists(atPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/python3") { continue }
            return URL(fileURLWithPath: c)
        }
        return nil
    }

    static func resolve(_ request: [String: Any]) async -> ResolveReply {
        guard let py = python(), let br = bridge else { return ResolveReply(ok: false, error: "no_python") }
        let body = (try? JSONSerialization.data(withJSONObject: request)) ?? Data()
        return await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process(); p.executableURL = py; p.arguments = [br.path]
                let i = Pipe(), o = Pipe(); p.standardInput = i; p.standardOutput = o; p.standardError = FileHandle.nullDevice
                do { try p.run() } catch { cont.resume(returning: ResolveReply(ok: false, error: "no_python")); return }
                i.fileHandleForWriting.write(body); try? i.fileHandleForWriting.close()
                let data = o.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
                let r = (try? JSONDecoder().decode(ResolveReply.self, from: data)) ?? ResolveReply(ok: false, error: "resolve_unavailable")
                cont.resume(returning: r)
            }
        }
    }
}
