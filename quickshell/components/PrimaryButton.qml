import QtQuick
import qs.config

// The one filled action of a view (the music drawer's play button). Round with only an icon,
// a pill when it has a label.
Rectangle {
    id: pb
    property string icon: ""
    property string label: ""
    property int size: label ? 36 : 50
    property color fill: Atelier.accentFill
    signal clicked()

    implicitWidth: label ? pbRow.implicitWidth + 32 : size
    implicitHeight: size
    radius: size / 2
    color: pb.fill
    opacity: enabled ? 1 : 0.4
    scale: pbMa.pressed ? 0.92 : (pbMa.containsMouse ? 1.05 : 1)
    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
    Row {
        id: pbRow
        anchors.centerIn: parent
        spacing: 7
        Text { anchors.verticalCenter: parent.verticalCenter; visible: pb.icon !== ""; text: pb.icon
               font.family: Atelier.font; font.pixelSize: pb.label ? 14 : Math.round(pb.size * 0.44); color: Atelier.onFill }
        Text { anchors.verticalCenter: parent.verticalCenter; visible: pb.label !== ""; text: pb.label
               font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: Atelier.onFill }
    }
    MouseArea { id: pbMa; anchors.fill: parent; enabled: pb.enabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
}
