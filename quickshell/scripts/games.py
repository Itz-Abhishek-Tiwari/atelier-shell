#!/usr/bin/env python3
"""List installed games for the Atelier Games overlay (GamesOverlay.qml).

Prints one JSON array; each game is
  {id, title, source, launch: [argv], cover, hero, lastPlayed}
cover/hero are file paths or https URLs ("" if unknown); lastPlayed is a unix time (0 = never).

Sources (each optional, silently skipped when missing):
  Steam   every library in libraryfolders.vdf, plus /mnt/games/SteamLibrary
  Heroic  Epic (legendary), GOG and sideloaded games
  Lutris  installed games in pga.db
  Manual  ~/.config/atelier/games.json: [{"title": "...", "command": "...", "cover": "/path.jpg"}]
Games from .desktop files (Categories=Game) are added in QML from DesktopEntries.
"""
import glob
import json
import os
import re
import sqlite3
import sys

HOME = os.path.expanduser("~")
games = []

# ── Steam ───────────────────────────────────────────────────────────────────
STEAM_ROOTS = [
    f"{HOME}/.local/share/Steam",
    f"{HOME}/.steam/steam",
    f"{HOME}/.var/app/com.valvesoftware.Steam/.local/share/Steam",
]
# runtimes and compatibility tools Steam installs like games
STEAM_SKIP = re.compile(r"^(Proton|Steam Linux Runtime|Steamworks Common|Steam Audio)|Redistributable", re.I)
STEAM_CDN = "https://cdn.cloudflare.steamstatic.com/steam/apps"


def acf_value(text, key):
    m = re.search(r'"%s"\s+"([^"]*)"' % key, text, re.I)
    return m.group(1) if m else ""


def steam_art(root, appid, kind):
    """kind: library_600x900 (portrait cover) or library_hero (wide background)."""
    cache = f"{root}/appcache/librarycache"
    for p in (f"{cache}/{appid}_{kind}.jpg", f"{cache}/{appid}/{kind}.jpg"):
        if os.path.isfile(p):
            return p
    hits = glob.glob(f"{cache}/{appid}/**/{kind}*.jpg", recursive=True)
    return hits[0] if hits else f"{STEAM_CDN}/{appid}/{kind}.jpg"


