import SwiftUI
import AVFoundation
import AppKit

/// Frame provider shared by the table rows, the inspector preview and the enlarged view. One decoded frame per (file, pixel size), cached.
/// The same AVAssetImageGenerator mechanism as before; only the requested size changes (rows 160 px, inspector 720 px, enlarged 1920 px).
@MainActor final class ThumbStore {
    static let shared = ThumbStore()
    private let cache = NSCache<NSString, NSImage>()
    init() { cache.countLimit = 120 }

    func image(path: String, demoIndex: Int?, maxPixel: CGFloat) async -> NSImage? {
        let key = "\(path)|\(Int(maxPixel))" as NSString
        if let c = cache.object(forKey: key) { return c }
        var img: NSImage?
        if let i = demoIndex {
            let cands = [Bundle.main.url(forResource: "thumb_\(i)", withExtension: "png")?.path, (ProcessInfo.processInfo.environment["GDC_DEV_RES"] ?? "") + "/thumb_\(i).png"].compactMap { $0 }
            for c in cands { if let im = NSImage(contentsOfFile: c) { img = im; break } }
        } else {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
            for t in [1.0, 0.0] {
                if let r = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)) { img = NSImage(cgImage: r.image, size: .zero); break }
            }
        }
        if let img { cache.setObject(img, forKey: key) }
        return img
    }
}

/// Small frame for a table row. Parameters are explicit: Table cells may be evaluated outside the environment.
struct ThumbView: View {
    let path: String; let id: String; let demoIndex: Int?
    var width: CGFloat = 44; var height: CGFloat = 25; var maxPixel: CGFloat = 160
    @State private var img: NSImage?
    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            if let i = img { Image(nsImage: i).resizable().scaledToFit() } else { Image(systemName: "film").font(.caption2).foregroundStyle(.tertiary) }
        }
        .frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityHidden(true)
        .task(id: id) { img = await ThumbStore.shared.image(path: path, demoIndex: demoIndex, maxPixel: maxPixel) }
    }
}

/// Enlarged static frame, opened on demand from the inspector. Selection, active clip, filter and table position live in AppState / the table and are untouched.
struct PreviewSheet: View {
    @EnvironmentObject var s: AppState
    @EnvironmentObject var L: Loc
    @Environment(\.dismiss) private var dismiss
    let clip: Clip
    @State private var img: NSImage?
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let i = img { Image(nsImage: i).resizable().scaledToFit() } else { ProgressView() }
            }
            HStack(spacing: 12) {
                Text(clip.name).font(.headline).lineLimit(1).truncationMode(.middle)
                Text(clip.value("timecode") ?? "").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                Text(L.t("preview.note")).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                Spacer()
                Button(L.t("close")) { dismiss() }.keyboardShortcut(.cancelAction).accessibilityLabel(L.t("close"))
            }.padding(10).background(Theme.surface)
        }
        .frame(minWidth: 720, idealWidth: 1100, minHeight: 460, idealHeight: 680)
        .task(id: clip.id) { img = await ThumbStore.shared.image(path: clip.path, demoIndex: s.demo ? s.clips.firstIndex { $0.id == clip.id } : nil, maxPixel: 1920) }
    }
}
