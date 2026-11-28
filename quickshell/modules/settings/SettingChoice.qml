import QtQuick
import qs.components
import qs.config

// Segmented choice row. options: [{ id, label }].
SettingRow {
    id: root

    property var options: []
    property string value: ""
    property color tint: Atelier.accent        // accepted for compatibility; controls use the one system accent
    readonly property color hue: Atelier.accent
    signal picked(string id)

    Rectangle {
        implicitWidth: seg.implicitWidth + 6
        implicitHeight: 32
        radius: Atelier.radiusMd
        color: Atelier.containerHigh

        Row {
            id: seg
            x: 3
            y: 3
            spacing: 2
            Repeater {
                model: root.options
                ActionSurface {
                    id: segment
                    required property var modelData
                    readonly property bool on: root.value === modelData.id
                    accessibleLabel: modelData.label
                    checkable: true
                    checked: on
                    onActivated: root.picked(modelData.id)
                    width: label.implicitWidth + 26
                    height: 26
                    radius: Math.min(height / 2, Atelier.radiusSm)
                    color: on ? Atelier.fill(root.hue) : "transparent"
                    Behavior on color { CAnim {} }
                    StateLayer { mouseArea: ma }
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: modelData.label
                        font.family: Atelier.fontUi
                        font.pixelSize: Atelier.fsMd
                        font.weight: Font.DemiBold
                        color: parent.on ? Atelier.onFill : Atelier.text
                        Behavior on color { CAnim {} }
                    }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: segment.activated() }
                }
            }
        }
    }
}
