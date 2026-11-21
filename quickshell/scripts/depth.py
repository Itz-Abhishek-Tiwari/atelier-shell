#!/usr/bin/env python3
"""Depth-effect lock screen helper: cut the wallpaper's subject out so the lock clock can sit
*behind* it (the subject is drawn again on top of the clock).

  depth.py cutout <wallpaper>   → one JSON line:
        {"ok": true, "cutout": "<png>", "profile": [64 floats], "coverage": f}
        {"ok": false, "error": "...", "hint": "..."}
  depth.py status               → {"onnxruntime": bool, "model": bool, "modelPath": "..."}
  depth.py setup                → installs the model + runtime it shares with wallfx.py (the
                                  Outline transition) via `wallfx.py install`; no sudo. JSON.

The cutout is the wallpaper at its own aspect ratio with alpha = subject mask, so the lock
screen can draw it with the same fillMode as the wallpaper and the two line up exactly.
`profile` holds, for 64 equal columns across the image, the topmost row (0..1 of height)
where the subject is solid (1.0 = no subject in that column): the lock uses it to place the
clock so the subject overlaps just its lower part.

Segmentation: IS-Net general-use (DIS) on onnxruntime, CPU only. Results are cached by
path + mtime + size in ~/.cache/atelier/depth, so each wallpaper is processed once (~2-4 s).
Uses the ISNet model and venv of scripts/wallfx.py (~/.local/share/atelier/wallfx), so the
Outline transition and the Depth lock share one ~170 MB model and one onnxruntime install.
"""
import hashlib
import json
import os
import sys

HOME = os.path.expanduser("~")
CACHE = os.path.join(HOME, ".cache", "atelier", "depth")
MODEL_NAME = "isnet-general-use"
# Shared with scripts/wallfx.py (the "Outline" wallpaper transition): same ISNet model, same
# venv (onnxruntime, numpy, Pillow). One install serves both; `setup` runs `wallfx.py install`.
WALLFX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wallfx.py")
BASE = os.path.join(HOME, ".local", "share", "atelier", "wallfx")
MODEL = os.path.join(BASE, MODEL_NAME + ".onnx")
VENV = os.path.join(BASE, "venv")
VENV_PY = os.path.join(VENV, "bin", "python")
VERSION = 5          # bump when the mask post-processing changes (invalidates the cache)
MAX_W = 2560         # cutouts are stored at most this wide
COLS = 64


def out(obj):
    print(json.dumps(obj), flush=True)


def has_ort():
    try:
        import onnxruntime  # noqa: F401
        return True
    except Exception:
        return False


def maybe_reexec():
    """No system onnxruntime but the private venv exists → run this script with the venv's
    python instead (it sees the system numpy/Pillow through --system-site-packages)."""
    if has_ort() or not os.path.isfile(VENV_PY) or os.path.realpath(sys.prefix) == os.path.realpath(VENV):
        return
    os.execv(VENV_PY, [VENV_PY, "-I", os.path.abspath(__file__)] + sys.argv[1:])


