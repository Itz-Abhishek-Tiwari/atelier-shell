#!/usr/bin/env bash
# Camera drawer gallery helper (modules/drawers/CameraOverlay.qml).
#
#   camera-gallery.sh list <dir>    newest first, one line per file:  <photo|video>\t<path>\t<thumb>
#                                   (video thumbnails made once with ffmpeg, cached)
#   camera-gallery.sh zoom <file> <factor>
#                                   crop a photo to the centre 1/factor and scale it back up, in place
#                                   (the drawer's zoom is digital, so the saved photo has to match)

cache=${XDG_CACHE_HOME:-$HOME/.cache}/atelier/camera-thumbs

case "$1" in
list)
    dir=$2
    [ -d "$dir" ] || exit 0
    mkdir -p "$cache"
    find "$dir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.mp4' \) \
        -printf '%T@\t%p\n' | sort -rn | head -n 300 | cut -f2- |
    while IFS= read -r f; do
        case "${f,,}" in
        *.mp4)
            t="$cache/$(basename "$f").jpg"
            if [ ! -s "$t" ] || [ "$f" -nt "$t" ]; then
                ffmpeg -hide_banner -loglevel error -y -ss 0.4 -i "$f" -frames:v 1 -vf scale=480:-2 "$t" </dev/null 2>/dev/null ||
                ffmpeg -hide_banner -loglevel error -y -i "$f" -frames:v 1 -vf scale=480:-2 "$t" </dev/null 2>/dev/null
            fi
            [ -s "$t" ] || t=""
            printf 'video\t%s\t%s\n' "$f" "$t"
            ;;
        *)  printf 'photo\t%s\t%s\n' "$f" "$f" ;;
        esac
    done
    # thumbnails of deleted videos
    find "$cache" -maxdepth 1 -name '*.jpg' 2>/dev/null | while IFS= read -r t; do
        v=$(basename "$t" .jpg); [ -e "$dir/$v" ] || command rm -f "$t"
    done
    ;;
zoom)
    f=$2; z=$3
    [ -f "$f" ] || exit 1
    pct=$(awk -v z="$z" 'BEGIN { printf "%.4f", 100 / z }')
    up=$(awk -v z="$z" 'BEGIN { printf "%.4f", 100 * z }')
    magick "$f" -gravity center -crop "${pct}%x${pct}%+0+0" +repage -resize "${up}%" -quality 92 "$f.tmp.jpg" &&
        command mv -f "$f.tmp.jpg" "$f"
    ;;
*)
    echo "usage: $0 list <dir> | zoom <file> <factor>" >&2; exit 2 ;;
esac
