// Script-only verification of manual PDFs (no rendering into LLM context): pages, selectable text, links, key UI names, forbidden words.
// usage: verify_manual <ro|en|es> <file.pdf> <expected-version>
import Foundation
import PDFKit
let A = CommandLine.arguments; let lang = A[1], ver = A[3]
guard let doc = PDFDocument(url: URL(fileURLWithPath: A[2])) else { print("FAIL cannot open"); exit(1) }
var text = ""; var thin = 0, urlLinks = 0, destLinks = 0, imgPages = 0
for i in 0..<doc.pageCount {
    let p = doc.page(at: i)!; let t = p.string ?? ""; text += t + "\n"; if t.count < 120 { thin += 1 }
    for an in p.annotations where an.type == "Link" { if an.url != nil { urlLinks += 1 } else if an.destination != nil || an.action != nil { destLinks += 1 } }
}
let need: [String: [String]] = [
 "ro": ["Trimite în Resolve", "Aplică în Media Pool", "Alege folderul", "Indisponibil", "Caută actualizări", "White Point (Kelvin)", "5100", "5700", "Match using filename", "Gyroflow"],
 "en": ["Send to Resolve", "Apply to Media Pool", "Choose folder", "Unavailable", "Check for Updates", "White Point (Kelvin)", "5100", "5700", "Match using filename", "Gyroflow"],
 "es": ["Enviar a Resolve", "Aplicar al Media Pool", "Elegir carpeta", "No disponible", "Buscar actualizaciones", "White Point (Kelvin)", "5100", "5700", "Match using filename", "Gyroflow"]]
let missing = need[lang]!.filter { !text.contains($0) }
let forbid = ["preț", "cumpără", "price", "buy", "precio", "comprar", "Claude", "Anthropic"].filter { text.localizedCaseInsensitiveContains($0) }
let hasVer = text.contains(ver)
print("file=\(A[2])\npages=\(doc.pageCount) chars=\(text.count) thinPages=\(thin) urlLinks=\(urlLinks) internalLinks=\(destLinks) version=\(hasVer ? "ok" : "MISSING") missingPhrases=\(missing) forbidden=\(forbid)")
let ok = doc.pageCount >= 6 && thin == 0 && destLinks >= 15 && urlLinks >= 3 && missing.isEmpty && forbid.isEmpty && hasVer
print(ok ? "VERIFY OK" : "VERIFY FAIL"); exit(ok ? 0 : 1)
