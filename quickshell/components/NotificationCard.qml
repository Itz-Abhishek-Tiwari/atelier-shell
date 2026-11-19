import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.config
import qs.services

// One notification. Used by the pop-ups (popup: true → auto-expires, pauses on hover)
// and by the control center list.
Rectangle {
    id: root

    required property var notif
    property bool popup: false

    readonly property bool critical: notif && notif.urgency === NotificationUrgency.Critical
    readonly property string icon: notif ? Notifs.iconFor(notif) : ""
    readonly property var extraActions: notif ? notif.actions.filter(a => a.identifier !== "default" && a.text) : []

    implicitHeight: layout.implicitHeight + 24
    radius: 16
    color: hover.hovered ? Atelier.containerHigh : Atelier.container
    border.width: 1
    border.color: critical ? Qt.alpha(Atelier.red, 0.6) : Atelier.outline
    Behavior on color { ColorAnimation { duration: 120 } }

    // Close the pop-up when the app (or anyone) closes the notification
    Connections {
        target: root.notif
        function onClosed() { Notifs.hidePopup(root.notif); }
    }

    Timer {
        running: root.popup && Notifs.timeoutFor(root.notif) > 0 && !hover.hovered
        interval: Notifs.timeoutFor(root.notif)
        onTriggered: Notifs.hidePopup(root.notif)
    }

    HoverHandler { id: hover }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: (m) => {
            if (m.button === Qt.LeftButton) Notifs.activate(root.notif);
            else if (root.popup && m.button === Qt.RightButton) Notifs.hidePopup(root.notif);
            else Notifs.dismiss(root.notif);
        }
    }

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 12

        // App icon / image, or a bell glyph tile
        Item {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 38
            implicitHeight: 38

            ClippingRectangle {
                anchors.fill: parent
                radius: 12
                visible: root.icon !== ""
                color: "transparent"
                IconImage {
                    anchors.fill: parent
                    source: root.icon
                    asynchronous: true
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: 12
                visible: root.icon === ""
                color: Qt.alpha(root.critical ? Atelier.red : Atelier.accent, 0.16)
                Text {
                    anchors.centerIn: parent
                    text: root.critical ? "󰀦" : "󰂚"
                    font.family: Atelier.font
                    font.pixelSize: 17
                    color: root.critical ? Atelier.red : Atelier.accent
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    text: root.notif ? (root.notif.appName || "Notification") : ""
                    font.family: Atelier.fontUi
                    font.pixelSize: 10
                    color: Atelier.subtext
                    elide: Text.ElideRight
                }
                Text {
                    text: root.notif ? Notifs.timeAgo(Notifs.receivedAt(root.notif)) : ""
                    font.family: Atelier.font
                    font.pixelSize: 10
                    color: Atelier.subtext
                    opacity: 0.7
                    visible: !closeBtn.visible
                }
                // dismiss
                Rectangle {
                    id: closeBtn
                    visible: hover.hovered
                    implicitWidth: 18
                    implicitHeight: 18
                    radius: 9
                    color: closeMa.containsMouse ? Qt.alpha(Atelier.red, 0.2) : Atelier.containerHigh
                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        font.family: Atelier.font
                        font.pixelSize: 10
                        color: closeMa.containsMouse ? Atelier.red : Atelier.subtext
                    }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifs.dismiss(root.notif)
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.notif ? root.notif.summary : ""
                font.family: Atelier.fontUi
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Atelier.text
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.notif ? root.notif.body : ""
                textFormat: Text.StyledText
                font.family: Atelier.fontUi
                font.pixelSize: 11
                color: Atelier.subtext
                wrapMode: Text.Wrap
                maximumLineCount: root.popup ? 3 : 4
                elide: Text.ElideRight
                linkColor: Atelier.blue
                onLinkActivated: (link) => Quickshell.execDetached(["xdg-open", link])
            }

            // Non-default actions as pill buttons
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: root.extraActions.length > 0
                spacing: 6
                Repeater {
                    model: root.extraActions
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: 14
                        color: actMa.containsMouse ? Qt.alpha(Atelier.accent, 0.22) : Atelier.containerHigh
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 16
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.text
                            font.family: Atelier.fontUi
                            font.pixelSize: 11
                            font.bold: true
                            color: actMa.containsMouse ? Atelier.accent : Atelier.text
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            id: actMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { modelData.invoke(); Notifs.dismiss(root.notif); }
                        }
                    }
                }
            }
        }
    }
}
