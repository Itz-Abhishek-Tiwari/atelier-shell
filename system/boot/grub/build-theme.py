#!/usr/bin/env python3
"""Build the Atelier GRUB theme from the live desktop theme.

Reads the palette (~/.config/atelier/theme.json) and the current wallpaper
(~/.cache/current_wallpaper) and writes a complete GRUB theme into OUT_DIR.

    build-theme.py OUT_DIR [--width 1920 --height 1080] [--items 3]
                           [--preview preview.png --entries "Arch Linux,Advanced,UEFI Firmware Settings"]

Design: one glass card in the middle of the (softly blurred) wallpaper, the same look as the
lock and login screens. Everything static — the card, the title, the key hints — is drawn into
background.png with the real Inter font at full quality; GRUB's own bitmap fonts are only used
for what it fills in at boot (the entries and the countdown). Every position is an absolute
pixel value computed here for the exact screen size, so nothing drifts between resolutions.

system/boot/grub/install.sh calls this and copies the result to /boot/grub/themes/atelier.
"""
import argparse
import json
import shutil
import socket
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HOME = Path.home()
INTER = "/usr/share/fonts/inter/Inter.ttc"           # static weights (a variable font renders badly in grub-mkfont)
FACE = {"regular": 0, "medium": 10, "semibold": 12, "display_semibold": 30}
FONT_MONO = "/usr/share/fonts/TTF/JetBrainsMonoNerdFontMono-Regular.ttf"
FONT_ICONS = "/usr/share/fonts/TTF/JetBrainsMonoNerdFontPropo-Regular.ttf"
GLYPHS = "0x20-0x7E,0xB7-0xB7,0x2190-0x2193,0x23CE-0x23CE"    # ASCII + · ← → ↑ ↓ ⏎


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def palette():
    try:
        c = json.loads((HOME / ".config/atelier/theme.json").read_text())["colors"]
    except Exception:  # Catppuccin Mocha
        c = {}
    d = {"base": "#1e1e2e", "mantle": "#181825", "crust": "#11111b", "text": "#cdd6f4",
         "subtext1": "#bac2de", "subtext0": "#a6adc8", "overlay0": "#6c7086",
         "surface0": "#313244", "accent": "#cba6f7"}
    return {**d, **{k: v for k, v in c.items() if isinstance(v, str)}}


def wallpaper():
    try:
        w = Path((HOME / ".cache/current_wallpaper").read_text().strip())
        return w if w.is_file() else None
    except OSError:
        return None


def ttf(face, px):
    return ImageFont.truetype(INTER, px, index=FACE[face])


# ───────────────────────────── layout ─────────────────────────────

class Layout:
    """All geometry in screen pixels, scaled from a 1080p design."""

    def __init__(self, W, H, items):
        self.W, self.H = W, H
        s = self.s = H / 1080
        self.items = max(1, min(items, 6))
        self.card_w = round(620 * s)
        self.pad = round(36 * s)                      # card inner padding
        self.item_h = round(54 * s)
        self.item_gap = round(6 * s)
        self.sel_r = round(12 * s)                    # selection pill corner = its 9-slice border
        self.header_h = round(112 * s)
        self.footer_h = round(64 * s)
        self.menu_h = self.items * (self.item_h + self.item_gap) - self.item_gap + 2 * self.sel_r
        self.card_h = self.pad + self.header_h + self.menu_h + self.footer_h
        self.card_x = (W - self.card_w) // 2
        self.card_y = (H - self.card_h) // 2
        self.radius = round(24 * s)
        # menu box: the pill's border sticks out sel_r around each item, so inset by it
        self.menu_x = self.card_x + self.pad - self.sel_r
        self.menu_y = self.card_y + self.pad + self.header_h
        self.menu_w = self.card_w - 2 * self.pad + 2 * self.sel_r
        self.foot_y = self.menu_y + self.menu_h + round(10 * s)
        self.px = {k: round(v * s) for k, v in
                   {"title": 34, "sub": 16, "item": 20, "small": 15, "mono": 18}.items()}
        self.icon = round(26 * s)


