import QtQuick
import QtQuick.Layouts
import qs.config

// A titled group of settings, native style: a small label above, and the rows inside one
// rounded group (SettingRow draws the hairline dividers between rows).
ColumnLayout {
    id: card

    property string title: ""
    property string icon: ""
    property color tint: Atelier.accent
    default property alias content: col.data

    Layout.fillWidth: true
    spacing: 7

    // plain group title, system-settings style (icon and tint are accepted but not drawn)
    Text {
        visible: card.title !== ""
        Layout.leftMargin: 4
        text: card.title
        font.family: Atelier.fontUi
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: Atelier.text
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: col.implicitHeight + 8
        radius: 12
        color: Atelier.container
        border.width: 1
        border.color: Atelier.outline

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 4
            spacing: 0
        }
    }
}
