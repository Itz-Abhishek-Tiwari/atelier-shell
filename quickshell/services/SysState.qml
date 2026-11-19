pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared system status for the bar + control center: Wi-Fi (event-driven via
// `nmcli monitor`, no polling), screen brightness, and the theme toggle.
Singleton {
    id: root

    // ── Wi-Fi ────────────────────────────────────────────────────────────────
    property bool wifiEnabled: true
    property string ssid: ""
    property int wifiSignal: 0
    readonly property bool wifiConnected: ssid !== ""
    readonly property string wifiIcon: !wifiEnabled ? "󰤮"
        : !wifiConnected ? "󰤯"
        : wifiSignal > 75 ? "󰤨" : wifiSignal > 50 ? "󰤥" : wifiSignal > 25 ? "󰤢" : "󰤟"

    function refreshWifi(): void { wifiProc.running = true; }

    function setWifi(on: bool): void {
        wifiEnabled = on;   // optimistic
        Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]);
    }

    Process {
        id: wifiProc
        command: ["sh", "-c", "nmcli -t -f WIFI radio; nmcli -t -f ACTIVE,SIGNAL,SSID dev wifi 2>/dev/null | grep '^yes' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.wifiEnabled = lines[0] === "enabled";
                const act = lines[1] || "";
                if (act.startsWith("yes:")) {
                    const rest = act.slice(4);
                    const i = rest.indexOf(":");
                    root.wifiSignal = parseInt(rest.slice(0, i)) || 0;
                    root.ssid = rest.slice(i + 1).replace(/\\:/g, ":");
                } else {
                    root.ssid = "";
                    root.wifiSignal = 0;
                }
            }
        }
    }

    // NetworkManager events → refresh (debounced)
    Process {
        id: nmMonitor
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: debounce.restart() }
        onExited: monitorRestart.start()
    }
    Timer { id: monitorRestart; interval: 5000; onTriggered: nmMonitor.running = true }
    Timer { id: debounce; interval: 400; onTriggered: root.refreshWifi() }
    // signal strength drifts without events; refresh it slowly
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refreshWifi() }

    // ── Brightness ───────────────────────────────────────────────────────────
    property real brightness: 0.5
    property real _pending: -1

    function refreshBrightness(): void { brightProc.running = true; }

    function setBrightness(v: real): void {
        brightness = Math.max(0.01, Math.min(1, v));
        _pending = brightness;
        if (!brightThrottle.running) brightThrottle.start();
    }

    Process {
        id: brightProc
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                // amdgpu_bl1,backlight,43164,66%,65535
                const f = text.trim().split(",");
                if (f.length >= 5) root.brightness = parseInt(f[2]) / parseInt(f[4]);
            }
        }
    }
    Timer {
        id: brightThrottle
        interval: 60
        onTriggered: {
            if (root._pending < 0) return;
            Quickshell.execDetached(["brightnessctl", "-q", "set", Math.round(root._pending * 100) + "%"]);
            root._pending = -1;
        }
    }
    Component.onCompleted: refreshBrightness()

    // ── Theme: light <-> dark side of the current theme (atelier-theme) ──────
    function toggleTheme(): void {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/atelier-theme", "toggle-mode"]);
    }
}
