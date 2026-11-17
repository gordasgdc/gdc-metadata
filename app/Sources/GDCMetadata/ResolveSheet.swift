import SwiftUI

struct ResolveSheet: View {
    @EnvironmentObject var s: AppState
    @EnvironmentObject var L: Loc
    @Environment(\.dismiss) var dismiss

    var counts: (Int, Int, Int) { (s.resolveRows.filter { $0.match == "exact" }.count, s.resolveRows.filter { $0.match == "none" }.count, s.resolveRows.filter { $0.match == "ambiguous" }.count) }
    func name(_ p: String) -> String { URL(fileURLWithPath: p).lastPathComponent }
    func dir(_ p: String) -> String { URL(fileURLWithPath: p).deletingLastPathComponent().path }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.t("resolve.send")).font(.title2.weight(.semibold)); Spacer()
                Button(L.t("resolve.refresh")) { Task { await s.loadResolvePlan() } }.disabled(s.resolveLoading)
            }
            if let e = s.resolveError {
                Label(L.t("resolve.err." + e) == "resolve.err." + e ? L.t("resolve.err.resolve_unavailable") : L.t("resolve.err." + e), systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 16) {
                    VStack(alignment: .leading) { Text(L.t("resolve.project")).font(.caption).foregroundStyle(.secondary); Text(s.resolveProject ?? "—").font(.headline) }
                    Divider().frame(height: 28)
                    Text(L.f("resolve.matches", counts.0, counts.1, counts.2)).font(.callout.monospacedDigit())
                    if s.resolveLoading { ProgressView().controlSize(.small) }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) { ForEach(s.resolveRows) { row in rowView(row) } }
                }.frame(minHeight: 260)
                Label(L.t("resolve.only_in_sidecar"), systemImage: "doc.text").font(.caption).foregroundStyle(.secondary)
            }
            Label(L.t("resolve.csv_warn"), systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L.t("resolve.csv")) { Task { await s.saveCSV() } }.disabled(s.demo)
                Spacer()
                Button(L.t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L.t("resolve.apply")) { Task { await s.applyResolve() } }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(s.resolveError != nil || counts.0 == 0 || s.resolveLoading || s.lastApplied)
            }
        }
        .padding(20).frame(minWidth: 640, minHeight: 460)
    }

    func rowView(_ row: ResolveRow) -> some View {
        let w = row.fields.filter { $0.action == "write" || $0.action == "written" }.count
        let k = row.fields.filter { $0.action == "keep" }.count
        let same = row.fields.filter { $0.action == "same" }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: row.match == "exact" ? "checkmark.circle.fill" : row.match == "none" ? "questionmark.circle" : "exclamationmark.triangle.fill")
                    .foregroundStyle(row.match == "exact" ? Theme.ok : Theme.warn).frame(width: 18)
                Text(name(row.path)).font(.body.weight(.medium))
                Text(dir(row.path)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                Spacer(minLength: 8)
                Text(row.match == "exact" ? L.f("resolve.summary", w, k, same) : row.match == "none" ? L.t("resolve.none") : L.t("resolve.ambiguous") + (row.folder.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(row.match == "exact" ? .secondary : Theme.warn).lineLimit(1)
            }.padding(.vertical, 6)
            if row.match == "exact" && !row.fields.isEmpty {
                DisclosureGroup(L.t("resolve.details")) {
                    VStack(spacing: 0) {
                        ForEach(row.fields) { f in
                            HStack {
                                Text(f.key).font(.caption).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                                Text(f.new).font(.caption.monospacedDigit())
                                if !f.current.isEmpty && f.current != f.new { Text("(\(L.t("resolve.value.in")): \(f.current))").font(.caption.monospacedDigit()).foregroundStyle(Theme.accent) }
                                Spacer()
                                Text(L.t("resolve." + f.action)).font(.caption2.weight(.medium)).foregroundStyle(f.action == "write" || f.action == "written" ? Theme.ok : f.action == "failed" ? Theme.warn : .secondary)
                            }.padding(.vertical, 3).overlay(alignment: .bottom) { Divider().opacity(0.4) }
                        }
                    }
                }.font(.caption).padding(.leading, 26).padding(.bottom, 4)
            }
        }.overlay(alignment: .bottom) { Divider() }
    }
}
