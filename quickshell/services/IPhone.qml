pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// The paired iPhone (Tether, AUR tether-bin), for the control center's phone strip.
//   battery / name / connected: live from BlueZ (the iPhone's Battery Service), no polling
//   notifications: whether Tether's notification link (BLE, ANCS) is up, from
//                  `tether --bt-diagnostics` (≈30 ms), polled only while someone is looking
// The phone is the device Tether paired: device_address in ~/.config/tether/bluetooth.json.
Singleton {
    id: root

    property string address: ""
    readonly property bool paired: address !== ""
    readonly property var device: paired ? Bluetooth.devices.values.find(d => d.address.toUpperCase() === address.toUpperCase()) || null : null
    readonly property string name: device ? (device.name || device.deviceName || "iPhone") : "iPhone"
    readonly property bool connected: !!device && device.connected
    // 0..1, or -1 when unknown (not connected, or the phone isn't sharing it)
    readonly property real battery: device && device.connected && device.batteryAvailable ? device.battery : -1
    property bool notifications: false

    readonly property string status: !paired ? "Not paired"
        : !connected ? "Not nearby"
        : notifications ? "Connected · notifications on" : "Connected"

    // set by the UI while visible: refresh the notification-link state then (and every 20 s)
    property int watchers: 0
    function watch(on: bool): void { watchers = Math.max(0, watchers + (on ? 1 : -1)); if (on) diag.running = true; }
    function openApp(): void { Quickshell.execDetached(["tether-gtk"]); }

    FileView {
        path: Quickshell.env("HOME") + "/.config/tether/bluetooth.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.address = JSON.parse(text()).device_address || ""; } catch (e) { root.address = ""; } }
        onLoadFailed: root.address = ""
    }

    Process {
        id: diag
        command: ["tether", "--bt-diagnostics"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.notifications = !!JSON.parse(text).connection.le_connected; }
                catch (e) { root.notifications = false; }
            }
        }
    }
    Timer {
        interval: 20000; repeat: true
        running: root.watchers > 0 && root.paired
        onTriggered: diag.running = true
    }
    onConnectedChanged: if (watchers > 0) diag.running = true
}
