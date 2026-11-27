#!/usr/bin/env bash
# Install (or refresh) rEFInd with the Atelier theme, next to GRUB.
#
#   system/boot/refind/install.sh                  run as your user; asks for sudo for the system steps
#   system/boot/refind/install.sh --theme atelier  use the generated Atelier theme instead
#   system/boot/refind/install.sh --uninstall      remove rEFInd's boot entry and folder (GRUB boots again)
#
# What it does:
# - installs the `refind` package and copies its loader to <ESP>/EFI/refind
# - installs the theme:
#     minimal  (default) github.com/evanpurkhiser/rEFInd-minimal at a pinned commit,
#              background rescaled to the panel's native resolution if it isn't 1920x1080
#     atelier  built from the current Atelier palette + wallpaper (build-theme.py)
# - pins rEFInd to the panel's native resolution (read from the eDP connector)
# - writes refind.conf with clean, hand-made entries:
#     Arch Linux   one per UKI in <ESP>/EFI/Linux (running kernel first, *-fallback skipped)
#     GRUB         the existing GRUB, untouched, as a fallback
#   USB sticks and discs are still found automatically.
# - adds a "rEFInd" firmware boot entry and puts it first.
#
# GRUB and the firmware's fallback loader (EFI/BOOT/BOOTX64.EFI) are NOT touched: if the
# firmware ever drops the rEFInd entry, the laptop simply boots GRUB like before.
# Re-run it after switching theme or wallpaper, or after adding a kernel.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
esp="$(bootctl --print-esp-path 2>/dev/null || echo /boot)"
dest="$esp/EFI/refind"
dev="$(findmnt -no SOURCE "$esp")"
disk="/dev/$(lsblk -no PKNAME "$dev")"
part="$(cat "/sys/class/block/$(basename "$dev")/partition")"

entry_num() { efibootmgr | sed -nE 's/^Boot([0-9A-Fa-f]{4})\*? rEFInd.*/\1/p' | head -1; }

theme=minimal
MINIMAL_REPO=https://github.com/evanpurkhiser/rEFInd-minimal
MINIMAL_COMMIT=56a06a4bd9ed76c05523a22017056dbecca4145d
if [ "${1:-}" = "--theme" ]; then
    theme="${2:-}"
    case "$theme" in minimal|atelier) ;; *) echo "usage: $0 [--theme minimal|atelier] | --uninstall" >&2; exit 2 ;; esac
fi

if [ "${1:-}" = "--uninstall" ]; then
    n="$(entry_num)"
    [ -n "$n" ] && sudo efibootmgr -q -b "$n" -B && echo "removed boot entry Boot$n"
    sudo rm -rf "$dest" && echo "removed $dest"
    echo "GRUB is the boot loader again."
    exit 0
fi

# panel resolution (fallback 1920x1080)
res="$(cat /sys/class/drm/card*-eDP-*/modes 2>/dev/null | head -1)"
w="${res%x*}"; h="${res#*x}"
[[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]] || { w=1920; h=1080; }

build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT
if [ "$theme" = minimal ]; then
    tdir=rEFInd-minimal                     # its theme.conf hard-codes this folder name
    git init -q "$build/src"
    git -C "$build/src" fetch -q --depth 1 "$MINIMAL_REPO" "$MINIMAL_COMMIT"
    git -C "$build/src" checkout -q FETCH_HEAD
    mkdir "$build/$tdir"
    cp -r "$build/src/icons" "$build/src/theme.conf" "$build/src/background.png" \
          "$build/src/selection_big.png" "$build/src/selection_small.png" "$build/$tdir/"
    # the background ships at 1920x1080; match other panels pixel for pixel
    if [ "${w}x${h}" != 1920x1080 ]; then
        python3 -I -c 'import sys; from PIL import Image
p, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
Image.open(p).convert("RGB").resize((w, h), Image.LANCZOS).save(p)' "$build/$tdir/background.png" "$w" "$h"
    fi
    arch_icon="/EFI/refind/themes/$tdir/icons/os_arch.png"
    grub_icon="/EFI/refind/themes/$tdir/icons/os_linux.png"
    tools=""                                # the theme sets its own (shutdown only)
