#!/usr/bin/env python3
"""GIF search for the Atelier GIF finder (modules/drawers/EmojiOverlay.qml, "GIFs" tab).

    gifs.py trending              popular GIFs right now
    gifs.py search <words>        search
    gifs.py fetch <url>           download a GIF into the cache, print its path (for copying the file)

Provider and key come from the environment (never argv, so the key does not show in `ps`):
    ATELIER_GIF_PROVIDER = giphy | tenor
    ATELIER_GIF_KEY      = the API key (free: developers.giphy.com / Google Cloud "Tenor API")

Safe search is always on (GIPHY rating "pg", Tenor contentfilter "medium").
Searches are cached for 30 minutes in ~/.cache/atelier/gifs/.

Output (search/trending): one JSON object
    {"items": [{"id", "title", "still", "preview", "gif", "url", "w", "h"}], "error": ""}
  still   = small still image for the grid      preview = small animated GIF (on hover)
  gif     = the full GIF (copied as a file)     url     = share link (embeds in chat apps)
"""
import hashlib
import json
import os
import sys
import time
import urllib.parse
import urllib.request

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "atelier", "gifs")
TTL = 30 * 60
LIMIT = 36
UA = {"User-Agent": "atelier-gifs/1"}


def get_json(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)


def giphy(kind, q, key):
    base = "https://api.giphy.com/v1/gifs/"
    params = {"api_key": key, "limit": LIMIT, "rating": "pg", "bundle": "messaging_non_clips"}
    if kind == "search":
        params["q"] = q
    data = get_json(base + ("search" if kind == "search" else "trending") + "?" + urllib.parse.urlencode(params))
    out = []
    for g in data.get("data", []):
        im = g.get("images", {})
        small = im.get("fixed_width_small") or im.get("fixed_width") or {}
        still = im.get("fixed_width_small_still") or im.get("fixed_width_still") or {}
        full = im.get("downsized") or im.get("original") or {}
        if not small.get("url"):
            continue
        out.append({
            "id": g.get("id", ""), "title": g.get("title", ""),
            "still": still.get("url", small["url"]), "preview": small["url"],
            "gif": full.get("url", small["url"]), "url": g.get("url") or full.get("url", ""),
            "w": int(small.get("width") or 100), "h": int(small.get("height") or 100),
        })
    return out


def tenor(kind, q, key):
    base = "https://tenor.googleapis.com/v2/"
    params = {"key": key, "client_key": "atelier", "limit": LIMIT, "contentfilter": "medium",
              "media_filter": "gif,tinygif,nanogifpreview,gifpreview"}
    if kind == "search":
        params["q"] = q
    data = get_json(base + ("search" if kind == "search" else "featured") + "?" + urllib.parse.urlencode(params))
    out = []
    for g in data.get("results", []):
        m = g.get("media_formats", {})
        tiny = m.get("tinygif") or m.get("gif") or {}
        still = m.get("nanogifpreview") or m.get("gifpreview") or tiny
        full = m.get("gif") or tiny
        if not tiny.get("url"):
            continue
        dims = tiny.get("dims") or [100, 100]
        out.append({
            "id": g.get("id", ""), "title": g.get("content_description", ""),
            "still": still.get("url", tiny["url"]), "preview": tiny["url"],
            "gif": full.get("url", tiny["url"]), "url": g.get("itemurl") or full.get("url", ""),
            "w": int(dims[0] or 100), "h": int(dims[1] or 100),
        })
    return out


def listing(kind, q):
    provider = os.environ.get("ATELIER_GIF_PROVIDER", "giphy").strip().lower()
    key = os.environ.get("ATELIER_GIF_KEY", "").strip()
    if not key:
        return {"items": [], "error": "nokey"}
    os.makedirs(CACHE, exist_ok=True)
    tag = hashlib.sha1(f"{provider}|{kind}|{q.lower()}".encode()).hexdigest()[:16]
    path = os.path.join(CACHE, f"q-{tag}.json")
    try:
        if time.time() - os.path.getmtime(path) < TTL:
            with open(path, encoding="utf-8") as f:
                return {"items": json.load(f), "error": ""}
    except Exception:
        pass
    try:
        items = (tenor if provider == "tenor" else giphy)(kind, q, key)
    except urllib.error.HTTPError as e:
        return {"items": [], "error": "badkey" if e.code in (400, 401, 403) else f"HTTP {e.code}"}
    except Exception as e:
        return {"items": [], "error": "offline" if isinstance(e, urllib.error.URLError) else str(e)}
    with open(path + ".part", "w", encoding="utf-8") as f:
        json.dump(items, f)
    os.replace(path + ".part", path)
    return {"items": items, "error": ""}


def fetch(url):
    if not url.startswith("https://"):
        return 1
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, "gif-" + hashlib.sha1(url.encode()).hexdigest()[:16] + ".gif")
    if not (os.path.exists(path) and os.path.getsize(path) > 0):
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=30) as r, open(path + ".part", "wb") as f:
            while chunk := r.read(65536):
                f.write(chunk)
        os.replace(path + ".part", path)
    # keep the cache small: drop downloaded GIFs older than a week
    now = time.time()
    for name in os.listdir(CACHE):
        p = os.path.join(CACHE, name)
        if name.startswith("gif-") and now - os.path.getmtime(p) > 7 * 86400:
            try:
                os.remove(p)
            except OSError:
                pass
    print(path)
    return 0


def main():
    a = sys.argv[1:]
    if a[:1] == ["trending"]:
        print(json.dumps(listing("trending", "")))
    elif a[:1] == ["search"] and len(a) > 1:
        print(json.dumps(listing("search", " ".join(a[1:]).strip())))
    elif a[:1] == ["fetch"] and len(a) == 2:
        return fetch(a[1])
    else:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
