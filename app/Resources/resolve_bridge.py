#!/usr/bin/env python3
"""GDC Metadata -> DaVinci Resolve bridge (stdlib only, Python 3.9+).
stdin: JSON {"action": "status"|"plan"|"apply", ...}  stdout: one JSON object.
Writes ONLY Media Pool metadata through MediaPoolItem.SetMetadata; never touches
colour management, Camera RAW or grades. Existing non-empty values are kept unless overwrite=true.
"""
import json, os, sys

API = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting"
LIB = "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so"
os.environ.setdefault("RESOLVE_SCRIPT_API", API)
os.environ.setdefault("RESOLVE_SCRIPT_LIB", LIB)
sys.path.append(os.path.join(os.environ["RESOLVE_SCRIPT_API"], "Modules"))

def out(o):
    sys.stdout.write(json.dumps(o)); sys.stdout.flush(); sys.exit(0)

def connect():
    try:
        import DaVinciResolveScript as dvr
    except Exception as e:
        out({"ok": False, "error": "no_module", "detail": str(e)})
    r = dvr.scriptapp("Resolve")
    if not r:
        out({"ok": False, "error": "resolve_unavailable"})
    return r

def walk(folder, acc):
    for c in folder.GetClipList() or []:
        acc.append((folder.GetName(), c))
    for s in folder.GetSubFolderList() or []:
        walk(s, acc)

def index(project):
    acc = []
    walk(project.GetMediaPool().GetRootFolder(), acc)
    by_path = {}
    for fname, c in acc:
        p = c.GetClipProperty("File Path")
        if p:
            by_path.setdefault(os.path.realpath(p), []).append((fname, c))
    return by_path

def main():
    req = json.load(sys.stdin)
    r = connect()
    pm = r.GetProjectManager()
    project = pm.GetCurrentProject()
    if not project:
        out({"ok": False, "error": "no_project"})
    act = req.get("action")
    if act == "status":
        out({"ok": True, "version": r.GetVersionString(), "project": project.GetName(),
             "clips": sum(len(v) for v in index(project).values())})
    keys = req.get("keys", [])
    idx = index(project)
    results = []
    for it in req.get("items", []):
        path = os.path.realpath(it["path"])
        hits = idx.get(path, [])
        row = {"path": it["path"], "match": "none", "folder": None, "fields": []}
        if len(hits) == 1:
            row["match"] = "exact"; row["folder"] = hits[0][0]
            clip = hits[0][1]
            cur = clip.GetMetadata() or {}
            for k, v in it["values"]:
                have = (cur.get(k) or "").strip()
                if have == v:
                    row["fields"].append({"key": k, "new": v, "current": have, "action": "same"})
                elif have and not req.get("overwrite"):
                    row["fields"].append({"key": k, "new": v, "current": have, "action": "keep"})
                else:
                    row["fields"].append({"key": k, "new": v, "current": have, "action": "write"})
            if act == "apply":
                for f in row["fields"]:
                    if f["action"] == "write":
                        ok = clip.SetMetadata({f["key"]: f["new"]})
                        after = (clip.GetMetadata(f["key"]) or "")
                        f["action"] = "written" if ok and after == f["new"] else "failed"
        elif len(hits) > 1:
            row["match"] = "ambiguous"
            row["folder"] = ", ".join(sorted(set(h[0] for h in hits)))
        results.append(row)
    if act == "apply":
        pm.SaveProject()
    out({"ok": True, "project": project.GetName(), "results": results})

main()
