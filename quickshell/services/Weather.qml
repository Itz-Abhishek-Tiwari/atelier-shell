pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Weather for the control center (wttr.in via scripts/weather-detail.sh, cached 15 min).
// Uses the same location / units as the desktop widget (Settings → Widgets).
Singleton {
    id: root

    property var w: ({ ok: false })
    readonly property bool ok: w.ok === true
    // "24°C Clear": the one-line form the desktop widget and lock screens show
    readonly property string line: ok ? w.temp + w.unit + " " + w.desc : ""

    // wttr.in condition code → Material Design glyph
    function glyph(code: int): string {
        if (code === 113) return "󰖙";
        if (code === 116) return "󰖕";
        if ([119, 122].indexOf(code) >= 0) return "󰖐";
        if ([143, 248, 260].indexOf(code) >= 0) return "󰖑";
        if ([200, 386, 389, 392, 395].indexOf(code) >= 0) return "󰖓";
        if ([179, 227, 230, 323, 326, 329, 332, 335, 338, 368, 371, 350, 374, 377].indexOf(code) >= 0) return "󰖘";
        if (code >= 176 && code <= 359) return "󰖗";
        return "󰖐";
    }

    function refresh(): void { proc.running = false; proc.running = true; }
    Process {
        id: proc
        command: [Quickshell.shellDir + "/scripts/weather-detail.sh", Settings.widgets.weatherLocation, Settings.widgets.weatherUnits]
        stdout: StdioCollector { onStreamFinished: { try { const j = JSON.parse(text); if (j.ok) root.w = j; } catch (e) {} } }
    }
    readonly property string _key: Settings.widgets.weatherLocation + "|" + Settings.widgets.weatherUnits
    on_KeyChanged: refresh()
    Component.onCompleted: refresh()
    Timer { interval: 900000; running: true; repeat: true; onTriggered: root.refresh() }
}
