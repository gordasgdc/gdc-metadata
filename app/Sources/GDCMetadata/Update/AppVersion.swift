import Foundation

/// Version, build and identity are read from the running bundle, so the UI always matches the binary.
enum AppVersion {
    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    static var label: String { "v\(current)" }
    static var detail: String { "\(current) (\(build))" }
    static let bundleID = "dev.gordas.GDCMetadata"
    static let appName = "GDC Metadata.app"
    static let teamID = "8AR6XP8MG7"
    /// Ed25519 public key that verifies update manifests (the private seed is kept outside the repository).
    static let manifestKey = "Tpxpl7bdiS89iQ3XI77E8kC997f2hyVhVQSCyswUvP0="
    static let feedURL = URL(string: "https://gordas.dev/gdc-metadata/update.json")!
}

/// Small diagnostic log (~/Library/Logs/GDC Metadata.log, rotated at ~5 MB). Never records secrets or file contents.
enum DiagnosticLog {
    private static let queue = DispatchQueue(label: "gdc.metadata.log")
    static func write(_ tag: String, _ message: String) {
        queue.async {
            let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs")
            let url = dir.appendingPathComponent("GDC Metadata.log")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int), size > 5_000_000 {
                let old = dir.appendingPathComponent("GDC Metadata.log.1"); try? FileManager.default.removeItem(at: old); try? FileManager.default.moveItem(at: url, to: old)
            }
            let line = "\(ISO8601DateFormatter().string(from: Date())) [\(tag)] \(message)\n"
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() } else { try? line.write(to: url, atomically: true, encoding: .utf8) }
        }
    }
}
