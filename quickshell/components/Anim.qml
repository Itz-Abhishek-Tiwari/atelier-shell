import QtQuick
import qs.config

// The shell's one animation: a NumberAnimation that takes its curve and duration from the
// Material 3 motion tokens (Atelier.m3 / Atelier.m3dur), as Caelestia does.
//
//   Behavior on y { Anim {} }                          // spatial (default): moves, sizes, scale
//   Behavior on opacity { Anim { type: "effects" } }   // fades
//
// Types: fastSpatial · spatial · slowSpatial · fastEffects · effects · slowEffects ·
//        standard · standardAccel · standardDecel · emphasized · emphasizedAccel · emphasizedDecel
// Spatial curves overshoot once in normal mode; effects never do.
NumberAnimation {
    property string type: "spatial"
    duration: Atelier.m3dur[type] ?? Atelier.m3dur.spatial
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Atelier.m3[type] ?? Atelier.m3.spatial
}
