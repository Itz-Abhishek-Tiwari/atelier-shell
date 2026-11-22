import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.config
import qs.services

// One notification. Used by the pop-ups (popup: true → auto-expires, pauses on hover)
// and by the control center list. macOS-like:
//   [icon] App · iPhone                          now  ✕
//   Title                                            [image]
//   Body, up to 3 lines (4 when hovered)
//                                     [Action] [Reply]
//   Reply opens a field in the card (inline reply, e.g. Tether: answer an iPhone message).
Rectangle {
    id: root

    required property var notif
    property bool popup: false

    readonly property bool critical: notif && notif.urgency === NotificationUrgency.Critical
    readonly property string icon: notif ? Notifs.iconFor(notif) : ""
    // a real picture (contact photo, screenshot…): shown big on the right; app icons stay small
    // (Tether sends the iPhone app's icon as the image: that's an app icon, kept small in the header)
    readonly property string picture: notif && notif.image && !fromPhone ? notif.image : ""
    readonly property var hints: notif && notif.hints ? notif.hints : ({})
    // Tether mirrors the iPhone: show the phone's app ("Messages"), not "Tether"
    readonly property bool fromPhone: !!notif && (/tether/i.test(notif.desktopEntry || "") || notif.appName === "Tether")
    readonly property string appLabel: notif ? (hints["x-kde-display-appname"] || notif.appName || "Notification") : ""
    readonly property var extraActions: notif ? notif.actions.filter(a => a.identifier !== "default" && a.identifier !== "inline-reply" && a.text) : []
    readonly property bool canReply: !!notif && notif.hasInlineReply

    // the stack this card stands for (same app + title), newest first; 1 = just this one
    readonly property int stackCount: notif ? Notifs.groupOf(notif).length : 1
    readonly property bool stacked: stackCount > 1

    property bool replyOpen: false
    onReplyOpenChanged: Notifs.replying = replyOpen
    Component.onDestruction: if (replyOpen) Notifs.replying = false

    implicitHeight: layout.implicitHeight + 26
    // stacked look: two thin cards peeking out underneath (inside the delegate's own height)
    readonly property int stackPeek: stacked ? 8 : 0
    radius: 18
    color: Atelier.container
    border.width: 1
    border.color: critical ? Qt.alpha(Atelier.red, 0.6) : Atelier.outline
    Behavior on color { ColorAnimation { duration: 120 } }

    // calm hover: a faint wash over the card, no resizing
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Atelier.text
        opacity: hover.hovered ? 0.035 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }
    // the stack: two thinner cards peeking out underneath
    Repeater {
        model: root.stacked ? 2 : 0
        Rectangle {
            required property int index
            z: -1 - index
            anchors.horizontalCenter: parent.horizontalCenter
            // only the part below the card is drawn (the cards are a little see-through)
            y: root.height + index * 4
            width: root.width - (index + 1) * 18
            height: 4
            radius: 2
            color: Atelier.container
            border.width: 1
            border.color: Atelier.outline
            opacity: index === 0 ? 0.9 : 0.6
        }
    }

    // Close the pop-up when the app (or anyone) closes the notification
    Connections {
        target: root.notif
        function onClosed() { Notifs.hidePopup(root.notif); }
    }

    Timer {
        running: root.popup && Notifs.timeoutFor(root.notif) > 0 && !hover.hovered && !root.replyOpen
        interval: Notifs.timeoutFor(root.notif)
        onTriggered: Notifs.hidePopup(root.notif)
    }

    HoverHandler { id: hover }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: (m) => {
            if (root.replyOpen) return;
            if (m.button === Qt.LeftButton) { const n = root.notif; Notifs.activate(n); Notifs.dismissGroup(n); }
            else if (root.popup && m.button === Qt.RightButton) Notifs.hidePopup(root.notif);
            else Notifs.dismissGroup(root.notif);
        }
    }

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 13
        spacing: 8

        // ── header: small app icon · app (· iPhone) · time / close ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 7

            Item {
                implicitWidth: 18
                implicitHeight: 18
                ClippingRectangle {
                    anchors.fill: parent
                    radius: 5
                    visible: root.icon !== "" && root.icon !== root.picture
                    color: "transparent"
                    IconImage { anchors.fill: parent; source: root.icon; asynchronous: true }
                }
                Text {
                    anchors.centerIn: parent
                    visible: root.icon === "" || root.icon === root.picture
                    text: root.critical ? "󰀦" : root.fromPhone ? "󰄜" : "󰂚"
                    font.family: Atelier.font
                    font.pixelSize: 13
                    color: root.critical ? Atelier.red : Atelier.subtext
                }
            }
            Text {
                text: root.appLabel
                font.family: Atelier.fontUi
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: Atelier.subtext
                elide: Text.ElideRight
                Layout.maximumWidth: 180
            }
            // "· iPhone" marker for mirrored notifications
            Row {
                visible: root.fromPhone
                spacing: 3
                Text { text: "·"; font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext; opacity: 0.6 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰄜"; font.family: Atelier.font; font.pixelSize: 10; color: Atelier.subtext }
                Text { text: "iPhone"; font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext }
            }
            Item { Layout.fillWidth: true }
            Rectangle {     // "+4" more in this stack
                visible: root.stacked
                implicitWidth: stackText.implicitWidth + 12
                implicitHeight: 18
                radius: 9
                color: Qt.alpha(Atelier.accent, 0.14)
                Text {
                    id: stackText
                    anchors.centerIn: parent
                    text: "+" + (root.stackCount - 1)
                    font.family: Atelier.font
                    font.pixelSize: 10
                    font.bold: true
                    color: Atelier.accent
                }
            }
            Text {
                text: root.notif ? Notifs.timeAgo(Notifs.receivedAt(root.notif)) : ""
                font.family: Atelier.font
                font.pixelSize: 10
                color: Atelier.subtext
                opacity: 0.75
                visible: !closeBtn.visible
            }
            Rectangle {
                id: closeBtn
                visible: hover.hovered
                implicitWidth: 20
                implicitHeight: 20
                radius: 10
                color: closeMa.containsMouse ? Qt.alpha(Atelier.red, 0.18) : Atelier.containerHigh
                Text {
                    anchors.centerIn: parent
                    text: "󰅖"
                    font.family: Atelier.font
                    font.pixelSize: 11
                    color: closeMa.containsMouse ? Atelier.red : Atelier.subtext
                }
                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifs.dismissGroup(root.notif)
                }
            }
        }

        // ── title + body, with a picture on the right when there is one ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: root.notif ? root.notif.summary : ""
                    font.family: Atelier.fontUi
                    font.pixelSize: 14
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
                    font.pixelSize: 12
                    lineHeight: 1.12
                    color: Atelier.text
                    opacity: 0.78
                    wrapMode: Text.Wrap
                    maximumLineCount: root.popup ? 3 : 5
                    elide: Text.ElideRight
                    linkColor: Atelier.blue
                    onLinkActivated: (link) => Quickshell.execDetached(["xdg-open", link])
                }
            }
            ClippingRectangle {
                visible: root.picture !== ""
                Layout.alignment: Qt.AlignTop
                implicitWidth: 44
                implicitHeight: 44
                radius: 12
                color: Atelier.containerHigh
                Image {
                    anchors.fill: parent
                    source: root.picture
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 88
                    sourceSize.height: 88
                }
            }
        }

        // ── inline reply ──
        Rectangle {
            Layout.fillWidth: true
            visible: root.replyOpen
            implicitHeight: 36
            radius: 18
            color: Atelier.surface
            border.width: 1
            border.color: replyField.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 4
                spacing: 6
                TextInput {
                    id: replyField
                    Layout.fillWidth: true
                    clip: true
                    font.family: Atelier.fontUi
                    font.pixelSize: 12
                    color: Atelier.text
                    selectionColor: Qt.alpha(Atelier.accent, 0.35)
                    Text {
                        visible: !parent.text
                        text: root.notif && root.notif.inlineReplyPlaceholder ? root.notif.inlineReplyPlaceholder : "Reply…"
                        font: parent.font
                        color: Atelier.subtext
                    }
                    function send() {
                        if (!text.trim() || !root.notif) return;
                        root.notif.sendInlineReply(text.trim());
                        text = "";
                        root.replyOpen = false;
                        Notifs.dismiss(root.notif);
                    }
                    Keys.onReturnPressed: send()
                    Keys.onEnterPressed: send()
                    Keys.onEscapePressed: { text = ""; root.replyOpen = false; }
                }
                Rectangle {   // send
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: 14
                    color: replyField.text.trim() ? Atelier.accentFill : Atelier.containerHigh
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: "󰒊"
                        font.family: Atelier.font
                        font.pixelSize: 13
                        color: replyField.text.trim() ? Atelier.onFill : Atelier.subtext
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: replyField.send() }
                }
            }
        }

        // ── actions: compact pills on the right ──
        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: !root.replyOpen && (root.extraActions.length > 0 || root.canReply)
            layoutDirection: Qt.RightToLeft
            spacing: 6

            // Reply first in the code = rightmost on screen (the primary action)
            Pill {
                visible: root.canReply
                label: "Reply"
                glyph: "󰑚"
                primary: true
                onClicked: { root.replyOpen = true; replyField.forceActiveFocus(); }
            }
            Repeater {
                model: root.extraActions
                Pill {
                    required property var modelData
                    required property int index
                    label: modelData.text
                    quiet: true
                    onClicked: { modelData.invoke(); Notifs.dismiss(root.notif); }
                }
            }
        }
    }

    component Pill: Rectangle {
        id: pill
        property string label
        property string glyph: ""
        property bool primary: false
        property bool quiet: false          // plain text button (e.g. "Mute WhatsApp")
        signal clicked()
        width: pillRow.implicitWidth + (quiet ? 14 : 24)
        height: 28
        radius: 14
        color: primary ? (pillMa.containsMouse ? Qt.lighter(Atelier.accentFill, 1.08) : Atelier.accentFill)
             : quiet ? (pillMa.containsMouse ? Atelier.containerHigh : "transparent")
             : (pillMa.containsMouse ? Atelier.containerHigh : Atelier.surface)
        border.width: primary || quiet ? 0 : 1
        border.color: Atelier.outline
        scale: pillMa.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 100 } }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 5
            Text {
                visible: pill.glyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: pill.glyph
                font.family: Atelier.font
                font.pixelSize: 12
                color: pill.primary ? Atelier.onFill : Atelier.text
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.label
                font.family: Atelier.fontUi
                font.pixelSize: 11
                font.weight: pill.quiet ? Font.Medium : Font.DemiBold
                color: pill.primary ? Atelier.onFill : pill.quiet ? Atelier.subtext : Atelier.text
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 160)
            }
        }
        MouseArea { id: pillMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pill.clicked() }
    }
}
