import QtQuick
import qs.config

// Atelier Music's scrolling (its own copy: tuned for long pages, unlike the shell's panels).
//  - mouse wheel: each notch glides (OutQuint), notches stack into one continuous motion;
//  - touchpad: follows the fingers 1:1, then keeps going with momentum when they lift;
//  - horizontal: set `horizontal: true` for shelves (sideways gestures only, so the vertical
//    wheel always reaches the page underneath).
//
//   ListView { id: list; SmoothWheel { flickable: list } }
WheelHandler {
    id: root

    required property Flickable flickable
    property bool horizontal: false
    property real step: 150
    property real _target: 0
    property real _vel: 0
    property double _last: 0

    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    orientation: horizontal ? Qt.Horizontal : Qt.Vertical

    readonly property string prop: horizontal ? "contentX" : "contentY"
    function lo() { const f = flickable; return horizontal ? f.originX - f.leftMargin : f.originY - f.topMargin; }
    function hi() {
        const f = flickable;
        return horizontal ? Math.max(lo(), f.originX + f.contentWidth + f.rightMargin - f.width)
                          : Math.max(lo(), f.originY + f.contentHeight + f.bottomMargin - f.height);
    }
    function clamp(v) { return Math.max(lo(), Math.min(hi(), v)); }

    onWheel: (event) => {
        const f = flickable;
        const px = horizontal ? (event.pixelDelta.x || event.pixelDelta.y) : event.pixelDelta.y;
        const ad = horizontal ? (event.angleDelta.x) : event.angleDelta.y;
        if (px !== 0) {                              // touchpad
            anim.stop();
            f.cancelFlick();
            const now = Date.now();
            const dt = Math.max(1, now - _last);
            _vel = dt < 80 ? 0.6 * _vel + 0.4 * (px / dt * 1000) : px / dt * 1000;
            _last = now;
            f[prop] = clamp(f[prop] - px);
            momentum.restart();
            return;
        }
        if (ad === 0) { event.accepted = false; return; }
        const base = anim.running ? _target : f[prop];
        _target = clamp(base - (ad / 120) * step);
        anim.to = _target;
        anim.restart();
    }

    // fingers lifted (no event for a moment): fling with the last measured speed
    property Timer momentum: Timer {
        interval: 60
        onTriggered: {
            const v = Math.max(-5000, Math.min(5000, root._vel));
            if (Math.abs(v) > 300) {
                if (root.horizontal) root.flickable.flick(v, 0);
                else root.flickable.flick(0, v);
            }
            root._vel = 0;
        }
    }

    property NumberAnimation anim: NumberAnimation {
        target: root.flickable
        property: root.prop
        duration: 420
        easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.emphasizedDecel
    }
}
