#!/usr/bin/env bash
# Screen recorder behind services/Recorder.qml.
#
#   record.sh <out.mp4> <monitor> [geometry "x,y wxh"] [audio none|system|mic] [fps]
#
# Encodes on the integrated GPU (VAAPI, AMD/Intel render node) and falls back to software x264
# if that fails to start. Stop it with SIGINT (the shell does); the file is finalised and its
# path printed on stdout. Exit 127 = wf-recorder is not installed.
set -u
out=$1 mon=$2 geo=${3:-} audio=${4:-none} fps=${5:-60}

command -v wf-recorder >/dev/null || { echo "wf-recorder is not installed" >&2; exit 127; }
mkdir -p "$(dirname "$out")"

args=(-y -f "$out" -r "$fps")
if [[ -n $geo ]]; then args+=(-g "$geo"); else args+=(-o "$mon"); fi
case $audio in
    system) args+=("--audio=$(pactl get-default-sink).monitor") ;;
    mic)    args+=("--audio=$(pactl get-default-source)") ;;
esac

# the integrated GPU's render node (AMD 0x1002 / Intel 0x8086), never the NVIDIA one
node=""
for d in /sys/class/drm/renderD*; do
    v=$(cat "$d/device/vendor" 2>/dev/null)
    if [[ $v == 0x1002 || $v == 0x8086 ]]; then node=/dev/dri/${d##*/}; break; fi
done

pid="" stopping=0
# wf-recorder installs its own SIGINT handler (so the "ignored in background jobs" rule doesn't
# stop it) and finalises the file; SIGTERM 3 s later is only a safety net.
stop() {
    stopping=1
    [[ -n $pid ]] || return
    kill -INT "$pid" 2>/dev/null
    ( sleep 3; kill -TERM "$pid" 2>/dev/null ) &
}
trap stop INT TERM

run() {
    wf-recorder "${args[@]}" "$@" </dev/null &
    pid=$!
    local rc
    wait "$pid"; rc=$?
    while kill -0 "$pid" 2>/dev/null; do wait "$pid"; rc=$?; done   # wait again after the trap
    return "$rc"
}
software=(-c libx264 -p preset=veryfast -p crf=23)

t0=$SECONDS
if [[ -n $node ]]; then
    run -c h264_vaapi -d "$node"; rc=$?
    if (( rc != 0 && stopping == 0 && SECONDS - t0 < 3 )); then
        echo "hardware encoder failed, using software" >&2
        run "${software[@]}"; rc=$?
    fi
else
    run "${software[@]}"; rc=$?
fi

if [[ -s $out ]]; then echo "$out"; exit 0; fi
exit "${rc:-1}"
