// Renders one language of the GDC Metadata manual to PDF (selectable text, clickable TOC, outline, links).
// usage: swift tools/make_manual.swift <source.json> <ro|en|es> <captures-dir> <out.pdf>
import Foundation
import CoreGraphics
import CoreText
import ImageIO

let A = CommandLine.arguments
guard A.count == 5 else { FileHandle.standardError.write("usage: make_manual <source.json> <lang> <captures-dir> <out.pdf>\n".data(using: .utf8)!); exit(2) }
let lang = A[2], capDir = A[3], outPath = A[4]
let src = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: A[1]))) as! [String: Any]
func tr(_ v: Any?) -> String { ((v as? [String: String])?[lang]) ?? "" }
let version = src["version"] as! String
let blocks = src["blocks"] as! [[String: Any]]

let PW: CGFloat = 595, PH: CGFloat = 842, M: CGFloat = 56, CW = PW - 2 * M
let ink = CGColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1), accent = CGColor(red: 0.69, green: 0.38, blue: 0.09, alpha: 1), grey = CGColor(red: 0.45, green: 0.45, blue: 0.47, alpha: 1)
let linkCol = CGColor(red: 0.10, green: 0.35, blue: 0.70, alpha: 1)
func font(_ size: CGFloat, bold: Bool = false) -> CTFont { CTFontCreateWithName((bold ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString, size, nil) }
func mono(_ size: CGFloat) -> CTFont { CTFontCreateWithName("Menlo-Regular" as CFString, size, nil) }

/// **bold**, `code`, bare https:// URLs (kept as link ranges).
func attr(_ s: String, size: CGFloat, color: CGColor = ink, bold: Bool = false) -> (NSAttributedString, [(NSRange, String)]) {
    let out = NSMutableAttributedString(); var links: [(NSRange, String)] = []
    var isB = false, isC = false; var buf = ""
    func flush() {
        guard !buf.isEmpty else { return }
        let f = isC ? mono(size - 0.8) : font(size, bold: bold || isB)
        let col = isC ? CGColor(red: 0.45, green: 0.22, blue: 0.05, alpha: 1) : color
        let start = out.length
        out.append(NSAttributedString(string: buf, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): f, NSAttributedString.Key(kCTForegroundColorAttributeName as String): col]))
        buf = ""; _ = start
    }
    let chars = Array(s); var i = 0
    while i < chars.count {
        if chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "*" { flush(); isB.toggle(); i += 2; continue }
        if chars[i] == "`" { flush(); isC.toggle(); i += 1; continue }
        buf.append(chars[i]); i += 1
    }
    flush()
    let ns = out.string as NSString
    if let re = try? NSRegularExpression(pattern: "https?://[A-Za-z0-9._~:/?#@!$&*+,;=%-]+[A-Za-z0-9/]") {
        for m in re.matches(in: out.string, range: NSRange(location: 0, length: ns.length)) {
            out.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: linkCol, range: m.range)
            links.append((m.range, ns.substring(with: m.range)))
        }
    }
    var ls: CGFloat = 2.2
    withUnsafeMutablePointer(to: &ls) { p in
        var setting = CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: p)
        let st = CTParagraphStyleCreate(&setting, 1)
        out.addAttribute(NSAttributedString.Key(kCTParagraphStyleAttributeName as String), value: st, range: NSRange(location: 0, length: out.length))
    }
    return (out, links)
}

struct Dest { var name: String; var title: String; var level: Int; var page: Int; var y: CGFloat }

final class Renderer {
    var ctx: CGContext!; var page = 0; var y: CGFloat = 0
    var dests: [Dest] = []; var known: [String: Int]   // pass-1 page numbers
    var tocRects: [(String, CGRect)] = []
    var data = NSMutableData()
    var imagesFound = 0, imagesMissing: [String] = []
    init(known: [String: Int]) { self.known = known }