# ───────────────────────────── images ─────────────────────────────

def rounded_mask(size, r, scale=4):
    w, h = size
    m = Image.new("L", (w * scale, h * scale), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * scale - 1, h * scale - 1), r * scale, fill=255)
    return m.resize(size, Image.LANCZOS)


def background(L, c, host):
    W, H = L.W, L.H
    crust = hex_rgb(c["crust"])
    src = wallpaper()
    if src:
        img = Image.open(src).convert("RGB")
        k = max(W / img.width, H / img.height)
        img = img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)
        l, t = (img.width - W) // 2, (img.height - H) // 2
        img = img.crop((l, t, l + W, t + H))
        bg = Image.blend(img.filter(ImageFilter.GaussianBlur(6 * L.s)), Image.new("RGB", (W, H), crust), 0.45)
    else:
        img = bg = Image.new("RGB", (W, H), crust)

    # vignette: calmer edges, the card stays the brightest thing
    vig = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vig).ellipse((-W * 0.25, -H * 0.35, W * 1.25, H * 1.35), fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(160 * L.s))
    bg = Image.composite(bg, Image.blend(bg, Image.new("RGB", (W, H), crust), 0.5), vig)

    box = (L.card_x, L.card_y, L.card_x + L.card_w, L.card_y + L.card_h)
    mask = rounded_mask((L.card_w, L.card_h), L.radius)

    # soft shadow under the card
    sh = Image.new("L", (W, H), 0)
    sh.paste(mask, (L.card_x, L.card_y + round(14 * L.s)))
    sh = sh.filter(ImageFilter.GaussianBlur(36 * L.s)).point(lambda v: v * 0.55)
    bg = Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), bg, sh)

    # glass: the wallpaper behind the card, blurred hard and tinted with the palette
    glass = img.crop(box).filter(ImageFilter.GaussianBlur(40 * L.s))
    glass = Image.blend(glass, Image.new("RGB", glass.size, hex_rgb(c["base"])), 0.72)
    bg.paste(glass, box[:2], mask)

    d = ImageDraw.Draw(bg, "RGBA")
    d.rounded_rectangle(box, L.radius, outline=hex_rgb(c["text"]) + (28,), width=max(1, round(L.s)))

    # header: title + who/where
    x, y = L.card_x + L.pad, L.card_y + L.pad
    d.text((x, y), "Atelier", font=ttf("display_semibold", L.px["title"]), fill=hex_rgb(c["text"]))
    d.text((x, y + round(46 * L.s)), f"{host}  ·  choose what to start", font=ttf("regular", L.px["sub"]),
           fill=hex_rgb(c["subtext0"]))
    dy = L.menu_y - round(18 * L.s)
    d.line((L.card_x + L.pad, dy, L.card_x + L.card_w - L.pad, dy), fill=hex_rgb(c["text"]) + (22,),
           width=max(1, round(L.s)))

    # footer: key hints on the right (the countdown label sits on the left, drawn by GRUB)
    hint = "↑↓ select   ⏎ boot   E edit   C console"
    f = ttf("regular", L.px["small"])
    tw = d.textlength(hint, font=f)
    d.text((L.card_x + L.card_w - L.pad - tw, L.foot_y + round(8 * L.s)), hint, font=f,
           fill=hex_rgb(c["overlay0"]) if "overlay0" in c else hex_rgb(c["subtext0"]))
    return bg


