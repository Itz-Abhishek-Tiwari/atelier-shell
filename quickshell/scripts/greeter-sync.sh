#!/usr/bin/env bash
# usage: greeter-sync.sh [data dir]      (default /var/lib/atelier-greeter)
#
# Copies what the login screen shows from your $HOME into its data folder (the greeter runs as
# the `greeter` user and cannot read $HOME). greeter/install.sh makes that folder yours, so this
# needs no root. Called by Settings → Login screen (automatically when the theme or wallpaper
# changes) and by greeter/install.sh.
#   colors.json     <- ~/.config/atelier/theme.json
#   wallpaper.jpg   <- the current wallpaper, scaled to 1920px (skipped when unchanged)
#   faces/$USER     <- ~/.face
#   lock.json       <- your lock-screen options (the login screen uses the same style)
#   fonts/          <- SpaceMono Nerd Font Propo (the shell's clock font), once
# Prints one line per item; exits 1 if the folder isn't writable.
set -u
DATA="${1:-/var/lib/atelier-greeter}"
[ -d "$DATA" ] && [ -w "$DATA" ] || { echo "not-writable $DATA"; exit 1; }
mkdir -p "$DATA/faces" "$DATA/fonts"

# write via a temp file + rename, so the greeter never reads half a file
put() { # put <src> <dest>
    local tmp="$2.tmp.$$"
    command cp -f "$1" "$tmp" && chmod 644 "$tmp" && command mv -f "$tmp" "$2"
}

theme="$HOME/.config/atelier/theme.json"
if [ -f "$theme" ]; then put "$theme" "$DATA/colors.json" && echo "colors ok"; else echo "colors missing"; fi

wp=""
cur="$HOME/.cache/current_wallpaper"
if [ -f "$cur" ]; then
    if file -b --mime-type "$cur" | grep -q '^image/'; then wp="$cur"; else wp="$(head -n1 "$cur")"; fi
fi
if [ -n "$wp" ] && [ -f "$wp" ]; then
    stamp="$(readlink -f "$wp")|$(stat -c %Y "$wp")"
    if [ -f "$DATA/wallpaper.jpg" ] && [ "$(cat "$DATA/.wallpaper-src" 2>/dev/null)" = "$stamp" ]; then
        echo "wallpaper unchanged"
    else
        tmp="$DATA/wallpaper.tmp.$$.jpg"
        if command -v ffmpeg >/dev/null 2>&1 \
            && ffmpeg -loglevel error -y -i "$wp" -vf "scale='min(1920,iw)':-2" -q:v 3 -frames:v 1 "$tmp" 2>/dev/null; then
            :
        elif command -v magick >/dev/null 2>&1 && magick "${wp}[0]" -resize '1920x>' -quality 90 "$tmp" 2>/dev/null; then
            :
        else
            command cp -f "$wp" "$tmp"
        fi
        chmod 644 "$tmp" && command mv -f "$tmp" "$DATA/wallpaper.jpg"
        printf '%s' "$stamp" > "$DATA/.wallpaper-src"
        echo "wallpaper ok"
    fi
else
    echo "wallpaper missing"
fi

# your lock-screen look: the login screen uses the same style with the same options
settings="$HOME/.config/atelier/settings.json"
if [ -f "$settings" ] && python3 -I - "$settings" "$DATA/lock.json.tmp.$$" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
keep = {
    "lock": s.get("lock", {}), "lockStyle": s.get("lockStyle", {}),
    "notifications": {"lockShowCount": s.get("notifications", {}).get("lockShowCount", True)},
    "widgets": {k: s.get("widgets", {}).get(k, d) for k, d in (("weatherLocation", ""), ("weatherUnits", "metric"))},
    "general": {k: s.get("general", {}).get(k, d) for k, d in (("clock24", False), ("animSpeed", 1))},
    "appearance": {"rounding": s.get("appearance", {}).get("rounding", 24)},
}
json.dump(keep, open(sys.argv[2], "w"), indent=1)
PY
then chmod 644 "$DATA/lock.json.tmp.$$" && command mv -f "$DATA/lock.json.tmp.$$" "$DATA/lock.json" && echo "lock ok"
else command rm -f "$DATA/lock.json.tmp.$$"; echo "lock missing"; fi

face="$HOME/.face"
[ -f "$HOME/.face.icon" ] && [ ! -f "$face" ] && face="$HOME/.face.icon"
if [ -f "$face" ]; then put "$face" "$DATA/faces/$USER" && echo "face ok"
else command rm -f "$DATA/faces/$USER"; echo "face none"; fi

if [ ! -f "$DATA/fonts/mono-regular.ttf" ] || [ ! -f "$DATA/fonts/mono-bold.ttf" ]; then
    reg="$(fc-list : file family | grep -m1 'SpaceMonoNerdFontPropo-Regular' | cut -d: -f1)"
    bold="$(fc-list : file family | grep -m1 'SpaceMonoNerdFontPropo-Bold\.' | cut -d: -f1)"
    [ -n "$reg" ] && put "$reg" "$DATA/fonts/mono-regular.ttf"
    [ -n "$bold" ] && put "$bold" "$DATA/fonts/mono-bold.ttf"
    [ -n "$reg" ] && echo "fonts ok" || echo "fonts missing"
fi
date +%s > "$DATA/.synced"
