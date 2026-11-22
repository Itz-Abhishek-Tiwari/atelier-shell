#!/usr/bin/env bash
# Plugged-in drive actions for the shell (services/Drives.qml):
#   drive.sh open   <device>                 mount if needed, open it in the file manager
#   drive.sh eject  <device>                 unmount every partition of its disk, power it off
#   drive.sh notify <device> <label> <size>  "connected" notification with Open / Eject
# eject exits 2 when a partition is still in use.
set -u
cmd=${1:-} dev=${2:-}
[ -b "$dev" ] || exit 1

mountpoint_of() { lsblk -no MOUNTPOINT "$1" 2>/dev/null | head -1; }

open_drive() {
    local m; m=$(mountpoint_of "$dev")
    if [ -z "$m" ]; then
        udisksctl mount -b "$dev" --no-user-interaction >/dev/null 2>&1 || exit 1
        m=$(mountpoint_of "$dev")
    fi
    [ -n "$m" ] && xdg-open "$m" >/dev/null 2>&1 &
}

eject_drive() {
    local disk p
    disk=$(lsblk -npo PKNAME "$dev" 2>/dev/null | head -1)
    disk=${disk:-$dev}                     # a filesystem on the whole disk has no parent
    sync
    for p in $(lsblk -lnpo NAME,MOUNTPOINT "$disk" | awk 'NF == 2 { print $1 }'); do
        udisksctl unmount -b "$p" --no-user-interaction >/dev/null 2>&1 || exit 2
    done
    udisksctl power-off -b "$disk" --no-user-interaction >/dev/null 2>&1
    exit 0
}

case $cmd in
    open)  open_drive ;;
    eject) eject_drive ;;
    notify)
        label=${3:-USB drive} size=${4:-}
        action=$(notify-send -a "Drives" -i drive-removable-media -A open=Open -A eject=Eject \
            -h "string:x-dunst-stack-tag:atelier-drive-$dev" \
            "$label connected" "${size:+$size · }Open it to see the files")
        case $action in
            open) open_drive ;;
            eject)
                ( eject_drive ); rc=$?
                if [ $rc -eq 0 ]; then notify-send -a "Drives" -i drive-removable-media "$label can be removed" "It's safe to unplug now."
                else notify-send -a "Drives" -i dialog-warning "$label is still in use" "Close the files or apps using it, then eject again."; fi ;;
        esac ;;
    *) exit 1 ;;
esac