def setup():
    """Install the shared model + venv through wallfx.py (prints S/P lines for the UI)."""
    import subprocess
    if os.path.isfile(VENV_PY) and os.path.isfile(MODEL):
        out({"ok": True})
        return
    print("S model", flush=True)
    r = subprocess.run([sys.executable, "-I", WALLFX, "install"], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if r.returncode != 0 or not os.path.isfile(MODEL):
        out({"ok": False, "error": "install failed: " + (r.stderr.strip().splitlines() or ["?"])[-1]})
        sys.exit(1)
    out({"ok": True})


def status():
    out({"onnxruntime": has_ort() or os.path.isfile(VENV_PY), "model": os.path.isfile(MODEL), "modelPath": MODEL})


def cache_key(path):
    st = os.stat(path)
    raw = "%s|%d|%d|%s|%d" % (os.path.realpath(path), st.st_mtime_ns, st.st_size, MODEL_NAME, VERSION)
    return hashlib.sha1(raw.encode()).hexdigest()[:20]


def segment(img):
    """img: PIL RGB → PIL L mask (same size), 0..255."""
    import numpy as np
    import onnxruntime as ort
    from PIL import Image

    opts = ort.SessionOptions()
    opts.intra_op_num_threads = max(1, min(4, (os.cpu_count() or 2) // 2))
    opts.log_severity_level = 3
    sess = ort.InferenceSession(MODEL, sess_options=opts, providers=["CPUExecutionProvider"])

    x = np.asarray(img.convert("RGB").resize((1024, 1024), Image.LANCZOS), dtype=np.float32)
    x = x / max(float(x.max()), 1e-6)
    x = (x - 0.5) / 1.0
    x = x.transpose(2, 0, 1)[None, ...]
    pred = sess.run(None, {sess.get_inputs()[0].name: x})[0][:, 0, :, :]
    lo, hi = float(pred.min()), float(pred.max())
    pred = (pred - lo) / max(hi - lo, 1e-6)
    m = Image.fromarray((np.squeeze(pred) * 255).astype("uint8"), mode="L")
    return m.resize(img.size, Image.LANCZOS)


def clock_ink(img):
    """A clock colour taken from the wallpaper, One UI style.
    Bright sky behind the clock → a deep tone of the picture's own most vivid colour;
    dark sky → a pale tint of it. Returns (hex, is_dark_ink, luma)."""
    import colorsys
    import numpy as np
    small = np.asarray(img.resize((160, round(160 * img.height / img.width))), dtype=np.float32) / 255.0
    h, w, _ = small.shape
    band = small[: int(h * 0.45), int(w * 0.25): int(w * 0.75)]
    lum = float((band @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)).mean())
    px = small.reshape(-1, 3)
    mx, mn = px.max(axis=1), px.min(axis=1)
    sat = (mx - mn) / np.maximum(mx, 1e-6)
    vivid = px[(sat >= np.quantile(sat, 0.85)) & (mx > 0.25)]
    r, g, b = (vivid.mean(axis=0) if len(vivid) else band.reshape(-1, 3).mean(axis=0))
    hue, _l, s_ = colorsys.rgb_to_hls(float(r), float(g), float(b))
    dark = lum > 0.55
    if dark:
        rgb = colorsys.hls_to_rgb(hue, 0.33, min(0.6, max(0.4, s_)))
    else:
        rgb = colorsys.hls_to_rgb(hue, 0.93, min(0.6, max(0.25, s_)))
    return "#%02x%02x%02x" % tuple(int(round(c * 255)) for c in rgb), dark, round(lum, 3)


def cutout(path):
    if not os.path.isfile(path):
        out({"ok": False, "error": "wallpaper not found"})
        return
    os.makedirs(CACHE, exist_ok=True)
    key = cache_key(path)
    png = os.path.join(CACHE, key + ".png")
    meta = os.path.join(CACHE, key + ".json")
    if os.path.isfile(png) and os.path.isfile(meta):
        try:
            with open(meta) as f:
                out(json.load(f))
            return
        except Exception:
            pass

    if not has_ort():
        out({"ok": False, "error": "onnxruntime missing", "hint": "Settings → Lock screen → Depth → Set up"})
        return
    if not os.path.isfile(MODEL):
        out({"ok": False, "error": "model missing", "hint": "Settings → Lock screen → Depth → Set up (shared with the Outline transition)"})
        return

    import numpy as np
    from PIL import Image, ImageFilter

    img = Image.open(path)
    img.load()
    img = img.convert("RGB")
    if img.width > MAX_W:
        img = img.resize((MAX_W, round(img.height * MAX_W / img.width)), Image.LANCZOS)

    m = segment(img)
    # tighten the soft mask: drop the faint haze, keep a short smooth edge, and pull the edge
    # in by ~1 px so no background fringe shows around the subject over the clock
    a = np.asarray(m, dtype=np.float32) / 255.0
    # IS-Net is often unsure on illustrations (a ship or statue comes out at 0.4-0.6): scale by
    # the mask's own peak first, so a faint-but-clear subject still becomes solid
    peak = float(np.percentile(a, 99.8))
    if peak > 0.2:
        a = np.clip(a / peak, 0.0, 1.0)
    a = np.clip((a - 0.30) / 0.40, 0.0, 1.0)
    m = Image.fromarray((a * 255).astype("uint8"), mode="L")
    m = m.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    a = np.asarray(m, dtype=np.float32) / 255.0

    coverage = float((a > 0.5).mean())
    solid = a > 0.5
    h, w = solid.shape
    profile = []
    for i in range(COLS):
        col = solid[:, i * w // COLS:(i + 1) * w // COLS]
        # a row counts once ~15 % of the column's pixels are subject (ignores lone specks)
        rows = np.nonzero(col.mean(axis=1) > 0.15)[0]
        profile.append(round(float(rows[0]) / h, 4) if rows.size else 1.0)

    ink, ink_dark, luma = clock_ink(img)
    if coverage < 0.004:
        res = {"ok": False, "error": "no clear subject in this wallpaper", "coverage": round(coverage, 4),
               "ink": ink, "inkDark": ink_dark, "luma": luma}
    else:
        rgba = img.copy()
        rgba.putalpha(m)
        rgba.save(png, optimize=False, compress_level=3)
        res = {"ok": True, "cutout": png, "profile": profile, "coverage": round(coverage, 4),
               "width": img.width, "height": img.height, "ink": ink, "inkDark": ink_dark, "luma": luma}
    with open(meta, "w") as f:
        json.dump(res, f)
    out(res)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        if cmd in ("status", "cutout"):
            maybe_reexec()
        if cmd == "status":
            status()
        elif cmd == "setup":
            setup()
        elif cmd == "cutout" and len(sys.argv) > 2:
            cutout(os.path.expanduser(sys.argv[2]))
        else:
            print(__doc__, file=sys.stderr)
            sys.exit(2)
    except Exception as e:
        out({"ok": False, "error": str(e)})
        sys.exit(1)


if __name__ == "__main__":
    main()
