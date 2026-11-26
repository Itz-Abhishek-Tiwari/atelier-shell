#!/bin/sh
# Atelier greeter: starts the chosen session quietly.
#
# greetd runs the session on the login VT, so anything the session prints (start-hyprland's
# watchdog messages, uwsm, etc.) used to flash on screen as text between the login screen and
# the desktop. This clears the VT, hides its cursor, and sends that output to a log file:
#     ~/.local/state/atelier-session.log   (previous login: atelier-session.log.old)
printf '\033[2J\033[3J\033[H\033[?25l' 2>/dev/null

log_dir="${XDG_STATE_HOME:-$HOME/.local/state}"
mkdir -p "$log_dir" 2>/dev/null
log="$log_dir/atelier-session.log"
[ -f "$log" ] && mv -f "$log" "$log.old" 2>/dev/null
# never block the login over a log file
( : >>"$log" ) 2>/dev/null || log=/dev/null

# GPU choice: the login screen's GPU pill (ATELIER_GPU) or, without it, the file written by
# system/gpu/atelier-gpu. "amd" lets only the AMD card reach Hyprland so the NVIDIA dGPU can
# power down. Anything else, or no AMD card found, leaves Hyprland on all GPUs.
gpu="${ATELIER_GPU:-$(cat "$HOME/.config/atelier/gpu" 2>/dev/null)}"
if [ "$gpu" = "amd" ]; then
    for c in /sys/class/drm/card[0-9]*; do
        if [ "$(cat "$c/device/vendor" 2>/dev/null)" = "0x1002" ]; then
            export AQ_DRM_DEVICES="/dev/dri/${c##*/}"
            break
        fi
    done
fi

exec "$@" >>"$log" 2>&1
