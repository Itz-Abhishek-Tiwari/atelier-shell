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
    // measured from the cards themselves: ListView.contentHeight is an estimate that lagged behind a
    // card finishing its text layout, so the drawer opened half-height until a hover re-measured it
    readonly property real wantHeight: list.contentItem.childrenRect.height + 32   // + room for the last stack's strips
    function syncHeight() { if (hasPopups && wantHeight > 30) heldHeight = wantHeight; }
    onWantHeightChanged: syncHeight()
    onHasPopupsChanged: syncHeight()          // a new pop-up of the same size changes nothing above

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
            spacing: 14            // room for a stack's peeking layers
            model: Notifs.popups

            delegate: NotificationCard {
                required property var modelData
                width: list.width
                notif: modelData
                popup: true
            }

            // arrive: fade in and settle down a few px (the same way the drawer grows), no sideways slide
            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "y"; from: ViewTransition.destination.y - 14; to: ViewTransition.destination.y
                        duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveSmooth }
                    NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: 420
                        easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveSmooth }
                }
            }
            // leave (or replaced by a newer message of its stack): a short fade with a slight shrink
            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; to: 0; duration: 140; easing.type: Easing.InCubic }
                    NumberAnimation { property: "scale"; to: 0.97; duration: 140; easing.type: Easing.InCubic }
                }
            }
            displaced: Transition {
                NumberAnimation { properties: "y"; duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard }
            }
        }
    }
}
