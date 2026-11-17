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
                    clipList.frame(minWidth: 300, idealWidth: 380, maxWidth: 560)
                    Group { if let c = s.selected { InspectorView(clip: c) } else { Text(L.t("empty.sel")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) } }
                        .frame(minWidth: 420)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in if let u = url { Task { @MainActor in await s.scan(u.path) } } }
            return true
        }
        .overlay { if targeted { RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8])).padding(6).allowsHitTesting(false) } }
        .toolbar { toolbar }
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
            Table(s.filtered(s.query), selection: $s.selection) {
                TableColumn(L.t("col.clip")) { c in
                    HStack(spacing: 6) {
                        Image(systemName: c.ok ? "film" : "exclamationmark.triangle.fill").foregroundStyle(c.ok ? Theme.muted : Theme.warn).frame(width: 16)
                        Text(c.name).lineLimit(1).truncationMode(.middle)
                    }
                }.width(min: 130, ideal: 170)
                TableColumn(L.t("col.camera")) { c in Text(c.value("camera_model") ?? L.t("st.unavailable")).foregroundStyle(c.value("camera_model") == nil ? .tertiary : .primary).lineLimit(1) }.width(min: 80, ideal: 110)
                TableColumn(L.t("col.tc")) { c in Text(c.value("timecode") ?? "—").mono().foregroundStyle(c.value("timecode") == nil ? .tertiary : .primary) }.width(min: 80, ideal: 96)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            statusBar
        }
    }

    var statusBar: some View {
        HStack(spacing: 8) {
            if s.scanning { ProgressView(value: Double(s.clips.count), total: Double(max(s.found, 1))).frame(width: 90); Text(L.f("scan.progress", s.clips.count, s.found)).font(.caption) }
            else if !s.summary.isEmpty { let p = s.summary.split(separator: "|").compactMap { Int($0) }; if p.count == 3 { Text(L.f("scan.done", p[0], p[1], p[2])).font(.caption) } }
            Spacer()
            Button { s.showResolve = true; Task { await s.loadResolvePlan() } } label: { Label(L.t("resolve.send"), systemImage: "paperplane.fill").font(.caption.weight(.semibold)) }
                .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small).disabled(s.clips.isEmpty)
            if s.demo { Text(L.t("demo.badge")).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.accent.opacity(0.18), in: Capsule()) }
        }
        .padding(.horizontal, Theme.pad).padding(.vertical, 6).foregroundStyle(.secondary)
        .background(Theme.surface).overlay(alignment: .top) { Divider() }
    }

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { s.chooseFolder() } label: { Label(L.t("drop.choose"), systemImage: "folder") }
            Menu {
                Button(L.t("export.sidecar")) { Task { if let n = await s.exportSidecars(share: false, chooseDir: false) { exportMsg = L.f("export.done", Int(n) ?? 0) } } }
                Button(L.t("export.choose")) { Task { if let n = await s.exportSidecars(share: false, chooseDir: true) { exportMsg = L.f("export.done", Int(n) ?? 0) } } }
                Button(L.t("export.share")) { Task { if let n = await s.exportSidecars(share: true, chooseDir: true) { exportMsg = L.f("export.done", Int(n) ?? 0) } } }
            } label: { Label(L.t("export.sidecar"), systemImage: "square.and.arrow.down") }.disabled(s.clips.isEmpty)
            Button { s.showResolve = true; Task { await s.loadResolvePlan() } } label: { HStack(spacing: 4) { Image(systemName: "paperplane"); Text(L.t("resolve.send")) } }.disabled(s.clips.isEmpty).help(L.t("resolve.send"))
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
