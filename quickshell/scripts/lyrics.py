#!/usr/bin/env python3
"""Lyrics for the music drawer, from lrclib.net (free, no account).

    lyrics.py <artist> <title> <album> <duration-seconds>

Prints JSON: {"synced": [[seconds, "line"], ...]} for time-synced lyrics,
{"plain": "text"} when only plain lyrics exist, {"instrumental": true}, or {"none": true}.
Results (including misses) are cached in ~/.cache/atelier/lyrics/ so a song is fetched once.
Only the track's artist / title / album / duration are sent.
"""
import hashlib
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

CACHE = Path.home() / ".cache/atelier/lyrics"
API = "https://lrclib.net/api"
UA = {"User-Agent": "atelier-shell (https://github.com/quickshell-atelier)"}
TS = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")


def get(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=8) as r:
            return json.loads(r.read().decode())
    except Exception:
        return None


def parse_lrc(text):
    out = []
    for raw in text.splitlines():
        stamps = TS.findall(raw)
        line = TS.sub("", raw).strip()
        for m, s in stamps:
            out.append([round(int(m) * 60 + float(s), 2), line])
    out.sort(key=lambda x: x[0])
    return out


def shape(rec):
    if not rec:
        return {"none": True}
    if rec.get("instrumental"):
        return {"instrumental": True}
    if rec.get("syncedLyrics"):
        lines = parse_lrc(rec["syncedLyrics"])
        if lines:
            return {"synced": lines}
    if rec.get("plainLyrics"):
        return {"plain": rec["plainLyrics"].strip()}
    return {"none": True}


def clean(title):
    # "Song (Official Video)" / "Song - Remastered 2011" → "Song"
    t = re.sub(r"\s*[\(\[][^)\]]*(official|video|audio|lyric|remaster|visualizer|hd|4k)[^)\]]*[\)\]]", "", title, flags=re.I)
    t = re.sub(r"\s+-\s+(remaster|live|mono|stereo).*$", "", t, flags=re.I)
    return t.strip() or title


def main():
    artist, title, album = (a.strip() for a in sys.argv[1:4])
    try:
        duration = round(float(sys.argv[4]))
    except (IndexError, ValueError):
        duration = 0
    if not title:
        print(json.dumps({"none": True}))
        return
    CACHE.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha1(f"{artist}\n{title}\n{album}\n{duration}".encode()).hexdigest()
    cached = CACHE / f"{key}.json"
    if cached.exists():
        print(cached.read_text())
        return

    title = clean(title)
    rec = None
    if artist and duration:
        q = {"artist_name": artist, "track_name": title, "duration": duration}
        if album:
            q["album_name"] = album
        rec = get(f"{API}/get?" + urllib.parse.urlencode(q))
        if rec and rec.get("statusCode"):
            rec = None
    if not rec:
        found = get(f"{API}/search?" + urllib.parse.urlencode({"q": f"{artist} {title}".strip()})) or []
        # prefer synced results with a close duration
        def score(r):
            d = abs((r.get("duration") or 0) - duration) if duration else 0
            return (0 if r.get("syncedLyrics") else 1, d)
        found = [r for r in found if isinstance(r, dict)]
        if found:
            best = min(found, key=score)
            if not duration or abs((best.get("duration") or 0) - duration) <= 8:
                rec = best

    result = json.dumps(shape(rec), ensure_ascii=False)
    cached.write_text(result)
    print(result)


if __name__ == "__main__":
    main()