def steam():
    root = next((r for r in STEAM_ROOTS if os.path.isdir(f"{r}/steamapps")), None)
    libs = set()
    if root:
        libs.add(os.path.realpath(f"{root}/steamapps"))
        try:
            vdf = open(f"{root}/steamapps/libraryfolders.vdf", encoding="utf-8", errors="replace").read()
            for p in re.findall(r'"path"\s+"([^"]+)"', vdf):
                libs.add(os.path.realpath(f"{p}/steamapps"))
        except OSError:
            pass
    for extra in ("/mnt/games/SteamLibrary/steamapps", "/mnt/games/steamapps"):
        if os.path.isdir(extra):
            libs.add(os.path.realpath(extra))

    seen = set()
    for lib in sorted(libs):
        for acf in glob.glob(f"{lib}/appmanifest_*.acf"):
            try:
                text = open(acf, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            appid, name = acf_value(text, "appid"), acf_value(text, "name")
            flags = int(acf_value(text, "StateFlags") or 0)
            if not appid or appid in seen or not name or STEAM_SKIP.search(name) or not flags & 4:
                continue
            seen.add(appid)
            games.append({
                "id": f"steam:{appid}",
                "title": name,
                "source": "Steam",
                "launch": ["steam", f"steam://rungameid/{appid}"],
                "cover": steam_art(root or "", appid, "library_600x900"),
                "hero": steam_art(root or "", appid, "library_hero"),
                "lastPlayed": int(acf_value(text, "LastPlayed") or 0),
            })


# ── Heroic (Epic / GOG / sideload) ──────────────────────────────────────────
HEROIC = next((d for d in (f"{HOME}/.config/heroic", f"{HOME}/.var/app/com.heroicgameslauncher.hgl/config/heroic")
               if os.path.isdir(d)), None)


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def heroic_entry(runner, app, title, art):
    games.append({
        "id": f"heroic:{runner}:{app}",
        "title": title,
        "source": {"legendary": "Epic", "gog": "GOG", "sideload": "Heroic"}.get(runner, "Heroic"),
        "launch": ["xdg-open", f"heroic://launch/{runner}/{app}"],
        "cover": (art or {}).get("art_square") or "",
        "hero": (art or {}).get("art_cover") or "",
        "lastPlayed": 0,
    })


def heroic():
    if not HEROIC:
        return
    epic_art = {g.get("app_name"): g for g in ((load(f"{HEROIC}/store_cache/legendary_library.json") or {}).get("library") or [])}
    for app, info in (load(f"{HEROIC}/legendaryConfig/legendary/installed.json") or {}).items():
        heroic_entry("legendary", app, info.get("title") or app, epic_art.get(app))

    gog_art = {g.get("app_name"): g for g in ((load(f"{HEROIC}/store_cache/gog_library.json") or {}).get("games") or [])}
    for g in (load(f"{HEROIC}/gog_store/installed.json") or {}).get("installed") or []:
        app = g.get("appName")
        if app:
            art = gog_art.get(app) or {}
            heroic_entry("gog", app, art.get("title") or app, art)

    for g in (load(f"{HEROIC}/sideload_apps/library.json") or {}).get("games") or []:
        if g.get("is_installed") and g.get("app_name"):
            heroic_entry("sideload", g["app_name"], g.get("title") or g["app_name"], g)


# ── Lutris ──────────────────────────────────────────────────────────────────
def lutris():
    db = f"{HOME}/.local/share/lutris/pga.db"
    if not os.path.isfile(db):
        return
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        rows = con.execute("SELECT name, slug, lastplayed FROM games WHERE installed = 1").fetchall()
        con.close()
    except sqlite3.Error:
        return
    for name, slug, last in rows:
        cover = next((p for p in (f"{HOME}/.local/share/lutris/coverart/{slug}.jpg",
                                  f"{HOME}/.cache/lutris/coverart/{slug}.jpg") if os.path.isfile(p)), "")
        games.append({
            "id": f"lutris:{slug}",
            "title": name,
            "source": "Lutris",
            "launch": ["lutris", f"lutris:rungame/{slug}"],
            "cover": cover,
            "hero": "",
            "lastPlayed": int(last or 0),
        })


# ── Hand-written list ───────────────────────────────────────────────────────
def manual():
    for i, g in enumerate(load(f"{HOME}/.config/atelier/games.json") or []):
        if isinstance(g, dict) and g.get("title") and g.get("command"):
            games.append({
                "id": f"manual:{i}",
                "title": g["title"],
                "source": g.get("source") or "Other",
                "launch": ["sh", "-c", g["command"]],
                "cover": os.path.expanduser(g.get("cover") or ""),
                "hero": os.path.expanduser(g.get("hero") or ""),
                "lastPlayed": 0,
            })


for fn in (steam, heroic, lutris, manual):
    try:
        fn()
    except Exception as e:  # one broken source must not hide the others
        print(f"games.py: {fn.__name__}: {e}", file=sys.stderr)

games.sort(key=lambda g: (-g["lastPlayed"], g["title"].lower()))


# ── Artwork cache ───────────────────────────────────────────────────────────
# Qt's Image can't fetch https inside Quickshell, so remote art is downloaded once into
# ~/.cache/atelier/game-art and served from disk. A ".miss" marker stops retrying 404s.
# Plain run: swap URLs for cached files ("" while not downloaded yet).
# --fetch:   download whatever is missing (the overlay runs this in the background, then rescans).
CACHE = f"{HOME}/.cache/atelier/game-art"
pending = []
for g in games:
    for kind in ("cover", "hero"):
        url = g[kind]
        if not url.startswith("http"):
            continue
        path = f"{CACHE}/{re.sub(r'[^A-Za-z0-9_.-]', '_', g['id'])}_{kind}.jpg"
        if os.path.isfile(path):
            g[kind] = path
        else:
            g[kind] = ""
            if not os.path.exists(path + ".miss"):
                pending.append((url, path))

if "--fetch" in sys.argv:
    import concurrent.futures
    import urllib.request

    def fetch(job):
        url, path = job
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "atelier-games/1"})
            with urllib.request.urlopen(req, timeout=15) as r:
                data = r.read()
            with open(path + ".part", "wb") as f:
                f.write(data)
            os.replace(path + ".part", path)
        except Exception:
            open(path + ".miss", "w").close()

    os.makedirs(CACHE, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(8) as pool:
        list(pool.map(fetch, pending))
    print(len(pending))
else:
    json.dump({"games": games, "pending": len(pending)}, sys.stdout)
