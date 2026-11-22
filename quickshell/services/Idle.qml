pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Idle & sleep (Settings → Display & power): writes ~/.config/atelier/hypridle.conf from
// Settings.idle and restarts hypridle on it. Autostart (hypr/conf/autostart.lua) uses this
// file when it exists, the repo's hypr/hypridle.conf otherwise.
// hypridle is only restarted when the file's content actually changes, so a shell reload
// doesn't reset the idle timers.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.config/atelier/hypridle.conf"

    function listener(seconds: int, onTimeout: string, onResume: string): string {
        if (!(seconds > 0)) return "";
        return "listener {\n    timeout    = " + seconds + "\n    on-timeout = " + onTimeout + "\n"
             + (onResume ? "    on-resume  = " + onResume + "\n" : "") + "}\n";
    }

    readonly property string text: {
        const i = Settings.idle;
        // while charging: skip the suspend unless the user wants it (any mains/USB supply online)
        const suspend = i.suspendOnAC ? "systemctl suspend"
                                      : "grep -qsx 1 /sys/class/power_supply/*/online || systemctl suspend";
        return "# Written by the Atelier shell (Settings → Display & power → Idle & sleep).\n"
             + "# Changes here are overwritten; hypr/hypridle.conf in the repo is the fallback.\n"
             + "$LOCKSCREEN = qs ipc call lock lock || hyprlock\n"
             + "$SCREEN_OFF = hyprctl dispatch 'hl.dsp.dpms({ action = \"off\" })'\n"
             + "$SCREEN_ON  = hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'\n\n"
             + "general {\n"
             + "    lock_cmd         = pidof hyprlock || $LOCKSCREEN\n"
             + "    before_sleep_cmd = loginctl lock-session\n"
             + "    after_sleep_cmd  = $SCREEN_ON\n"
             + "    ignore_dbus_inhibit    = false\n"
             + "    ignore_systemd_inhibit = false\n"
             + "}\n\n"
             + listener(i.dimAfter, "brightnessctl -s && brightnessctl s 1%", "brightnessctl -r")
             + listener(i.lockAfter, "loginctl lock-session", "")
             + listener(i.screenOffAfter, "$SCREEN_OFF", "$SCREEN_ON")
             + listener(i.suspendAfter, suspend, "");
    }

    FileView {
        id: file
        path: root.path
        printErrors: false
        blockLoading: true
    }

    Timer {
        id: apply
        interval: 800
        onTriggered: {
            if (!Settings.ready) return;
            if (file.text() === root.text) return;      // unchanged: leave hypridle alone
            file.setText(root.text);
            Quickshell.execDetached(["sh", "-c",
                'pkill -x hypridle; for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x hypridle >/dev/null || break; sleep 0.1; done; exec hypridle -q -c "$1"',
                "sh", root.path]);
        }
    }
    onTextChanged: apply.restart()
    Connections {
        target: Settings
        function onReadyChanged() { apply.restart(); }
    }
    Component.onCompleted: apply.restart()
}
