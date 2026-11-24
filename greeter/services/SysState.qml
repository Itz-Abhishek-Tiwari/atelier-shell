pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Login-screen stand-in for the Wi-Fi status the lock styles show (nmcli, every few seconds).
Singleton {
    id: root
    property bool wifiEnabled: true
    property string ssid: ""
    property int wifiSignal: 0
    readonly property bool wifiConnected: ssid !== ""
    readonly property string wifiIcon: !wifiEnabled ? "󰤮" : !wifiConnected ? "󰤯"
        : wifiSignal >= 75 ? "󰤨" : wifiSignal >= 50 ? "󰤥" : wifiSignal >= 25 ? "󰤢" : "󰤟"
    Process {
        id: p
        running: true
        command: ["sh", "-c", "nmcli -t -f WIFI radio 2>/dev/null; nmcli -t -f ACTIVE,SIGNAL,SSID dev wifi 2>/dev/null | grep -m1 '^yes'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                root.wifiEnabled = l[0] !== "disabled";
                const a = (l[1] || "").split(":");
                root.wifiSignal = Number(a[1] || 0);
                root.ssid = a.slice(2).join(":");
            }
        }
    }
    Timer { interval: 8000; running: true; repeat: true; onTriggered: p.running = true }
}
