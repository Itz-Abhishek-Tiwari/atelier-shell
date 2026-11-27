import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

ColumnLayout {
    property int titleSize: 22
    spacing: 3
    Text {
        Layout.fillWidth: true
        text: (Music.current !== null) ? Music.current.title : "Nothing playing"
        elide: Text.ElideRight
        font.family: Atelier.fontUi; font.pixelSize: parent.titleSize; font.weight: Font.Bold
        color: Atelier.text
    }
    Text {
        Layout.fillWidth: true
        text: (Music.current !== null) ? (Music.current.artist || "") : "Find something in Home or Search"
        elide: Text.ElideRight
        font.family: Atelier.fontUi; font.pixelSize: 15
        color: Atelier.subtext
    }
}
