import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.config
import qs.services

// Notification pop-ups: a drawer that drops out of the top border at the top-right
// corner (Caelestia's notification position). Cards slide in/out individually.
Item {
    id: root

    // a strip along the top of the shared DrawerHost window
    anchors { top: parent.top; left: parent.left; right: parent.right }
    height: Math.min(parent ? parent.height * 0.85 : 900, drawer.bodyHeight + 60 + Atelier.maxInset)
    visible: drawer.visible || Notifs.popups.length > 0
    readonly property Item inputItem: drawer      // the host makes only this clickable

    readonly property bool hasPopups: Notifs.popups.length > 0
    // keep the last size while closing so the drawer doesn't collapse before it retracts
    property real heldHeight: 120
    readonly property real wantHeight: list.contentHeight + 24
    onWantHeightChanged: if (hasPopups && wantHeight > 30) heldHeight = wantHeight

    EdgeDrawer {
        id: drawer
        edge: "top"
        open: root.hasPopups
        bodyWidth: 400
        bodyHeight: root.heldHeight
        // sits just left of the desktop-widget column (372px wide + 18px margin) so the
        // two never overlap; top-centre is kept free for toasts
        anchorPos: root.width - Atelier.insetRight - 18 - 372 - 20 - total / 2

        Behavior on bodyHeight {
            NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard }
        }

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 12
            interactive: false
            spacing: 8
            model: Notifs.popups

            delegate: NotificationCard {
                required property var modelData
                width: list.width
                notif: modelData
                popup: true
            }

            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "x"; from: 60; to: 0; duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen }
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220 }
                }
            }
            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "x"; to: 80; duration: 200; easing.type: Easing.InCubic }
                    NumberAnimation { property: "opacity"; to: 0; duration: 180 }
                }
            }
            displaced: Transition {
                NumberAnimation { properties: "y"; duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard }
            }
        }
    }
}
