import QtQuick
import qs.components
import qs.config

// On/off row (iOS-style switch).
SettingRow {
    id: root

    property bool checked: false
    property color tint: Atelier.accent        // accepted for compatibility; controls use the one system accent
    signal toggled(bool value)

    ToggleSwitch {
        implicitWidth: 44; implicitHeight: 26
        on: root.checked
        onToggled: root.toggled(!root.checked)
    }
}