    func begin(to url: URL?) {
        var box = CGRect(x: 0, y: 0, width: PW, height: PH)
        let consumer: CGDataConsumer = url != nil ? CGDataConsumer(url: url! as CFURL)! : CGDataConsumer(data: data)!
        let info: [CFString: Any] = [kCGPDFContextTitle: "\(tr(src["title"])) — GDC Metadata \(version)", kCGPDFContextAuthor: "Cristi Gordaș · GDC", kCGPDFContextCreator: "GDC Metadata manual generator", kCGPDFContextSubject: tr(src["sub"]), kCGPDFContextKeywords: "GDC Metadata, DaVinci Resolve, metadata, \(lang)"]
        ctx = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)
        newPage()
    }
    func newPage() {
        if page > 0 { footer(); ctx.endPDFPage() }
        page += 1; ctx.beginPDFPage(nil); y = PH - M
    }
    func footer() {
        let (a, _) = attr("\(tr(src["foot"]))", size: 7.5, color: grey)
        draw(a, x: M, top: M - 14, width: CW - 40, links: [])
        let (n, _) = attr("\(page)", size: 8, color: grey)
        draw(n, x: PW - M - 30, top: M - 14, width: 30, links: [], align: .right)
    }
    func height(_ a: NSAttributedString, width: CGFloat) -> CGFloat {
        let fs = CTFramesetterCreateWithAttributedString(a)
        return ceil(CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRange(location: 0, length: 0), nil, CGSize(width: width, height: 10000), nil).height)
    }
    enum Align { case left, right }
    /// Draws `a` with its top at `top` (PDF coords); returns height. Adds link annotations for URL ranges.
    @discardableResult func draw(_ a: NSAttributedString, x: CGFloat, top: CGFloat, width: CGFloat, links: [(NSRange, String)], align: Align = .left) -> CGFloat {
        let h = height(a, width: width)
        let fs = CTFramesetterCreateWithAttributedString(a)
        let rect = CGRect(x: x, y: top - h, width: width, height: h + 2)
        let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
        if align == .right {
            // right-align a short single line
            let line = CTLineCreateWithAttributedString(a); let w = CTLineGetTypographicBounds(line, nil, nil, nil)
            ctx.textPosition = CGPoint(x: x + width - CGFloat(w), y: top - h + 3); CTLineDraw(line, ctx); return h
        }
        CTFrameDraw(frame, ctx)
        if !links.isEmpty {
            let lines = CTFrameGetLines(frame) as! [CTLine]; var origins = [CGPoint](repeating: .zero, count: lines.count)
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
            for (i, line) in lines.enumerated() {
                let lr = CTLineGetStringRange(line)
                for (r, url) in links {
                    let s = max(r.location, lr.location), e = min(r.location + r.length, lr.location + lr.length)
                    guard s < e, let u = URL(string: url) else { continue }
                    let x0 = CTLineGetOffsetForStringIndex(line, s, nil), x1 = CTLineGetOffsetForStringIndex(line, e, nil)
                    ctx.setStrokeColor(linkCol); ctx.setLineWidth(0.4)
                    let by = rect.minY + origins[i].y - 1.5
                    ctx.move(to: CGPoint(x: x + x0, y: by)); ctx.addLine(to: CGPoint(x: x + x1, y: by)); ctx.strokePath()
                    ctx.setURL(u as CFURL, for: CGRect(x: x + x0, y: rect.minY + origins[i].y - 3, width: x1 - x0, height: 14))
                }
            }
        }
        return h
    }
    func need(_ h: CGFloat) { if y - h < M + 8 { newPage() } }
    func block(_ a: NSAttributedString, links: [(NSRange, String)], x: CGFloat = M, width: CGFloat = CW, gap: CGFloat = 6) {
        let h = height(a, width: width); need(h); draw(a, x: x, top: y, width: width, links: links); y -= h + gap
    }
    func mark(_ id: String, title: String, level: Int) {
        dests.append(Dest(name: id, title: title, level: level, page: page, y: y))
        ctx.addDestination(id as CFString, at: CGPoint(x: 0, y: y + 14))
    }
    func rule() { ctx.setStrokeColor(CGColor(red: 0.85, green: 0.85, blue: 0.86, alpha: 1)); ctx.setLineWidth(0.6); ctx.move(to: CGPoint(x: M, y: y)); ctx.addLine(to: CGPoint(x: PW - M, y: y)); ctx.strokePath() }

    func cover() {
        let (t, _) = attr("GDC Metadata", size: 30, color: accent, bold: true); block(t, links: [], gap: 2)
        let (t2, _) = attr(tr(src["title"]), size: 20, bold: true); block(t2, links: [], gap: 4)
        let (v, _) = attr("\(version) · \(tr(src["sub"]))", size: 10.5, color: grey); block(v, links: [], gap: 4)
        let (w, _) = attr(tr(src["who"]), size: 10, color: ink); block(w, links: [], gap: 12)
        rule(); y -= 14
        let (c, _) = attr(tr(src["contents"]), size: 13, bold: true); block(c, links: [], gap: 6)
    }
    func tocEntries() -> [(id: String, title: String, level: Int)] {
        var r: [(String, String, Int)] = []; var h1n = ""
        for (i, b) in blocks.enumerated() {
            if b["t"] as? String == "h1" { h1n = b["id"] as! String; r.append((h1n, tr(b["x"]), 1)) }
            if b["t"] as? String == "h2" { r.append(("h2_\(i)", tr(b["x"]), 2)) }
        }
        return r
    }
    func toc() {
        for e in tocEntries() {
            let ind: CGFloat = e.level == 1 ? 0 : 16
            let (a, _) = attr(e.title, size: e.level == 1 ? 10.5 : 9.5, color: e.level == 1 ? ink : grey, bold: e.level == 1)
            let h = height(a, width: CW - ind - 40); need(h + 3)
            draw(a, x: M + ind, top: y, width: CW - ind - 40, links: [])
            let pg = known[e.id].map(String.init) ?? "·"
            let (p, _) = attr(pg, size: e.level == 1 ? 10.5 : 9.5, color: grey); draw(p, x: PW - M - 30, top: y, width: 30, links: [], align: .right)
            ctx.setDestination(e.id as CFString, for: CGRect(x: M + ind, y: y - h - 1, width: CW - ind, height: h + 3))
            y -= h + 4
        }
    }

    func body() {
        for (i, b) in blocks.enumerated() {
            let t = b["t"] as! String
            switch t {
            case "h1":
                newPage(); let id = b["id"] as! String
                mark(id, title: tr(b["x"]), level: 1)
                let (a, _) = attr(tr(b["x"]), size: 19, color: accent, bold: true); block(a, links: [], gap: 6); rule(); y -= 12
            case "h2":
                need(60); y -= 6; mark("h2_\(i)", title: tr(b["x"]), level: 2)
                let (a, _) = attr(tr(b["x"]), size: 12.5, bold: true); block(a, links: [], gap: 5)
            case "p":
                let (a, l) = attr(tr(b["x"]), size: 10); block(a, links: l, gap: 7)
            case "list":
                for it in b["items"] as! [[String: String]] {
                    let (a, l) = attr(it[lang] ?? "", size: 10); let h = height(a, width: CW - 16); need(h)
                    let (dot, _) = attr("•", size: 10, color: accent, bold: true); draw(dot, x: M + 3, top: y, width: 10, links: [])
                    draw(a, x: M + 16, top: y, width: CW - 16, links: l); y -= h + 4
                }
                y -= 4
            case "steps":
                for (n, it) in (b["items"] as! [[String: String]]).enumerated() {
                    let (a, l) = attr(it[lang] ?? "", size: 10); let h = height(a, width: CW - 24); need(h)
                    let (num, _) = attr("\(n + 1).", size: 10, color: accent, bold: true); draw(num, x: M, top: y, width: 20, links: [])
                    draw(a, x: M + 24, top: y, width: CW - 24, links: l); y -= h + 5
                }
                y -= 4
            case "note", "tip", "warn":
                let col: CGColor = t == "warn" ? CGColor(red: 0.80, green: 0.20, blue: 0.15, alpha: 1) : (t == "tip" ? CGColor(red: 0.15, green: 0.50, blue: 0.30, alpha: 1) : accent)
                let label = t == "warn" ? (lang == "ro" ? "ATENȚIE" : lang == "es" ? "ATENCIÓN" : "WARNING") : (t == "tip" ? (lang == "ro" ? "SFAT" : lang == "es" ? "CONSEJO" : "TIP") : (lang == "ro" ? "NOTĂ" : lang == "es" ? "NOTA" : "NOTE"))
                let (a, l) = attr("**\(label)** — " + tr(b["x"]), size: 9.5); let h = height(a, width: CW - 22); need(h + 12)
                ctx.setFillColor(col.copy(alpha: 0.09)!); ctx.fill(CGRect(x: M, y: y - h - 8, width: CW, height: h + 12))
                ctx.setFillColor(col); ctx.fill(CGRect(x: M, y: y - h - 8, width: 3, height: h + 12))
                draw(a, x: M + 12, top: y - 2, width: CW - 22, links: l); y -= h + 20
            case "img":
                let id = b["id"] as! String; let path = "\(capDir)/\(id)_\(lang).png"
                let (cap, _) = attr(tr(b["x"]), size: 8.5, color: grey)
                guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let im = CGImageSourceCreateImageAtIndex(src, 0, nil) else { imagesMissing.append(path); continue }
                imagesFound += 1
                let w = CW, h = floor(w * CGFloat(im.height) / CGFloat(im.width)); let ch = height(cap, width: CW)
                need(h + ch + 14); ctx.draw(im, in: CGRect(x: M, y: y - h, width: w, height: h))
                ctx.setStrokeColor(CGColor(red: 0.8, green: 0.8, blue: 0.82, alpha: 1)); ctx.setLineWidth(0.5); ctx.stroke(CGRect(x: M, y: y - h, width: w, height: h))
                y -= h + 5; draw(cap, x: M, top: y, width: CW, links: []); y -= ch + 12
            case "table":
                let head = b["head"] as! [[String: String]], rows = b["rows"] as! [[[String: String]]]
                let n = head.count
                let cw: [CGFloat] = n == 2 ? [CW * 0.28, CW * 0.72] : (n == 4 ? [CW * 0.22, CW * 0.30, CW * 0.24, CW * 0.24] : Array(repeating: CW / CGFloat(n), count: n))
                func row(_ cells: [String], header: Bool) {
                    let parts = cells.enumerated().map { (j, c) in attr(c, size: 9, color: header ? .white : ink, bold: header || j == 0) }
                    let hs = parts.enumerated().map { (j, p) in height(p.0, width: cw[j] - 10) }
                    let h = (hs.max() ?? 10) + 8; need(h)
                    if header { ctx.setFillColor(accent); ctx.fill(CGRect(x: M, y: y - h, width: CW, height: h)) }
                    var x = M
                    for (j, p) in parts.enumerated() { draw(p.0, x: x + 5, top: y - 4, width: cw[j] - 10, links: p.1); x += cw[j] }
                    if !header { ctx.setStrokeColor(CGColor(red: 0.87, green: 0.87, blue: 0.88, alpha: 1)); ctx.setLineWidth(0.5); ctx.move(to: CGPoint(x: M, y: y - h)); ctx.addLine(to: CGPoint(x: PW - M, y: y - h)); ctx.strokePath() }
                    y -= h
                }
                row(head.map { $0[lang] ?? "" }, header: true)
                for r in rows { row(r.map { $0[lang] ?? "" }, header: false) }
                y -= 10
            default: break
            }
        }
    }

    func outline() {
        func node(_ d: Dest) -> [CFString: Any] {
            [kCGPDFOutlineTitle: d.title, kCGPDFOutlineDestination: d.name, kCGPDFOutlineDestinationRect: CGRect(x: 0, y: d.y, width: 1, height: 1).dictionaryRepresentation]
        }
        var top: [[CFString: Any]] = []
        for d in dests {
            if d.level == 1 { top.append(node(d)) }
            else if !top.isEmpty { var last = top.removeLast(); var ch = (last[kCGPDFOutlineChildren] as? [[CFString: Any]]) ?? []; ch.append(node(d)); last[kCGPDFOutlineChildren] = ch; top.append(last) }
        }
        CGPDFContextSetOutline(ctx, [kCGPDFOutlineChildren: top as NSArray] as NSDictionary)
    }
    func finish() { footer(); ctx.endPDFPage(); ctx.closePDF() }
}

func render(known: [String: Int], to url: URL?) -> Renderer {
    let r = Renderer(known: known); r.begin(to: url); r.cover(); r.toc(); r.body(); r.finish(); return r
}
let p1 = render(known: [:], to: nil)
var pages: [String: Int] = [:]; for d in p1.dests { pages[d.name] = d.page }
let p2 = render(known: pages, to: URL(fileURLWithPath: outPath))
print("pdf=\(outPath) pages=\(p2.page) h1=\(p2.dests.filter { $0.level == 1 }.count) dests=\(p2.dests.count) images=\(p2.imagesFound) missing=\(p2.imagesMissing.count)")
for m in p2.imagesMissing { print("MISSING \(m)") }
