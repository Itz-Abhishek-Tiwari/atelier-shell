#!/usr/bin/env python3
import os
import sys
import json
import glob
import time
import urllib.request
import urllib.parse
import urllib.error
import subprocess
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

WALL_DIR = Path.home() / ".config/hypr/wall"
# your own wallpapers: anything dropped here shows up in the picker too
USER_WALL_DIR = Path.home() / "Pictures/Wallpapers"
THUMB_DIR = Path.home() / ".cache/wallhaven/thumbs"
CURRENT_WALL_FILE = Path.home() / ".cache/current_wallpaper"
LOCAL_THUMB_DIR = Path.home() / ".cache/atelier/wall-thumbs"
THUMB_SIZE = (480, 270)

WALL_DIR.mkdir(parents=True, exist_ok=True)
THUMB_DIR.mkdir(parents=True, exist_ok=True)
LOCAL_THUMB_DIR.mkdir(parents=True, exist_ok=True)

def set_wallpaper(path):
    # The shell renders the wallpaper itself (Background.qml) and watches this file,
    # so applying is just recording the choice.
    try:
        CURRENT_WALL_FILE.write_text(str(path))
        print(json.dumps({"status": "success", "path": str(path)}))
    except Exception as e:
        print(json.dumps({"status": "error", "message": str(e)}))

def make_thumb(p):
    """Small cover-cropped JPEG, cached by name + mtime. Falls back to the original."""
    try:
        st = p.stat()
        dest = LOCAL_THUMB_DIR / f"{p.stem}-{int(st.st_mtime)}.jpg"
        if dest.exists():
            return str(dest)
        from PIL import Image, ImageOps
        with Image.open(p) as im:
            im.draft("RGB", (THUMB_SIZE[0] * 2, THUMB_SIZE[1] * 2))   # fast JPEG downscale-on-decode
            im = ImageOps.fit(im.convert("RGB"), THUMB_SIZE, Image.LANCZOS)
            tmp = dest.with_suffix(".tmp")
            im.save(tmp, "JPEG", quality=85, optimize=True)
            tmp.replace(dest)
        return str(dest)
    except Exception:
        return str(p.resolve())

def list_local():
    valid_exts = {".jpg", ".jpeg", ".png", ".webp"}
    current = ""
    if CURRENT_WALL_FILE.exists():
        try:
            current = CURRENT_WALL_FILE.read_text().strip()
        except Exception:
            pass

    paths = []
    for d in (WALL_DIR, USER_WALL_DIR):
        if d.is_dir():
            paths += [p for p in sorted(d.iterdir()) if p.is_file() and p.suffix.lower() in valid_exts]
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        thumbs = list(ex.map(make_thumb, paths))
    files = []
    for p, thumb in zip(paths, thumbs):
        full = str(p.resolve())
        files.append({
            "id": p.stem,
            "name": p.name,
            "path": full,
            "thumb": thumb,
            "is_current": full == current
        })
    print(json.dumps(files))

# ── Wallhaven ────────────────────────────────────────────────────────────────
# Safe for work ONLY, enforced here (not just in the UI):
#   purity=100      Wallhaven's SFW rating, on every request
#   categories      General, optionally Anime; never People
#   EXCLUDE         tags added to every query as "-tag"
#   atleast/ratios  desktop-sized, desktop-shaped results
API = "https://wallhaven.cc/api/v1/search"
UA = {"User-Agent": "atelier-shell"}
FULL_DIR = Path.home() / ".cache/wallhaven/full"
FULL_DIR.mkdir(parents=True, exist_ok=True)
SEARCH_DIR = Path.home() / ".cache/wallhaven/search"
SEARCH_DIR.mkdir(parents=True, exist_ok=True)
EXCLUDE = ["bikini", "swimsuit", "swimwear", "lingerie", "underwear", "panties", "cleavage",
           "nude", "ecchi", "feet", "pantyhose", "stockings", "sexy", "blood", "gore", "weapon"]
