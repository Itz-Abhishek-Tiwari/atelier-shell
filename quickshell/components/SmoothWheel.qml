import QtQuick

// Smooth mouse-wheel scrolling for a Flickable/ListView/GridView.
// Qt's default wheel handling on Wayland jumps in big uneven steps; this animates
// each notch and passes touchpad (pixel) scrolling straight through.
//
//   GridView { id: grid; SmoothWheel { flickable: grid } }
WheelHandler {
    id: root

    required property Flickable flickable
    property real step: 120
    property real _target: 0

    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

    function clamp(y) {
        const f = flickable;
        const min = f.originY - f.topMargin;
        const max = Math.max(min, f.originY + f.contentHeight + f.bottomMargin - f.height);
        return Math.max(min, Math.min(max, y));
    }

    onWheel: (event) => {
        const f = flickable;
        if (event.pixelDelta.y !== 0) {          // touchpad: follow the fingers 1:1
            anim.stop();
            f.contentY = clamp(f.contentY - event.pixelDelta.y);
            return;
        }
        const base = anim.running ? _target : f.contentY;
        _target = clamp(base - (event.angleDelta.y / 120) * step);
        anim.to = _target;
        anim.restart();
    }

    property NumberAnimation anim: NumberAnimation {
        target: root.flickable
        property: "contentY"
        duration: 260
        easing.type: Easing.OutCubic
    }
}
