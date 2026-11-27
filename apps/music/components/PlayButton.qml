import QtQuick
import qs.config

// The round accent play / pause button. While a song loads a thin ring spins around it
// (a separate item: the play / pause icon itself never rotates).
Rectangle {
    id: pb
    property bool playing: false
    property bool busy: false
    property int size: 46
    signal clicked()

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    color: Atelier.accentFill
    scale: ma.pressed ? 0.92 : (ma.containsMouse ? 1.05 : 1)
    Behavior on scale { Anim { type: "fastSpatial" } }

    SvgIcon {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: pb.playing ? 0 : Math.round(pb.size * 0.03)
        name: pb.playing ? "pause" : "play"
        size: Math.round(pb.size * 0.44)
        color: Atelier.onFill
    }

    // loading ring
    Item {
        anchors.fill: parent
        anchors.margins: -3
        visible: pb.busy
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Qt.alpha(Atelier.accent, 0.25)
        }
        Rectangle {          // the moving arc: a short bright segment riding the ring
            width: 8; height: 8; radius: 4
            color: Atelier.accent
            x: parent.width / 2 - 4 + (parent.width / 2 - 1) * Math.cos(spin.angle)
            y: parent.height / 2 - 4 + (parent.height / 2 - 1) * Math.sin(spin.angle)
        }
        QtObject { id: spin; property real angle: 0 }
        SequentialAnimation {
            running: pb.busy
            loops: Animation.Infinite
            NumberAnimation { target: spin; property: "angle"; from: 0; to: Math.PI * 2; duration: 900 }
        }
    }

    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
}
