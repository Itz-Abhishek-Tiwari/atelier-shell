#!/usr/bin/env bash
# Send files to a nearby iPhone with AirDrop through the shell (services/AirDrop.qml), so the
# AirDrop card shows progress. Used by the Dolphin service menu "Send with AirDrop".
#   airdrop-send.sh FILE...
[ $# -gt 0 ] || { echo "usage: $0 FILE..." >&2; exit 2; }
paths=""
for f in "$@"; do
    f=$(realpath -- "$f") || continue
    [ -f "$f" ] && paths+="$f"$'\n'
done
[ -n "$paths" ] || { notify-send -a AirDrop "AirDrop" "Only files can be sent (not folders)"; exit 1; }
qs ipc call airdrop sendFiles "$paths" 2>/dev/null ||
    notify-send -a AirDrop "AirDrop" "The shell isn't running"
