import QtQuick
import qs.config

// One key of the on-screen keyboard. Fires `tapped()` on press (not release, so typing feels
// immediate) and, for keys with `repeat`, keeps firing while held (backspace, arrows, space...).
Rectangle {
    id: key

    property string label: ""
    property string sub: ""              // small secondary legend (the shifted character)
    property real weight: 1              // relative width within its row
    property bool active: false          // latched modifier / caps lock
    property bool repeat: false
    property color tint: Atelier.accent
    property bool dim: false             // e.g. secondary legend while not shifted
    property int labelSize: 15
    signal tapped()

    radius: 10
    color: active ? Qt.alpha(tint, 0.3) : (ma.pressed ? Atelier.containerHigh : (ma.containsMouse ? Atelier.containerHigh : Atelier.container))
    border.width: 1
    border.color: active ? Qt.alpha(tint, 0.7) : Atelier.outline
    scale: ma.pressed ? 0.94 : 1
    Behavior on color { ColorAnimation { duration: 90 } }
    Behavior on scale { NumberAnimation { duration: 80 } }

    Text {
        visible: key.sub !== ""
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 7
        anchors.topMargin: 4
        text: key.sub
        font.family: Atelier.font
        font.pixelSize: 10
        color: Atelier.subtext
        opacity: 0.8
    }

    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: key.sub !== "" ? 4 : 0
        text: key.label
        font.family: key.label.length > 2 ? Atelier.fontUi : Atelier.font
        font.pixelSize: key.label.length > 2 ? 12 : key.labelSize
        font.weight: Font.DemiBold
        color: key.active ? key.tint : Atelier.text
    }

    Timer { id: first; interval: 420; onTriggered: again.start() }
    Timer { id: again; interval: 55; repeat: true; onTriggered: key.tapped() }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: { key.tapped(); if (key.repeat) first.restart(); }
        onReleased: { first.stop(); again.stop(); }
        onCanceled: { first.stop(); again.stop(); }
    }
}
