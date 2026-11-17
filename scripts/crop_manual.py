#!/usr/bin/env python3
"""Crops raw window captures into the manual images (bigger, readable text). usage: crop_manual.py <captures/manual dir>"""
import sys, pathlib
from PIL import Image
d = pathlib.Path(sys.argv[1]); raw = d / "raw"
# name -> (x0, y0, x1, y1) as fractions of the raw capture
CROPS = {"import_three": (0, 0, 1, 1), "inspector": (0.47, 0, 1, 0.80), "search": (0.47, 0, 1, 0.80), "resolve_sheet": (0.06, 0.15, 0.94, 0.85)}
for lang in ("ro", "en", "es"):
    for name, (a, b, c, e) in CROPS.items():
        im = Image.open(raw / f"{name}_{lang}.png"); w, h = im.size
        im.crop((int(a * w), int(b * h), int(c * w), int(e * h))).save(d / f"{name}_{lang}.png")
    im = Image.open(raw / f"inspector_{lang}.png"); w, h = im.size
    im.crop((0, h - 64, int(w * 0.62), h)).save(d / f"version_bar_{lang}.png")
print("cropped")
