#!/usr/bin/env bash
# Install (or refresh) the Atelier GRUB theme and tidy the boot menu.
#
#   grub/install.sh            run as your user; asks for sudo for the system steps
#
# - builds the theme from the current Atelier palette + wallpaper (grub/build-theme.py),
#   sized to the panel's resolution and the number of menu entries
# - copies it to /boot/grub/themes/atelier and points GRUB_THEME at it
# - shows the menu for 2 s (GRUB_TIMEOUT_STYLE=menu) so the theme is actually seen
# - hides the "EFI BootNext" entries (PXE, DVD, USB, ...) with GRUB_DISABLE_BOOTNEXT=true
# - regenerates /boot/grub/grub.cfg
# - installs grub/10_atelier: the boot entries with icon classes
# Re-run it after switching theme or wallpaper. Entries: Arch Linux (+ other kernels),
# Advanced (GRUB's own UKI scan, the rescue path), UEFI Firmware Settings.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
dest=/boot/grub/themes/atelier
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

# panel resolution (fallback 1920x1080)
res="$(cat /sys/class/drm/card*-eDP-*/modes 2>/dev/null | head -1)"
w="${res%x*}"; h="${res#*x}"
[[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]] || { w=1920; h=1080; }

# Boot entries with icon classes (grub/10_atelier). It replaces the runtime `uki` scan in
# /etc/grub.d/15_uki (yours, so it stays off) and the stock firmware entry (a grub update may
# turn that back on; 10_atelier then leaves the firmware entry to it, so nothing doubles).
sudo install -m 755 "$here/10_atelier" /etc/grub.d/10_atelier
[ -x /etc/grub.d/15_uki ] && sudo chmod -x /etc/grub.d/15_uki
[ -x /etc/grub.d/30_uefi-firmware ] && sudo chmod -x /etc/grub.d/30_uefi-firmware

# how many entries the menu will have (a dry run of grub-mkconfig): the card is sized to fit
items="$(sudo grub-mkconfig 2>/dev/null | grep -cE "^\s*(menuentry|submenu) " || true)"
[[ "$items" =~ ^[0-9]+$ && "$items" -gt 0 ]] || items=3

python3 -I "$here/build-theme.py" "$build" --width "$w" --height "$h" --items "$items"

sudo rm -rf "$dest"
sudo install -d -m 755 "$dest"
sudo cp -r "$build"/. "$dest"/
sudo chmod -R u=rwX,go=rX "$dest"

set_key() {   # set_key KEY VALUE  -> replace or append KEY=VALUE in /etc/default/grub
    if sudo grep -qE "^#?\s*$1=" /etc/default/grub; then
        sudo sed -i -E "s|^#?\s*$1=.*|$1=$2|" /etc/default/grub
    else
        echo "$1=$2" | sudo tee -a /etc/default/grub >/dev/null
    fi
}
set_key GRUB_THEME "\"$dest/theme.txt\""
set_key GRUB_GFXMODE "${w}x${h},auto"
set_key GRUB_TIMEOUT_STYLE menu
set_key GRUB_TIMEOUT 2
set_key GRUB_TERMINAL_OUTPUT gfxterm
set_key GRUB_DISABLE_BOOTNEXT true   # hides EFI PXE IPv4/IPv6, USB, DVD, Network, "EFI Hard Drive"

# after the theme is in place: grub-mkconfig adds a `loadfont` for each .pf2 in the theme folder
sudo grub-mkconfig -o /boot/grub/grub.cfg
echo
echo "Boot menu entries now:"
sudo grep -E "^\s*(menuentry|submenu) " /boot/grub/grub.cfg | sed -E "s/^\s*(menuentry|submenu) '([^']*)'.*/  \2/"
sudo grub-script-check /boot/grub/grub.cfg && echo "grub.cfg syntax OK"
