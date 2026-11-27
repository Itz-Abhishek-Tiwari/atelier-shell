import QtQuick
import qs.config

// Colour changes: Material 3 "expressive slow effects" (300 ms, no overshoot).
//   Behavior on color { CAnim {} }
ColorAnimation {
    property string type: "slowEffects"
    duration: Atelier.m3dur[type] ?? Atelier.m3dur.slowEffects
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Atelier.m3[type] ?? Atelier.m3.slowEffects
}
