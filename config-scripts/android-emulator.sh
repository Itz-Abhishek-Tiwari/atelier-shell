#!/usr/bin/env bash
# Start the Android emulator (no Android Studio). Used by the "Android Emulator" launcher entry.
#   android-emulator.sh            boot the default virtual device (or the first one found)
#   android-emulator.sh <avd>      boot a specific one
#   android-emulator.sh --list     list virtual devices
#   android-emulator.sh --cold     boot without the saved snapshot (if it misbehaves)
set -euo pipefail

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk}"
EMU="$ANDROID_HOME/emulator/emulator"
DEFAULT_AVD="Pixel_9_API_36"

notify() { command -v notify-send >/dev/null && notify-send -a "Android Emulator" -i phone "$1" "${2:-}" || true; }

if [ ! -x "$EMU" ]; then
    notify "Android emulator is not installed" "Expected it in $ANDROID_HOME/emulator"
    exit 1
fi

case "${1:-}" in
    --list) "$EMU" -list-avds; exit 0 ;;
esac

extra=()
if [ "${1:-}" = "--cold" ]; then extra+=(-no-snapshot-load); shift; fi

avd="${1:-}"
if [ -z "$avd" ]; then
    if "$EMU" -list-avds | grep -qx "$DEFAULT_AVD"; then avd="$DEFAULT_AVD"
    else avd="$("$EMU" -list-avds | head -n1)"; fi
fi
if [ -z "$avd" ]; then
    notify "No Android virtual device" "Create one with: avdmanager create avd ..."
    exit 1
fi

# already running? just say so instead of starting a second copy
if pgrep -f -- "-avd $avd" >/dev/null 2>&1; then
    notify "$avd is already running"
    exit 0
fi

notify "Starting $avd" "First boot takes a minute"
# GPU: render with OpenGL on the AMD iGPU (Mesa), which drives the screen.
#  - Only NVIDIA's Vulkan driver is installed (no vulkan-radeon), so with Vulkan on the emulator
#    rendered on the GTX 1650 while compositing with GL on the AMD chip, without interop: the
#    window hung. `-feature -Vulkan` + hiding the NVIDIA Vulkan ICD keeps everything on the AMD GPU.
#  - The emulator's own Qt has no Wayland plugin, so it runs on XWayland (xcb).
env QT_QPA_PLATFORM=xcb \
    __GLX_VENDOR_LIBRARY_NAME=mesa \
    __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json \
    VK_ICD_FILENAMES=/dev/null \
    "$EMU" -avd "$avd" -gpu host -feature -Vulkan -no-boot-anim "${extra[@]}" &
emu_pid=$!

# Float + centre the phone window. hypr/conf/rules.lua floats class "Emulator", but this XWayland
# window sometimes sets its class just after it maps, so the float rule (checked only at map)
# can miss it and the phone lands in a tile. Fix it up once the window shows.
if command -v hyprctl >/dev/null; then
    for _ in $(seq 1 120); do
        kill -0 "$emu_pid" 2>/dev/null || break
        win=$(hyprctl clients -j 2>/dev/null | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if c["title"].startswith("Android Emulator"):
        print(c["address"], "float" if c["floating"] else "tiled"); break' 2>/dev/null || true)
        if [ -n "$win" ]; then
            addr=${win%% *}
            if [ "${win##* }" = tiled ]; then
                hyprctl dispatch "hl.dsp.window.float({ action = \"enable\", window = \"address:$addr\" })" >/dev/null
                sleep 0.3
                hyprctl dispatch "hl.dsp.window.center({ window = \"address:$addr\" })" >/dev/null
            fi
            break
        fi
        sleep 0.5
    done
fi
wait "$emu_pid"
