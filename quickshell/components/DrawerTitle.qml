import QtQuick
import QtQuick.Layouts
import qs.config

// The drawer title used across the shell (Games, Wallpapers, System, Timers…):
// a tinted glyph tile, the title, and a quiet line under it.
RowLayout {
    id: dt
    property string icon: ""
    property color tint: Atelier.accent
    property string title: ""
    property string subtitle: ""
    spacing: 10

    Rectangle {
        implicitWidth: 36; implicitHeight: 36; radius: Atelier.radiusMd
        color: Qt.alpha(dt.tint, 0.14)
        border.width: 1
        border.color: Qt.alpha(dt.tint, 0.35)
        Text { anchors.centerIn: parent; text: dt.icon; font.family: Atelier.font; font.pixelSize: 17; color: dt.tint }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 0
        Text { Layout.fillWidth: true; text: dt.title; elide: Text.ElideRight
               font.family: Atelier.fontUi; font.pixelSize: Atelier.fsXl; font.weight: Font.DemiBold; color: Atelier.text }
        Text { Layout.fillWidth: true; visible: dt.subtitle !== ""; text: dt.subtitle; elide: Text.ElideRight
               font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
    }
}
