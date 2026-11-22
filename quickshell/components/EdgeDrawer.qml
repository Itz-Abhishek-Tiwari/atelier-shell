import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import qs.config
import qs.services

// A panel that grows out of a frame edge, Caelestia-style: flush with the border,
// same surface colour, concave fillets where it meets the border, rounded outer corners.
//
// Place it as a direct child of a full-screen item/window. Put content inside; it is
// laid out in a bodyWidth x bodyHeight box and slides out with the drawer.
//
// Motion: the silhouette is built ONCE at full size and the whole sheet (shape, shadow and
// content) slides out from under the frame edge with a plain transform. The masked shadow is
// baked into a cached texture (shadowCache), so a frame of the slide is just translates.
//
//   EdgeDrawer { edge: Atelier.barEdge; anchorPos: centerAlongBar
//            open: root.animActive; bodyWidth: 320; bodyHeight: 400
//            ColumnLayout { anchors.fill: parent; anchors.margins: 16 ... } }
Item {
    id: root

    property string edge: "left"             // left | right | top | bottom
    property bool open: false
    property real bodyWidth: 300
    property real bodyHeight: 300
    property real anchorPos: -1               // centre of the body along the edge (parent coords); -1 = centred
    property real edgeInset: Atelier.inset(edge)       // bar thickness on the bar's edge, frame thickness elsewhere
    property real fillet: Atelier.fillet
    property real cornerRadius: Atelier.rounding
    property color color: Atelier.surface
    property bool shadowEnabled: !Perf.lean       // no drop shadows in Game mode (Settings → Modes)

    default property alias content: contentHolder.data
    readonly property alias contentItem: contentHolder

    // 0 = hidden inside the border, 1 = fully out
    property real progress: open ? 1 : 0
    Behavior on progress {
        NumberAnimation {
            duration: root.open ? Atelier.durOpen : Atelier.durClose
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.open ? Atelier.curveOpen : Atelier.curveClose
        }
    }

    readonly property bool horizontal: edge === "top" || edge === "bottom"
    readonly property real depthFull: horizontal ? bodyHeight : bodyWidth
    readonly property real lengthBody: horizontal ? bodyWidth : bodyHeight
    readonly property real depth: Math.max(0, progress * depthFull)
    readonly property real total: lengthBody + 2 * fillet
    // extra room on the depth axis so the overshoot is not clipped
    readonly property real itemDepth: depthFull * 1.25 + 8

    readonly property real parentLength: parent ? (horizontal ? parent.width : parent.height) : 0
    // room along the edge between the two perpendicular insets (frame corners / the bar)
    readonly property real alongMin: horizontal ? Atelier.insetLeft : Atelier.insetTop
    readonly property real alongEnd: horizontal ? Atelier.insetRight : Atelier.insetBottom
    readonly property real alongMax: parentLength - alongEnd - total
    readonly property real alongStart: {
        const c = anchorPos < 0 ? (alongMin + (parentLength - alongEnd)) / 2 : anchorPos;
        return Math.max(alongMin, Math.min(alongMax, c - total / 2));
    }

    visible: progress > 0.002
    width: horizontal ? total : itemDepth
    height: horizontal ? itemDepth : total
    x: edge === "left" ? edgeInset
       : edge === "right" ? (parent ? parent.width : 0) - edgeInset - width
       : alongStart
    y: edge === "top" ? edgeInset
       : edge === "bottom" ? (parent ? parent.height : 0) - edgeInset - height
       : alongStart

    // ── Silhouette ───────────────────────────────────────────────────────────
    // Built in canonical coords (u along the edge, v away from it), then mapped. Plain numbers
    // feeding PathLine/PathArc: a resize (bodyHeight animating) only moves points, no SVG
    // string is built and re-parsed per frame.
    function pt(u, v) {
        if (edge === "top") return Qt.point(u, v);
        if (edge === "bottom") return Qt.point(u, height - v);
        if (edge === "left") return Qt.point(v, u);
        return Qt.point(width - v, u); // right
    }
    readonly property bool flip: edge === "bottom" || edge === "left"
    readonly property var geo: {
        const d = Math.max(0.02, depthFull);
        const F = fillet, L = lengthBody;
        const f = Math.min(F, d / 2);
        const c = Math.max(0, Math.min(cornerRadius, d - f, L / 2));
        const cw = PathArc.Clockwise, ccw = PathArc.Counterclockwise;
        return {
            f: f, c: c,
            dirFillet: flip ? ccw : cw,       // SVG sweep 1 (mirrored on bottom/left)
            dirCorner: flip ? cw : ccw,       // SVG sweep 0
            p0: pt(F - f, 0), p1: pt(F, f), p2: pt(F, d - c), p3: pt(F + c, d),
            p4: pt(F + L - c, d), p5: pt(F + L, d - c), p6: pt(F + L, f), p7: pt(F + L + f, 0)
        };
    }

    // The window onto the sheet: clips at the attached edge (so the sheet is hidden while it
    // is "inside" the frame) and leaves room for the shadow on the other three sides.
    Item {
        id: window
        clip: true
        x: root.edge === "left" ? 0 : -40
        y: root.edge === "top" ? 0 : -40
        width: root.horizontal ? root.width + 80 : root.width + 40
        height: root.horizontal ? root.height + 40 : root.height + 80

        // Everything that moves: slides out from the frame edge by (1 - progress) * depth.
        Item {
            id: sheet
            readonly property real slide: (1 - Math.min(1, root.progress)) * root.depthFull
            x: root.edge === "left" ? -slide : root.edge === "right" ? slide : 0
            y: root.edge === "top" ? -slide : root.edge === "bottom" ? slide : 0
            width: window.width
            height: window.height

            // body rectangle at full depth, in window coordinates
            readonly property real bx: (root.edge === "left" ? 0 : root.edge === "right" ? root.width - root.depthFull : root.fillet) - window.x
            readonly property real by: (root.edge === "top" ? 0 : root.edge === "bottom" ? root.height - root.depthFull : root.fillet) - window.y
            readonly property real bw: root.horizontal ? root.lengthBody : root.depthFull
            readonly property real bh: root.horizontal ? root.depthFull : root.lengthBody
            readonly property bool shadowOn: root.shadowEnabled && root.depthFull > 1

            // Drop shadow = a rounded-rect shadow with the menu's exact silhouette cut out of it,
            // so nothing darkens the glass from underneath (it would show through and make
            // menus darker than the bar) and there are no hard-edged boxes at the corners.
            // Both layers are cached textures: sliding them costs only a translate.
            Item {
                id: silhouetteMask
                visible: false
                layer.enabled: true
                width: window.width
                height: window.height
                Shape {
                    x: -window.x
                    y: -window.y
                    width: root.width
                    height: root.height
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: -1
                        strokeColor: "transparent"
                        fillColor: "white"
                        startX: root.geo.p0.x; startY: root.geo.p0.y
                        PathArc { x: root.geo.p1.x; y: root.geo.p1.y; radiusX: root.geo.f; radiusY: root.geo.f; direction: root.geo.dirFillet }
                        PathLine { x: root.geo.p2.x; y: root.geo.p2.y }
                        PathArc { x: root.geo.p3.x; y: root.geo.p3.y; radiusX: root.geo.c; radiusY: root.geo.c; direction: root.geo.dirCorner }
                        PathLine { x: root.geo.p4.x; y: root.geo.p4.y }
                        PathArc { x: root.geo.p5.x; y: root.geo.p5.y; radiusX: root.geo.c; radiusY: root.geo.c; direction: root.geo.dirCorner }
                        PathLine { x: root.geo.p6.x; y: root.geo.p6.y }
                        PathArc { x: root.geo.p7.x; y: root.geo.p7.y; radiusX: root.geo.f; radiusY: root.geo.f; direction: root.geo.dirFillet }
                        PathLine { x: root.geo.p0.x; y: root.geo.p0.y }
                    }
                }
            }
            // shadowCache bakes the masked shadow into ONE texture. Without it the mask shader
            // re-ran over the whole window on every frame of the slide; now a frame just moves a
            // texture (it re-renders only when the drawer's size changes).
            Item {
                id: shadowCache
                width: window.width
                height: window.height
                visible: sheet.shadowOn
                opacity: Math.min(1, root.progress * 1.5)
                layer.enabled: sheet.shadowOn
            Item {
                id: shadowLayer
                width: window.width
                height: window.height
                layer.enabled: sheet.shadowOn
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskInverted: true
                    maskSource: silhouetteMask
                    maskThresholdMin: 0.3
                    maskSpreadAtMin: 0.2
                }
                RectangularShadow {
                    x: sheet.bx
                    y: sheet.by
                    width: sheet.bw
                    height: sheet.bh
                    radius: root.cornerRadius
                    blur: 26
                    spread: 0
                    color: Atelier.shadow
                }
            }
            }

            Shape {
                x: -window.x
                y: -window.y
                width: root.width
                height: root.height
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    strokeColor: "transparent"
                    fillColor: root.color
                    startX: root.geo.p0.x; startY: root.geo.p0.y
                    PathArc { x: root.geo.p1.x; y: root.geo.p1.y; radiusX: root.geo.f; radiusY: root.geo.f; direction: root.geo.dirFillet }
                    PathLine { x: root.geo.p2.x; y: root.geo.p2.y }
                    PathArc { x: root.geo.p3.x; y: root.geo.p3.y; radiusX: root.geo.c; radiusY: root.geo.c; direction: root.geo.dirCorner }
                    PathLine { x: root.geo.p4.x; y: root.geo.p4.y }
                    PathArc { x: root.geo.p5.x; y: root.geo.p5.y; radiusX: root.geo.c; radiusY: root.geo.c; direction: root.geo.dirCorner }
                    PathLine { x: root.geo.p6.x; y: root.geo.p6.y }
                    PathArc { x: root.geo.p7.x; y: root.geo.p7.y; radiusX: root.geo.f; radiusY: root.geo.f; direction: root.geo.dirFillet }
                    PathLine { x: root.geo.p0.x; y: root.geo.p0.y }
                }
            }

            // ── Body: content area, fixed at full depth ─────────────────────
            Item {
                id: body
                clip: true
                x: sheet.bx
                y: sheet.by
                width: sheet.bw
                height: sheet.bh

                // Swallow clicks on the panel so the overlay's dismiss area doesn't fire
                MouseArea {
                    anchors.fill: parent
                    onClicked: (mouse) => mouse.accepted = true
                }

                Item {
                    id: contentHolder
                    width: root.bodyWidth
                    height: root.bodyHeight
                    // content arrives slightly after the sheet, so the glass leads and the
                    // contents settle in behind it
                    opacity: Math.max(0, Math.min(1, (root.progress - 0.2) / 0.6))
                }
            }
        }
    }
}
