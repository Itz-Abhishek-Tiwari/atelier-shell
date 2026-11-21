#!/bin/sh
# wallblur.sh off|on — pause Hyprland's blur while the wallpaper animates (Background.qml).
#
# Blur uses new_optimizations + xray: the wallpaper is blurred once and that cached copy is
# reused by every window and shell layer. An animating wallpaper invalidates the cache on
# every frame, so Hyprland re-blurs the whole screen each frame; on the iGPU that stalled
# the screen for the whole transition (measured: a 1.7 s freeze with blur, none without).
#
# `off` remembers the current state (Game mode may already have blur off) and turns it off;
# `on` restores exactly what was there. Safe to call twice.
state="${XDG_RUNTIME_DIR:-/tmp}/atelier-wallblur"
case "$1" in
    off)
        [ -f "$state" ] && exit 0                     # already paused by a running transition
        cur=$(hyprctl getoption decoration:blur:enabled 2>/dev/null | awk '/bool:|int:/ {print ($2 == "true" || $2 == "1") ? "true" : "false"; exit}')
        [ -n "$cur" ] || exit 0
        echo "$cur" > "$state"
        [ "$cur" = "true" ] && hyprctl eval 'hl.config({ decoration = { blur = { enabled = false } } })' >/dev/null 2>&1
        ;;
    on)
        [ -f "$state" ] || exit 0
        cur=$(cat "$state"); rm -f "$state"
        [ "$cur" = "true" ] && hyprctl eval 'hl.config({ decoration = { blur = { enabled = true } } })' >/dev/null 2>&1
        ;;
esac
exit 0
