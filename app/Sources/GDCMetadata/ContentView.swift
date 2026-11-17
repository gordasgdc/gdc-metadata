import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var s: AppState
    @EnvironmentObject var L: Loc
    @FocusState private var searchFocus: Bool
    @State private var targeted = false
    @State private var exportMsg: String?

    var body: some View {
        Group {
            if s.clips.isEmpty && !s.scanning { dropZone } else {
                HSplitView {
                    clipList.frame(minWidth: 400, idealWidth: 760)
                    Group {
                        if let c = s.selected { InspectorView(clip: c) }
                        else if s.selection.count > 1 { BatchView() }
                        else { Text(L.t("empty.sel")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    }
                        .frame(minWidth: 330, idealWidth: 400, maxWidth: 520)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard !providers.isEmpty else { return false }
            // one gesture can carry many files; collect all of them (they arrive in any order), then import them as a single batch
            let lock = NSLock(); var urls: [URL] = []; let group = DispatchGroup()
            for p in providers {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { url, _ in if let u = url { lock.lock(); urls.append(u); lock.unlock() }; group.leave() }
            }
            group.notify(queue: .main) { let paths = urls.map(\.path).sorted(); Task { @MainActor in await s.scan(paths) } }
            return true
        }
        .overlay { if targeted { RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8])).padding(6).allowsHitTesting(false) } }
        .toolbar { toolbar }
        .sheet(isPresented: $s.showPreview) { if let c = s.selected { PreviewSheet(clip: c).environmentObject(s).environmentObject(L) } }
        .sheet(isPresented: $s.showResolve) { ResolveSheet().environmentObject(s).environmentObject(L) }
        .navigationTitle(L.t("app.title"))
        .alert(exportMsg ?? "", isPresented: Binding(get: { exportMsg != nil }, set: { if !$0 { exportMsg = nil } })) { Button("OK") {} }
    }

    var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.plus").font(.system(size: 44, weight: .light)).foregroundStyle(Theme.accent)
            Text(L.t("drop.title")).font(.title2.weight(.semibold))
            Text(L.t("drop.sub")).foregroundStyle(.secondary)
            Button(L.t("drop.choose")) { s.chooseFolder() }.controlSize(.large).keyboardShortcut("o")
            Text("MOV · MP4 · MXF · BRAW · R3D · CRM").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6])).padding(24))
    }

    var clipList: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                if geo.size.width >= 700 { wideTable } else { narrowTable }
            }
            actionBar
            statusBar
        }
    }
    func demoIdx(_ c: Clip) -> Int? { s.demo ? s.clips.firstIndex { $0.id == c.id } : nil }
    func clipCell(_ c: Clip) -> some View {
        HStack(spacing: 8) {
            ThumbView(path: c.path, id: c.id, demoIndex: demoIdx(c))
            if !c.ok { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn) }
            Text(c.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
        }
    }
    func tcCell(_ c: Clip) -> some View { Text(c.value("timecode") ?? "—").mono().foregroundStyle(c.value("timecode") == nil ? .tertiary : .primary).lineLimit(1).fixedSize() }
    func valueCell(_ v: String?) -> some View { Text(v ?? L.t("st.unavailable")).italic(v == nil).foregroundStyle(v == nil ? .secondary : .primary).lineLimit(1).truncationMode(.tail) }
    /// Wide layout (variant B): every column that matters for comparing clips; the full timecode always fits.
    var wideTable: some View {
        Table(s.filtered(s.query), selection: $s.selection) {
            TableColumn(L.t("col.clip")) { c in clipCell(c) }.width(min: 150, ideal: 200)
            TableColumn(L.t("col.profile")) { c in PairCell(pair: s.pair(c), L: L) }.width(min: 170, ideal: 220)
            TableColumn(L.t("col.camera")) { c in valueCell(c.value("camera_model")) }.width(min: 80, ideal: 110)
            TableColumn(L.t("col.lens")) { c in valueCell(c.value("lens")) }.width(min: 80, ideal: 130)
            TableColumn(L.t("col.wb")) { c in valueCell(c.value("wb_temp") ?? c.value("wb_mode")) }.width(min: 60, ideal: 80)
            TableColumn(L.t("col.exposure")) { c in valueCell([c.value("aperture"), c.value("shutter"), c.value("iso")].compactMap { $0 }.joined(separator: " · ").nilIfEmpty) }.width(min: 120, ideal: 170)
            TableColumn(L.t("col.tc")) { c in tcCell(c) }.width(min: 100, ideal: 104)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
    }
    /// Narrow layout: clip name, gamut/curve pair and the complete timecode stay visible.
    var narrowTable: some View {
        Table(s.filtered(s.query), selection: $s.selection) {
            TableColumn(L.t("col.clip")) { c in clipCell(c) }.width(min: 120, ideal: 150)
            TableColumn(L.t("col.profile")) { c in PairCell(pair: s.pair(c), L: L) }.width(min: 150, ideal: 190)
            TableColumn(L.t("col.tc")) { c in tcCell(c) }.width(min: 100, ideal: 104)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
    }

    var n: Int { s.selection.count }
    var hidden: Int { s.hiddenByFilter(s.query) }
    func exportRun(share: Bool, chooseDir: Bool) { Task {
        if let (ok, bad) = await s.exportSidecars(share: share, chooseDir: chooseDir) { s.opErrors = bad; exportMsg = L.f("export.done", ok) + (bad.isEmpty ? "" : "\n" + L.f("op.errors", bad.count) + ":\n" + bad.joined(separator: "\n")) }
    } }
    var actionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if n == 0 { Label(L.t("sel.none"), systemImage: "cursorarrow.click.2").font(.caption).foregroundStyle(.secondary) }
                else { Text(L.f("sel.count", n, s.clips.count)).font(.caption.weight(.semibold)) }
                if n > 0, hidden > 0 { Label(L.f("sel.hidden", hidden), systemImage: "line.3.horizontal.decrease.circle").font(.caption).foregroundStyle(Theme.warn).lineLimit(2) }
                Spacer()
                if s.busy { ProgressView().controlSize(.small); Text(L.t("op.running")).font(.caption).foregroundStyle(.secondary) }
            }
            HStack(spacing: 8) {
                Button(L.t("act.accept")) { let sk = s.acceptDetected(s.selection); if sk > 0 { exportMsg = L.f("batch.skipped", sk) } }.accessibilityLabel(L.t("act.accept"))
                    .disabled(n == 0).help(L.t("act.accept.help"))
                Button(L.t("act.revoke")) { s.revoke(s.selection) }.disabled(!s.selection.contains { s.confirmedBase[$0] != nil }).accessibilityLabel(L.t("act.revoke"))
                Spacer()
            }
            HStack(spacing: 8) {
                Button(L.t("act.remove")) { s.removeSelected() }.disabled(n == 0).help(L.t("act.remove.help")).accessibilityLabel(L.t("act.remove"))
                Button(L.t("clear.list")) { s.clearList() }.help(L.t("act.clear.help")).accessibilityLabel(L.t("clear.list"))
                Spacer()
            }
            HStack(spacing: 8) {
                Menu {
                    Button(L.t("export.sidecar")) { exportRun(share: false, chooseDir: false) }
                    Button(L.t("export.choose")) { exportRun(share: false, chooseDir: true) }
                    Button(L.t("export.share")) { exportRun(share: true, chooseDir: true) }
                } label: { Label(n == 0 ? L.t("export.sidecar") : n == 1 ? L.t("act.export.1") : L.f("act.export.n", n), systemImage: "square.and.arrow.down") }
                    .disabled(n == 0 || s.busy).fixedSize()
                Button { s.showResolve = true; Task { await s.loadResolvePlan() } } label: { Label(n == 0 ? L.t("resolve.send") : n == 1 ? L.t("act.send.1") : L.f("act.send.n", n), systemImage: "paperplane.fill").font(.callout.weight(.semibold)) }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(n == 0 || s.busy)
                    .accessibilityLabel(n == 0 ? L.t("resolve.send") : n == 1 ? L.t("act.send.1") : L.f("act.send.n", n))
                Spacer()
            }
        }
        .padding(.horizontal, Theme.pad).padding(.vertical, 8)
        .background(Theme.surface).overlay(alignment: .top) { Divider() }
    }

    func importPopover(_ i: AppState.ImportInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.f("import.result", i.imported)).font(.headline)
            if i.duplicates > 0 { Text(L.f("import.dups", i.duplicates)).font(.caption).foregroundStyle(.secondary) }
            if !i.rejected.isEmpty {
                Text(L.t("import.rejected")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.warn)
                ScrollView { VStack(alignment: .leading, spacing: 6) { ForEach(i.rejected) { r in
                    VStack(alignment: .leading, spacing: 1) { Text(URL(fileURLWithPath: r.path).lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                        Text(L.t("import.why." + r.reason)).font(.caption).foregroundStyle(.secondary) }
                } } }.frame(maxHeight: 180)
            }
        }.padding(14).frame(width: 340)
    }

    var statusBar: some View {
        HStack(spacing: 8) {
            if s.scanning { ProgressView(value: Double(s.clips.count), total: Double(max(s.found, 1))).frame(width: 90); Text(L.f("scan.progress", s.clips.count, s.found)).font(.caption) }
            else if !s.summary.isEmpty { let p = s.summary.split(separator: "|").compactMap { Int($0) }; if p.count == 3 { Text(L.f("scan.done", p[0], p[1], p[2])).font(.caption) } }
            if let i = s.importInfo, !s.scanning {
                Button { s.showImportInfo = true } label: {
                    Text(i.rejected.isEmpty ? L.f("import.result", i.imported) : L.f("import.result.rej", i.imported, i.rejected.count)).font(.caption.weight(.semibold)).foregroundStyle(i.rejected.isEmpty ? Theme.ok : Theme.warn)
                }.buttonStyle(.plain)
                .popover(isPresented: $s.showImportInfo, arrowEdge: .top) { importPopover(i) }
            }
            Spacer()
            Text(AppVersion.label).font(.caption).foregroundStyle(.tertiary).help("\(L.t("about.title")): \(AppVersion.detail)")
            if s.demo { Text(L.t("demo.badge")).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.accent.opacity(0.18), in: Capsule()) }
        }
        .padding(.horizontal, Theme.pad).padding(.vertical, 6).foregroundStyle(.secondary)
        .background(Theme.surface).overlay(alignment: .top) { Divider() }
    }

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { s.chooseFolder() } label: { Label(L.t("drop.choose"), systemImage: "folder") }
            Button { L.openGuide() } label: { Label(L.t("help.guide"), systemImage: "questionmark.circle") }.help(L.t("help.guide"))
            Menu {
                ForEach(Lang.allCases) { l in Button { L.langRaw = l.rawValue } label: { if L.langRaw == l.rawValue { Label(l.name, systemImage: "checkmark") } else { Text(l.name) } } }
            } label: { HStack(spacing: 4) { Image(systemName: "globe"); Text(Lang(rawValue: L.langRaw)?.name ?? "English") } }.menuIndicator(.visible).fixedSize()
        }
        ToolbarItem(placement: .automatic) {
            TextField(L.t("search"), text: $s.query).textFieldStyle(.roundedBorder).frame(width: 220).focused($searchFocus)
        }
    }
}


