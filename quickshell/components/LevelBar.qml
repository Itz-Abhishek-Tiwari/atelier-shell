import QtQuick
import qs.config

// A slim level bar with a gradient fill (the control center's battery bar).
Rectangle {
    id: lb
    property real value: 0          // 0 … 1
    property color tint: Atelier.accent
    implicitHeight: 5
    radius: height / 2
    color: Atelier.containerHigh
    Rectangle {
        width: Math.max(parent.height, parent.width * Math.min(1, Math.max(0, lb.value)))
        height: parent.height
        radius: parent.radius
        Behavior on width { Anim { type: "spatial" } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(lb.tint, 0.55) }
            GradientStop { position: 1; color: lb.tint }
        }
    }
}
