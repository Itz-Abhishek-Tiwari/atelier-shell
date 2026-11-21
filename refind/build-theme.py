#!/usr/bin/env python3
"""Build the Atelier rEFInd theme from the live desktop theme.

Reads the palette (~/.config/atelier/theme.json) and the current wallpaper
(~/.cache/current_wallpaper) and writes a rEFInd theme into OUT_DIR:

  theme.conf             included from refind.conf
  background.png         the wallpaper, softly blurred and dimmed, with a quiet wordmark
  selection_big.png      the highlight behind the selected OS icon (accent tint)
  selection_small.png    the same for the small tool icons
  font.png               the label font (rEFInd only takes a monospaced PNG strip)
  icons/os_*.png         OS icons: a glass tile with a Nerd Font glyph
  icons/func_*.png       tool icons (shutdown, reboot, firmware)

    build-theme.py OUT_DIR [--width 1920 --height 1080] [--preview preview.png]

refind/install.sh calls this and copies the result to <ESP>/EFI/refind/themes/atelier.
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HOME = Path.home()
INTER = "/usr/share/fonts/inter/Inter.ttc"
INTER_DISPLAY_SEMIBOLD = 30
INTER_REGULAR = 0
MONO = "/usr/share/fonts/TTF/JetBrainsMonoNerdFontMono-Medium.ttf"
GLYPHS = "/usr/share/fonts/TTF/JetBrainsMonoNerdFontPropo-Regular.ttf"

BIG, SMALL = 128, 48                 # icon sizes (theme.conf: big_icon_size / small_icon_size)
SEL_BIG, SEL_SMALL = 144, 64         # selection images (rEFInd centres them behind the icon)

# OS icons rEFInd looks up by name; the glyph drawn on each
OS = {"arch": 0xF303, "linux": 0xF31A, "grub": 0xF0493, "unknown": 0xF0A39, "windows": 0xF05B3}
FUNC = {"shutdown": 0xF0425, "reboot": 0xF0709, "firmware": 0xF035B, "exit": 0xF0206}


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def palette():
    try:
        c = json.loads((HOME / ".config/atelier/theme.json").read_text())["colors"]
    except Exception:
        c = {}
    d = {"base": "#1e1e2e", "crust": "#11111b", "text": "#cdd6f4", "subtext0": "#a6adc8",
         "surface0": "#313244", "accent": "#cba6f7"}
    return {**d, **{k: v for k, v in c.items() if isinstance(v, str)}}


def wallpaper():
    try:
        w = Path((HOME / ".cache/current_wallpaper").read_text().strip())
        return w if w.is_file() else None
    except OSError:
        return None


def supersampled(size, draw, k=4):
    """Draw at k× and scale down: smooth edges on everything rEFInd shows."""
    im = Image.new("RGBA", (size * k, size * k), (0, 0, 0, 0))
    draw(ImageDraw.Draw(im), size * k, k)
    return im.resize((size, size), Image.LANCZOS)


def glyph(d, n, cp, fill, fill_frac=0.5, cy=0.5):
    ch = chr(cp)
    f = ImageFont.truetype(GLYPHS, n)
    l, t, r, b = f.getbbox(ch)
    f = ImageFont.truetype(GLYPHS, int(n * (n * fill_frac) / max(r - l, b - t)))
    l, t, r, b = f.getbbox(ch)
    d.text(((n - (r - l)) / 2 - l, n * cy - (b - t) / 2 - t), ch, font=f, fill=fill)


def background(out, W, H, c):
    crust = hex_rgb(c["crust"])
    src = wallpaper()
    if src:
        img = Image.open(src).convert("RGB")
        k = max(W / img.width, H / img.height)
        img = img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)
        l, t = (img.width - W) // 2, (img.height - H) // 2
        img = img.crop((l, t, l + W, t + H)).filter(ImageFilter.GaussianBlur(H / 1080 * 10))
        bg = Image.blend(img, Image.new("RGB", (W, H), crust), 0.5)
    else:
        bg = Image.new("RGB", (W, H), crust)
    # a darker band through the middle, where rEFInd draws the icons: calmer behind them
    band = Image.new("L", (W, H), 0)
    ImageDraw.Draw(band).rectangle((0, H * 0.36, W, H * 0.74), fill=150)
    band = band.filter(ImageFilter.GaussianBlur(H * 0.09))
    bg = Image.composite(Image.new("RGB", (W, H), crust), bg, band)
    # quiet wordmark above the icons
    d = ImageDraw.Draw(bg)
    s = H / 1080
    f = ImageFont.truetype(INTER, round(40 * s), index=INTER_DISPLAY_SEMIBOLD)
    t = "Atelier"
    d.text(((W - d.textlength(t, font=f)) / 2, H * 0.26), t, font=f, fill=hex_rgb(c["text"]))
    f2 = ImageFont.truetype(INTER, round(16 * s), index=INTER_REGULAR)
    t2 = "choose what to start"
    d.text(((W - d.textlength(t2, font=f2)) / 2, H * 0.26 + 56 * s), t2, font=f2, fill=hex_rgb(c["subtext0"]))
    bg.save(out / "background.png", optimize=True)
    return bg


def tile_icon(size, cp, c, frac):
    """A glass rounded tile with the glyph in the text colour."""
    def draw(d, n, k):
        r = n * 0.26
        d.rounded_rectangle((k, k, n - k, n - k), r, fill=hex_rgb(c["base"]) + (150,),
                            outline=hex_rgb(c["text"]) + (40,), width=k)
        glyph(d, n, cp, hex_rgb(c["text"]) + (240,), frac)
    return supersampled(size, draw)


def icons(out, c):
    (out / "icons").mkdir(exist_ok=True)
    for name, cp in OS.items():
        tile_icon(BIG, cp, c, 0.46).save(out / "icons" / f"os_{name}.png")
    for name, cp in FUNC.items():
        tile_icon(SMALL, cp, c, 0.44).save(out / "icons" / f"func_{name}.png")


def selections(out, c):
    acc = hex_rgb(c["accent"])
    for name, size, rad in (("selection_big", SEL_BIG, 0.28), ("selection_small", SEL_SMALL, 0.3)):
        def draw(d, n, k, rad=rad):
            d.rounded_rectangle((k, k, n - k, n - k), n * rad, fill=acc + (70,), outline=acc + (200,), width=2 * k)
        supersampled(size, draw).save(out / f"{name}.png")


def font(out, c, H):
    """rEFInd's font: ASCII 32..126 plus one 'unknown' cell, in one row of equal cells."""
    px = round(22 * H / 1080)
    f = ImageFont.truetype(MONO, px)
    asc, desc = f.getmetrics()
    cw = round(f.getlength("M"))
    ch = asc + desc + 2
    chars = [chr(i) for i in range(32, 127)] + ["?"]
    im = Image.new("RGBA", (cw * len(chars), ch), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i, chx in enumerate(chars):
        d.text((i * cw, 1), chx, font=f, fill=hex_rgb(c["text"]) + (255,))
    im.save(out / "font.png")
    return cw, ch


def theme_conf(out, W, H):
    (out / "theme.conf").write_text(f"""# Atelier rEFInd theme — generated by refind/build-theme.py for {W}x{H} from the desktop
# palette and wallpaper. Re-run refind/install.sh after changing either.
banner themes/atelier/background.png
banner_scale fillscreen
icons_dir themes/atelier/icons
selection_big themes/atelier/selection_big.png
selection_small themes/atelier/selection_small.png
font themes/atelier/font.png
big_icon_size {BIG}
small_icon_size {SMALL}
# keep only the entry name under the icons (no hint lines, no drive badges, no scroll arrows)
hideui hints,badges,arrows
""")


def preview(path, bg, out, entries, c):
    """Approximately what rEFInd draws: a centred row of big icons, the name of the selected
    one under it, and the small tools row below."""
    im = bg.convert("RGBA")
    W, H = im.size
    gap = 24
    n = len(entries)
    row_w = n * SEL_BIG + (n - 1) * gap
    x0, y0 = (W - row_w) // 2, int(H * 0.44)
    sel_b = Image.open(out / "selection_big.png")
    for i, (name, icon) in enumerate(entries):
        x = x0 + i * (SEL_BIG + gap)
        if i == 0:
            im.alpha_composite(sel_b, (x, y0))
        ic = Image.open(out / "icons" / f"os_{icon}.png")
        im.alpha_composite(ic, (x + (SEL_BIG - BIG) // 2, y0 + (SEL_BIG - BIG) // 2))
    tools = ["shutdown", "reboot", "firmware"]
    tw = len(tools) * SEL_SMALL + (len(tools) - 1) * 12
    for i, t in enumerate(tools):
        ic = Image.open(out / "icons" / f"func_{t}.png")
        x = (W - tw) // 2 + i * (SEL_SMALL + 12)
        im.alpha_composite(ic, (x + (SEL_SMALL - SMALL) // 2, y0 + SEL_BIG + 40))
    # label under the row, in the bitmap font
    fnt = Image.open(out / "font.png")
    cw, chh = fnt.width // 96, fnt.height
    label = "Boot " + entries[0][0]
    lx = (W - len(label) * cw) // 2
    for i, chx in enumerate(label):
        k = ord(chx) - 32 if 32 <= ord(chx) <= 126 else 95
        im.alpha_composite(fnt.crop((k * cw, 0, (k + 1) * cw, chh)), (lx + i * cw, y0 + SEL_BIG + 40 + SEL_SMALL + 28))
    im.convert("RGB").save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--width", type=int, default=1920)
    ap.add_argument("--height", type=int, default=1080)
    ap.add_argument("--preview")
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for f in out.iterdir():
        shutil.rmtree(f) if f.is_dir() else f.unlink()
    c = palette()
    bg = background(out, a.width, a.height, c)
    icons(out, c)
    selections(out, c)
    font(out, c, a.height)
    theme_conf(out, a.width, a.height)
    if a.preview:
        preview(a.preview, bg, out, [("Arch Linux", "arch"), ("GRUB", "grub")], c)
    print(f"built rEFInd theme in {out} ({a.width}x{a.height})")


if __name__ == "__main__":
    sys.exit(main())