struct PairCell: View {
    let pair: AppState.Pair
    // passed explicitly: Table cells can be re-evaluated outside the environment (crashed with @EnvironmentObject)
    @ObservedObject var L: Loc
    var color: Color { switch pair.state { case .confirmed: return Theme.ok; case .read: return Theme.accent; case .differ, .partial: return Theme.warn; default: return Theme.muted } }
    var icon: String { switch pair.state { case .confirmed: return "checkmark.seal.fill"; case .read: return "eye"; case .inferred: return "wand.and.stars"; case .partial: return "exclamationmark.circle"; case .differ: return "exclamationmark.triangle.fill"; case .none: return "minus.circle" } }
    var key: String { switch pair.state { case .confirmed: return "pair.confirmed"; case .read: return "pair.read"; case .inferred: return "pair.inferred"; case .partial: return "pair.partial"; case .differ: return "pair.differ"; case .none: return "pair.none" } }
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 16)
            if pair.state == .none { Text(L.t("pair.none")).foregroundStyle(.tertiary) }
            else { Text([pair.gamut, pair.curve].map { $0 ?? "—" }.joined(separator: " / ")).lineLimit(1).truncationMode(.tail) }
        }.help(L.t(key))
    }
}

/// Inspector for a multi-selection: each clip keeps its own pair; incomplete or contradictory ones are flagged.
struct BatchView: View {
    @EnvironmentObject var s: AppState
    @EnvironmentObject var L: Loc
    @State private var manual = ""
    var batchSummary: some View {
        let cs = s.selectedClips; let st = cs.map { s.pair($0).state }
        let conf = st.filter { $0 == .confirmed }.count
        let ready = st.filter { $0 == .read || $0 == .inferred }.count
        let none = cs.count - conf - ready
        return VStack(alignment: .leading, spacing: 4) {
            Text(L.t("batch.will")).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent).textCase(.uppercase)
            sumRow("batch.sel", "\(cs.count)")
            sumRow("batch.confirmed", "\(conf)")
            sumRow("batch.toconfirm", "\(ready)")
            sumRow("batch.nopair", "\(none)")
            sumRow("batch.export", "\(cs.count)")
            sumRow("batch.resolve", "\(conf + ready)")
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
    func sumRow(_ k: String, _ v: String) -> some View { HStack { Text(L.t(k)).foregroundStyle(.secondary); Spacer(); Text(v).fontWeight(.semibold).monospacedDigit() } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.f("batch.title", s.selection.count)).font(.title2.weight(.semibold))
            batchSummary
            Text(L.t("batch.help")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L.t("act.accept")) { let sk = s.acceptDetected(s.selection); s.opMessage = sk > 0 ? L.f("batch.skipped", sk) : nil }.buttonStyle(.borderedProminent).tint(Theme.accent)
                Menu(L.t("confirm.pick")) {
                    ForEach(AppState.knownPairs, id: \.curve) { p in Button("\(p.gamut) / \(p.curve)") { s.acceptManual(s.selection, curve: p.curve, gamut: p.gamut) } }
                }.fixedSize()
                Button(L.t("act.revoke")) { s.revoke(s.selection) }.disabled(!s.selection.contains { s.confirmedBase[$0] != nil })
            }
            if let m = s.opMessage { Label(m, systemImage: "info.circle").font(.caption).foregroundStyle(Theme.warn) }
            List(s.selectedClips) { c in
                let p = s.pair(c)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.name).lineLimit(1).truncationMode(.middle)
                        Text(c.dir).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                    }.frame(minWidth: 140, alignment: .leading)
                    Spacer(minLength: 6)
                    PairCell(pair: p, L: L)
                    Text(L.t(p.state == .confirmed ? "pair.confirmed" : p.state == .read ? "pair.read" : p.state == .inferred ? "pair.inferred" : p.state == .partial ? "pair.partial" : p.state == .differ ? "pair.differ" : "pair.none")).font(.caption2).foregroundStyle(.secondary).frame(width: 110, alignment: .trailing)
                }
            }.listStyle(.inset)
        }.padding(Theme.pad + 4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: s.selection) { _, _ in s.opMessage = nil }
    }
}

extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
