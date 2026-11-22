#!/usr/bin/env bash
# Lists available system updates without root, one per line:
#   repo <name> <old> -> <new>
#   aur  <name> <old> -> <new>
# Repo updates: checkupdates (pacman-contrib) if installed, otherwise the same trick it uses:
# sync a private copy of the package database under fakeroot, never touching the real one.
# Used by services/Updates.qml.
set -u

if command -v checkupdates >/dev/null 2>&1; then
    checkupdates 2>/dev/null | sed 's/^/repo /'
else
    db="${XDG_CACHE_HOME:-$HOME/.cache}/atelier/pacman-db"
    mkdir -p "$db" && ln -sfn /var/lib/pacman/local "$db/local"
    # --disable-sandbox: pacman 7's download sandbox (an "alpm" user + Landlock) can't start under
    # fakeroot; this only ever writes the private copy above
    if fakeroot -- pacman -Sy --dbpath "$db" --logfile /dev/null --disable-sandbox >/dev/null 2>&1; then
        pacman -Qu --dbpath "$db" 2>/dev/null | grep -v '\[ignored\]' | sed 's/^/repo /'
    fi
fi

for helper in yay paru; do
    if command -v "$helper" >/dev/null 2>&1; then
        "$helper" -Qua 2>/dev/null | grep -v '\[ignored\]' | sed 's/^/aur /'
        break
    fi
done
exit 0
