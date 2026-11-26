#!/usr/bin/env bash
# battery-tweaks.sh — two system-level battery savings that need root.
#
#   1. NVIDIA GPU sleep. The dGPU (GTX 1650) is held powered ("power/control = on", ~1 W) even
#      though the screen runs on the AMD GPU and nothing uses it. This lets it suspend.
#        /etc/modprobe.d/nvidia-pm.conf          NVreg_DynamicPowerManagement=0x02
#        /etc/udev/rules.d/80-atelier-nvidia-pm.rules   power/control = auto when the driver binds
#      The module option is read when the driver loads (it is in your initramfs), so it needs
#      `mkinitcpio -P` and a reboot. The script asks before rebuilding the initramfs. It also
#      sets power/control = auto right now, which takes effect fully after the reboot.
#
#   2. CPU turbo boost off while on battery (back on when the charger is plugged in).
#        /etc/udev/rules.d/61-atelier-cpu-boost.rules
#      Takes effect immediately for the current power source and on every plug / unplug.
#      The rule also lets the wheel group write the boost switch, so the shell can override it
#      per mode without a password: Game mode turns boost ON (even on battery), Battery saver
#      turns it OFF, Normal / Programming follow the charger (services/Perf.qml).
#
# Only NEW files are created; nothing existing (nvidia.conf, mkinitcpio.conf.d, ...) is edited.
#
#   sudo ./battery-tweaks.sh              install
#   ./battery-tweaks.sh --dry-run         print exactly what would be written (no root needed)
#   sudo ./battery-tweaks.sh --uninstall  remove the files and put boost / GPU back to the defaults
#
# Check afterwards (after the reboot):
#   cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status      → suspended (when idle)
#   cat /sys/devices/system/cpu/cpufreq/boost                       → 0 on battery, 1 on AC

set -euo pipefail

MODPROBE=/etc/modprobe.d/nvidia-pm.conf
UDEV_GPU=/etc/udev/rules.d/80-atelier-nvidia-pm.rules
UDEV_BOOST=/etc/udev/rules.d/61-atelier-cpu-boost.rules
BOOST=/sys/devices/system/cpu/cpufreq/boost

mode=install
case "${1:-}" in
    "" ) ;;
    --dry-run) mode=dry ;;
    --uninstall) mode=uninstall ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

# ── the files ────────────────────────────────────────────────────────────────
modprobe_conf='# Let the NVIDIA dGPU power itself down when idle (RTD3, fine-grained). Written by
# system/power/battery-tweaks.sh; remove this file to undo. Needs mkinitcpio -P + reboot.
options nvidia NVreg_DynamicPowerManagement=0x02'

udev_gpu='# NVIDIA dGPU + its audio function: runtime power management on while the driver is bound.
# Written by system/power/battery-tweaks.sh.
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="on"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="on"'

udev_boost='# CPU turbo boost: off on battery, on with the charger. Written by system/power/battery-tweaks.sh.
# The wheel group may write the switch (the shell overrides it per mode: Game on, Saver off).
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ACTION=="add|change", RUN+="/bin/chgrp wheel /sys/devices/system/cpu/cpufreq/boost", RUN+="/bin/chmod g+w /sys/devices/system/cpu/cpufreq/boost"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ACTION=="add|change", ATTR{online}=="0", RUN+="/bin/sh -c '\''echo 0 > /sys/devices/system/cpu/cpufreq/boost'\''"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ACTION=="add|change", ATTR{online}=="1", RUN+="/bin/sh -c '\''echo 1 > /sys/devices/system/cpu/cpufreq/boost'\''"'

# ── dry run ──────────────────────────────────────────────────────────────────
if [ "$mode" = dry ]; then
    for f in MODPROBE:modprobe_conf UDEV_GPU:udev_gpu UDEV_BOOST:udev_boost; do
        path_var=${f%%:*}; body_var=${f##*:}
        printf '\n### would write %s\n%s\n' "${!path_var}" "${!body_var}"
    done
    printf '\n### would also, right now:\n'
    printf '    set power/control = auto on every NVIDIA PCI function\n'
    printf '    write 0 (battery) or 1 (AC) to %s\n' "$BOOST"
    printf '    udevadm control --reload   (and ask before running: mkinitcpio -P)\n'
    printf '\n(nothing was changed)\n'
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo:  sudo $0 ${1:-}" >&2
    exit 1
fi

# "on AC?" from the first Mains supply
on_ac() {
    local s
    for s in /sys/class/power_supply/*; do
        [ "$(cat "$s/type" 2>/dev/null)" = Mains ] && { [ "$(cat "$s/online")" = 1 ] && return 0 || return 1; }
    done
    return 0      # no Mains supply found: treat as AC (leave boost on)
}

nvidia_functions() {
    local d
    for d in /sys/bus/pci/devices/*; do
        [ "$(cat "$d/vendor" 2>/dev/null)" = 0x10de ] && echo "$d"
    done
}

write_if_changed() {       # path, content
    if [ -f "$1" ] && [ "$(cat "$1")" = "$2" ]; then echo "  ok       $1 (already up to date)"
    else printf '%s\n' "$2" > "$1"; chmod 644 "$1"; echo "  wrote    $1"; fi
}

# ── uninstall ────────────────────────────────────────────────────────────────
if [ "$mode" = uninstall ]; then
    echo "Removing the battery tweaks…"
    for f in "$MODPROBE" "$UDEV_GPU" "$UDEV_BOOST"; do
        [ -f "$f" ] && { rm -f "$f"; echo "  removed  $f"; } || echo "  absent   $f"
    done
    [ -w "$BOOST" ] && echo 1 > "$BOOST" && echo "  boost    on"
    for d in $(nvidia_functions); do echo on > "$d/power/control" 2>/dev/null && echo "  gpu      $(basename "$d") power/control = on"; done
    udevadm control --reload
    echo "Done. The module option goes away at the next initramfs rebuild:  sudo mkinitcpio -P"
    exit 0
fi

# ── install ──────────────────────────────────────────────────────────────────
echo "Installing the battery tweaks…"
write_if_changed "$MODPROBE"   "$modprobe_conf"
write_if_changed "$UDEV_GPU"   "$udev_gpu"
write_if_changed "$UDEV_BOOST" "$udev_boost"
udevadm control --reload
echo "  udev rules reloaded"

# apply right now
if [ -w "$BOOST" ]; then
    if on_ac; then echo 1 > "$BOOST"; echo "  boost    on (charger plugged in)"
    else echo 0 > "$BOOST"; echo "  boost    off (on battery)"; fi
else
    echo "  boost    control not found at $BOOST (skipped)"
fi
for d in $(nvidia_functions); do
    if echo auto > "$d/power/control" 2>/dev/null; then echo "  gpu      $(basename "$d") power/control = auto"; fi
done

# the NVIDIA module is in the initramfs, so the new option only counts after a rebuild
echo
read -r -p "Rebuild the initramfs now (mkinitcpio -P) so the GPU option is used at the next boot? [y/N] " ans
if [ "${ans:-n}" = y ] || [ "${ans:-n}" = Y ]; then
    mkinitcpio -P
else
    echo "Skipped. Run  sudo mkinitcpio -P  yourself, then reboot."
fi

echo
echo "Done. After a reboot, check:"
echo "  cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status   → suspended (when idle)"
echo "  cat $BOOST                         → 0 on battery"
echo "To undo everything:  sudo $0 --uninstall"
