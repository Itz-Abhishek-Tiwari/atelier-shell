import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// Settings → Windows (Hyprland).
ColumnLayout {
    required property var win
    Layout.fillWidth: true
    spacing: 20

    SettingCard {
        title: "Spacing & corners"; icon: "󰖲"; tint: Atelier.sky
        SettingSlider { label: "Gap between windows"; from: 0; to: 20; step: 1; suffix: " px"; tint: Atelier.sky
            value: Settings.windows.gapsIn; onMoved: (v) => Settings.windows.gapsIn = v }
        SettingSlider { label: "Gap to screen edge"; from: 0; to: 30; step: 1; suffix: " px"; tint: Atelier.sky
            value: Settings.windows.gapsOut; onMoved: (v) => Settings.windows.gapsOut = v }
        SettingRow {
            visible: Settings.appearance.linkRounding
            label: "Window corner rounding"
            description: "Linked to the shell's roundness (Appearance), so corners line up with the frame"
            Chip { text: Settings.windowRounding + " px  ·  linked"; mono: true; tint: Atelier.sky; implicitHeight: 28 }
        }
        SettingSlider { visible: !Settings.appearance.linkRounding; label: "Window corner rounding"; from: 0; to: 28; step: 1; suffix: " px"; tint: Atelier.sky
            value: Settings.windows.rounding; onMoved: (v) => Settings.windows.rounding = v }
    }

    SettingCard {
        title: "Animations"; icon: "󰓅"; tint: Atelier.green
        SettingSwitch { label: "Window animations"; description: "Opening, closing, moving and workspace switches"; tint: Atelier.green
            checked: Settings.windows.animations; onToggled: (v) => Settings.windows.animations = v }
    }

}
