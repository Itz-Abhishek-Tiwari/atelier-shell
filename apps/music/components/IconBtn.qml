import QtQuick
import qs.config

// A round, borderless button with a vector icon (SvgIcon). `active` tints it with the accent
// (shuffle / repeat on); a small dot under it marks active toggles, like YouTube Music.
Rectangle {
    id: b
    property string icon: "play"
    property int size: 36
    property real iconSize: Math.round(size * 0.55)
    property bool active: false
    property bool dot: false            // show the "on" dot under the icon when active
    property color tint: Atelier.text
    signal clicked()

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    opacity: enabled ? 1 : 0.35
    color: ma.pressed ? Atelier.pressed : "transparent"
    StateLayer { mouseArea: ma }
    scale: ma.pressed ? 0.9 : 1
    Behavior on color { CAnim {} }
    Behavior on scale { Anim { type: "fastSpatial" } }

    SvgIcon {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: b.dot && b.active ? -2 : 0
        name: b.icon
        size: b.iconSize
        color: b.active ? Atelier.accent : (ma.containsMouse ? Atelier.text : (b.tint === Atelier.text ? Atelier.subtext1 : b.tint))
        Behavior on color { CAnim {} }
    }
    Rectangle {
        visible: b.dot && b.active
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(b.size * 0.1)
        width: 4; height: 4; radius: 2
        color: Atelier.accent
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
}