SORTINGS = {"toplist", "hot", "date_added", "random", "relevance", "favorites", "views"}


def describe(item):
    """One result for the picker. The thumbnail is Wallhaven's own URL (the picker loads it
    while you look), so a search returns in about a second instead of after 24 downloads."""
    wid = item.get("id")
    thumbs = item.get("thumbs", {})
    thumb = thumbs.get("original") or thumbs.get("large") or thumbs.get("small")
    if not wid or not thumb:
        return None
    ext = Path(item.get("path", "")).suffix or ".jpg"
    cached = FULL_DIR / f"{wid}{ext}"
    owned = WALL_DIR / f"wallhaven-{wid}{ext}"
    return {
        "id": wid,
        "name": f"wallhaven-{wid}",
        "thumb": thumb,
        "full_url": item.get("path", ""),
        "page_url": item.get("url", ""),
        "resolution": item.get("resolution", ""),
        "favorites": item.get("favorites", 0),
        "views": item.get("views", 0),
        "file_size": item.get("file_size", 0),
        "colors": item.get("colors", [])[:5],
        "category": item.get("category", ""),
        "full": str(owned) if owned.exists() else (str(cached) if cached.exists() else ""),
        "owned": owned.exists(),
    }


def search_wallhaven(args):
    """search_wallhaven [q=..] [sorting=..] [color=rrggbb] [page=N] [anime=0|1] [seed=..]"""
    opt = dict(a.split("=", 1) for a in args if "=" in a)
    q = opt.get("q", "").strip()
    sorting = opt.get("sorting", "") or ("relevance" if q else "toplist")
    if sorting not in SORTINGS:
        sorting = "toplist"
    params = {
        "purity": "100",                                         # SFW only, always
        "categories": "110" if opt.get("anime") == "1" else "100",   # general (+ anime), never people
        "sorting": sorting,
        "order": "desc",
        "atleast": "1920x1080",
        "ratios": "16x9,16x10,21x9",
        "page": str(max(1, int(opt.get("page", "1") or 1))),
        "q": " ".join(([q] if q else []) + ["-" + t for t in EXCLUDE]),
    }
    if sorting == "toplist":
        params["topRange"] = "1M"
    if sorting == "random":
        params["seed"] = opt.get("seed") or "".join(__import__("random").choices("abcdefghijklmnopqrstuvwxyz0123456789", k=6))
    color = opt.get("color", "").lstrip("#")
    if color:
        params["colors"] = color
    out = {"items": [], "page": int(params["page"]), "last_page": 1, "seed": params.get("seed", "")}
    # Wallhaven takes 1-7 s to answer; remember each search for 30 min (random is always fresh)
    import hashlib
    key = hashlib.sha1(urllib.parse.urlencode(sorted(params.items())).encode()).hexdigest()[:16]
    cache = SEARCH_DIR / f"{key}.json"
    if sorting != "random" and cache.exists() and time.time() - cache.stat().st_mtime < 1800:
        try:
            cached = json.loads(cache.read_text())
            for it in cached["items"]:             # refresh "already downloaded" marks
                ext = Path(it["full_url"]).suffix or ".jpg"
                owned = WALL_DIR / f"wallhaven-{it['id']}{ext}"
                full = FULL_DIR / f"{it['id']}{ext}"
                it["owned"] = owned.exists()
                it["full"] = str(owned) if owned.exists() else (str(full) if full.exists() else "")
            print(json.dumps(cached))
            return
        except Exception:
            pass
    data, kind, msg = None, "", ""
    url = API + "?" + urllib.parse.urlencode(params)
    for attempt in range(2):                       # one retry: Wallhaven is often just slow
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as e:
            kind, msg = ("rate", "Too many searches, wait a few seconds") if e.code == 429 else ("http", f"Wallhaven error {e.code}")
            if e.code == 429 or e.code >= 500:
                time.sleep(min(10, int(e.headers.get("Retry-After") or 3)))
                continue
            break
        except (TimeoutError, __import__("socket").timeout):
            kind, msg = "timeout", "Wallhaven is slow right now"
        except urllib.error.URLError as e:
            if isinstance(e.reason, (TimeoutError, __import__("socket").timeout)):
                kind, msg = "timeout", "Wallhaven is slow right now"
            else:
                kind, msg = "offline", "You seem to be offline"
                break
        except Exception as e:
            kind, msg = "http", str(e)[:120]
            break
    if data is not None:
        raw = [r for r in data.get("data", []) if r.get("purity") == "sfw" and r.get("category") != "people"]
        out["items"] = [r for r in map(describe, raw) if r]
        out["last_page"] = data.get("meta", {}).get("last_page", 1)
        if sorting != "random" and out["items"]:
            cache.write_text(json.dumps(out))
    else:
        # failed: show the last saved results for this search, however old, rather than nothing
        if cache.exists():
            try:
                out = json.loads(cache.read_text())
                out["stale"] = True
            except Exception:
                pass
        out["error"] = msg or "Couldn't reach Wallhaven"
        out["error_kind"] = kind or "http"
    print(json.dumps(out))


