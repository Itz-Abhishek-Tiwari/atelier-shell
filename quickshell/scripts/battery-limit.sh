#!/usr/bin/env bash
# Battery charge limit via the kernel's `charge_types` (Standard | Long_Life = "conservation").
# usage: battery-limit.sh get | on | off
# Writes directly when the udev rule (system/etc/udev/rules.d/60-atelier-battery.rules) made the
# file writable; otherwise asks for the password through pkexec.
set -u
BAT=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
F="$BAT/charge_types"
[ -n "$BAT" ] && [ -e "$F" ] || { echo "unsupported"; exit 2; }
cur() { sed -n 's/.*\[\(.*\)\].*/\1/p' "$F"; }
case "${1:-get}" in
    get) cur ;;
    on|off)
        want=Standard; [ "$1" = on ] && want=Long_Life
        if ! echo "$want" > "$F" 2>/dev/null; then
            pkexec sh -c "echo $want > $F" || { echo "denied"; exit 1; }
        fi
        cur ;;
esac