def pill(out, L, c):
    """9-slice selection pill: a soft accent tint. Its corner size (sel_r) is the border GRUB
    draws outside each item, which Layout accounts for."""
    r = L.sel_r
    n = 4 * r
    big = 4
    acc = hex_rgb(c["accent"])
    im = Image.new("RGBA", (n * big, n * big), (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle((0, 0, n * big - 1, n * big - 1), radius=r * big,
                                         fill=acc + (52,), outline=acc + (70,), width=big)
    im = im.resize((n, n), Image.LANCZOS)
    parts = {"nw": (0, 0, r, r), "n": (r, 0, n - r, r), "ne": (n - r, 0, n, r),
             "w": (0, r, r, n - r), "c": (r, r, n - r, n - r), "e": (n - r, r, n, n - r),
             "sw": (0, n - r, r, n), "s": (r, n - r, n - r, n), "se": (n - r, n - r, n, n)}
    for k, b in parts.items():
        im.crop(b).save(out / f"select_{k}.png")
    return im


ICONS = {"arch": 0xF303, "gnu-linux": 0xF31A, "os": 0xF31A, "submenu": 0xF062E,
         "efi": 0xF035B, "firmware": 0xF035B, "windows": 0xF05B3, "recovery": 0xF0A39}


def icons(out, L, c):
    (out / "icons").mkdir(exist_ok=True)
    big, n = 4, L.icon * 4
    col = hex_rgb(c["text"])
    for name, cp in ICONS.items():
        ch = chr(cp)
        f = ImageFont.truetype(FONT_ICONS, n)
        l, t, r, b = f.getbbox(ch)
        f = ImageFont.truetype(FONT_ICONS, int(n * (n * 0.82) / max(r - l, b - t)))
        l, t, r, b = f.getbbox(ch)
        im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        ImageDraw.Draw(im).text(((n - (r - l)) / 2 - l, (n - (b - t)) / 2 - t), ch, font=f, fill=col + (230,))
        im.resize((L.icon, L.icon), Image.LANCZOS).save(out / "icons" / f"{name}.png")


def mkfont(out, face, px, fname, src=INTER):
    cmd = ["grub-mkfont", "-s", str(px), "-r", GLYPHS, "-o", str(out / fname)]
    if src == INTER:   # every face of the .ttc reports "Inter Regular": name them, or GRUB mixes them up
        cmd += ["-i", str(FACE[face or "regular"]), "-n", "Inter " + (face or "regular").replace("_", " ").title()]
    subprocess.run(cmd + [src], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    data = (out / fname).read_bytes()          # GRUB knows a font by the NAME stored in it
    i = data.index(b"NAME") + 8
    return data[i:data.index(b"\0", i)].decode()


def theme_txt(out, L, c, fonts):
    T = lambda k: c.get(k, "#ffffff")
    txt = f"""# Atelier GRUB theme — generated by system/boot/grub/build-theme.py for {L.W}x{L.H} from the desktop
# palette and wallpaper. Re-run system/boot/grub/install.sh after changing either.
title-text: ""
desktop-image: "background.png"
desktop-image-scale-method: "stretch"
desktop-color: "{T('crust')}"
terminal-font: "{fonts['mono']}"
terminal-left: "{L.card_x}"
terminal-top: "{L.card_y}"
terminal-width: "{L.card_w}"
terminal-height: "{L.card_h}"
terminal-border: "0"

+ boot_menu {{
    left = {L.menu_x}
    top = {L.menu_y}
    width = {L.menu_w}
    height = {L.menu_h}
    item_font = "{fonts['item']}"
    selected_item_font = "{fonts['item_sel']}"
    item_color = "{T('subtext1')}"
    selected_item_color = "{T('text')}"
    item_height = {L.item_h}
    item_spacing = {L.item_gap}
    item_padding = {round(16 * L.s)}
    icon_width = {L.icon}
    icon_height = {L.icon}
    item_icon_space = {round(14 * L.s)}
    selected_item_pixmap_style = "select_*.png"
    scrollbar = false
}}

+ label {{
    id = "__timeout__"
    left = {L.card_x + L.pad}
    top = {L.foot_y + round(4 * L.s)}
    width = {L.card_w // 2}
    height = {round(28 * L.s)}
    align = "left"
    text = "Starting in %d s"
    font = "{fonts['small']}"
    color = "{T('subtext0')}"
}}
"""
    (out / "theme.txt").write_text(txt)


def preview(path, bg, sel, L, c, entries):
    """What GRUB will draw, approximately: the background + entries, first one selected."""
    im = bg.convert("RGBA")
    d = ImageDraw.Draw(im)
    f_item, f_sel = ttf("medium", L.px["item"]), ttf("semibold", L.px["item"])
    pad, ispace = round(16 * L.s), round(14 * L.s)
    for i, name in enumerate(entries[:L.items]):
        y = L.menu_y + L.sel_r + i * (L.item_h + L.item_gap)
        x = L.menu_x + L.sel_r
        w = L.menu_w - 2 * L.sel_r
        if i == 0:   # 9-slice stretch of the pill around the item
            box = (x - L.sel_r, y - L.sel_r, x + w + L.sel_r, y + L.item_h + L.sel_r)
            p = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), (0, 0, 0, 0))
            ImageDraw.Draw(p).rounded_rectangle((0, 0, p.width - 1, p.height - 1), L.sel_r,
                                                fill=hex_rgb(c["accent"]) + (52,), outline=hex_rgb(c["accent"]) + (70,))
            im.alpha_composite(p, box[:2])
        cls = "arch" if "Arch" in name else "submenu" if "Advanced" in name else "efi"
        ic = Image.open(Path(path).parent / "_theme" / "icons" / f"{cls}.png") if (Path(path).parent / "_theme").exists() else None
        if ic:
            im.alpha_composite(ic, (x + pad, y + (L.item_h - L.icon) // 2))
        f = f_sel if i == 0 else f_item
        tx = x + pad + L.icon + ispace
        asc, desc = f.getmetrics()
        d.text((tx, y + (L.item_h - asc - desc) // 2), name, font=f,
               fill=hex_rgb(c["text"] if i == 0 else c["subtext1"]))
    d.text((L.card_x + L.pad, L.foot_y + round(8 * L.s)), "Starting in 2 s", font=ttf("regular", L.px["small"]),
           fill=hex_rgb(c["subtext0"]))
    im.convert("RGB").save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--width", type=int, default=1920)
    ap.add_argument("--height", type=int, default=1080)
    ap.add_argument("--items", type=int, default=3, help="menu entries (sizes the card)")
    ap.add_argument("--preview")
    ap.add_argument("--entries", default="Arch Linux,Advanced,UEFI Firmware Settings")
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for f in out.iterdir():
        shutil.rmtree(f) if f.is_dir() else f.unlink()

    c = palette()
    L = Layout(a.width, a.height, a.items)
    bg = background(L, c, socket.gethostname())
    bg.save(out / "background.png", optimize=True)
    sel = pill(out, L, c)
    icons(out, L, c)
    fonts = {
        "item": mkfont(out, "medium", L.px["item"], "inter-medium.pf2"),
        "item_sel": mkfont(out, "semibold", L.px["item"], "inter-semibold.pf2"),
        "small": mkfont(out, "regular", L.px["small"], "inter-regular.pf2"),
        "mono": mkfont(out, None, L.px["mono"], "mono.pf2", FONT_MONO if Path(FONT_MONO).exists() else INTER),
    }
    theme_txt(out, L, c, fonts)
    if a.preview:
        tmp = Path(a.preview).parent / "_theme"
        if tmp.exists():
            shutil.rmtree(tmp)
        shutil.copytree(out, tmp)
        preview(a.preview, bg, sel, L, c, [e.strip() for e in a.entries.split(",")])
        shutil.rmtree(tmp)
    print(f"built GRUB theme in {out} ({L.W}x{L.H}, {L.items} entries; fonts: {', '.join(fonts.values())})")


if __name__ == "__main__":
    sys.exit(main())
