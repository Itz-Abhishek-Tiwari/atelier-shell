import QtQuick
import Quickshell.Widgets
import qs.config
import qs.services

// ── Profile picture (~/.face), else the initial on an accent fill ───────
Item {
    id: av
    property int size: 38
    property bool ring: false
    implicitWidth: size; implicitHeight: size
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Atelier.fill(Atelier.accent)
        visible: avImg.status !== Image.Ready
        Text { anchors.centerIn: parent; text: Atelier.userName.charAt(0).toUpperCase(); font.family: Atelier.fontUi
            font.pixelSize: av.size * 0.42; font.weight: Font.DemiBold; color: Atelier.onFill }
    }
    ClippingRectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        visible: avImg.status === Image.Ready
        Image {
            id: avImg
            anchors.fill: parent
            source: Profile.faceUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: av.size * 2; sourceSize.height: av.size * 2
        }
    }
    Rectangle {
        visible: av.ring
        anchors.fill: parent
        anchors.margins: -4
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Qt.alpha(Atelier.accent, 0.55)
    }
}
