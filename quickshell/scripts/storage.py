#!/usr/bin/env python3
"""Storage breakdown for Settings → Storage.

usage: storage.py scan      measure everything, print JSON, cache it
       storage.py cached    print the last scan (or {} if there is none)

Categories are measured with `du` (allocated size, one filesystem, in parallel). Whatever
`used` has that no category covers (the rest of /var, /opt, btrfs metadata, other users,
snapshots) is reported as "System & other", so the bar always adds up to the disk's usage.
Nothing here needs root: unreadable folders are skipped and counted under "System & other".
"""
import json
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HOME = Path.home()
CACHE = HOME / ".cache/atelier/storage.json"


def h(*parts):
    return str(HOME.joinpath(*parts))


# id, label, icon (nerd glyph), colour role, folders, the folder "Open" goes to
CATEGORIES = [
    ("apps", "Apps", "󰀻", "blue",
     ["/usr", "/opt", h("Applications"), h("apps"), h(".local/share/flatpak"), "/var/lib/flatpak",
      h(".local/share/applications")], h("Applications")),
    ("games", "Games", "󰊗", "green",
     [h(".local/share/Steam"), h(".steam"), h("Games"), h(".local/share/lutris"), h(".local/share/heroic")], h("Games")),
    ("documents", "Documents", "󰈙", "peach",
     [h("Documents"), h("Desktop"), h("Templates"), h("Public")], h("Documents")),
    ("downloads", "Downloads", "󰉍", "sapphire", [h("Downloads")], h("Downloads")),
    ("pictures", "Pictures", "󰉏", "pink", [h("Pictures")], h("Pictures")),
    ("videos", "Videos", "󰕧", "red", [h("Videos")], h("Videos")),
    ("music", "Music", "󰝚", "mauve", [h("Music")], h("Music")),
    ("developer", "Developer", "󰅩", "teal",
     [h("Projects"), h(".cargo"), h(".rustup"), h(".npm"), h(".bun"), h(".pnpm-store"), h("go"), h(".dotnet"),
      h(".vscode"), h(".gradle"), h(".m2"), h(".nvm"), h(".pyenv"), h(".conda"), h("miniconda3"), h(".android")],
     h("Projects")),
    ("cache", "Caches", "󰃢", "yellow", [h(".cache"), "/var/cache/pacman/pkg"], h(".cache")),
    ("data", "App data & settings", "󰒓", "lavender",
     [h(".config"), h(".local/share"), h(".local/state"), h(".local/lib"), h(".local/bin"),
      h(".claude"), h(".gemini"), h(".copilot"), h(".themes"), h(".icons"), h(".mozilla"), h(".nv")], h(".config")),
    ("trash", "Trash", "󰩹", "subtext", [h(".local/share/Trash")], h(".local/share/Trash/files")),
]
# folders that sit inside another category's folder: measured there, subtracted here
MINUS = {"data": [h(".local/share/Trash"), h(".local/share/Steam"), h(".local/share/lutris"),
                  h(".local/share/heroic"), h(".local/share/flatpak"), h(".local/share/applications")]}


# things Settings → Storage can clean up
CLEANUP = {
    "trash": [h(".local/share/Trash")],
    "aur": [h(".cache/yay"), h(".cache/paru")],                 # AUR build folders
    "pacman": ["/var/cache/pacman/pkg"],                         # old package downloads
    "thumbnails": [h(".cache/thumbnails"), h(".cache/atelier/wall-thumbs")],
    # developer download caches: pip/npm/Go/yarn/pnpm/Cargo fetch them again when needed
    "devcache": [h(".cache/pip"), h(".npm/_cacache"), h(".cache/go-build"), h(".cache/yarn"),
                 h(".cache/pnpm"), h(".cargo/registry/cache")],
}


def du(paths):
    """Allocated bytes of the given paths (missing ones ignored), staying on each filesystem."""
    paths = [p for p in paths if os.path.lexists(p)]
    if not paths:
        return 0
    try:
        out = subprocess.run(["du", "-scx", "--block-size=1", *paths], capture_output=True, text=True, timeout=600).stdout
        last = out.strip().splitlines()[-1] if out.strip() else ""
        return int(last.split()[0]) if last.endswith("total") else 0
    except Exception:
        return 0


def du_children(folder, depth=1):
    """[(bytes, path)] for each direct child of folder."""
    if not os.path.isdir(folder):
        return []
    try:
        out = subprocess.run(["du", "-x", "--block-size=1", f"--max-depth={depth}", folder],
                             capture_output=True, text=True, timeout=600).stdout
    except Exception:
        return []
    rows = []
    for line in out.splitlines():
        size, _, path = line.partition("\t")
        if path and path != folder:
            rows.append((int(size), path))
    return rows


def scan():
    t0 = time.time()
    total, used, free = (0, 0, 0)
    try:
        u = shutil.disk_usage("/")
        total, used, free = u.total, u.total - u.free, u.free
    except Exception:
        pass
    home = shutil.disk_usage(str(HOME))

    with ThreadPoolExecutor(max_workers=6) as ex:
        sizes = dict(zip([c[0] for c in CATEGORIES], ex.map(lambda c: du(c[4]), CATEGORIES)))
        minus = dict(zip(MINUS, ex.map(du, MINUS.values())))
        clean = dict(zip(CLEANUP, ex.map(du, CLEANUP.values())))
        big = []
        for rows in ex.map(du_children, [str(HOME), h(".cache"), h(".local/share"), h("Downloads"), h(".config")]):
            big += rows

    for cid, m in minus.items():
        sizes[cid] = max(0, sizes[cid] - m)

    cats = []
    for cid, label, icon, color, paths, open_path in CATEGORIES:
        cats.append({"id": cid, "label": label, "icon": icon, "color": color, "bytes": sizes[cid],
                     "open": open_path if os.path.isdir(open_path) else "",
                     "paths": [p.replace(str(HOME), "~") for p in paths if os.path.lexists(p)]})
    counted = sum(c["bytes"] for c in cats)
    # btrfs (zstd) compresses: files can add up to more than the disk reports as used. Then the
    # difference is what compression saves, and there is no measurable "other".
    saved = max(0, counted - used)
    cats.append({"id": "system", "label": "System & other", "icon": "󰒋", "color": "overlay", "open": "",
                 "bytes": max(0, used - counted), "paths": ["/var, /boot, snapshots, other users, filesystem"]})
    cats.sort(key=lambda c: (c["id"] == "system", -c["bytes"]))

    # biggest folders: skip a parent when its children are already listed
    parents = {str(HOME), h(".cache"), h(".local"), h(".local/share"), h("Downloads"), h(".config")}
    seen, biggest = set(), []
    for size, path in sorted(big, reverse=True):
        if path in parents or path in seen or size < 50 * 1024 * 1024:
            continue
        seen.add(path)
        biggest.append({"path": path, "name": path.replace(str(HOME), "~"), "bytes": size})
        if len(biggest) >= 10:
            break

    data = {"total": total, "used": used, "free": free, "sameDiskAsHome": home.total == total,
            "counted": counted, "compressionSaved": saved, "cleanup": clean,
            "categories": cats, "biggest": biggest, "scannedAt": int(time.time()),
            "seconds": round(time.time() - t0, 1)}
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    tmp = CACHE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data))
    tmp.replace(CACHE)
    return data


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "scan"
    if cmd == "cached":
        try:
            print(CACHE.read_text())
        except Exception:
            print("{}")
    else:
        print(json.dumps(scan()))


if __name__ == "__main__":
    main()
