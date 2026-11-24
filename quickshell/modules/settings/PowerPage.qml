import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// Settings → Power & battery.
ColumnLayout {
    required property var win
    Layout.fillWidth: true
    spacing: 20

    SettingCard {
        title: "Idle & sleep"; icon: "󰒲"; tint: Atelier.lavender
        SettingSlider { label: "Dim the screen after"; from: 0; to: 300; step: 15; suffix: " s"; zeroText: "Never"; tint: Atelier.lavender
            value: Settings.idle.dimAfter; onMoved: (v) => Settings.idle.dimAfter = Math.round(v) }
        SettingSlider { label: "Lock after"; from: 0; to: 30; step: 1; suffix: " min"; zeroText: "Never"; tint: Atelier.lavender
            value: Settings.idle.lockAfter / 60; onMoved: (v) => Settings.idle.lockAfter = Math.round(v) * 60 }
        SettingSlider { label: "Turn the screen off after"; from: 0; to: 60; step: 1; suffix: " min"; zeroText: "Never"; tint: Atelier.lavender
            value: Settings.idle.screenOffAfter / 60; onMoved: (v) => Settings.idle.screenOffAfter = Math.round(v) * 60 }
        SettingSlider { label: "Sleep after"; from: 0; to: 120; step: 5; suffix: " min"; zeroText: "Never"; tint: Atelier.lavender
            value: Settings.idle.suspendAfter / 60; onMoved: (v) => Settings.idle.suspendAfter = Math.round(v) * 60 }
        SettingSwitch { label: "Sleep while charging too"; description: "Off: plugged in, it only locks and turns the screen off (downloads and builds keep going)"; tint: Atelier.lavender
            checked: Settings.idle.suspendOnAC; onToggled: (v) => Settings.idle.suspendOnAC = v }
    }

    SettingCard {
        title: "Keep awake"; icon: "󰅶"; tint: Atelier.peach
        SettingSwitch { label: "Caffeine"; description: "Keep the screen awake"; tint: Atelier.peach
            checked: Atelier.caffeine; onToggled: (v) => Atelier.caffeine = v }
    }

    SettingCard {
        title: "Screen time"; icon: "󰔛"; tint: Atelier.green
        SettingSwitch { label: "Count screen time"; tint: Atelier.green
            description: "Time in each app, shown in the System monitor (Super+Shift+M). Stays on this computer; paused while locked or away"
            checked: Settings.behavior.screenTime; onToggled: (v) => Settings.behavior.screenTime = v }
        SettingRow {
            label: "Clear history"; description: "Forget every day counted so far"
            Chip {   // two steps: the first click asks
                id: stClear
                property bool armed: false
                icon: "󰆴"; text: armed ? "Click again to clear" : "Clear"
                tint: armed ? Atelier.red : Atelier.subtext; interactive: true; implicitHeight: 28
                onClicked: { if (armed) { ScreenTime.clear(); armed = false; } else { armed = true; stDisarm.restart(); } }
                Timer { id: stDisarm; interval: 3000; onTriggered: stClear.armed = false }
            }
        }
    }

    SettingCard {
        title: "Battery"; icon: "󰂃"; tint: Atelier.yellow
        SettingSwitch { label: "Low battery alerts"; description: "A notification when it runs low; the critical one stays up and gets through Do Not Disturb"; tint: Atelier.yellow
            checked: Settings.battery.alerts; onToggled: (v) => Settings.battery.alerts = v }
        SettingSlider { visible: Settings.battery.alerts; label: "Low at"; from: 10; to: 40; step: 5; suffix: "%"; tint: Atelier.yellow
            value: Settings.battery.low; onMoved: (v) => Settings.battery.low = Math.round(v) }
        SettingSlider { visible: Settings.battery.alerts; label: "Critical at"; from: 3; to: 15; step: 1; suffix: "%"; tint: Atelier.yellow
            value: Settings.battery.critical; onMoved: (v) => Settings.battery.critical = Math.round(v) }
        SettingSwitch { label: "Charger toast"; description: "\"Charging · 64%\" when you plug in or unplug"; tint: Atelier.yellow
            checked: Settings.battery.chargerToast; onToggled: (v) => Settings.battery.chargerToast = v }
    }
}
