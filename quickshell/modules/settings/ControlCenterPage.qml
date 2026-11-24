import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// Settings → Control center.
ColumnLayout {
    required property var win
    Layout.fillWidth: true
    spacing: 20

    SettingCard {
        id: ccCard
        title: "Look"; icon: "󰒓"; tint: Atelier.lavender
        readonly property var all: [
            { id: "screenshot", label: "Screenshot" }, { id: "record", label: "Record" },
            { id: "wallpaper", label: "Wallpaper" }, { id: "theme", label: "Theme" },
            { id: "emoji", label: "Emoji" }, { id: "clipboard", label: "Clipboard" },
            { id: "camera", label: "Camera" }, { id: "keyboard", label: "On-screen keyboard" },
            { id: "keybinds", label: "Shortcuts list" }, { id: "settings", label: "Settings" }]
        readonly property var picked: Settings.controlCenter.shortcuts || []
        function setShortcut(id, on) {
            // keep the order of `all`; at most five
            const next = all.map(x => x.id).filter(x => x === id ? on : picked.indexOf(x) >= 0);
            Settings.controlCenter.shortcuts = next.slice(0, 5);
        }
        SettingChoice { label: "Layout"; description: "How the switches are drawn (also the grid button in its header)"; tint: Atelier.lavender
            options: [{ id: "list", label: "List" }, { id: "tiles", label: "Tiles" }, { id: "icons", label: "Icons" }, { id: "cards", label: "Cards" }]
            value: Settings.controlCenter.layout; onPicked: (id) => Settings.controlCenter.layout = id }
        SettingChoice { label: "Header"; description: "Big clock with the date, or one compact line"; tint: Atelier.lavender
            options: [{ id: "full", label: "Big clock" }, { id: "compact", label: "Compact" }]
            value: Settings.controlCenter.header; onPicked: (id) => Settings.controlCenter.header = id }
        SettingSlider { label: "Notifications shown"; description: "The rest behind \"Show more\""; from: 1; to: 10; step: 1; tint: Atelier.lavender
            value: Settings.controlCenter.notifLimit; onMoved: (v) => Settings.controlCenter.notifLimit = Math.round(v) }
    }

    SettingCard {
        title: "Shortcut buttons · " + ccCard.picked.length + " of 5"; icon: "󰒓"; tint: Atelier.lavender
        Repeater {
            model: ccCard.all
            SettingSwitch {
                required property var modelData
                label: modelData.label
                description: !checked && ccCard.picked.length >= 5 ? "Five already; turn one off first" : ""
                tint: Atelier.lavender
                checked: ccCard.picked.indexOf(modelData.id) >= 0
                onToggled: (v) => { if (!v || ccCard.picked.length < 5) ccCard.setShortcut(modelData.id, v); }
            }
        }
    }
}
