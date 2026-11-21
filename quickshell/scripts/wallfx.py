#!/usr/bin/env python3
"""wallfx — outline maps for the "Outline" wallpaper transition (shaders/outline.frag).

The transition draws the character of the NEW wallpaper as a thin line, fills it in from
that line, and then lets the rest of the image spread outward from it. To know where the
character is, the image is cut out once with an AI segmentation model (ISNet through
onnxruntime, ~2 s per image on a laptop CPU; BiRefNet-lite looked similar but took ~50 s)
and turned into two small maps, cached per image:

  <key>.map.png  R = depth inside the character (0 on the outline → 1 deepest)
                 G = signed distance to the outline (0.5 = on it, lower = inside), ±SD px
                 B = order in which the outside arrives (0 next to the character → 1)
  <key>.pen.png  R = where along the outline each nearby pixel is (0 = not near it,
                 then 1/255..1 in drawing order: two pens starting at the top)

A wallpaper without one clear subject gets a "<key>.none" marker and plays Spread instead.

  wallfx.py install         set up the model (a venv in ~/.local/share/atelier/wallfx)
  wallfx.py status          JSON: installed?, how many wallpapers are prepared
  wallfx.py map IMG         prints "<map> <pen>" if IMG is prepared, "none" if it has no
                            subject, "missing" if not prepared yet (fast: never computes)
  wallfx.py make IMG        prepares IMG (a few seconds); prints like `map`
  wallfx.py warm [DIR...]   prepares every wallpaper not done yet (default: the picker's folders)
"""
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
BASE = HOME / ".local/share/atelier/wallfx"
VENV = BASE / "venv"
VPY = VENV / "bin/python"
MODEL = BASE / "isnet-general-use.onnx"
MODEL_URL = "https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx"
CACHE = HOME / ".cache/atelier/wallfx"
DIRS = [HOME / ".config/hypr/wall", HOME / "Pictures/Wallpapers"]
EXTS = {".jpg", ".jpeg", ".png", ".webp"}

MAP_LONG = 960      # long side of the maps (the shader interpolates)
SD = 12.0           # signed distance stored within ±SD map px of the outline
PEN_BAND = 6.0      # pen progress is stored this close to the outline (map px)


def key(img: Path) -> str:
    st = img.stat()
    return hashlib.sha1(f"{img.resolve()}|{st.st_size}|{int(st.st_mtime)}".encode()).hexdigest()[:20]


def lookup(img: Path) -> str:
    k = key(img)
    m, p, n = CACHE / f"{k}.map.png", CACHE / f"{k}.pen.png", CACHE / f"{k}.none"
    if m.exists() and p.exists():
        return f"{m} {p}"
    return "none" if n.exists() else "missing"


def in_venv():
    """The model and its libraries live in their own venv: hand over if we're not in it."""
    if Path(sys.prefix) != VENV and VPY.exists():
        os.execv(str(VPY), [str(VPY), os.path.abspath(__file__), *sys.argv[1:]])
    if not VPY.exists() or not MODEL.exists():
        print("not-installed")
        sys.exit(3)


# ───────────────────────────── install ─────────────────────────────

def install():
    BASE.mkdir(parents=True, exist_ok=True)
    if not VPY.exists():
        subprocess.run([sys.executable, "-m", "venv", str(VENV)], check=True)
    subprocess.run([str(VPY), "-m", "pip", "install", "-q", "--upgrade", "pip"], check=True)
    subprocess.run([str(VPY), "-m", "pip", "install", "-q", "onnxruntime", "numpy", "pillow", "opencv-python-headless"], check=True)
    if not MODEL.exists():
        tmp = MODEL.with_suffix(".part")
        subprocess.run(["curl", "-fL", "--retry", "3", "-o", str(tmp), MODEL_URL], check=True)
        tmp.rename(MODEL)
    print("installed")


def status():
    imgs = list(images(DIRS))
    done = sum(1 for i in imgs if lookup(i) != "missing")
    print(json.dumps({"installed": VPY.exists() and MODEL.exists(), "total": len(imgs), "prepared": done}))


# ───────────────────────────── cutout ─────────────────────────────

_session = None


