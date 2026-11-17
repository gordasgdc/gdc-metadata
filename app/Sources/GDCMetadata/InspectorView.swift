import SwiftUI
import AppKit
import AVFoundation

struct InspectorView: View {
    let clip: Clip
    @EnvironmentObject var s: AppState
    @EnvironmentObject var L: Loc
    @State private var open: Set<String> = []
    @State private var thumb: NSImage?

    static let sections: [(id: String, ids: [String])] = [
        ("camera", ["make", "camera_model", "lens", "focal_length", "focal_eq", "focus_distance", "focus_mode"]),
        ("exposure", ["aperture", "iso", "shutter", "ae_mode"]),
        ("color", ["wb_mode", "wb_temp", "tint", "picture_profile"]),
        ("file", ["resolution", "frame_rate", "codec", "timecode", "audio", "date_recorded", "file_size"]),
    ]
    static let inputIDs = ["gamut", "curve"]
    static let containerIDs = ["container_primaries", "container_transfer", "container_matrix"]

    var q: String { s.query.trimmingCharacters(in: .whitespaces).lowercased() }

    func hit(_ f: Field) -> Bool {
        guard !q.isEmpty else { return false }
        return L.t("f." + f.id).lowercased().contains(q) || (f.value ?? "").lowercased().contains(q) || f.id.contains(q)
            || ([f.primary].compactMap { $0 } + f.alternates).contains { $0.label.lowercased().contains(q) || ($0.printed ?? $0.raw.text).lowercased().contains(q) }
    }
    func sectionHit(_ id: String) -> Bool {
        let ids = Self.sections.first { $0.id == id }?.ids ?? []
        let extra = id == "color" ? Self.containerIDs + Self.inputIDs : []
        return (ids + extra).compactMap { clip.field($0) }.contains(where: hit)
    }
    var rawHits: [RawTag] { q.isEmpty ? [] : clip.tags.filter { $0.name.lowercased().contains(q) || $0.group.lowercased().contains(q) || $0.shown.lowercased().contains(q) } }
    func isOpen(_ id: String) -> Bool { open.contains(id) || (!q.isEmpty && (id == "raw" ? !rawHits.isEmpty : sectionHit(id))) }
    func binding(_ id: String) -> Binding<Bool> { Binding(get: { isOpen(id) }, set: { v in if v { open.insert(id) } else { open.remove(id) } }) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    matchBanner
                    keyValues
                    ForEach(Self.sections, id: \.id) { sec in section(sec.id, sec.ids) }
                    motionSection
                    rawSection
                }
                .padding(Theme.pad + 4)
            }
            .onChange(of: s.query) { _, _ in
                if let first = firstHit() { withAnimation { proxy.scrollTo(first, anchor: .center) } }
            }
        }
        .task(id: clip.id) { await loadThumb() }
        .onAppear { open = s.openIDs; if s.expandAll { open = Set(Self.sections.map(\.id) + ["raw", "motion"]) } }
    }

    func reasons(_ f: Field) -> [String] {
        var r: [String] = []
        if L.t("f." + f.id).lowercased().contains(q) || f.id.contains(q) { r.append(L.t("match.name")) }
        if (f.value ?? "").lowercased().contains(q) { r.append(L.t("match.value")) }
        if let s = ([f.primary].compactMap { $0 } + f.alternates).first(where: { $0.label.lowercased().contains(q) || ($0.printed ?? $0.raw.text).lowercased().contains(q) }) { r.append(L.t("match.tag") + " " + s.label) }
        return r
    }
    @ViewBuilder var matchBanner: some View {
        if !q.isEmpty {
            let fs = clip.fields.filter(hit)
            VStack(alignment: .leading, spacing: 4) {
                Text(L.f("match.title", s.query.trimmingCharacters(in: .whitespaces))).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                if fs.isEmpty && rawHits.isEmpty {
                    Text(L.f("match.none", s.filtered(s.query).filter { $0.id != clip.id }.count)).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(fs.prefix(4), id: \.id) { f in
                    Text("\(L.t("f." + f.id)) — \(reasons(f).joined(separator: " · "))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if !rawHits.isEmpty { Text("\(L.t("match.raw")): \(rawHits.count) · \(rawHits.first!.group):\(rawHits.first!.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    func firstHit() -> String? {
        guard !q.isEmpty else { return nil }
        for id in Self.inputIDs { if let f = clip.field(id), hit(f) { return "row-" + id } }
        for sec in Self.sections { for id in sec.ids + (sec.id == "color" ? Self.containerIDs : []) { if let f = clip.field(id), hit(f) { return "row-" + id } } }
        return rawHits.isEmpty ? nil : "raw"
    }

    // MARK: header
    var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                if let t = thumb { Image(nsImage: t).resizable().scaledToFill() }
                else { LinearGradient(colors: [Color(white: 0.16), Color(white: 0.26)], startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: "film").font(.title).foregroundStyle(.tertiary) }
            }.frame(width: 192, height: 108).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline))
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.name).font(.title3.weight(.semibold)).lineLimit(2).textSelection(.enabled)
                Text(clip.dir).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.head).textSelection(.enabled)
                HStack(spacing: 6) { ForEach(clip.readers, id: \.self) { Text($0).font(.caption2).padding(.horizontal, 6).padding(.vertical, 1).background(Theme.hairline.opacity(0.5), in: Capsule()) } }
                if let e = clip.error { Label(e, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.warn) }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: first-look values
    var keyValues: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputBlock
            summaryRow("sum.camera", clip.value("camera_model"))
            summaryRow("sum.lens", lensText, fieldID: "lens", also: ["focal_length"])
            summaryRow("sum.focus", [clip.value("focus_distance"), clip.value("focus_mode")].compactMap { $0 }.joined(separator: " · "), fieldID: "focus_distance", also: ["focus_mode"])
            summaryRow("sum.wb", wbText, fieldID: "wb_mode", also: ["wb_temp"])
            summaryRow("sum.exposure", [clip.value("aperture"), clip.value("shutter"), clip.value("iso")].compactMap { $0 }.joined(separator: " · "))
            summaryRow("sum.profile", clip.value("picture_profile"), fieldID: "picture_profile")
            Text(L.t("profile.preset.note")).font(.caption2).foregroundStyle(.tertiary).padding(.top, 2).fixedSize(horizontal: false, vertical: true)
        }
    }
    /// The two values that decide the input in colour management, each with its own provenance and independent of the other.
    var inputBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L.t("input.title")).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent).textCase(.uppercase)
            ForEach(Self.inputIDs, id: \.self) { fid in
                if let f = clip.field(fid) {
                    FieldRow(clip: clip, field: f, highlighted: hit(f)).id("row-" + fid)
                    inputSource(f)
                }
            }
            confirmControls
            Text(L.t("input.hint")).font(.caption2).foregroundStyle(.tertiary).padding(.top, 2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 8)
    }
    /// Read / inferred / confirmed stay distinct: this line says which one the pair currently is, and lets the user change it (reversibly).
    var confirmControls: some View {
        let p = s.pair(clip)
        return HStack(spacing: 8) {
            PairCell(pair: p, L: L).font(.caption.weight(.semibold))
            Spacer(minLength: 4)
            if p.state == .confirmed { Button(L.t("act.revoke")) { s.revoke([clip.id]) } }
            else { Button(L.t("act.accept")) { s.acceptDetected([clip.id]) }.disabled(!p.complete || p.state == .differ).help(L.t("act.accept.help")) }
            Menu(L.t("confirm.pick")) { ForEach(AppState.knownPairs, id: \.curve) { k in Button("\(k.gamut) / \(k.curve)") { s.acceptManual([clip.id], curve: k.curve, gamut: k.gamut) } } }.fixedSize()
        }.padding(.top, 6)
    }
    @ViewBuilder func inputSource(_ f: Field) -> some View {
        if f.status == "confirmed" {
            Text(L.t("note.user_confirmed")).font(.caption).foregroundStyle(Theme.ok).fixedSize(horizontal: false, vertical: true).padding(.leading, Theme.labelWidth + 6)
        } else if f.status == "sources_differ", let p = f.primary {
            VStack(alignment: .leading, spacing: 1) {
                Text("⚠ \(L.t("note.differs"))").font(.caption).foregroundStyle(Theme.warn)
                Text("\(p.label): \(f.value ?? "")").font(.caption.monospaced())
                ForEach(f.alternates, id: \.self) { a in Text("\(a.label): \(a.printed ?? a.raw.text)").font(.caption.monospaced()) }
            }.padding(.leading, Theme.labelWidth + 6)
        } else if let p = f.primary {
            Text("\(L.t("input.source")): \(p.label)" + (f.note == "cndm_derived" ? " · \(L.t("input.derived"))" : f.status == "computed" ? " · \(L.t("st.computed"))" : "")).font(.caption).foregroundStyle(.secondary).padding(.leading, Theme.labelWidth + 6)
        } else if f.note == "maker_hint", let a = f.alternates.first {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(a.label) · \(a.printed ?? a.raw.text)").font(.caption.monospaced())
                Text(L.t("note.maker_hint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.leading, Theme.labelWidth + 6)
        } else if f.note == "cndm_unmapped", let a = f.alternates.first {
            Text("\(a.label) · \(a.printed ?? a.raw.text) — \(L.t("note.cndm_unmapped"))").font(.caption).foregroundStyle(.secondary).padding(.leading, Theme.labelWidth + 6)
        } else {
            Text(L.t("input.none")).font(.caption).foregroundStyle(.secondary).padding(.leading, Theme.labelWidth + 6)
        }
    }
    var wbText: String? {
        let m = clip.value("wb_mode"), t = clip.value("wb_temp")
        let s = [m, t].compactMap { $0 }.joined(separator: " · "); return s.isEmpty ? nil : s
    }
    var lensText: String? {
        var f = clip.value("focal_length"); if let e = clip.value("focal_eq"), f != nil { f! += " (\(e) " + L.t("eq35") + ")" }
        let s = [clip.value("lens"), f].compactMap { $0 }.joined(separator: " · "); return s.isEmpty ? nil : s
    }
    /// Short provenance line shown under a summary value: where it was read and, when it is a single moment, which one.
    func sourceCaption(_ ids: [String]) -> String? {
        let fs = ids.compactMap { clip.field($0) }
        let found = fs.filter { $0.value != nil && $0.primary != nil }
        if let f = found.first {
            var s = f.primary!.label
            if found.contains(where: { $0.note == "first_frame" }) { s += " · " + L.t("firstframe") }
            return s
        }
        if let n = fs.compactMap({ $0.note }).first(where: { ["sony_no_lens", "sony_no_kelvin"].contains($0) }) { return L.t("note." + n) }
        return nil
    }
    var profileText: String? {
        let p = clip.value("curve") ?? clip.value("picture_profile"); let g = clip.value("gamut")
        let s = [p, g].compactMap { $0 }.joined(separator: " · "); return s.isEmpty ? nil : s
    }
    func summaryRow(_ key: String, _ value: String?, fieldID: String? = nil, also: [String] = []) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L.t(key)).foregroundStyle(.secondary).frame(width: Theme.labelWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                if let v = value, !v.isEmpty { Text(v).font(.system(size: 15, weight: .medium).monospacedDigit()).textSelection(.enabled) }
                else { Text(L.t("st.unavailable")).foregroundStyle(.secondary).italic() }
                if let fid = fieldID, let c = sourceCaption([fid] + also) { Text(c).font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer()
        }.padding(.vertical, 5).overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }

    // MARK: sections
    func sectionSummary(_ id: String) -> String {
        func v(_ x: String) -> String? { clip.value(x) }
        switch id {
        case "file": return [v("resolution"), v("frame_rate"), v("timecode")].compactMap { $0 }.joined(separator: " · ")
        default:
            let ids = (Self.sections.first { $0.id == id }?.ids ?? []) + (id == "color" ? Self.containerIDs : [])
            let fs = ids.compactMap { clip.field($0) }
            let found = fs.filter { $0.value != nil }.count
            let differ = fs.filter { $0.status == "sources_differ" }.count
            return L.f("sec.count", found, fs.count) + (differ > 0 ? " · ⚠ \(differ)" : "")
        }
    }
    func section(_ id: String, _ ids: [String]) -> some View {
        DisclosureGroup(isExpanded: binding(id)) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ids, id: \.self) { fid in if let f = clip.field(fid) { FieldRow(clip: clip, field: f, highlighted: hit(f)).id("row-" + fid) } }
                if id == "color" {
                    Text(L.t("note.container_label")).font(.caption).foregroundStyle(.secondary).padding(.top, 10).padding(.bottom, 2)
                    ForEach(Self.containerIDs, id: \.self) { fid in if let f = clip.field(fid) { FieldRow(clip: clip, field: f, highlighted: hit(f)).id("row-" + fid) } }
                }
            }.padding(.top, 4)
        } label: {
            HStack { Text(L.t("sec." + id)).font(.headline); Spacer()
                if !isOpen(id) { Text(sectionSummary(id).isEmpty ? L.t("st.unavailable") : sectionSummary(id)).font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1) } }
        }
        .padding(.vertical, 8).overlay(alignment: .top) { Divider() }
    }
    var motionHit: Bool { !q.isEmpty && (L.t("sec.motion").lowercased().contains(q) || "gyro gyroflow gcsv telemetry".contains(q)) }
    func stepRow(_ n: Int, _ title: String, _ on: Bool, _ detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Theme.ok : Color.secondary.opacity(0.6)).frame(width: 18)
            Text(title).fontWeight(on ? .medium : .regular).foregroundStyle(on ? .primary : .secondary).frame(width: 150, alignment: .leading)
            if let d = detail { Text(d).font(.callout.monospacedDigit()).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 0)
        }
    }
    func gyroText(_ g: Motion.Gyro) -> String { "\(g.kind) · \(g.samples) \(L.t("mo.samples")) · \(Int(g.rate_hz.rounded())) Hz · \(Int(g.duration_s.rounded())) s · " + URL(fileURLWithPath: g.path).lastPathComponent }
    var motionSection: some View {
        let m = clip.motion
        let lvl = m?.level ?? 0
        let expanded = open.contains("motion") || motionHit
        return DisclosureGroup(isExpanded: Binding(get: { expanded }, set: { v in if v { open.insert("motion") } else { open.remove("motion") } })) {
            VStack(alignment: .leading, spacing: 6) {
                stepRow(1, L.t("mo.detected"), lvl >= 1, lvl >= 1 ? ((m?.embedded.first.map { "\($0.kind) · \($0.evidence)" }) ?? (m?.external.first.map { $0.kind + " · " + URL(fileURLWithPath: $0.path).lastPathComponent }) ?? "") : nil)
                stepRow(2, L.t("mo.confirmed"), lvl >= 2, m?.gyro.map(gyroText) ?? (lvl >= 1 ? L.t("mo.confirmed.no") : nil))
                stepRow(3, L.t("mo.ready"), lvl >= 3, lvl >= 3 ? L.t("mo.ready.yes") : L.t("mo.ready.no"))
                if lvl >= 1 {
                    Label(L.t("mo.unverified"), systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary).padding(.leading, 26)
                }
                if let m = m {
                    if let p = m.project {
                        HStack(alignment: .firstTextBaseline) {
                            Text(L.t("mo.project")).foregroundStyle(.secondary).frame(width: 150 + 26, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(URL(fileURLWithPath: p.path).lastPathComponent).font(.callout.monospaced())
                                Text("\(L.t("mo.sync")) \((p.has_sync ?? false) ? "✓" : "✗") · \(L.t("mo.lens")) \((p.has_lens ?? false) ? "✓" : "✗")").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if lvl >= 2 {
                        HStack {
                            Button(L.t("mo.prepare")) {
                                var urls = [URL(fileURLWithPath: clip.path)]
                                if let g = m.gyro { urls.append(URL(fileURLWithPath: g.path)) }
                                if let p = m.project { urls.append(URL(fileURLWithPath: p.path)) }
                                NSWorkspace.shared.activateFileViewerSelecting(urls); copy(m.project?.path ?? clip.path)
                            }.controlSize(.small)
                            Text(L.t("mo.prepare.hint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.padding(.leading, 26)
                    }
                    ForEach(m.notes.filter { $0 != "gyro_needs_project" }, id: \.self) { n in Text(L.t(n == "none_detected" ? "mo.none" : "mo." + n)).font(.caption).foregroundStyle(.secondary).padding(.leading, 26) }
                }
            }.padding(.top, 6)
        } label: {
            HStack {
                Text(L.t("sec.motion")).font(.headline); Spacer()
                if !expanded { Text(lvl >= 3 ? L.t("mo.ready") : lvl == 2 ? L.t("mo.confirmed") : lvl == 1 ? L.t("mo.detected") : L.t("st.unavailable")).foregroundStyle(lvl >= 2 ? Theme.ok : .secondary) }
            }
        }
        .padding(.vertical, 8).overlay(alignment: .top) { Divider() }
    }
    var rawSection: some View {
        DisclosureGroup(isExpanded: binding("raw")) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach((q.isEmpty ? clip.tags.sorted { ($0.group, $0.name) < ($1.group, $1.name) } : rawHits).prefix(400)) { t in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(t.group).font(.caption.monospaced()).foregroundStyle(Theme.accent).frame(width: 96, alignment: .leading).lineLimit(1)
                        Text(t.name).font(.caption.monospaced()).frame(width: 180, alignment: .leading).lineLimit(1)
                        Text(t.shown).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail).textSelection(.enabled)
                        Spacer(minLength: 0)
                    }.padding(.vertical, 2).contextMenu { Button(L.t("copy")) { copy(t.shown) } }
                }
            }.padding(.top, 4)
        } label: { HStack { Text(L.t("sec.raw")).font(.headline); Spacer(); if !isOpen("raw") { Text("\(clip.tags.count)").foregroundStyle(.secondary).monospacedDigit() } } }
        .padding(.vertical, 8).overlay(alignment: .top) { Divider() }.id("raw")
    }

    func loadThumb() async {
        thumb = nil
        let url = URL(fileURLWithPath: clip.path)
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url)); gen.appliesPreferredTrackTransform = true
        if s.demo, let i = s.clips.firstIndex(where: { $0.id == clip.id }) {
            let candidates = [Bundle.main.url(forResource: "thumb_\(i)", withExtension: "png", subdirectory: nil)?.path, (ProcessInfo.processInfo.environment["GDC_DEV_RES"] ?? "") + "/thumb_\(i).png"].compactMap { $0 }
            for c in candidates { if let im = NSImage(contentsOfFile: c) { thumb = im; return } }
            return
        }
        gen.maximumSize = CGSize(width: 480, height: 270)
        if let r = try? await gen.image(at: CMTime(seconds: 1, preferredTimescale: 600)) { thumb = NSImage(cgImage: r.image, size: .zero) }
    }
}

