// Renders site/logo.svg into app/Resources/GDCMetadata.icns (macOS icon grid: artwork 824/1024 centred on a transparent canvas).
// Usage: swift tools/make_icon.swift <logo.svg> <out.icns>
import AppKit
let a = CommandLine.arguments
guard a.count == 3, let svg = NSImage(contentsOfFile: a[1]) else { print("cannot read svg"); exit(1) }
let fm = FileManager.default
let set = NSTemporaryDirectory() + "GDCMetadata.iconset"
try? fm.removeItem(atPath: set); try! fm.createDirectory(atPath: set, withIntermediateDirectories: true)
func png(_ px: Int, _ name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let s = CGFloat(px), art = s * 824 / 1024, o = (s - art) / 2
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.30); sh.shadowBlurRadius = s * 0.012; sh.shadowOffset = NSSize(width: 0, height: -s * 0.008); sh.set()
    svg.draw(in: NSRect(x: o, y: o, width: art, height: art), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(set)/\(name).png"))
}
for (px, n) in [(16,"icon_16x16"),(32,"icon_16x16@2x"),(32,"icon_32x32"),(64,"icon_32x32@2x"),(128,"icon_128x128"),(256,"icon_128x128@2x"),(256,"icon_256x256"),(512,"icon_256x256@2x"),(512,"icon_512x512"),(1024,"icon_512x512@2x")] { png(px, n) }
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); p.arguments = ["-c", "icns", set, "-o", a[2]]; try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "ok \(a[2])" : "iconutil failed")
