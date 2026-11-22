#!/usr/bin/env bash
# Runs the system update in a terminal (opened by the control center's Updates strip), then
# tells the shell to look again so the count clears.
set -u
printf '\033[1;34m→\033[0m Updating the system\n\n'
if command -v yay >/dev/null 2>&1; then yay -Syu
elif command -v paru >/dev/null 2>&1; then paru -Syu
else sudo pacman -Syu
fi
status=$?
qs ipc call updates check >/dev/null 2>&1
echo
if [ $status -eq 0 ]; then printf '\033[1;32m✓\033[0m Done. '; else printf '\033[1;31m✗\033[0m The update stopped (exit %s). ' "$status"; fi
read -rp "Press Enter to close." _
