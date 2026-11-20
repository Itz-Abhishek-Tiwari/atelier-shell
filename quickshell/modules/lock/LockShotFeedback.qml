import QtQuick
import qs.config

// Feedback for a screenshot taken on the lock screen (Print key / camera button): a quick
// white flash and a small pill at the top. Shown AFTER grim has finished, so it is never
// in the picture. Used by DepthLock.qml and LockContent.qml.
Item {
    id: fb
    required property var lockRoot
    anchors.fill: parent

    property string text: ""
    property bool ok: true

    Connections {
        target: fb.lockRoot
        ignoreUnknownSignals: true
        function onShotTaken(path) { fb.ok = true; fb.text = "Screenshot saved · copied"; flash.restart(); pillAnim.restart(); }
        function onShotFailed(err) { fb.ok = false; fb.text = err || "Screenshot failed"; pillAnim.restart(); }
    }

    Rectangle {
        id: white
        anchors.fill: parent
        color: "white"
        opacity: 0
        NumberAnimation on opacity { id: flash; running: false; from: 0.55; to: 0; duration: 380; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        y: 28
        width: row.implicitWidth + 26
        height: 36
        radius: 18
        opacity: 0
        visible: opacity > 0
        readonly property color tint: fb.ok ? Atelier.green : Atelier.red
        color: Qt.alpha(Atelier.crust, 0.72)
        border.width: 1
        border.color: Qt.alpha(tint, 0.5)
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter; text: fb.ok ? "󰄀" : "󰀦"; font.family: Atelier.font; font.pixelSize: 15; color: pill.tint }
            Text { anchors.verticalCenter: parent.verticalCenter; text: fb.text; font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: Font.Medium; color: Atelier.text }
        }
        SequentialAnimation {
            id: pillAnim
            NumberAnimation { target: pill; property: "opacity"; to: 1; duration: 160 }
            PauseAnimation { duration: 2200 }
            NumberAnimation { target: pill; property: "opacity"; to: 0; duration: 300 }
        }
    }
}
