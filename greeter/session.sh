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

exec "$@" >>"$log" 2>&1
