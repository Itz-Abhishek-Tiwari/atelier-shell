import QtQuick
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
        radius: 16
        color: Atelier.containerHigh

        Row {
            id: seg
            x: 3
            y: 3
            spacing: 2
            Repeater {
                model: root.options
                Rectangle {
                    required property var modelData
                    readonly property bool on: root.value === modelData.id
                    width: label.implicitWidth + 26
                    height: 26
                    radius: 13
                    color: on ? Atelier.fill(root.hue) : (ma.containsMouse ? Atelier.container : "transparent")
                    Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: modelData.label
                        font.family: Atelier.fontUi
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: parent.on ? Atelier.onFill : Atelier.text
                    }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.picked(modelData.id) }
                }
            }
        }
    }
}
