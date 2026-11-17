import Foundation

struct SourceRef: Codable, Hashable {
    var source: String; var group: String; var tag: String
    var raw: JSONValue; var printed: String?; var kind: String
    var label: String { group.isEmpty ? tag : "\(group):\(tag)" }
}
struct Field: Codable, Identifiable, Hashable {
    var id: String; var section: String; var value: String?
    var status: String; var primary: SourceRef?; var alternates: [SourceRef]; var note: String?
}
struct RawTag: Codable, Hashable, Identifiable {
    var group: String; var name: String; var raw: JSONValue; var printed: String?
    var id: String { group + ":" + name }
    var shown: String { printed ?? raw.text }
}
struct Motion: Codable, Hashable {
    struct Embedded: Codable, Hashable { var kind: String; var evidence: String; var confidence: String }
    struct External: Codable, Hashable { var path: String; var kind: String }
    struct Project: Codable, Hashable { var path: String; var valid_json: Bool; var has_videofile: Bool; var has_sync: Bool?; var has_lens: Bool?; var keys: [String] }
    struct Gyro: Codable, Hashable { var path: String; var kind: String; var samples: Int; var rate_hz: Double; var duration_s: Double; var vendor: String }
    var embedded: [Embedded]; var external: [External]; var project: Project?; var gyro: Gyro?; var ready: Bool; var notes: [String]
    var level: Int { ready ? 3 : gyro != nil ? 2 : detected ? 1 : 0 }
    var detected: Bool { !embedded.isEmpty || !external.isEmpty || project != nil }
}
struct Clip: Codable, Identifiable, Hashable {
    var path: String; var dir: String; var name: String; var ext: String
    var size: UInt64; var ok: Bool; var error: String?
    var fields: [Field]; var tags: [RawTag]; var readers: [String]; var motion: Motion?
    var id: String { path }
    func field(_ id: String) -> Field? { fields.first { $0.id == id } }
    func value(_ id: String) -> String? { field(id)?.value }
}

enum JSONValue: Codable, Hashable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { self = .null }
    }
    func encode(to e: Encoder) throws {
        var c = e.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s); case .number(let n): try c.encode(n); case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a); case .object(let o): try c.encode(o); case .null: try c.encodeNil()
        }
    }
    var text: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .array(let a): return a.map(\.text).joined(separator: " ")
        case .object: return "{…}"
        case .null: return ""
        }
    }
}

struct ScanLine: Decodable { var event: String; var count: Int?; var clip: Clip?; var clips: Int?; var errors: Int?; var ms: Int?; var path: String?; var reason: String? }

// Resolve bridge payloads
struct ResolveField: Codable, Hashable, Identifiable { var key: String; var new: String; var current: String; var action: String; var id: String { key } }
struct ResolveRow: Codable, Hashable, Identifiable { var path: String; var match: String; var folder: String?; var fields: [ResolveField]; var id: String { path } }
struct ResolveReply: Codable { var ok: Bool; var error: String?; var detail: String?; var project: String?; var version: String?; var clips: Int?; var results: [ResolveRow]? }