else
    tdir=atelier
    python3 -I "$here/build-theme.py" "$build/$tdir" --width "$w" --height "$h"
    arch_icon="/EFI/refind/themes/$tdir/icons/os_arch.png"
    grub_icon="/EFI/refind/themes/$tdir/icons/os_grub.png"
    tools="showtools shutdown,reboot,firmware"
fi

sudo pacman -S --needed --noconfirm refind

sudo install -d -m 755 "$dest" "$dest/themes"
sudo install -m 644 /usr/share/refind/refind_x64.efi "$dest/refind_x64.efi"
# rEFInd's stock icons, for anything our theme has no icon for (a USB stick, a disc, ...)
sudo rm -rf "$dest/icons" && sudo cp -r /usr/share/refind/icons "$dest/icons"
# one theme at a time: drop whichever was installed before
sudo rm -rf "$dest/themes" && sudo install -d -m 755 "$dest/themes"
sudo cp -r "$build/$tdir" "$dest/themes/$tdir"

# ── entries ──
running="$(uname -r)"
ukis="$(sudo find "$esp/EFI/Linux" -maxdepth 1 -iname '*.efi' ! -iname '*-fallback.efi' 2>/dev/null | sort || true)"
first=""; rest=""
for f in $ukis; do
    flavor="$(basename "$f" .efi)"; flavor="${flavor#arch-}"; k="${flavor#linux}"; k="${k#-}"
    case "$running" in *"${k:-__none__}"*) first="$first $f" ;; *) rest="$rest $f" ;; esac
done
grub="$(sudo find "$esp/EFI" -maxdepth 2 -iname 'grubx64.efi' ! -path '*/refind/*' 2>/dev/null | head -1 || true)"
[ -n "$grub" ] || grub="$(sudo find "$esp/EFI/BOOT" -maxdepth 1 -iname 'bootx64.efi' 2>/dev/null | head -1 || true)"

rel() { echo "/${1#"$esp"/}"; }
conf="$build/refind.conf"
cat > "$conf" <<EOF
# rEFInd — written by system/boot/refind/install.sh (Atelier). Edit that script, not this file.
timeout 3
use_nvram false
# the panel's native mode, so the theme is drawn 1:1 instead of stretched
resolution $w $h
# manual entries below + anything plugged in (USB sticks, discs); the internal disk is
# not auto-scanned, or every UKI and GRUB would show up twice with long labels
scanfor manual,external,optical
$tools
default_selection "Arch Linux"
include themes/$tdir/theme.conf
EOF
n=0
for f in $first $rest; do
    flavor="$(basename "$f" .efi)"; flavor="${flavor#arch-}"; k="${flavor#linux}"; k="${k#-}"
    if [ $n = 0 ]; then title="Arch Linux"; else title="Arch Linux (${k:-standard} kernel)"; fi
    n=$((n + 1))
    cat >> "$conf" <<EOF

menuentry "$title" {
    icon $arch_icon
    loader $(rel "$f")
}
EOF
done
if [ -n "$grub" ]; then
    cat >> "$conf" <<EOF

menuentry "GRUB" {
    icon $grub_icon
    loader $(rel "$grub")
}
EOF
fi
[ $n -gt 0 ] || echo "warning: no UKIs found in $esp/EFI/Linux; only GRUB will be listed" >&2
sudo install -m 644 "$conf" "$dest/refind.conf"

# ── firmware boot entry, first in the order ──
num="$(entry_num)"
if [ -z "$num" ]; then
    sudo efibootmgr -q --create --disk "$disk" --part "$part" --loader '\EFI\refind\refind_x64.efi' --label 'rEFInd'
    num="$(entry_num)"
fi
order="$(efibootmgr | sed -nE 's/^BootOrder: //p')"
others="$(echo "$order" | tr ',' '\n' | grep -vix "$num" | paste -sd, -)"
sudo efibootmgr -q -o "$num${others:+,$others}"

echo
echo "rEFInd installed in $dest (boot entry Boot$num, first in the order):"
sed -nE 's/^menuentry "([^"]+)".*/  \1/p' "$conf"
echo
echo "If anything goes wrong at boot: open the firmware boot menu (usually F12) and pick"
echo "\"EFI Hard Drive\" to boot GRUB as before; then run: system/boot/refind/install.sh --uninstall"
efibootmgr | grep -E "^BootOrder|rEFInd"
