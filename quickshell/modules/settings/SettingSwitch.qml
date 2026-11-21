import QtQuick
import qs.config

// On/off row (iOS-style switch).
SettingRow {
    id: root

    property bool checked: false
    property color tint: Atelier.accent        // accepted for compatibility; controls use the one system accent
    readonly property color hue: Atelier.accent
    signal toggled(bool value)

    Rectangle {
        implicitWidth: 44
        implicitHeight: 26
        radius: 13
        color: root.checked ? Atelier.fill(root.hue) : Atelier.containerHigh
        border.width: 1
        border.color: root.checked ? Qt.alpha(root.hue, 0.5) : Atelier.outline
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }

        Rectangle {
            width: 20
            height: 20
            radius: 10
            y: 3
            x: root.checked ? parent.width - width - 3 : 3
            color: root.checked ? Atelier.onAccent : Atelier.text
            Behavior on x { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen } }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled(!root.checked)
        }
    }
}
