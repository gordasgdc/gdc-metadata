#!/usr/bin/env python3
"""Generates site/{index,ro,es}.html, site/guide-{en,ro,es}.html and README{,.ro,.es}.md from one source (synthetic images only)."""
import re, html, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
VER = (ROOT / "VERSION").read_text().strip()
DMG = f"GDCMetadata-{VER}.dmg"
DL = f"https://github.com/gordasgdc/gdc-metadata/releases/download/v{VER}/{DMG}"
REPO = "https://github.com/gordasgdc/gdc-metadata"
T = {
"en": dict(lang="English", tag="Free · macOS · RO / EN / ES",
  lead="Read camera, lens, exposure, white balance, image profile and timecode from multi-camera folders, see where each value comes from and send it to the DaVinci Resolve Media Pool. Everything stays on your Mac; originals are never modified.",
  h=["Folder → inspector", "Find any value", "Send to Resolve", "Motion & stabilization"],
  c=["Table and compact inspector. Each value carries its source.", "Search explains why a clip matches and keeps your selection.", "Preview first: values to write, kept and identical. Ambiguous clips are never touched.", "Detected motion data is listed with its source and marked “Gyroflow compatibility unverified”. Stabilization is not offered until a before/after route is demonstrated in Resolve. Illustrative state, synthetic data."],
  b=["Empty Resolve fields are written; existing values are kept; a clip present in several bins is skipped as ambiguous (verified in Resolve after reopening the project).", "CSV export is an alternative, but Resolve's import can overwrite existing values, and with duplicate file names every clip with that name gets the same values. Options verified: Match using filename on, clip start/end Timecode off.", "A sidecar <clip>.gdc-metadata.json is written next to each clip; originals are only read."],
  dl="Download for macOS", dlnote=f"Version {VER} · free · signed and notarized DMG", guide="User guide", lic="MIT licence · © 2026 Cristi Gordaș",
  deps_h="Requirements", deps=["macOS 14 or later.", "ExifTool (for example: brew install exiftool).", "Python 3 from the Xcode Command Line Tools — only for sending to Resolve.", "DaVinci Resolve running, with external scripting set to Local — only for sending to Resolve."],
  build="Build", note="All images use synthetic demo data."),
"ro": dict(lang="Română", tag="Gratuit · macOS · RO / EN / ES",
  lead="Citește camera, obiectivul, expunerea, balansul de alb, profilul de imagine și timecode-ul din foldere multi-cameră, arată de unde vine fiecare valoare și le trimite în Media Pool din DaVinci Resolve. Totul rămâne pe Mac; originalele nu sunt modificate.",
  h=["Folder → inspector", "Găsește orice valoare", "Trimite în Resolve", "Mișcare și stabilizare"],
  c=["Tabel și inspector compact. Fiecare valoare își arată sursa.", "Căutarea explică de ce se potrivește un clip și păstrează selecția.", "Întâi previzualizare: valori de scris, păstrate și identice. Clipurile ambigue nu sunt atinse.", "Datele de mișcare detectate apar cu sursa lor și cu mențiunea „Compatibilitate Gyroflow neverificată”. Stabilizarea nu este oferită până nu există un traseu demonstrat înainte/după în Resolve. Stare ilustrativă, date sintetice."],
  b=["Câmpurile goale din Resolve se scriu; valorile existente se păstrează; un clip din mai multe bin-uri e omis ca ambiguu (verificat în Resolve după redeschiderea proiectului).", "CSV e o alternativă, dar importul din Resolve poate suprascrie valorile existente, iar la nume de fișier duplicate fiecare clip cu acel nume primește aceleași valori. Opțiuni verificate: Match using filename bifat, timecode start/end debifat.", "Lângă fiecare clip se scrie un sidecar <clip>.gdc-metadata.json; originalele sunt doar citite."],
  dl="Descarcă pentru macOS", dlnote=f"Versiunea {VER} · gratuit · DMG semnat și notarizat", guide="Ghid de utilizare", lic="Licență MIT · © 2026 Cristi Gordaș",
  deps_h="Cerințe", deps=["macOS 14 sau mai nou.", "ExifTool (de exemplu: brew install exiftool).", "Python 3 din Xcode Command Line Tools — doar pentru trimiterea în Resolve.", "DaVinci Resolve pornit, cu External scripting setat pe Local — doar pentru trimiterea în Resolve."],
  build="Build", note="Toate imaginile folosesc date demo sintetice."),
"es": dict(lang="Español", tag="Gratis · macOS · RO / EN / ES",
  lead="Lee cámara, objetivo, exposición, balance de blancos, perfil de imagen y timecode de carpetas multicámara, muestra el origen de cada valor y los envía al Media Pool de DaVinci Resolve. Todo queda en tu Mac; los originales no se modifican.",
  h=["Carpeta → inspector", "Encuentra cualquier valor", "Enviar a Resolve", "Movimiento y estabilización"],
  c=["Tabla e inspector compacto. Cada valor muestra su origen.", "La búsqueda explica por qué coincide un clip y conserva la selección.", "Primero la vista previa: valores a escribir, conservados e idénticos. Los clips ambiguos no se tocan.", "Los datos de movimiento detectados se listan con su origen y la nota «Compatibilidad con Gyroflow sin verificar». No se ofrece estabilización hasta demostrar una ruta antes/después en Resolve. Estado ilustrativo, datos sintéticos."],
  b=["Los campos vacíos de Resolve se escriben; los valores existentes se conservan; un clip en varios bins se omite por ambiguo (verificado en Resolve tras reabrir el proyecto).", "El CSV es una alternativa, pero la importación de Resolve puede sobrescribir los valores existentes y, con nombres de archivo duplicados, todos los clips con ese nombre reciben los mismos valores. Opciones verificadas: Match using filename activado, Timecode inicio/fin desactivado.", "Junto a cada clip se escribe un sidecar <clip>.gdc-metadata.json; los originales solo se leen."],
  dl="Descargar para macOS", dlnote=f"Versión {VER} · gratis · DMG firmado y notarizado", guide="Guía de uso", lic="Licencia MIT · © 2026 Cristi Gordaș",
  deps_h="Requisitos", deps=["macOS 14 o posterior.", "ExifTool (por ejemplo: brew install exiftool).", "Python 3 de las Xcode Command Line Tools — solo para enviar a Resolve.", "DaVinci Resolve abierto, con External scripting en Local — solo para enviar a Resolve."],
  build="Build", note="Todas las imágenes usan datos de demostración sintéticos."),
}
PAGE = {"en": "index.html", "ro": "ro.html", "es": "es.html"}
READ = {"en": "README.md", "ro": "README.ro.md", "es": "README.es.md"}
IMGS = ["02_default_en", "03_search_en", "09_resolve_en", "07_motion_ready_en"]
CSS = """<style>
:root{--bg:#14161A;--panel:#1A1D22;--text:#EDEFF2;--mute:#9AA0AA;--accent:#DB8C3D;--on:#14161A;--line:#2A2E35}
@media (prefers-color-scheme:light){:root{--bg:#F5F3EF;--panel:#FFF;--text:#1A1D22;--mute:#5D6470;--accent:#B86F20;--on:#fff;--line:#DDD8CF}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:16px/1.55 -apple-system,system-ui,sans-serif}
main{max-width:1000px;margin:0 auto;padding:0 16px 48px}
header{display:flex;align-items:center;gap:14px;padding:36px 0 12px;flex-wrap:wrap}header img{width:56px;height:56px}
h1{font-size:2rem;margin:0}h2{font-size:1.25rem;margin:40px 0 8px}
.lead{color:var(--mute);max-width:62ch;margin:6px 0 20px}nav{margin-left:auto;display:flex;gap:12px}
.btn{display:inline-block;background:var(--accent);color:var(--on);padding:10px 18px;border-radius:10px;font-weight:600;text-decoration:none}
figure{margin:16px 0;background:var(--panel);border:1px solid var(--line);border-radius:14px;overflow:hidden}
figure img{display:block;width:100%;height:auto}figcaption{padding:10px 14px;color:var(--mute);font-size:.9rem}
ul,ol{padding-left:1.2rem}li{margin:6px 0}.note{border-left:3px solid var(--accent);padding:4px 12px;color:var(--mute)}
a{color:var(--accent)}.btn{color:var(--on)}footer{color:var(--mute);font-size:.85rem;margin-top:40px}code{background:var(--panel);padding:1px 5px;border-radius:5px}</style>"""
esc = lambda s: html.escape(s, quote=False)
for k, d in T.items():
    nav = "".join(f'<a href="{PAGE[o]}"{" aria-current=page" if o == k else ""}>{T[o]["lang"]}</a>' for o in T)
    idx = [0, 1, 2, 3]
    figs = "".join(f'<h2>{esc(d["h"][i])}</h2><figure><img src="img/{n}.png" alt="{esc(d["c"][i])}" loading="lazy"><figcaption>{esc(d["c"][i])}</figcaption></figure>' for i, n in zip(idx, IMGS))
    page = f'''<!doctype html>
<html lang="{k}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>GDC Metadata</title><meta name="description" content="{esc(d["lead"][:150])}"><link rel="icon" href="logo.svg">{CSS}</head><body><main>
<header><img src="logo.svg" alt=""><div><h1>GDC Metadata</h1><div class="lead" style="margin:0">{d["tag"]}</div></div><nav>{nav}</nav></header>
<p class="lead">{esc(d["lead"])}</p>
<p><a class="btn" href="{DL}">{esc(d["dl"])}</a> <span class="lead">{esc(d["dlnote"])}</span></p>
{figs}
<h2>{esc(d["deps_h"])}</h2><ul>{"".join(f"<li>{esc(x)}</li>" for x in d["deps"])}</ul>
<ul>{"".join(f"<li>{esc(x)}</li>" for x in d["b"])}</ul>
<p><a href="guide-{k}.html">{esc(d["guide"])}</a> · <a href="{REPO}">GitHub</a> · <a href="{REPO}/blob/main/LICENSE">{esc(d["lic"])}</a></p><p class="note">{esc(d["note"])}</p>
<footer>© 2026 Cristi Gordaș · gordas.dev/gdc-metadata</footer></main></body></html>'''
    (ROOT / "site" / PAGE[k]).write_text(page)
    rd = f'''<p align="center"><img src="docs/logo.svg" width="96" alt="GDC Metadata"></p>

# GDC Metadata

{d["lead"]}

**[{d["dl"]}]({DL})** — {d["dlnote"]}

[English](README.md) · [Română](README.ro.md) · [Español](README.es.md) · {d["guide"]}: [EN](docs/guide.en.md) · [RO](docs/guide.ro.md) · [ES](docs/guide.es.md)

![](site/img/02_default_en.png)

## {d["h"][2]}

![](site/img/09_resolve_en.png)

{"".join(f"- {x}" + chr(10) for x in d["b"])}
## {d["h"][3]}

{d["c"][3]}

## {d["deps_h"]}

{"".join(f"- {x}" + chr(10) for x in d["deps"])}
## {d["build"]}

```sh
export GDC_BUILD_ROOT=/path/to/build-folder
sh scripts/build_app.sh
GDC_SAMPLE_CLIP=/path/to/clip.mp4 GDC_SYNTH_DIR=/path/to/dir cargo test --manifest-path core/Cargo.toml
```

{d["lic"]} · [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) · {d["note"]}
'''
    (ROOT / READ[k]).write_text(rd)
    # guide html from docs/guide.<k>.md
    md = (ROOT / "docs" / f"guide.{k}.md").read_text().splitlines()
    inl = lambda s: re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", esc(s))
    out, lst = [], None
    for ln in md:
        m = re.match(r"(\d+)\. (.*)", ln); u = ln.startswith("- ")
        want = "ol" if m else "ul" if u else None
        if lst and lst != want: out.append(f"</{lst}>"); lst = None
        if want and not lst: out.append(f"<{want}>"); lst = want
        if m: out.append(f"<li>{inl(m.group(2))}</li>")
        elif u: out.append(f"<li>{inl(ln[2:])}</li>")
        elif ln.startswith("## "): out.append(f"<h2>{inl(ln[3:])}</h2>")
        elif ln.startswith("# "): out.append(f"<h1>{inl(ln[2:])}</h1>")
        elif ln.strip(): out.append(f"<p>{inl(ln)}</p>")
    if lst: out.append(f"</{lst}>")
    gnav = "".join(f'<a href="guide-{o}.html"{" aria-current=page" if o == k else ""}>{T[o]["lang"]}</a>' for o in T)
    (ROOT / "site" / f"guide-{k}.html").write_text(f'''<!doctype html>
<html lang="{k}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>GDC Metadata — {esc(d["guide"])}</title><link rel="icon" href="logo.svg">{CSS}</head><body><main>
<header><img src="logo.svg" alt=""><nav>{gnav}<a href="{PAGE[k]}">GDC Metadata</a></nav></header>
{chr(10).join(out)}
<footer>© 2026 Cristi Gordaș · MIT</footer></main></body></html>''')
print("ok", VER)
