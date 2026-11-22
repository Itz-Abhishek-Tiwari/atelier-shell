import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.config
import qs.services

// Notification pop-ups: free-floating cards in the top-right corner, each on its own with a
// soft shadow (no drawer panel behind them: that looked like a box holding boxes). Cards
// slide in from the right edge and back out, macOS-style. The host makes only the column
// of cards clickable (inputItem).
Item {
    id: root
    anchors.fill: parent

    readonly property bool hasPopups: Notifs.popups.length > 0
    // stay visible a moment after the last card leaves, so its exit animation can play
    visible: hasPopups || hold.running
    onHasPopupsChanged: if (!hasPopups) hold.restart()
    Timer { id: hold; interval: 260 }

    // only the cards are clickable: a box around them, measured from the cards (the list itself has
    // a fixed height, so measuring it can't feed back into its own layout: a binding loop at the bottom)
    readonly property Item inputItem: hit
    readonly property real cardsHeight: list.contentItem.childrenRect.height + 12
    // "Clear all" pill past the last card when two or more are up
    readonly property bool showClear: Notifs.popups.length >= 2
    readonly property real clearSpace: showClear ? 38 : 0
    Item {
        id: hit
        x: column.x
        width: column.width
        height: Math.min(column.height, root.cardsHeight + root.clearSpace)
        y: root.atBottom ? column.y + column.height - height : column.y
    }

    readonly property int cardWidth: Math.max(300, Math.min(480, Settings.notifications.popupWidth || 360))
    readonly property int gap: 12
    // Settings → Notifications → Position
    readonly property string pos: ["top-right", "top-left", "top-center", "bottom-right", "bottom-left"]
        .indexOf(Settings.notifications.position) >= 0 ? Settings.notifications.position : "top-right"
    readonly property bool atBottom: pos.startsWith("bottom")
    readonly property bool atLeft: pos.endsWith("left")
    readonly property bool atCenter: pos === "top-center"
    // which way cards slide in: from the nearest side (from above when centred)
    readonly property real slideX: atCenter ? 0 : atLeft ? -48 : 48
    readonly property real slideY: atCenter ? -24 : 0

    Item {
        id: column
        x: root.atCenter ? (root.width - root.cardWidth) / 2
         : root.atLeft ? Atelier.insetLeft + root.gap
         : root.width - Atelier.insetRight - root.gap - root.cardWidth
        y: root.atBottom ? root.height - Atelier.insetBottom - root.gap - height : Atelier.insetTop + root.gap
        width: root.cardWidth
        height: root.height * 0.85 - Atelier.insetTop - Atelier.insetBottom
        // (only the cards' box takes input, so this is "the pointer is over the pop-ups")
        HoverHandler { id: columnHover }

        Rectangle {
            id: clearPill
            visible: opacity > 0
            opacity: root.showClear ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            z: 5
            // right-aligned (left on the left side), just past the last card
            x: root.atLeft ? 0 : root.atCenter ? (parent.width - width) / 2 : parent.width - width
            y: root.atBottom ? parent.height - root.cardsHeight - height - 4 : root.cardsHeight + 4
            width: clearRow.implicitWidth + 24
            height: 30
            radius: 15
            color: clearMa.containsMouse ? Qt.alpha(Atelier.red, 0.16) : Atelier.surface
            border.width: 1
            border.color: clearMa.containsMouse ? Qt.alpha(Atelier.red, 0.45) : Atelier.outline
            Behavior on color { ColorAnimation { duration: 120 } }
            Row {
                id: clearRow
                anchors.centerIn: parent
                spacing: 6
                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰎟"; font.family: Atelier.font; font.pixelSize: 12
                    color: clearMa.containsMouse ? Atelier.red : Atelier.subtext }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Clear all"; font.family: Atelier.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold
                    color: clearMa.containsMouse ? Atelier.red : Atelier.text }
            }
            MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.dismissPopups() }
        }
        RectangularShadow {
            anchors.fill: clearPill
            visible: clearPill.visible
            opacity: clearPill.opacity
            radius: clearPill.radius
            blur: 12
            offset.y: 2
            color: Atelier.shadow
            z: 4
        }

        ListView {
            id: list
            anchors.fill: parent
            interactive: false
            spacing: 14                 // room for a stack's peeking strips
            model: Notifs.popups
            // at the bottom, the newest sits nearest the screen edge too
            verticalLayoutDirection: root.atBottom ? ListView.BottomToTop : ListView.TopToBottom

            delegate: Item {
                id: slot
                required property var modelData
                width: list.width
                height: card.implicitHeight

                RectangularShadow {
                    anchors.fill: card
                    radius: card.radius
                    blur: 18
                    spread: 0
                    offset.y: 4
                    color: Atelier.shadow
                }
                NotificationCard {
                    id: card
                    width: parent.width
                    notif: slot.modelData
                    popup: true
                    paused: columnHover.hovered
                }
            }

            // arrive: slide in from the right edge and fade in
            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "x"; from: root.slideX; to: 0; duration: 420
                        easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveSmooth }
                    NumberAnimation { property: "y"; from: ViewTransition.destination.y + root.slideY; to: ViewTransition.destination.y; duration: 420
                        easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveSmooth }
                }
            }
            // leave (or replaced by a newer message of its stack): slide back out to the right
            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
                    NumberAnimation { property: "x"; to: root.slideX * 1.25; duration: 200; easing.type: Easing.InCubic }
                }
            }
            displaced: Transition {
                NumberAnimation { properties: "y"; duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard }
            }
        }
    }
}
