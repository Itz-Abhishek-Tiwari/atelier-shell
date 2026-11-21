#!/usr/bin/env python3
"""Emoji data for the Atelier emoji picker (modules/drawers/EmojiOverlay.qml).

    emoji.py data     print the emoji list as JSON (built once, then cached)

Source: Unicode's emoji-test.txt (every fully-qualified emoji, in the standard order and
groups) plus CLDR's English annotations for search keywords ("lol" finds 😂). Both are
downloaded once into ~/.cache/atelier/emoji/; without a network the picker still works with
whatever was cached (or with names only if the keywords are missing).

Output: {"groups": [names...], "items": [{"e": "😀", "n": "grinning face", "g": 0,
          "k": "face grin smile", "t": ["👋🏻", ... 5 skin tones] (only when it has them)}]}
"""
import json
import os
import re
import sys
import urllib.request

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "atelier", "emoji")
TEST_URL = "https://unicode.org/Public/emoji/latest/emoji-test.txt"
CLDR_URL = ("https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/"
            "cldr-annotations-full/annotations/en/annotations.json")
OUT = os.path.join(CACHE, "emoji.json")
VERSION = 2          # bump when the output format changes

TONES = ["light skin tone", "medium-light skin tone", "medium skin tone",
         "medium-dark skin tone", "dark skin tone"]
# groups as Unicode names them → shorter labels for the tabs
GROUP_LABEL = {
    "Smileys & Emotion": "Smileys", "People & Body": "People", "Animals & Nature": "Nature",
    "Food & Drink": "Food", "Travel & Places": "Travel", "Activities": "Activities",
    "Objects": "Objects", "Symbols": "Symbols", "Flags": "Flags",
}


def fetch(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return True
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "atelier-emoji/1"})
        with urllib.request.urlopen(req, timeout=20) as r:
            data = r.read()
        tmp = path + ".part"
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, path)
        return True
    except Exception as e:  # offline: use what we have
        print(f"emoji.py: could not download {url}: {e}", file=sys.stderr)
        return False


def keywords():
    path = os.path.join(CACHE, "annotations-en.json")
    if not fetch(CLDR_URL, path):
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            ann = json.load(f)["annotations"]["annotations"]
    except Exception:
        return {}
    return {e: " ".join(v.get("default", [])) for e, v in ann.items()}


def build():
    test = os.path.join(CACHE, "emoji-test.txt")
    if not fetch(TEST_URL, test):
        return None
    kw = keywords()
    groups, items, by_name = [], [], {}
    group = None
    line_re = re.compile(r"^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*(\S+)\s+E[\d.]+\s+(.+)$")
    with open(test, encoding="utf-8") as f:
        for line in f:
            if line.startswith("# group:"):
                name = line.split(":", 1)[1].strip()
                group = None if name == "Component" else name
                if group:
                    groups.append(GROUP_LABEL.get(group, group))
                continue
            if group is None:
                continue
            m = line_re.match(line.strip())
            if not m:
                continue
            emoji, name = m.group(2), m.group(3)
            if ": " in name:
                base, mods = name.split(": ", 1)
                # single skin-tone variants attach to their base emoji; skip mixed-tone combos
                if mods in TONES and base in by_name:
                    by_name[base].setdefault("t", [None] * 5)[TONES.index(mods)] = emoji
                    continue
                if any(t in mods for t in TONES):
                    continue
            k = kw.get(emoji) or kw.get(emoji.replace("️", ""), "")
            item = {"e": emoji, "n": name, "g": len(groups) - 1}
            if k:
                item["k"] = k
            items.append(item)
            by_name[name] = item
    for it in items:            # keep only complete tone sets
        if "t" in it and None in it["t"]:
            del it["t"]
    return {"v": VERSION, "groups": groups, "items": items}


def main():
    if len(sys.argv) < 2 or sys.argv[1] != "data":
        print(__doc__.strip(), file=sys.stderr)
        return 2
    os.makedirs(CACHE, exist_ok=True)
    try:
        with open(OUT, encoding="utf-8") as f:
            data = json.load(f)
        if data.get("v") == VERSION and data.get("items"):
            sys.stdout.write(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
            return 0
    except Exception:
        pass
    data = build()
    if not data:
        print('{"groups":[],"items":[],"error":"offline"}')
        return 1
    text = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    with open(OUT + ".part", "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(OUT + ".part", OUT)
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
