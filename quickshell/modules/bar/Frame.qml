import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.config
import qs.services

// Caelestia-style screen frame: the bar (on any edge) and a thin border around the whole
// screen form one continuous surface, with rounded inner corners and a soft shadow
// falling onto the desktop. Children are placed inside the bar strip.
Scope {
    id: root

    required property ShellScreen screen
    default property alias barContent: barArea.data
    signal edgeHovered()          // pointer rested on the right screen edge (Open on hover)
    signal topHovered()           // pointer rested on the middle of the top edge (music drawer)
    signal topClicked()
    property bool topHover: topSensor.containsMouse   // DrawerHost keeps the music drawer open while true

    PanelWindow {
        id: frameWindow
        screen: root.screen
        // re-map after a glass change so Hyprland applies the new blur threshold (Atelier.remapToken)
        property bool remapping: false
        visible: !remapping
        Connections { target: Atelier; function onRemapTokenChanged() { frameWindow.remapping = true; frameRemap.restart(); } }
        Timer { id: frameRemap; interval: 60; onTriggered: frameWindow.remapping = false }
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-frame"

        // Only the bar (and, with "Open on hover", the right-edge sensor) takes input; the rest
        // of the frame is click-through.
        mask: Region {
            item: barArea
            Region { item: edgeSensor.enabled ? edgeSensor : null }
            Region { item: topSensor.enabled ? topSensor : null }
        }

        // Open on hover: pointing at the right screen edge shows the volume/brightness OSD
        // (Caelestia-style). Only when the bar isn't on the right, where it would be in the way.
        MouseArea {
            id: edgeSensor
            enabled: Settings.bar.openOnHover && Atelier.barEdge !== "right"
            x: parent.width - Math.max(2, Atelier.insetRight)
            y: parent.height * 0.25
            width: Math.max(2, Atelier.insetRight)
            height: parent.height * 0.5
            hoverEnabled: true
            onContainsMouseChanged: if (containsMouse) edgeDwell.restart(); else edgeDwell.stop()
            Timer { id: edgeDwell; interval: 180; onTriggered: root.edgeHovered() }
        }

        // Open on hover: resting on the middle third of the top edge opens the music drawer
        // (shell.qml only opens it while a player exists). Not when the bar is on top.
        MouseArea {
            id: topSensor
            enabled: Settings.bar.openOnHover && Atelier.barEdge !== "top"
            x: parent.width / 3
            y: 0
            width: parent.width / 3
            height: Math.max(2, Atelier.insetTop)
            hoverEnabled: true
            cursorShape: containsMouse ? Qt.PointingHandCursor : Qt.ArrowCursor
            onContainsMouseChanged: if (containsMouse) topDwell.restart(); else topDwell.stop()
            onClicked: root.topClicked()
            Timer { id: topDwell; interval: 260; onTriggered: root.topHovered() }
        }

        // The frame silhouette: the whole screen with a rounded rectangle cut out of it.
        component Ring: Shape {
            id: ring
            property color fill: Atelier.surface
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            Behavior on fill { ColorAnimation { duration: 300 } }

            readonly property real x0: Atelier.insetLeft
            readonly property real y0: Atelier.insetTop
            readonly property real x1: width - Atelier.insetRight
            readonly property real y1: height - Atelier.insetBottom
            readonly property real r: Atelier.rounding

            ShapePath {
                fillRule: ShapePath.OddEvenFill
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: ring.fill

                PathSvg {
                    path: "M 0 0 L " + ring.width + " 0 L " + ring.width + " " + ring.height + " L 0 " + ring.height + " Z"
                        + " M " + (ring.x0 + ring.r) + " " + ring.y0
                        + " L " + (ring.x1 - ring.r) + " " + ring.y0
                        + " A " + ring.r + " " + ring.r + " 0 0 1 " + ring.x1 + " " + (ring.y0 + ring.r)
                        + " L " + ring.x1 + " " + (ring.y1 - ring.r)
                        + " A " + ring.r + " " + ring.r + " 0 0 1 " + (ring.x1 - ring.r) + " " + ring.y1
                        + " L " + (ring.x0 + ring.r) + " " + ring.y1
                        + " A " + ring.r + " " + ring.r + " 0 0 1 " + ring.x0 + " " + (ring.y1 - ring.r)
                        + " L " + ring.x0 + " " + (ring.y0 + ring.r)
                        + " A " + ring.r + " " + ring.r + " 0 0 1 " + (ring.x0 + ring.r) + " " + ring.y0
                        + " Z"
                }
            }
        }

        // Soft shadow falling from the frame onto the desktop. It is the frame's real
        // (rounded-corner) shadow with the frame itself cut out of it, so it only exists
        // INSIDE the opening: a shadow under the translucent glass would show through and
        // make the bar darker than the menus, and a hand-cut shadow leaves hard boxes at
        // the corners. Static content, so these are cached textures with no per-frame cost.
        Item {
            id: frameMask
            visible: false
            layer.enabled: true
            anchors.fill: parent
            Ring { fill: "white" }
        }
        Item {
            id: frameShadow
            anchors.fill: parent
            visible: !Perf.game             // no frame shadow in Game mode
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskInverted: true
                maskSource: frameMask
                maskThresholdMin: 0.3
                maskSpreadAtMin: 0.2
            }
            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowBlur: 1.0
                    blurMax: 18
                    shadowColor: Atelier.shadow
                }
                Ring { fill: "black" }
            }
        }

        Ring { id: frameShape }

        IdleInhibitor {
            window: frameWindow
            enabled: Atelier.caffeine
        }

        Item {
            id: barArea
            x: Atelier.barEdge === "right" ? parent.width - Atelier.barWidth : 0
            y: Atelier.barEdge === "bottom" ? parent.height - Atelier.barWidth : 0
            width: Atelier.barVertical ? Atelier.barWidth : parent.width
            height: Atelier.barVertical ? parent.height : Atelier.barWidth
        }
    }

    // Tiled windows sit inside the frame because Hyprland reserves these edges per monitor
    // (hypr/conf/monitors.lua, values from Settings.qml → atelier-settings.lua). This used to be
    // four 1×1 exclusive-zone windows, each costing a render thread and a GL context.
}
