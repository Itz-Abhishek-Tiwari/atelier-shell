#!/usr/bin/env bash
# iPhone as a webcam: the DroidCam app on the iPhone serves MJPEG at :4747/video; this pipes it
# into the v4l2loopback device "iPhone Camera" (/dev/video10, see /etc/modprobe.d/v4l2loopback.conf)
# so every app (the camera drawer, OBS, browsers, Discord) can use it.
# (The droidcam-cli Linux client doesn't speak the current iOS app's protocol, hence ffmpeg.)
#
#   iphonecam.sh run [auto|usb|hotspot|wifi] [wifi-address]
#       runs until stopped (SIGTERM/SIGINT) or the stream ends. Prints one line per event:
#         S connecting <link>      trying a link
#         S live <link>            frames are flowing into the device
#         E <message>              gave up (exit 1)
#   iphonecam.sh reap              kill leftovers of an earlier run
#   iphonecam.sh probe             JSON: {"usb":bool,"hotspot":bool,"device":bool}
#
# Links, in auto order: usb (iproxy through the cable, works on any network) → hotspot (the
# iPhone is the gateway, always 172.20.10.1) → wifi (saved address, else <name>.local).

DEV=/dev/video10
# the shell's own copy: exclusive_caps=0, so it's always listed as a camera. Qt builds its camera
# list once per process and never notices video10 turning into a camera when frames start
# (exclusive_caps=1, which browsers/Discord need), so the camera drawer reads this one instead.
DEV2=/dev/video11
PORT=4747
LPORT=14747
HOTSPOT=172.20.10.1

# leftovers of an earlier run (e.g. the shell crashed and orphaned them): DroidCam serves one
# viewer at a time, so a stale ffmpeg makes every new connection fail with "Invalid data"
reap() {
    pkill -f "iproxy $LPORT:$PORT" 2>/dev/null
    pkill -f "ffmpeg .*:$PORT/video .*$DEV" 2>/dev/null
    pkill -f "ffmpeg .*$LPORT/video .*$DEV" 2>/dev/null
    pkill -f "ffmpeg .*/video .*$DEV2" 2>/dev/null
    [ "$1" = "all" ] && pkill -f "lavfi -i color=.* $DEV2" 2>/dev/null
}

usb_ok()     { [ -n "$(idevice_id -l 2>/dev/null)" ]; }
hotspot_ok() { ip route show default 2>/dev/null | grep -q "via $HOTSPOT "; }
answers()    { curl -s -m 3 -o /dev/null -w '%{http_code}' "http://$1/" 2>/dev/null | grep -qE '^(200|302)$'; }

if [ "$1" = "reap" ]; then reap "$2"; exit 0; fi

if [ "$1" = "probe" ]; then
    u=false; h=false; d=false
    usb_ok && u=true; hotspot_ok && h=true; [ -e "$DEV" ] && d=true
    printf '{"usb":%s,"hotspot":%s,"device":%s}\n' "$u" "$h" "$d"
    exit 0
fi

[ "$1" = "run" ] || { echo "usage: $0 run [auto|usb|hotspot|wifi] [address] | probe" >&2; exit 2; }
mode=${2:-auto}
addr=$3

reap; sleep 0.3
[ -e "$DEV" ] || { echo "E iPhone Camera device missing (sudo modprobe v4l2loopback)"; exit 1; }

pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done; wait 2>/dev/null; }
trap 'cleanup; exit 0' TERM INT
trap cleanup EXIT

try_usb() {
    usb_ok || return 1
    echo "S connecting usb"
    iproxy "$LPORT:$PORT" >/dev/null 2>&1 &
    pids+=($!)
    for _ in 1 2 3 4 5 6; do sleep 0.5; answers "127.0.0.1:$LPORT" && { host="127.0.0.1:$LPORT"; link=usb; return 0; }; done
    kill "${pids[-1]}" 2>/dev/null; unset 'pids[-1]'
    return 1
}
try_hotspot() {
    hotspot_ok || return 1
    echo "S connecting hotspot"
    answers "$HOTSPOT:$PORT" && { host="$HOTSPOT:$PORT"; link=hotspot; return 0; }
    return 1
}
try_wifi() {
    local a=$addr
    if [ -z "$a" ]; then
        # the iPhone's local name, e.g. "Abhishek’s iPhone" → Abhisheks-iPhone.local
        local n; n=$(ideviceinfo -k DeviceName 2>/dev/null | tr -cd '[:alnum:] -' | tr ' ' '-')
        [ -n "$n" ] && a="$n.local"
    fi
    [ -n "$a" ] || return 1
    echo "S connecting wifi"
    answers "$a:$PORT" && { host="$a:$PORT"; link=wifi; return 0; }
    return 1
}

host=""; link=""
case "$mode" in
    usb)     try_usb ;;
    hotspot) try_hotspot ;;
    wifi)    try_wifi ;;
    *)       try_usb || try_hotspot || try_wifi ;;
esac
if [ -z "$host" ]; then
    echo "E iPhone not found: open DroidCam on the iPhone (unlocked), or plug in the cable"
    exit 1
fi

if [ -e "$DEV2" ]; then
    ffmpeg -hide_banner -loglevel error -fflags nobuffer -flags low_delay -i "http://$host/video" \
        -filter_complex "[0:v]format=yuv420p,split=2[a][b];[b]scale=1280:720,format=yuv420p[c]" \
        -map "[a]" -f v4l2 "$DEV" -map "[c]" -f v4l2 "$DEV2" &
else
    ffmpeg -hide_banner -loglevel error -fflags nobuffer -flags low_delay \
        -i "http://$host/video" -vf format=yuv420p -f v4l2 "$DEV" &
fi
ff=$!
pids+=($ff)
sleep 1.5
if kill -0 "$ff" 2>/dev/null; then
    echo "S live $link"
    wait "$ff"
    echo "E stream ended (DroidCam closed on the iPhone?)"
else
    echo "E couldn't read the iPhone's video"
fi
exit 1
