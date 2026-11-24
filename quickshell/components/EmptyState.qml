import QtQuick
import QtQuick.Layouts
import qs.config

// What an empty list shows: a quiet glyph and one line.
ColumnLayout {
    id: es
    property string icon: ""
    property string text: ""
    spacing: 8
    Text { Layout.alignment: Qt.AlignHCenter; text: es.icon; font.family: Atelier.font; font.pixelSize: 26; color: Atelier.overlay1 }
    Text { Layout.alignment: Qt.AlignHCenter; text: es.text; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: Atelier.subtext }
}
