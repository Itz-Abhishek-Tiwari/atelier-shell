import QtQuick
import qs.config

// The pill switch from the control center.
Rectangle {
    id: ts
    property bool on: false
    signal toggled()
    implicitWidth: 36
    implicitHeight: 20
    radius: 10
    opacity: enabled ? 1 : 0.45
    color: on ? Atelier.accentFill : Atelier.containerHigh
    border.width: on ? 0 : 1
    border.color: Atelier.outline
    Behavior on color { ColorAnimation { duration: Atelier.durFast } }
    Rectangle {
        width: 14; height: 14; radius: 7
        y: 3
        x: ts.on ? parent.width - width - 3 : 3
        color: ts.on ? Atelier.onFill : Atelier.subtext
        Behavior on x { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen } }
    }
    MouseArea { anchors.fill: parent; enabled: ts.enabled; cursorShape: Qt.PointingHandCursor; onClicked: ts.toggled() }
}