def fetch(url, dest):
    """Stream url to dest, printing 'P <fraction>' progress lines; no overall time limit."""
    tmp = dest.with_suffix(dest.suffix + ".part")
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as resp:
        total = int(resp.headers.get("Content-Length") or 0)
        got, last = 0, -1
        with open(tmp, "wb") as f:
            while True:
                chunk = resp.read(65536)
                if not chunk:
                    break
                f.write(chunk)
                got += len(chunk)
                if total:
                    pct = int(got * 100 / total)
                    if pct != last:
                        last = pct
                        print(f"P {pct / 100:.2f}", flush=True)
    tmp.replace(dest)


def prefetch(wid, full_url):
    """Fetch the full image into the cache (sharp preview, instant apply)."""
    ext = Path(full_url).suffix or ".jpg"
    owned = WALL_DIR / f"wallhaven-{wid}{ext}"
    dest = FULL_DIR / f"{wid}{ext}"
    try:
        if owned.exists():
            dest = owned
        elif not dest.exists():
            fetch(full_url, dest)
        print(json.dumps({"status": "success", "id": wid, "path": str(dest.resolve())}), flush=True)
    except Exception as e:
        print(json.dumps({"status": "error", "id": wid, "message": str(e)[:120]}), flush=True)


def download(wid, full_url):
    """Keep it: move the cached full image (or download it) into the wallpaper folder."""
    ext = Path(full_url).suffix or ".jpg"
    dest = WALL_DIR / f"wallhaven-{wid}{ext}"
    cached = FULL_DIR / f"{wid}{ext}"
    try:
        if not dest.exists():
            if cached.exists():
                cached.replace(dest)
            else:
                fetch(full_url, dest)
        print(json.dumps({"status": "success", "path": str(dest.resolve())}), flush=True)
    except Exception as e:
        print(json.dumps({"status": "error", "message": str(e)[:120]}), flush=True)


def main():
    if len(sys.argv) < 2:
        print("Usage: wallpaper_service.py list_local | set_wallpaper <path> | "
              "search_wallhaven [q=] [sorting=] [color=] [page=] [anime=0|1] [seed=] | "
              "prefetch <id> <url> | download <id> <url>")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "list_local":
        list_local()
    elif cmd == "search_wallhaven":
        search_wallhaven(sys.argv[2:])
    elif cmd == "set_wallpaper" and len(sys.argv) > 2:
        set_wallpaper(sys.argv[2])
    elif cmd == "prefetch" and len(sys.argv) > 3:
        prefetch(sys.argv[2], sys.argv[3])
    elif cmd in ("download", "download_and_set") and len(sys.argv) > 3:
        download(sys.argv[2], sys.argv[3])


if __name__ == "__main__":
    main()
