import QtQuick
import QtQuick.Layouts
import qs.config

// The atelier "chip": tinted pill with a 1px tinted border, optional glyph + label.
// Clickable when `interactive` is set.
Rectangle {
    id: chip

    property string icon: ""
    property string text: ""
    property color tint: Atelier.accent
    property bool interactive: false
    property bool mono: false            // SpaceMono for numbers
    property int pad: 10
    signal clicked()

    implicitHeight: 26
    implicitWidth: row.implicitWidth + 2 * pad
    radius: height / 2
    color: Qt.alpha(tint, ma.containsMouse ? 0.24 : 0.14)
    border.width: 1
    border.color: Qt.alpha(tint, 0.35)
    Behavior on color { ColorAnimation { duration: Atelier.durFast } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Text {
            visible: chip.icon !== ""
            text: chip.icon
            font.family: Atelier.font
            font.pixelSize: Atelier.fsMd
            color: chip.tint
        }
        Text {
            visible: chip.text !== ""
            text: chip.text
            font.family: chip.mono ? Atelier.font : Atelier.fontUi
            font.pixelSize: Atelier.fsSm
            font.weight: Font.DemiBold
            color: chip.tint
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: chip.interactive
        hoverEnabled: chip.interactive
        cursorShape: chip.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: chip.clicked()
    }
}
