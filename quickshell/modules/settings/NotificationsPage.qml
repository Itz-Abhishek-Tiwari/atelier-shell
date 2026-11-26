import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// Settings → Notifications.
ColumnLayout {
    required property var win
    Layout.fillWidth: true
    spacing: 20

    SettingCard {
        title: "Notifications"; icon: "󰂚"; tint: Atelier.yellow
        SettingSwitch { label: "Do Not Disturb"; description: "Notifications still arrive in the control center, without pop-ups"; tint: Atelier.yellow
            checked: Notifs.dnd; onToggled: (v) => Notifs.dnd = v }
        SettingSlider { label: "Pop-up duration"; description: "Apps can ask for longer; critical ones stay"; from: 2; to: 15; step: 1; suffix: " s"; tint: Atelier.yellow
            value: Settings.notifications.popupSeconds; onMoved: (v) => Settings.notifications.popupSeconds = v }
        SettingSlider { label: "Pop-ups at once"; from: 1; to: 8; step: 1; tint: Atelier.yellow
            value: Settings.notifications.maxPopups; onMoved: (v) => Settings.notifications.maxPopups = v }
        SettingChoice { label: "Clear history after"; description: "Old notifications leave the control center by themselves"; tint: Atelier.yellow
            options: [{ id: "0", label: "Never" }, { id: "1", label: "1 hour" }, { id: "6", label: "6 hours" }, { id: "24", label: "1 day" }]
            value: String(Settings.notifications.historyHours); onPicked: (id) => Settings.notifications.historyHours = parseInt(id) }
    }

    SettingCard {
        title: "Pop-up look"; icon: "󰍡"; tint: Atelier.yellow
        SettingChoice { label: "Position"; description: "Where pop-ups appear; they slide in from that side"; tint: Atelier.yellow
            options: [{ id: "top-left", label: "Top left" }, { id: "top-center", label: "Top" }, { id: "top-right", label: "Top right" },
                      { id: "bottom-left", label: "Bottom left" }, { id: "bottom-right", label: "Bottom right" }]
            value: Settings.notifications.position; onPicked: (id) => Settings.notifications.position = id }
        SettingSlider { label: "Width"; from: 320; to: 440; step: 10; suffix: " px"; tint: Atelier.yellow
            value: Settings.notifications.popupWidth; onMoved: (v) => Settings.notifications.popupWidth = Math.round(v) }
        SettingSwitch { label: "Group by chat"; description: "Messages from the same app and sender become one card with +N; click it to see them all"; tint: Atelier.yellow
            checked: Settings.notifications.stack; onToggled: (v) => Settings.notifications.stack = v }
        SettingSwitch { label: "Show message text"; description: "Off: only who it's from (handy when sharing your screen)"; tint: Atelier.yellow
            checked: Settings.notifications.showBody; onToggled: (v) => Settings.notifications.showBody = v }
        SettingSwitch { label: "Show the app line"; description: "\"WhatsApp · iPhone\" under each message"; tint: Atelier.yellow
            checked: Settings.notifications.showSource; onToggled: (v) => Settings.notifications.showSource = v }
        SettingRow {
            label: "Try it"
            description: Notifs.dnd ? "Do Not Disturb is on, so it only shows up in the control center" : "Sends a sample notification"
            RowLayout {
                spacing: 6
                Chip { icon: "󰂚"; text: "Send one"; tint: Atelier.accent; interactive: true; implicitHeight: 30
                    onClicked: Quickshell.execDetached(["notify-send", "-a", "Atelier", "-i", "preferences-system-notifications", "This is a notification", "Pop-ups look like this, for " + Settings.notifications.popupSeconds + " seconds."]) }
                Chip { icon: "󰂞"; text: "Send all kinds"; tint: Atelier.accent; interactive: true; implicitHeight: 30
                    onClicked: Quickshell.execDetached([Quickshell.shellDir + "/scripts/notify-test.sh"]) }
            }
        }
    }
}
