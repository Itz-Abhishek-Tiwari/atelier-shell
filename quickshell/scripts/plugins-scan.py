#!/usr/bin/env python3
"""Lists the user's plugins as JSON: ~/.config/atelier/plugins/<id>/plugin.json.
A plugin is switched off by an empty file called `.disabled` in its folder.
It only runs once the user has approved it: `.trusted` holds the hash of its files, and a changed
file means a changed hash, so an edited or updated plugin has to be approved again.
usage: plugins-scan.py [plugins dir]"""
import hashlib, json, os, sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.config/atelier/plugins")

# kind -> (keys every entry needs, entry points at a QML file)
KINDS = {
    "lockStyles":      (("id", "file"), True),
    "desktopWidgets":  (("id", "file"), True),
    "settingsPages":   (("id", "file"), True),
    "barItems":        (("id", "file"), True),
    "launcherActions": (("id", "title"), False),
    "controlTiles":    (("id", "label"), False),
}
SKIP = {".disabled", ".trusted"}


def tree_hash(d):
    h = hashlib.sha256()
    for base, dirs, files in os.walk(d):
        dirs[:] = sorted(x for x in dirs if x != ".git")
        for f in sorted(files):
            if f in SKIP and base == d:
                continue
            p = os.path.join(base, f)
            h.update(os.path.relpath(p, d).encode() + b"\0")
            try:
                h.update(open(p, "rb").read())
            except OSError:
                pass
    return h.hexdigest()


def scan(name, d):
    p = {"id": name, "dir": d, "enabled": not os.path.exists(os.path.join(d, ".disabled")),
         "name": name, "version": "", "author": "", "description": "", "error": "",
         "hash": "", "trusted": False, **{k: [] for k in KINDS}}
    try:
        p["hash"] = tree_hash(d)
        try:
            p["trusted"] = open(os.path.join(d, ".trusted")).read().strip() == p["hash"]
        except OSError:
            pass
        m = json.load(open(os.path.join(d, "plugin.json")))
        for k in ("name", "version", "author", "description"):
            if isinstance(m.get(k), str):
                p[k] = m[k]
        for kind, (need, isfile) in KINDS.items():
            entries = m.get(kind, [])
            for e in entries if isinstance(entries, list) else []:
                if not isinstance(e, dict) or not all(isinstance(e.get(k), str) and e[k] for k in need):
                    p["error"] = "bad entry in " + kind
                    continue
                e = dict(e)
                if isfile:
                    f = os.path.realpath(os.path.join(d, e["file"]))
                    if not f.startswith(os.path.realpath(d) + os.sep) or not os.path.isfile(f):
                        p["error"] = e["file"] + " not found"
                        continue
                    e["file"] = f
                elif not (isinstance(e.get("cmd"), str) or isinstance(e.get("overlay"), str)):
                    p["error"] = kind + " entry '" + e["id"] + "' needs cmd or overlay"
                    continue
                e["uid"] = name + "." + e["id"]       # plugin-unique id
                p[kind].append(e)
    except Exception as ex:
        p["error"] = "plugin.json: " + str(ex)
    return p


out = []
if os.path.isdir(root):
    for name in sorted(os.listdir(root)):
        d = os.path.join(root, name)
        if not name.startswith(".") and os.path.isfile(os.path.join(d, "plugin.json")):
            out.append(scan(name, d))
print(json.dumps(out))
