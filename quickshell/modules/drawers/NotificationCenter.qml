import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config
import qs.services

// Notification center: its own drawer, out of the left border (the control center keeps the
// right one), so the two never share a panel or a shadow. History only: newest first, stacks
// of one app + title folded into one card, Do Not Disturb and Clear all in the header.
Item {
    id: root
    visible: false
    anchors.fill: parent

    property bool isLight: false
    property bool animActive: false
    property bool showAll: false
    property real openedAt: 0
    signal closedSignal()

    function toggle() { if (visible && animActive) close(); else open(); }
    function open() {
        visible = true;
        animActive = true;
        openedAt = Date.now();
        Notifs.hideAllPopups();               // they're all in the list here
        focusTimer.restart();
    }
    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }
    onVisibleChanged: if (!visible) showAll = false

    Timer { id: focusTimer; interval: 40; onTriggered: keys.forceActiveFocus() }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!root.animActive) root.visible = false }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: (e) => { if (!e.isAutoRepeat && Date.now() - root.openedAt > 350) root.close(); }
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    readonly property int limit: Math.max(1, Settings.controlCenter.notifLimit)
    readonly property int hiddenCount: Notifs.groups.length - limit

    EdgeDrawer {
        id: drawer
        edge: "left"
        open: root.animActive
        bodyWidth: 380
        bodyHeight: Math.min(root.height - Atelier.insetTop - Atelier.insetBottom - 2 * Atelier.fillet - 24,
                             22 + col.implicitHeight + 28)
        Behavior on bodyHeight { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }

        Flickable {
            id: flick
            x: 22
            y: 22
            width: parent.width - 44
            height: parent.height - 44
            contentWidth: width
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: col
                width: flick.width
                spacing: 14

                // ── Header ───────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: "Notifications"
                        font.family: Atelier.fontUi
                        font.pixelSize: Atelier.fsLg
                        font.weight: Font.Medium
                        color: Atelier.text
                    }
                    Rectangle {
                        visible: Notifs.count > 0
                        implicitWidth: ncText.implicitWidth + 12; implicitHeight: 18; radius: 9
                        color: Qt.alpha(Atelier.accent, 0.14)
                        Text { id: ncText; anchors.centerIn: parent; text: Notifs.count; font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; color: Atelier.accent }
                    }
                    Item { Layout.fillWidth: true }
                    RoundBtn { icon: Notifs.dnd ? "󰂛" : "󰂚"; active: Notifs.dnd; onClicked: Notifs.dnd = !Notifs.dnd }
                    Text {
                        visible: Notifs.count > 0
                        text: "Clear all"
                        font.family: Atelier.fontUi
                        font.pixelSize: Atelier.fsMd
                        font.weight: Font.Medium
                        color: clearMa.containsMouse ? Atelier.text : Atelier.subtext
                        MouseArea { id: clearMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.clearAll() }
                    }
                }

                // ── Empty ────────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    visible: Notifs.count === 0
                    spacing: 8
                    Text { text: Notifs.dnd ? "󰂛" : "󰄬"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: Notifs.dnd ? Atelier.peach : Atelier.green }
                    Text {
                        Layout.fillWidth: true
                        text: Notifs.dnd ? "Do Not Disturb is on. Pop-ups are silenced." : "You're all caught up."
                        font.family: Atelier.fontUi
                        font.pixelSize: Atelier.fsMd
                        color: Atelier.subtext
                    }
                }

                // ── List ─────────────────────────────────────────────────
                ListView {
                    id: notifList
                    Layout.fillWidth: true
                    visible: Notifs.count > 0
                    implicitHeight: contentHeight
                    interactive: false
                    spacing: 14            // room for a stack's peeking layers
                    model: root.showAll ? Notifs.groups : Notifs.groups.slice(0, root.limit)
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: NotificationCard {
                        required property var modelData
                        width: notifList.width
                        notif: modelData
                    }

                    add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Atelier.durFast } }
                    remove: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "x"; to: -120; duration: Atelier.durClose; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveClose }
                            NumberAnimation { property: "opacity"; to: 0; duration: Atelier.durClose }
                        }
                    }
                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard }
                    }
                }

                Text {
                    visible: !root.showAll && root.hiddenCount > 0
                    Layout.alignment: Qt.AlignHCenter
                    text: "Show " + root.hiddenCount + " more"
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.Medium
                    color: moreMa.containsMouse ? Atelier.text : Atelier.subtext
                    MouseArea { id: moreMa; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.showAll = true }
                }
            }
        }
    }

    // Do Not Disturb switch: a transparent round glyph, tonal wash when on
    component RoundBtn: Rectangle {
        id: rb
        property string icon
        property bool active: false
        signal clicked()
        implicitWidth: 26; implicitHeight: 26; radius: 13
        color: active ? Qt.alpha(Atelier.accent, 0.16) : rbMa.containsMouse ? Atelier.containerHigh : "transparent"
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Text { anchors.centerIn: parent; text: rb.icon; font.family: Atelier.font; font.pixelSize: 13
            color: rb.active ? Atelier.accent : rbMa.containsMouse ? Atelier.text : Atelier.subtext }
        MouseArea { id: rbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
    }
}
