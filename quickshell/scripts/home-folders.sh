#!/usr/bin/env bash
# usage: home-folders.sh [check]
#
# The usual home folders, created if missing (nothing is moved or deleted):
#   Desktop Documents Downloads Music Pictures Videos Projects Templates Public
#   Pictures/Screenshots   screenshots (Print key)
#   Pictures/Wallpapers    your wallpapers: they show up in the wallpaper picker
#   Videos/Recordings      screen recordings
# Also registers them with xdg-user-dirs (apps' "Save" dialogs) and adds them to the file
# manager sidebar (~/.config/gtk-3.0/bookmarks: Nautilus and GTK file pickers).
# `check` only prints one line per folder: "<path>|<exists 0/1>".
FOLDERS=(Desktop Documents Downloads Music Pictures Videos Projects Templates Public
         Pictures/Screenshots Pictures/Wallpapers Videos/Recordings)

if [ "${1:-}" = check ]; then
    for f in "${FOLDERS[@]}"; do [ -d "$HOME/$f" ] && echo "$f|1" || echo "$f|0"; done
    exit 0
fi

for f in "${FOLDERS[@]}"; do mkdir -p "$HOME/$f" && echo "ok $f"; done

# xdg-user-dirs: keep the user's own entries, make sure Projects is listed
if command -v xdg-user-dirs-update >/dev/null 2>&1; then
    xdg-user-dirs-update
    xdg-user-dirs-update --set PROJECTS "$HOME/Projects" 2>/dev/null || true
fi

# file manager sidebar
bm="$HOME/.config/gtk-3.0/bookmarks"
mkdir -p "$(dirname "$bm")"
touch "$bm"
for f in Documents Downloads Pictures Videos Music Projects Pictures/Wallpapers; do
    uri="file://$HOME/$f"
    grep -q "^$uri\( \|$\)" "$bm" || echo "$uri ${f##*/}" >> "$bm"
done
echo "bookmarks ok"
