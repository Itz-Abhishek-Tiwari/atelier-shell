import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// The Music drawer's seek bar: thickens and shows a knob under the pointer, drag to scrub.
ColumnLayout {
    id: sb
    property bool showTimes: true
    spacing: 4

    Item {
        id: seek
        Layout.fillWidth: true
        implicitHeight: 14
        readonly property real len: Music.dur
        property real dragFrac: -1
        readonly property bool active: seekMa.containsMouse || dragFrac >= 0
        readonly property real frac: dragFrac >= 0 ? dragFrac : (len > 0 ? Math.max(0, Math.min(1, Music.pos / len)) : 0)

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: seek.active ? 6 : 4
            radius: height / 2
            color: Atelier.containerHigh
            Behavior on height { Anim { type: "fastSpatial" } }
            Rectangle {
                width: Math.max(height, parent.width * seek.frac)
                height: parent.height
                radius: parent.radius
                color: Atelier.accent
            }
        }
        Rectangle {
            x: Math.max(0, Math.min(seek.width - width, seek.width * seek.frac - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: 12; height: 12; radius: 6
            color: Atelier.accent
            scale: seek.active ? 1 : 0
            Behavior on scale { Anim { type: "fastSpatial" } }
        }
        MouseArea {
            id: seekMa
            anchors.fill: parent
            anchors.topMargin: -6
            anchors.bottomMargin: -6
            enabled: seek.len > 0
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            function at(x) { return Math.max(0, Math.min(1, x / width)); }
            onPressed: (m) => seek.dragFrac = at(m.x)
            onPositionChanged: (m) => { if (pressed) seek.dragFrac = at(m.x); }
            onReleased: { Music.seek(seek.dragFrac * seek.len); seek.dragFrac = -1; }
        }
    }
    RowLayout {
        visible: sb.showTimes
        Layout.fillWidth: true
        Text { text: Music.clock(seek.frac * seek.len); font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; color: Atelier.subtext }
        Item { Layout.fillWidth: true }
        Text { text: Music.clock(seek.len); font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; color: Atelier.subtext }
    }
}
