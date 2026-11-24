import QtQuick
import qs.config

// A round, borderless glyph button (the control center / music drawer RoundBtn).
// `hoverTint` colours the glyph under the pointer (red for destructive ones); `active` lights it.
Rectangle {
    id: ib
    property string icon: ""
    property int size: 32
    property int glyphSize: 14
    property color hoverTint: Atelier.text
    property bool active: false
    signal clicked()

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    opacity: enabled ? 1 : 0.35
    color: active ? Qt.alpha(Atelier.accent, 0.16) : (ibMa.containsMouse ? Atelier.containerHigh : "transparent")
    scale: ibMa.pressed ? 0.88 : 1
    Behavior on color { ColorAnimation { duration: Atelier.durFast } }
    Behavior on scale { NumberAnimation { duration: 110 } }
    Text {
        anchors.centerIn: parent
        text: ib.icon
        font.family: Atelier.font
        font.pixelSize: ib.glyphSize
        color: ib.active ? Atelier.accent : (ibMa.containsMouse ? ib.hoverTint : Atelier.subtext1)
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
    }
    MouseArea { id: ibMa; anchors.fill: parent; enabled: ib.enabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
}
