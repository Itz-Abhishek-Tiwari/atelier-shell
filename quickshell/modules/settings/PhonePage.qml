import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// Settings → iPhone.
ColumnLayout {
    required property var win
    Layout.fillWidth: true
    spacing: 20

    SettingCard {
        title: "iPhone camera"
        SettingRow {
            label: PhoneCam.live ? "Live over " + PhoneCam.linkLabel
                : PhoneCam.state === "connecting" ? "Connecting…"
                : PhoneCam.state === "error" ? "Not connected" : "Off"
            description: PhoneCam.state === "error" ? PhoneCam.error
                : "Open DroidCam on the iPhone. It shows up as \"iPhone Camera\" in the camera drawer, OBS, browsers and Discord."
            Chip { icon: "󰄜"; text: PhoneCam.running ? "Disconnect" : "Connect"; tint: PhoneCam.running ? Atelier.red : Atelier.accent
                interactive: true; implicitHeight: 30; onClicked: PhoneCam.toggle() }
        }
        SettingChoice { label: "Connect over"; description: "Auto tries the USB cable, then your iPhone hotspot, then Wi-Fi"
            options: [{ id: "auto", label: "Auto" }, { id: "usb", label: "USB" }, { id: "hotspot", label: "Hotspot" }, { id: "wifi", label: "Wi-Fi" }]
            value: Settings.phone.mode; onPicked: (id) => Settings.phone.mode = id }
        SettingField { label: "iPhone address on Wi-Fi"; description: "Only for your router's Wi-Fi: the IP DroidCam shows. Empty = find it by name"
            placeholder: "192.168.1.23"
            text: Settings.phone.wifiAddress; onCommitted: (t) => Settings.phone.wifiAddress = t.trim() }
    }
}
