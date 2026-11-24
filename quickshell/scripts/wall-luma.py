#!/usr/bin/env python3
"""Brightness of the wallpaper behind a screen region (used by the desktop widget to pick ink).

    wall-luma.py <image> <screenW> <screenH> <x> <y> <w> <h>

The wallpaper is drawn with PreserveAspectCrop (cover), so the region is mapped through the same
crop. Prints JSON: {"luma": 0..1 mean perceived brightness, "spread": 0..1 how busy it is,
"rgb": [r, g, b] 0..1 mean colour (for picking a colour that stands out)}.
"""
import json
import sys

from PIL import Image, ImageStat


def main() -> None:
    path = sys.argv[1]
    sw, sh, x, y, w, h = (float(v) for v in sys.argv[2:8])
    with Image.open(path) as im:
        im.draft("RGB", (int(sw), int(sh)))          # fast JPEG downscale on decode
        im = im.convert("RGB")
        iw, ih = im.size
        scale = max(sw / iw, sh / ih)                 # cover: fill the screen, crop the rest
        ox = (iw * scale - sw) / 2
        oy = (ih * scale - sh) / 2
        box = (
            max(0, int((x + ox) / scale)), max(0, int((y + oy) / scale)),
            min(iw, int((x + w + ox) / scale)), min(ih, int((y + h + oy) / scale)),
        )
        if box[2] <= box[0] or box[3] <= box[1]:
            raise SystemExit(1)
        crop = im.crop(box).resize((64, 64))
        st = ImageStat.Stat(crop.convert("L"))
        rgb = [round(v / 255, 3) for v in ImageStat.Stat(crop).mean[:3]]
        print(json.dumps({"luma": round(st.mean[0] / 255, 3), "spread": round(st.stddev[0] / 255, 3), "rgb": rgb}))


if __name__ == "__main__":
    main()
