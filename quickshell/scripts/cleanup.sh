#!/bin/sh
# cleanup.sh [--pacman] — the one-click clean in Settings → Storage.
#
# Only things that are safe to delete and come back by themselves when needed:
#   trash · AUR build folders (yay/paru) · picture thumbnails ·
#   developer download caches (pip, npm, Go build, yarn, pnpm, Cargo registry)
# --pacman also empties /var/cache/pacman/pkg (asks for your password through polkit).
#
# Prints one JSON line: {"freed": <bytes>, "pacman": "done|skipped|cancelled"}
set -u

avail() { df -B1 --output=avail "$HOME" | tail -1 | tr -d ' '; }
before=$(avail)

gio trash --empty 2>/dev/null || rm -rf "$HOME/.local/share/Trash/files" "$HOME/.local/share/Trash/info" 2>/dev/null
rm -rf \
    "$HOME/.cache/yay" "$HOME/.cache/paru" \
    "$HOME/.cache/thumbnails" \
    "$HOME/.cache/pip" "$HOME/.npm/_cacache" "$HOME/.cache/go-build" \
    "$HOME/.cache/yarn" "$HOME/.cache/pnpm" "$HOME/.cargo/registry/cache" 2>/dev/null

pac=skipped
if [ "${1:-}" = "--pacman" ]; then
    # -Scc asks twice; answer yes to both. Without paccache there is no "keep the last version".
    if pkexec sh -c 'yes | pacman -Scc >/dev/null 2>&1'; then pac=done; else pac=cancelled; fi
fi

sync
after=$(avail)
freed=$(( after - before )); [ "$freed" -lt 0 ] && freed=0
printf '{"freed": %s, "pacman": "%s"}\n' "$freed" "$pac"
