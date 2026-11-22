#!/usr/bin/env bash
# Sends one of every kind of notification, a couple of seconds apart, to check how the
# shell's cards look (pop-ups + the control center list). Nothing here is real.
#   notify-test.sh          all of them
#   notify-test.sh clear    remove every notification afterwards
set -u
if [ "${1:-}" = clear ]; then qs ipc call notifications clear; exit 0; fi

gap() { sleep "${1:-2.5}"; }
say() { printf '\033[1;34m→\033[0m %s\n' "$*"; }
phone() {   # app title body actions(json-ish) — shaped like Tether's iPhone notifications
    gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify "Tether" 0 "$(echo "$1" | tr 'A-Z' 'a-z')" "$2" "$3" "$4" \
        "{'desktop-entry': <'tether'>, 'x-kde-display-appname': <'$1'>}" 9000 >/dev/null
}

say "simple";                notify-send "Hello" "This is a test notification"; gap
say "app + icon";            notify-send -a Firefox -i firefox "Download complete" "atelier-shell-main.zip (14.2 MB)"; gap
say "long message";          notify-send -a Notes -i accessories-text-editor "A long one" "This message keeps going so you can see how the card wraps the text over a couple of lines and then cuts the rest off with an ellipsis, instead of growing forever."; gap
say "buttons (hover)";       notify-send -a Mail -i mail-unread -A open=Open -A archive=Archive "New email" "Lunch tomorrow?" >/dev/null & gap
say "stack (+2)";            for m in "Hi" "are you there?" "call me"; do notify-send -a WhatsApp -i whatsapp "Praful" "$m"; sleep 0.3; done; gap
say "replace (same tag)";    for i in 1 2 3; do notify-send -h string:x-dunst-stack-tag:atelier-demo -a Updater "Updating" "Step $i of 3"; sleep 0.8; done; gap
pic=$(find "$HOME/Pictures" "$HOME/Downloads" -maxdepth 3 -type f \( -iname '*.jpg' -o -iname '*.png' \) 2>/dev/null | head -1)
if [ -n "$pic" ]; then
    say "picture";           notify-send -a Camera -i camera-photo -h "string:image-path:$pic" "Photo saved" "$(basename "$pic")"; gap
fi
say "iPhone: WhatsApp";      phone WhatsApp "Praful" "Are we still meeting at 6?" "['default','Open','mute','Mute WhatsApp']"; gap
say "iPhone: YouTube";       phone YouTube "Venom's Tech" "GTA 6 at 120 FPS with DLSS 5? ACTUALLY DID IT!" "['default','Open','mute','Mute YouTube']"; gap
say "iPhone: Messages + Reply"; phone Messages "Mom" "Did you eat?" "['default','Open','inline-reply','Reply']"; gap
say "volume (OSD, no card)"; notify-send -h string:x-canonical-private-synchronous:volume -h int:value:65 "Volume" "65%"; gap 1.5
say "critical (stays)";      notify-send -u critical -a System -i battery-caution "Battery low" "5% left, plug in now"

echo
echo "Done. Open the control center to see them listed; '$0 clear' removes them."
