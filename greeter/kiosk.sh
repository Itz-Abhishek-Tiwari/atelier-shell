#!/bin/sh
# Atelier greeter: runs inside cage, before the login screen.
#
# cage shows its one window on every output (-m extend) or on the last one plugged in
# (-m last), and has no option to pick a screen. So we start it with all outputs on and
# switch off everything except the laptop's built-in panel (eDP/LVDS/DSI) with wlr-randr.
# No built-in panel (desktop PC) or no wlr-randr: nothing is turned off. This never blocks
# the login. The desktop session sets up its own screens afterwards.
if command -v wlr-randr >/dev/null 2>&1; then
    outputs="$(wlr-randr 2>/dev/null | awk '/^[^ \t]/ { print $1 }')"
    internal="$(printf '%s\n' "$outputs" | grep -E '^(eDP|LVDS|DSI)' | head -n 1)"
    if [ -n "$internal" ]; then
        for o in $outputs; do
            [ "$o" = "$internal" ] || wlr-randr --output "$o" --off 2>/dev/null
        done
    fi
fi

exec quickshell -p "$(dirname "$0")/shell.qml"
