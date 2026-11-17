#!/usr/bin/env python3
"""Fails on duplicate keys in the Localization.swift dictionary literal (a duplicate traps at launch)."""
import re, sys, collections
src = open(sys.argv[1] if len(sys.argv) > 1 else "app/Sources/GDCMetadata/Localization.swift", encoding="utf-8").read()
keys = re.findall(r'"([A-Za-z0-9_.]+)":\s*\[\s*\.ro:', src)
dup = [k for k, n in collections.Counter(keys).items() if n > 1]
if dup: print("DUPLICATE l10n keys:", ", ".join(sorted(dup))); sys.exit(1)
print(f"OK l10n: {len(keys)} keys, no duplicates")
