pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Night light: warmer screen colours through hyprsunset (gamma; not visible in screenshots or
// recordings). The shell owns the hyprsunset process, so quitting it restores normal colours.
//
//   Settings.nightLight.on          the switch (control center, Super+Shift+N)
//   Settings.nightLight.schedule    automatically on between `from` and `to` (e.g. 20:00 → 07:00)
//   Settings.nightLight.temperature 2500 (very warm) … 6000 K (barely)
// With the schedule on, the switch overrides it until the next scheduled change.
//
//   qs ipc call nightlight toggle|on|off|isOn|setTemperature <K>
Singleton {
    id: root

    readonly property var s: Settings.nightLight
    property bool available: true
    property string override: ""            // "on" | "off" until the schedule next flips
    property bool inWindow: false
    readonly property bool active: override === "on" ? true
        : override === "off" ? false
        : (s.schedule ? inWindow : s.on)
    readonly property int temperature: Math.max(2500, Math.min(6000, s.temperature))
    readonly property string status: !available ? "Install hyprsunset"
        : active ? temperature + " K" + (s.schedule && override === "" ? " · until " + s.to : "")
        : s.schedule && override === "" ? "Scheduled from " + s.from : "Off"

    function toggle() { set(!active); }
    function set(on) {
        if (s.schedule) override = (on === inWindow) ? "" : (on ? "on" : "off");
        else s.on = on;
    }

    // ── schedule ────────────────────────────────────────────────────────────
    function minutes(t) {
        const m = String(t || "").match(/^(\d{1,2}):(\d{2})$/);
        return m ? Number(m[1]) * 60 + Number(m[2]) : -1;
    }
    function updateWindow() {
        const d = new Date(), now = d.getHours() * 60 + d.getMinutes();
        const a = minutes(s.from), b = minutes(s.to);
        const inside = a < 0 || b < 0 ? false : a <= b ? (now >= a && now < b) : (now >= a || now < b);
        if (inside !== inWindow) { inWindow = inside; override = ""; }
    }
    Timer {
        interval: 30000
        repeat: true
        running: root.s.schedule
        triggeredOnStart: true
        onTriggered: root.updateWindow()
    }
    Connections {
        target: root.s
        function onFromChanged() { root.updateWindow(); }
        function onToChanged() { root.updateWindow(); }
        function onScheduleChanged() { root.override = ""; root.updateWindow(); }
    }

    // ── hyprsunset ──────────────────────────────────────────────────────────
    Process {
        id: sunset
        running: root.active && root.available
        command: ["hyprsunset", "-t", String(root.temperature)]
        onExited: (code) => { if (code === 127) root.available = false; }
    }
    // a new temperature restarts it (debounced, so dragging the slider doesn't flicker)
    onTemperatureChanged: if (sunset.running) restart.restart()
    Timer {
        id: restart
        interval: 350
        onTriggered: { sunset.running = false; sunset.running = Qt.binding(() => root.active && root.available); }
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v hyprsunset"]
        onExited: (code) => root.available = code === 0
    }
    // re-check after an install, the next time it is switched on
    onActiveChanged: if (active && !available) check.running = true
    Process {
        id: check
        command: ["sh", "-c", "command -v hyprsunset"]
        onExited: (code) => root.available = code === 0
    }
}