func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }

struct FieldRow: View {
    let clip: Clip; let field: Field; var highlighted = false
    @EnvironmentObject var s: AppState
    @EnvironmentObject var L: Loc
    @State private var showing = false

    var resolveValue: String? {
        guard let key = AppState.resolveKeyFor[field.id], let v = s.resolveCurrent[clip.path]?[key], !v.isEmpty else { return nil }
        return v
    }
    func digits(_ x: String) -> String { x.filter { $0.isNumber || $0 == "." } }
    var resolveDiffers: Bool {
        guard let r = resolveValue, let v = field.value else { return false }
        return digits(r) != digits(v) && !v.lowercased().contains(r.lowercased())
    }
    var effectiveStatus: String { resolveDiffers ? "resolve_differs" : field.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { showing.toggle() } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(L.t("f." + field.id)).foregroundStyle(.secondary).frame(width: Theme.labelWidth, alignment: .leading)
                    if let v = field.value { Text(v).font(.body.monospacedDigit()).foregroundStyle(.primary) }
                    else { Text(L.t("st.unavailable")).foregroundStyle(.secondary).italic() }
                    Spacer(minLength: 6)
                    badge
                    if field.value != nil { Image(systemName: "info.circle").foregroundStyle(.tertiary).imageScale(.small) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if resolveDiffers, let r = resolveValue, let v = field.value {
                HStack(spacing: 14) {
                    Text("\(L.t("diff.file")): \(v)").font(.caption.monospacedDigit())
                    Text("\(L.t("diff.resolve")): \(r)").font(.caption.monospacedDigit()).foregroundStyle(Theme.accent)
                }.padding(.leading, Theme.labelWidth)
            }
            if field.status == "sources_differ" || field.note == "close_values", let n = field.note, n == "differs" || n == "close_values" {
                Text(L.t("note." + n)).font(.caption).foregroundStyle(.secondary).padding(.leading, Theme.labelWidth)
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(highlighted ? Theme.accent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
        .contextMenu { if let v = field.value { Button(L.t("copy")) { copy(v) } } }
        .popover(isPresented: $showing, arrowEdge: .trailing) { provenance.frame(width: 380).padding(14) }
    }

    @ViewBuilder var badge: some View {
        switch effectiveStatus {
        case "unavailable": EmptyView()
        case "sources_differ", "resolve_differs": chip(L.t("st.differ"), Theme.warn)
        case "computed": chip(L.t("st.computed"), Theme.muted)
        case "confirmed": chip(L.t("st.confirmed"), Theme.ok)
        default:
            if field.primary?.kind == "decoded" { chip(L.t("st.decoded"), Theme.accent) }
            else if field.primary?.kind == "container" { chip(L.t("st.container"), Theme.muted) }
            else if field.note == "close_values" { chip("≈", Theme.muted) }
        }
    }
    func chip(_ t: String, _ c: Color) -> some View { Text(t).font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 2).background(c.opacity(0.18), in: Capsule()).foregroundStyle(c) }

    var provenance: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("f." + field.id)).font(.headline)
            if let v = field.value { HStack { Text(v).font(.title3.monospacedDigit()).textSelection(.enabled); Spacer(); Button(L.t("copy")) { copy(v) } } }
            if let p = field.primary { refView(p, primary: true) } else if let n = field.note { Text(L.t("note." + n)).font(.callout).foregroundStyle(.secondary) } else { Text(L.t("note.no_source_tag")).font(.callout).foregroundStyle(.secondary) }
            if let r = resolveValue { Divider(); VStack(alignment: .leading) { Text(L.t("diff.resolve")).font(.caption).foregroundStyle(.secondary); Text(r).font(.body.monospacedDigit()).foregroundStyle(Theme.accent) } }
            if !field.alternates.isEmpty { Divider(); Text(L.t("detail.alt")).font(.caption).foregroundStyle(.secondary); ForEach(field.alternates, id: \.self) { refView($0, primary: false) } }
            if let n = field.note, ["differs", "close_values", "pair_rule", "container_label", "viewing_metadata", "ul_unmapped", "cndm_derived", "cndm_unmapped", "maker_hint", "user_confirmed", "sony_nrt", "sony_unmapped", "first_frame", "sony_no_lens", "sony_no_kelvin"].contains(n) { Divider(); Text(L.t("note." + n)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
    func refView(_ r: SourceRef, primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(r.label).font(.callout.monospaced()).foregroundStyle(Theme.accent); Spacer(); Text(L.t("src." + r.source)).font(.caption).foregroundStyle(.secondary) }
            HStack { Text("\(L.t("detail.raw")): ").font(.caption).foregroundStyle(.secondary); Text(r.raw.text).font(.caption.monospaced()).textSelection(.enabled)
                if let p = r.printed, p != r.raw.text { Text("→ \(p)").font(.caption).foregroundStyle(.secondary) } }
        }
    }
}
