#!/usr/bin/env python3
"""Helper for the Quickshell screenshot tool (ScreenshotOverlay.qml).

    screenshot.py capture <output> <file>        grim one monitor (the frozen frame)
    screenshot.py windows <output>               JSON rects of visible windows on that monitor
    screenshot.py crop <src> <x> <y> <w> <h>     crop, save to ~/Pictures/Screenshots, copy to clipboard
                                                 prints {"path": ...}
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

SAVE_DIR = Path(os.environ.get("XDG_PICTURES_DIR", Path.home() / "Pictures")) / "Screenshots"


def capture(output, dest):
    subprocess.run(["grim", "-o", output, "-l", "1", dest], check=True)   # -l 1: fast PNG
    print(json.dumps({"path": dest}))


def windows(output):
    mons = json.loads(subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, text=True).stdout)
    mon = next((m for m in mons if m["name"] == output), mons[0])
    ws_ids = {mon["activeWorkspace"]["id"]}
    if mon.get("specialWorkspace", {}).get("id"):
        ws_ids.add(mon["specialWorkspace"]["id"])
    clients = json.loads(subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True).stdout)
    out = []
    # focusHistoryID 0 = most recently focused = on top for overlapping floats
    for c in sorted(clients, key=lambda c: c.get("focusHistoryID", 99)):
        if not c.get("mapped") or c.get("hidden") or c["workspace"]["id"] not in ws_ids:
            continue
        x, y = c["at"][0] - mon["x"], c["at"][1] - mon["y"]
        w, h = c["size"]
        out.append({"x": x, "y": y, "w": w, "h": h, "title": c.get("title", ""), "class": c.get("class", "")})
    print(json.dumps(out))


def crop(src, x, y, w, h):
    from PIL import Image
    SAVE_DIR.mkdir(parents=True, exist_ok=True)
    dest = SAVE_DIR / time.strftime("Screenshot_%Y-%m-%d_%H-%M-%S.png")
    with Image.open(src) as im:
        x, y = max(0, int(x)), max(0, int(y))
        w, h = max(1, int(w)), max(1, int(h))
        box = (x, y, min(im.width, x + w), min(im.height, y + h))
        im.crop(box).save(dest, "PNG", optimize=False)
    with open(dest, "rb") as f:
        subprocess.run(["wl-copy", "--type", "image/png"], stdin=f)
    print(json.dumps({"path": str(dest)}))


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
    elif a[0] == "capture" and len(a) == 3:
        capture(a[1], a[2])
    elif a[0] == "windows" and len(a) == 2:
        windows(a[1])
    elif a[0] == "crop" and len(a) == 6:
        crop(a[1], *a[2:])
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