def cutout(im):
    """Subject mask (float 0..1, image size) from ISNet."""
    import numpy as np
    import onnxruntime as ort
    global _session
    if _session is None:
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = max(1, (os.cpu_count() or 4) // 2)   # leave the desktop room
        _session = ort.InferenceSession(str(MODEL), opts, providers=["CPUExecutionProvider"])
    inp = _session.get_inputs()[0]
    x = np.asarray(im.convert("RGB").resize((1024, 1024)), dtype=np.float32) / 255.0
    x = x - 0.5                                   # ISNet: mean 0.5, std 1
    x = x.transpose(2, 0, 1)[None].astype(np.float32)
    y = _session.run(None, {inp.name: x})[0][0, 0]
    y = (y - y.min()) / max(1e-6, float(y.max() - y.min()))
    from PIL import Image
    return np.asarray(Image.fromarray((y * 255).astype("uint8")).resize(im.size, Image.BILINEAR), dtype=np.float32) / 255.0


def make(img: Path) -> str:
    import cv2
    import numpy as np
    from PIL import Image

    CACHE.mkdir(parents=True, exist_ok=True)
    k = key(img)
    im = Image.open(img)
    im.draft("RGB", (2048, 2048))
    s = MAP_LONG / max(im.size)
    w, h = max(1, round(im.size[0] * s)), max(1, round(im.size[1] * s))
    small = im.convert("RGB").resize((w, h), Image.LANCZOS)
    mask = (cutout(small) > 0.5).astype(np.uint8)

    # keep the biggest subject; give up if there isn't one clear subject
    n, lab, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
    area = mask.sum()
    frac = area / float(w * h)
    if n < 2 or not (0.004 < frac < 0.65):
        (CACHE / f"{k}.none").touch()
        return "none"
    big = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    if stats[big, cv2.CC_STAT_AREA] < 0.6 * area:
        (CACHE / f"{k}.none").touch()
        return "none"
    mask = (lab == big).astype(np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))

    din = cv2.distanceTransform(mask, cv2.DIST_L2, 5)
    dout = cv2.distanceTransform(1 - mask, cv2.DIST_L2, 5)
    sd = np.where(mask > 0, -din, dout)

    depth = np.where(mask > 0, din / max(1.0, din.max()), 0.0)
    # the outside arrives outward from the character, roughened by noise
    rng = np.random.default_rng(int(k[:8], 16))
    noise = cv2.resize(rng.random((max(2, h // 40), max(2, w // 40))).astype(np.float32), (w, h), interpolation=cv2.INTER_CUBIC)
    outside = dout / max(1.0, dout.max())
    outside = np.clip(outside * 0.85 + (noise - 0.5) * 0.12 + 0.06, 0.0, 1.0)
    outside[mask > 0] = 0.0

    # pen order: the outline's contour points, from the top, two pens going opposite ways
    cs, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    c = max(cs, key=len)[:, 0, :]
    top = int(np.argmin(c[:, 1]))
    c = np.roll(c, -top, axis=0)
    L = len(c)
    i = np.arange(L)
    prog = np.minimum(i, L - i) / max(1.0, L / 2)          # 0 at the top, 1 where the pens meet
    line = np.zeros((h, w), np.uint8)
    line[c[:, 1], c[:, 0]] = 1
    # nearest contour point for every pixel near the outline
    _, labels = cv2.distanceTransformWithLabels(1 - line, cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
    # label → contour index
    lab_at = np.zeros(labels.max() + 1, np.float32)
    lab_at[labels[c[:, 1], c[:, 0]]] = prog
    pen = lab_at[labels]
    pen = np.where(np.abs(sd) <= PEN_BAND, np.maximum(pen, 1 / 255.0), 0.0)

    enc = lambda a: np.clip(np.round(a * 255.0), 0, 255).astype(np.uint8)
    sdn = np.clip(0.5 + sd / (2 * SD), 0.0, 1.0)
    rgb = np.dstack([enc(depth), enc(sdn), enc(outside)])
    mp, pp = CACHE / f"{k}.map.png", CACHE / f"{k}.pen.png"
    Image.fromarray(np.dstack([enc(pen)] * 3)).save(pp)
    Image.fromarray(rgb).save(mp)
    return f"{mp} {pp}"


def images(dirs):
    for d in dirs:
        d = Path(d).expanduser()
        if d.is_dir():
            for p in sorted(d.iterdir()):
                if p.is_file() and p.suffix.lower() in EXTS:
                    yield p.resolve()


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "install":
        install()
    elif cmd == "status":
        status()
    elif cmd == "map" and len(argv) > 2:
        print(lookup(Path(argv[2])))
    elif cmd == "make" and len(argv) > 2:
        img = Path(argv[2])
        r = lookup(img)
        if r == "missing":
            in_venv()
            r = make(img)
        print(r)
    elif cmd == "warm":
        in_venv()
        os.nice(15)
        for img in images(argv[2:] or DIRS):
            if lookup(img) == "missing":
                try:
                    print(img.name, make(img), flush=True)
                except Exception as e:   # one bad file must not stop the rest
                    print(img.name, "error", e, flush=True)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
