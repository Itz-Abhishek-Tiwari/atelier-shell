import QtQuick
import QtQuick.Shapes
import qs.config

// Hover + press feedback for anything clickable (Caelestia / Material 3 state layer):
//   - hover: an 8 % tint of `color` fades in over the whole shape;
//   - press: a ripple grows from the pointer, then fades once released.
// The ripple is a radial gradient filling the parent's own rounded shape (a Shape with the
// same corner radius), so it needs no clipping and no offscreen layer.
//
// Drop it into a Rectangle; it is also the MouseArea:
//   Rectangle { radius: 14
//       StateLayer { onClicked: … } }
// or use it alongside an existing MouseArea:  StateLayer { mouseArea: ma }
MouseArea {
    id: root

    property color color: Atelier.text
    property real radius: parent && parent.radius !== undefined ? parent.radius : 0
    property bool disabled: false
    property MouseArea mouseArea: null          // follow another MouseArea instead of our own
    readonly property MouseArea src: mouseArea ?? root
    readonly property bool hovered: src.containsMouse
    readonly property bool down: src.pressed

    anchors.fill: parent
    enabled: !disabled && mouseArea === null
    hoverEnabled: true
    cursorShape: disabled ? Qt.ArrowCursor : Qt.PointingHandCursor

    // ripple state
    property real rx: width / 2
    property real ry: height / 2
    property real rr: 0
    property real ra: 0
    readonly property real endRadius: {
        const dx = Math.max(rx, width - rx), dy = Math.max(ry, height - ry);
        return Math.sqrt(dx * dx + dy * dy) * 1.15;
    }

    function startRipple(x, y) {
        fade.stop();
        grow.stop();
        rx = x; ry = y;
        rr = 0;
        ra = 0.12;
        grow.to = endRadius;
        grow.start();
    }
    Connections {
        target: root.src
        function onPressed(m) { if (!root.disabled) root.startRipple(m.x, m.y); }
        function onReleased() { root.release(); }
        function onCanceled() { root.release(); }
    }
    function release() {
        if (grow.running && grow.to > 0 && rr < endRadius * 0.6) fadeLater.start();
        else fade.start();
    }

    Anim { id: grow; target: root; property: "rr"; type: "slowSpatial"; duration: Atelier.m3dur.large; easing.bezierCurve: Atelier.m3.standardDecel }
    Anim { id: fade; target: root; property: "ra"; to: 0; type: "slowEffects" }
    Timer { id: fadeLater; interval: Math.max(60, Atelier.m3dur.fastSpatial / 2); onTriggered: fade.start() }

    // hover tint
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.color
        opacity: root.disabled ? 0 : root.down ? 0.12 : root.hovered ? 0.08 : 0
        Behavior on opacity { Anim { type: "effects" } }
    }

    // press ripple
    Shape {
        anchors.fill: parent
        visible: root.ra > 0.001
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.rx; centerY: root.ry
                focalX: root.rx; focalY: root.ry
                centerRadius: Math.max(0.1, root.rr)
                focalRadius: 0
                GradientStop { position: 0; color: Qt.alpha(root.color, root.ra) }
                GradientStop { position: 0.98; color: Qt.alpha(root.color, root.ra) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathRectangle { width: root.width; height: root.height; radius: root.radius }
        }
    }
}
