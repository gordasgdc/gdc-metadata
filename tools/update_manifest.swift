// Update-manifest tooling (CryptoKit Ed25519).
//   swift tools/update_manifest.swift keygen <seed-file>
//   swift tools/update_manifest.swift sign <seed-file> <dmg> <version> <download-url> <changes-en> <changes-ro> <changes-es> <out.json> [mandatory]
// The private seed never goes into a repository; the public key is compiled into the app (UpdateKey.swift).
import CryptoKit
import Foundation
let a = CommandLine.arguments
func canonical(_ v: String, _ url: String, _ sha: String, _ size: Int) -> Data { Data("gdc-metadata-update/1\n\(v)\n\(url)\n\(sha)\n\(size)\n".utf8) }
switch a.dropFirst().first {
case "keygen":
    let k = Curve25519.Signing.PrivateKey()
    try k.rawRepresentation.base64EncodedString().write(toFile: a[2], atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: a[2])
    print(k.publicKey.rawRepresentation.base64EncodedString())
case "sign":
    let seed = Data(base64Encoded: try String(contentsOfFile: a[2], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    let dmg = try Data(contentsOf: URL(fileURLWithPath: a[3]))
    let sha = SHA256.hash(data: dmg).map { String(format: "%02x", $0) }.joined()
    let sig = try key.signature(for: canonical(a[4], a[5], sha, dmg.count)).base64EncodedString()
    let m: [String: Any] = ["version": a[4], "app_version": a[4], "download_url": ["mac": a[5]], "sha256": sha, "size": dmg.count,
        "changes": a[6], "changes_i18n": ["en": a[6], "ro": a[7], "es": a[8]], "mandatory": a.count > 10 && a[10] == "mandatory", "signature": sig]
    try JSONSerialization.data(withJSONObject: m, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: a[9]))
    print("signed \(a[4]) sha256=\(sha)")
default: print("usage: keygen | sign"); exit(2)
}
