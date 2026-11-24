import QtQuick
import qs.config

// A pill you pick (presets, phases, filters): filled with the accent when chosen.
Rectangle {
    id: cp
    property string icon: ""
    property string label: ""
    property bool on: false
    property bool mono: false
    signal clicked()

    implicitWidth: cpRow.implicitWidth + 24
    implicitHeight: 30
    radius: 15
    color: on ? Atelier.accentFill : (cpMa.containsMouse ? Atelier.containerHigh : Atelier.container)
    border.width: on ? 0 : 1
    border.color: Atelier.outline
    scale: cpMa.pressed ? 0.95 : 1
    Behavior on color { ColorAnimation { duration: Atelier.durFast } }
    Behavior on scale { NumberAnimation { duration: 110 } }
    Row {
        id: cpRow
        anchors.centerIn: parent
        spacing: 6
        Text { anchors.verticalCenter: parent.verticalCenter; visible: cp.icon !== ""; text: cp.icon
               font.family: Atelier.font; font.pixelSize: 12; color: cp.on ? Atelier.onFill : Atelier.subtext }
        Text { anchors.verticalCenter: parent.verticalCenter; text: cp.label
               font.family: cp.mono ? Atelier.font : Atelier.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold
               color: cp.on ? Atelier.onFill : Atelier.text }
    }
    MouseArea { id: cpMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cp.clicked() }
}
