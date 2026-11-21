#!/usr/bin/env python3
"""qylock lock-screen themes for the Atelier shell (https://github.com/Darkkal44/qylock, GPL-3.0).

qylock is a set of SDDM themes plus a small Quickshell wrapper that fakes the SDDM API
(sddm.login → PAM), so the themes work as a Wayland session lock. It is kept as a sparse git
checkout in ~/.local/share/atelier/qylock: the wrapper and the preview GIFs are always there,
each theme is downloaded only when it is first chosen.

    qylock.py list              JSON: [{id, name, preview, downloaded, sizeMB}]
    qylock.py fetch <id>        download one theme (sparse checkout)
    qylock.py lock <id>         lock the session with that theme (runs until unlocked)
    qylock.py preview <id>      the theme in a normal 1280x720 window (qylock's testing mode;
                                no session lock, close the window to quit)
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
ROOT = HOME / ".local/share/atelier/qylock"
REPO = "https://github.com/Darkkal44/qylock.git"
WRAPPER = ROOT / "quickshell-lockscreen"


def git(*args, check=True):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True, check=check)


def ensure_repo():
    if (ROOT / ".git").is_dir():
        return
    ROOT.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "clone", "-q", "--depth", "1", "--filter=blob:none", "--sparse", REPO, str(ROOT)], check=True)
    git("sparse-checkout", "set", "--no-cone", "/quickshell-lockscreen/", "/Assets/", "/LICENSE", "/README.md")


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def preview_for(theme_id, gifs):
    special = {"windows7": "win7"}
    key = special.get(norm(theme_id), norm(theme_id))
    by_norm = {norm(g.stem): g for g in gifs}
    if key in by_norm:
        return by_norm[key]
    for n, g in by_norm.items():               # e.g. last-of-us → the_last_of_us
        if key in n or n in key:
            return g
    return None


def pretty(theme_id):
    name = theme_id.replace("_", " ").replace("-", " ")
    return " ".join(w if w.isupper() or any(ch.isdigit() for ch in w) else w.capitalize() for w in name.split())


SIZES = ROOT / ".atelier-sizes.json"


def theme_sizes():
    """Theme sizes from GitHub's tree listing, cached. (`git ls-tree -l` would download every
    blob of the partial clone just to measure it.)"""
    try:
        return json.loads(SIZES.read_text())
    except Exception:
        pass
    sizes = {}
    try:
        import urllib.request
        with urllib.request.urlopen("https://api.github.com/repos/Darkkal44/qylock/git/trees/HEAD?recursive=1", timeout=15) as r:
            for x in json.load(r).get("tree", []):
                parts = x["path"].split("/")
                if x["type"] == "blob" and parts[0] == "themes" and len(parts) > 2:
                    sizes[parts[1]] = sizes.get(parts[1], 0) + x.get("size", 0)
        SIZES.write_text(json.dumps(sizes))
    except Exception:
        pass
    return sizes


def themes():
    names = git("ls-tree", "--name-only", "HEAD", "themes/").stdout.split()
    ids = sorted({n.split("/")[1] for n in names if n.count("/") == 1}, key=str.lower)
    sizes = theme_sizes()
    gifs = sorted((ROOT / "Assets").glob("*.gif"))
    out = []
    for tid in ids:
        pv = preview_for(tid, gifs)
        out.append({
            "id": tid,
            "name": pretty(tid),
            "preview": str(pv) if pv else "",
            "downloaded": (ROOT / "themes" / tid / "Main.qml").is_file(),
            "sizeMB": round(sizes.get(tid, 0) / 1048576, 1),
        })
    return out


def fetch(theme_id):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", theme_id):
        sys.exit("bad theme id")
    git("sparse-checkout", "add", f"/themes/{theme_id}/")
    if not (ROOT / "themes" / theme_id / "Main.qml").is_file():
        sys.exit(f"theme {theme_id} did not download")


def lock(theme_id, preview=False):
    theme_dir = ROOT / "themes" / theme_id
    if not (theme_dir / "Main.qml").is_file():
        fetch(theme_id)
    env = dict(os.environ)
    env["QML2_IMPORT_PATH"] = f"{WRAPPER}/imports" + (":" + env["QML2_IMPORT_PATH"] if env.get("QML2_IMPORT_PATH") else "")
    env["QML_XHR_ALLOW_FILE_READ"] = "1"          # the shim reads theme.conf with XMLHttpRequest
    env["QS_THEME"] = theme_id
    env["QS_THEME_PATH"] = str(theme_dir)
    env.setdefault("XDG_SESSION_TYPE", "wayland")
    if preview:
        # the wrapper's testing path: a plain window instead of WlSessionLock
        env["XDG_SESSION_TYPE"] = "x11"
        env["QS_TESTING"] = "1"
    os.execvpe("quickshell", ["quickshell", "-p", str(WRAPPER / "lock_shell.qml")], env)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        ensure_repo()
    except Exception as e:
        print(json.dumps({"error": str(e)}) if cmd == "list" else f"qylock: {e}", file=sys.stdout if cmd == "list" else sys.stderr)
        sys.exit(1)
    if cmd == "list":
        print(json.dumps(themes()))
    elif cmd == "fetch" and len(sys.argv) > 2:
        fetch(sys.argv[2])
        print("ok")
    elif cmd == "lock" and len(sys.argv) > 2:
        lock(sys.argv[2])
    elif cmd == "preview" and len(sys.argv) > 2:
        lock(sys.argv[2], preview=True)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
