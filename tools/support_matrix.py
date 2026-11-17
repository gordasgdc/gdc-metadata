#!/usr/bin/env python3
"""Regenerates the internal support matrix from real clips: python3 tools/support_matrix.py <core-binary> <out.md> <root>...
One row per make|model|container+readers; a representative clip (most confirmed fields). Output is INTERNAL (clip names are private)."""
import json, subprocess, sys
core, out, roots = sys.argv[1], sys.argv[2], sys.argv[3:]
FIELDS = ["make","camera_model","lens","focal_length","focal_eq","focus_distance","af_area","focus_mode","ae_mode","aperture","iso","shutter","wb_mode","wb_temp","tint","picture_profile","curve","gamut","timecode"]
rows = {}
p = subprocess.Popen([core, "scan"] + roots, stdout=subprocess.PIPE, text=True)
for line in p.stdout:
    j = json.loads(line)
    if j.get("event") != "clip": continue
    c = j["clip"]; f = {x["id"]: x for x in c["fields"]}
    for _i in FIELDS: f.setdefault(_i, {"value": None, "primary": None, "note": None})
    key = (f["make"]["value"] or "-", f["camera_model"]["value"] or "-", c["ext"].lower(), "+".join(c["readers"]))
    ok = [i for i in FIELDS if f[i]["value"]]
    if key not in rows or len(ok) > rows[key][0]: rows[key] = (len(ok), c, f, ok)
def src(x):
    p = x["primary"]
    return "" if not p else {"gdc-cndm": "cndm", "gdc-sony": "sony-nrt", "exiftool": "tag", "gdc-rule": "pair-rule"}.get(p["source"], p["source"])
with open(out, "w") as o:
    o.write("# Matriz de suport (probe reale) — generată de tools/support_matrix.py\n\n")
    o.write("Curbă/gamut: `cndm` = decodat din pista Canon (empiric, nedocumentat de Canon, validat față de Resolve); `sony-nrt` = metadate Sony NRT încorporate (XML); `tag` = etichetă declarată; `user` = confirmat de utilizator (nu apare în matrice); `pair-rule` = calculat dintr-o curbă declarată. Combinațiile care nu apar aici NU au fost testate. Canon `maker_hint` (CanonLogVersion/ColorSpace2) = indiciu neatribuit.\n\n")
    o.write("| Model/format | Câmpuri confirmate | Indisponibile | Curbă / gamut (sursă) | Probă |\n|---|---|---|---|---|\n")
    for k in sorted(rows):
        n, c, f, ok = rows[k]
        conf = "; ".join(f"{i}={f[i]['value']}" for i in ok if i not in ("curve","gamut")).replace("|", "/")
        un = ", ".join(i for i in FIELDS if i not in ok and i not in ("curve","gamut"))
        cg = []
        for i in ("curve","gamut"):
            if f[i]["value"]: cg.append(f"{i}={f[i]['value']} ({src(f[i])})")
            elif f[i]["note"] == "maker_hint": cg.append(f"{i}=Indisponibil (indiciu maker neconfirmat)")
            else: cg.append(f"{i}=Nedetectat")
        o.write(f"| {k[0]}|{k[1]}|{k[2]} ({k[3]}) | {conf} | {un} | {'; '.join(cg)} | {c['name']} |\n")
print(len(rows), "rows ->", out)
