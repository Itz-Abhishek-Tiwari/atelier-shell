import QtQuick
import qs.config
import qs.services

// Volume: the speaker toggles mute (and back to the last level), drag or scroll the slider.
Row {
    id: vc
    spacing: 4
    property int lastLevel: 70
    property bool compact: false          // just the mute button (narrow bars)
    readonly property int level: Music.volume

    IconBtn {
        anchors.verticalCenter: parent.verticalCenter
        icon: vc.level === 0 ? "volume_off" : vc.level < 50 ? "volume_down" : "volume_up"
        size: 34; iconSize: 16
        onClicked: {
            if (vc.level > 0) { vc.lastLevel = vc.level; Music.setVolume(0); }
            else Music.setVolume(vc.lastLevel || 70);
        }
    }
    Item {
        id: slider
        visible: !vc.compact
        anchors.verticalCenter: parent.verticalCenter
        width: 80; height: 22
        readonly property real frac: Math.min(1, vc.level / 100)
        readonly property bool active: sMa.containsMouse || sMa.pressed
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: slider.active ? 6 : 4
            radius: height / 2
            color: Atelier.containerHigh
            Behavior on height { Anim { type: "fastSpatial" } }
            Rectangle { width: Math.max(height, parent.width * slider.frac); height: parent.height; radius: parent.radius; color: vc.level === 0 ? Atelier.overlay1 : Atelier.accent }
        }
        Rectangle {
            x: Math.max(0, Math.min(slider.width - width, slider.width * slider.frac - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: 12; height: 12; radius: 6
            color: Atelier.accent
            scale: slider.active ? 1 : 0
            Behavior on scale { Anim { type: "fastSpatial" } }
        }
        MouseArea {
            id: sMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            function set(x) { Music.setVolume(Math.round(Math.max(0, Math.min(1, x / width)) * 100)); }
            onPressed: (m) => set(m.x)
            onPositionChanged: (m) => { if (pressed) set(m.x); }
            onWheel: (w) => Music.setVolume(Math.max(0, Math.min(100, vc.level + (w.angleDelta.y > 0 ? 5 : -5))))
        }
    }
}
