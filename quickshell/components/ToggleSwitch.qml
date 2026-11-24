import QtQuick
import qs.config

// The one on/off pill switch (control center, settings rows, drawers). Size it with
// implicitWidth/implicitHeight; the knob follows the height.
Rectangle {
    id: ts
    property bool on: false
    signal toggled()
    implicitWidth: 40
    implicitHeight: 22
    radius: height / 2
    opacity: enabled ? 1 : 0.45
    color: on ? Atelier.accentFill : Atelier.containerHigh
    border.width: 1
    border.color: on ? Qt.alpha(Atelier.accent, 0.5) : Atelier.outline
    Behavior on color { ColorAnimation { duration: Atelier.durFast } }
    Rectangle {
        width: ts.height - 8; height: width; radius: width / 2
        y: 3
        x: ts.on ? parent.width - width - 4 : 3
        color: ts.on ? Atelier.onFill : Atelier.subtext
        Behavior on x { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen } }
    }
    MouseArea { anchors.fill: parent; enabled: ts.enabled; cursorShape: Qt.PointingHandCursor; onClicked: ts.toggled() }
}
