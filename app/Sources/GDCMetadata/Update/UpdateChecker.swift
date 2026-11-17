import AppKit
import CryptoKit
import Foundation

/// Checks the signed update manifest silently at launch and on request (menu: “Check for Updates…”).
/// A new version is announced in a dialog once per version; “Update Now” hands over to SelfUpdater (never a browser).
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    struct Available: Equatable { let version: String; let changes: String; let url: URL; let sha256: String; let size: Int; let mandatory: Bool }
    @Published private(set) var available: Available?
    @Published private(set) var checking = false
    private let dismissedKey = "GDCMetadata.dismissedUpdateVersion"
    private var loc: Loc { Loc.shared }

    /// Test channel: a manifest on disk or on a local server. It still has to carry a valid signature, so it can never deliver an unsigned package.
    private var feed: (url: URL, overridden: Bool) {
        if let s = UserDefaults.standard.string(forKey: "GDCUpdateFeed"), let u = URL(string: s) { return (u, true) }
        return (AppVersion.feedURL, false)
    }

    struct Manifest: Decodable {
        var version: String?; var appVersion: String?; var changes: String?; var changesI18n: [String: String]?
        var downloadURL: [String: String]; var sha256: String?; var size: Int?; var mandatory: Bool; var signature: String?
        enum CodingKeys: String, CodingKey { case version, changes, mandatory, sha256, size, signature; case appVersion = "app_version"; case downloadURL = "download_url"; case changesI18n = "changes_i18n" }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(String.self, forKey: .version); appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
            changes = try c.decodeIfPresent(String.self, forKey: .changes); changesI18n = try c.decodeIfPresent([String: String].self, forKey: .changesI18n)
            sha256 = try c.decodeIfPresent(String.self, forKey: .sha256); size = try c.decodeIfPresent(Int.self, forKey: .size)
            mandatory = try c.decodeIfPresent(Bool.self, forKey: .mandatory) ?? false; signature = try c.decodeIfPresent(String.self, forKey: .signature)
            if let dict = try? c.decode([String: String].self, forKey: .downloadURL) { downloadURL = dict } else if let s = try? c.decode(String.self, forKey: .downloadURL) { downloadURL = ["mac": s] } else { downloadURL = [:] }
        }
        var effectiveVersion: String { appVersion ?? version ?? "0.0.0" }
    }
    struct CheckError: LocalizedError { let message: String; var errorDescription: String? { message } }

    nonisolated static func canonical(_ v: String, _ url: String, _ sha: String, _ size: Int) -> Data { Data("gdc-metadata-update/1\n\(v)\n\(url)\n\(sha)\n\(size)\n".utf8) }

    /// Provenance checks: valid Ed25519 signature over version + URL + hash + size, HTTPS to the expected hosts (or the feed's own folder on the test channel).
    nonisolated static func verify(_ m: Manifest, feed: URL, overridden: Bool, key: String = AppVersion.manifestKey) throws -> Available {
        func bad(_ k: String) -> CheckError { CheckError(message: Loc.shared.t(k)) }
        guard let urlStr = m.downloadURL["mac"], let url = URL(string: urlStr), let sha = m.sha256, let size = m.size, let sigB64 = m.signature,
              let sig = Data(base64Encoded: sigB64), let pub = Data(base64Encoded: key),
              let pk = try? Curve25519.Signing.PublicKey(rawRepresentation: pub) else { throw bad("upd.err.manifest") }
        guard pk.isValidSignature(sig, for: canonical(m.effectiveVersion, urlStr, sha, size)) else { throw bad("upd.err.signature") }
        let official = url.scheme == "https" && url.host == "github.com" && url.path.hasPrefix("/gordasgdc/gdc-metadata/releases/download/")
        let sameFolder = overridden && url.scheme == feed.scheme && url.host == feed.host && url.deletingLastPathComponent() == feed.deletingLastPathComponent()
        guard official || sameFolder else { throw bad("upd.err.origin") }
        let lang = Loc.shared.lang.rawValue
        return Available(version: m.effectiveVersion, changes: m.changesI18n?[lang] ?? m.changes ?? "", url: url, sha256: sha.lowercased(), size: size, mandatory: m.mandatory)
    }

    func checkAtLaunch() {
        Task {
            switch await fetch() {
            case .failure(let e): DiagnosticLog.write("update", "launch check failed: \(e.localizedDescription)")
            case .success(let a):
                guard let a else { DiagnosticLog.write("update", "up to date (\(AppVersion.current))"); return }
                DiagnosticLog.write("update", "update available: \(a.version)")
                available = a
                #if GDC_TEST_HOOKS
                // Test builds only (never compiled into the public package): headless end-to-end install from the signed test feed.
                if feed.overridden, ProcessInfo.processInfo.environment["GDC_UPDATE_AUTOINSTALL"] == "1" { DiagnosticLog.write("update", "test channel: auto-install \(a.version)"); installNow(); return }
                #endif
                if a.mandatory || UserDefaults.standard.string(forKey: dismissedKey) != a.version { present(a) }
            }
        }
    }

    /// Menu “Check for Updates…”: always answers (new version / you are up to date / could not check).
    func checkManually() {
        guard !checking else { return }
        Task {
            switch await fetch() {
            case .failure(let e):
                DiagnosticLog.write("update", "manual check failed: \(e.localizedDescription)")
                let al = NSAlert(); al.alertStyle = .warning; al.messageText = loc.t("upd.fail.title")
                al.informativeText = e.localizedDescription + "\n\n" + loc.t("upd.fail.hint"); al.addButton(withTitle: "OK"); al.runModal()
            case .success(let a):
                available = a
                if let a { present(a) } else {
                    let al = NSAlert(); al.messageText = loc.t("upd.uptodate"); al.informativeText = loc.f("upd.uptodate.body", AppVersion.detail); al.addButton(withTitle: "OK"); al.runModal()
                }
            }
        }
    }

    func installNow() { if let a = available { Task { await SelfUpdater.downloadAndInstall(a) } } }

    func present(_ a: Available) {
        let al = NSAlert(); al.messageText = loc.f("upd.new.title", a.version)
        al.informativeText = (a.changes.isEmpty ? "" : a.changes + "\n\n") + loc.f("upd.new.body", AppVersion.detail)
        al.addButton(withTitle: loc.t("upd.now")); if !a.mandatory { al.addButton(withTitle: loc.t("upd.later")) }
        if al.runModal() == .alertFirstButtonReturn { installNow() } else if !a.mandatory { UserDefaults.standard.set(a.version, forKey: dismissedKey) }
    }

    private func fetch() async -> Result<Available?, Error> {
        checking = true; defer { checking = false }
        let (feedURL, overridden) = feed
        var request: URLRequest
        if feedURL.isFileURL { request = URLRequest(url: feedURL) } else {
            var c = URLComponents(url: feedURL, resolvingAgainstBaseURL: false)!
            c.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
            request = URLRequest(url: c.url!)
        }
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData; request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                guard (200...299).contains(http.statusCode) else { return .failure(CheckError(message: loc.f("upd.err.status", http.statusCode))) }
                if !overridden, let host = http.url?.host, host != "gordas.dev" { return .failure(CheckError(message: loc.t("upd.err.origin"))) }
            }
            guard let m = try? JSONDecoder().decode(Manifest.self, from: data) else { return .failure(CheckError(message: loc.t("upd.err.manifest"))) }
            let a = try Self.verify(m, feed: feedURL, overridden: overridden)
            return .success(Self.semVerCompare(a.version, AppVersion.current) > 0 ? a : nil)
        } catch { return .failure(error) }
    }

    nonisolated static func semVerCompare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] { var s = s; if s.lowercased().hasPrefix("v") { s.removeFirst() }; return s.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 } }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) { let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0; if x != y { return x > y ? 1 : -1 } }
        return 0
    }
}
