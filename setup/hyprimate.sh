#!/usr/bin/env bash
# Build the hyprimate Hyprland plugin (https://github.com/JustinBacher/hyprimate) for Showcase mode.
# Builds from source against the installed Hyprland headers (no hyprpm needed) and installs
# ~/.local/lib/atelier/hyprimate.so. It is NOT loaded here: only Showcase mode loads it.
# Rerun after every Hyprland update (the plugin must match the running build).
#
#   setup/hyprimate.sh            build + install
#   setup/hyprimate.sh --remove   delete the plugin and its sources
set -euo pipefail

SRC="${XDG_CACHE_HOME:-$HOME/.cache}/atelier/hyprimate"
OUT="$HOME/.local/lib/atelier/hyprimate.so"

if [ "${1:-}" = "--remove" ]; then
    hyprctl plugin unload "$OUT" 2>/dev/null || true
    rm -rf "$SRC" "$OUT"; echo "hyprimate removed"; exit 0
fi

for t in git cmake ninja pkg-config; do
    command -v "$t" >/dev/null || { echo "missing: $t (pacman -S cmake ninja pkgconf git)"; exit 1; }
done
[ -f /usr/include/nlohmann/json.hpp ] || { echo "missing: nlohmann-json (sudo pacman -S nlohmann-json)"; exit 1; }
pkg-config --exists hyprland || { echo "missing Hyprland development headers (pkg-config hyprland)"; exit 1; }

if [ -d "$SRC/.git" ]; then
    git -C "$SRC" reset -q --hard; git -C "$SRC" clean -qfd -e build; git -C "$SRC" pull --ff-only
else
    mkdir -p "$(dirname "$SRC")"; git clone --depth 1 https://github.com/JustinBacher/hyprimate "$SRC"
fi
# Atelier patch: the burn style's fire takes the desktop theme's colours (reads
# ~/.config/atelier/theme.json when the plugin loads) instead of fixed orange.
git -C "$SRC" apply "$(dirname "$(readlink -f "$0")")/hyprimate-theme-burn.patch" \
    || echo "warning: theme patch no longer applies to this hyprimate version; burn keeps its own colours"
echo "building against Hyprland $(pkg-config --modversion hyprland), commit $(git -C "$SRC" rev-parse --short HEAD)"
cmake -S "$SRC" -B "$SRC/build" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTING=OFF
cmake --build "$SRC/build" --target hyprimate
mkdir -p "$(dirname "$OUT")"
cp "$SRC/build/hyprimate.so" "$OUT.new" && mv -f "$OUT.new" "$OUT"   # new inode: safe while an old copy is still mapped
echo "installed $OUT. Switch on with Super+Shift+A (Showcase mode)."
