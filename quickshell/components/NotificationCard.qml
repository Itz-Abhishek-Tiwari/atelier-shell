import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.config
import qs.services

// One notification, compact and macOS-like. Used by the pop-ups (popup: true → auto-expires,
// pauses on hover) and by the control center list.
//
//   [icon]  Title ……………………………… +3  2m
//           Message, up to 2 lines (pop-up) / 3 (list)          [picture]
//           WhatsApp · iPhone            (hover:)  Mute WhatsApp  ✕
//
// - The app icon sits on the left; the source is a quiet line under the message.
// - Actions (Mute…, Open…) only show on hover, in that line, so the card never grows.
//   Reply (inline reply, e.g. an iPhone message through Tether) is always visible.
// - A stack (same app + title, Notifs.groupOf) is one card with a +N badge and two thin
//   strips peeking out underneath; ✕ / click clear the whole stack.
Rectangle {
    id: root

    required property var notif
    property bool popup: false
    // the pop-up column is hovered: every card waits, not just the one under the cursor
    property bool paused: false

    readonly property bool critical: notif && notif.urgency === NotificationUrgency.Critical
    readonly property var hints: notif && notif.hints ? notif.hints : ({})
    // Tether mirrors the iPhone: show the phone's app ("WhatsApp"), not "Tether"
    readonly property bool fromPhone: !!notif && (/tether/i.test(notif.desktopEntry || "") || notif.appName === "Tether")
    readonly property string appLabel: notif ? (hints["x-kde-display-appname"] || notif.appName || "Notification") : ""
    readonly property string icon: notif ? Notifs.iconFor(notif) : ""
    // a real picture (contact photo, screenshot…) shown on the right; Tether's image is an app icon
    readonly property string picture: notif && notif.image && !fromPhone && notif.image !== icon ? notif.image : ""
    readonly property var extraActions: notif ? notif.actions.filter(a => a.identifier !== "default" && a.identifier !== "inline-reply" && a.text) : []
    readonly property bool canReply: !!notif && notif.hasInlineReply

    readonly property int stackCount: notif ? Notifs.groupOf(notif).length : 1
    readonly property bool stacked: stackCount > 1

    property bool replyOpen: false
    // a stack opens in place on click (older messages listed under the newest); open/clear
    // then happen per message, instead of one click throwing the whole stack away
    property bool expanded: false
    readonly property var older: notif && stacked ? Notifs.groupOf(notif).slice(1, 8) : []
    onStackedChanged: if (!stacked) expanded = false
    onReplyOpenChanged: Notifs.replying = replyOpen
    Component.onDestruction: if (replyOpen) Notifs.replying = false

    readonly property bool hovered: hover.hovered

    implicitHeight: body.implicitHeight + 28
    radius: Atelier.radiusLg
    // pop-ups float on their own: the shell's surface + a hairline; in the control center list
    // they sit on its panel: a faint card, no border
    color: popup ? Atelier.surface : (hovered ? Atelier.containerHigh : Atelier.container)
    border.width: critical || popup ? 1 : 0
    border.color: critical ? Qt.alpha(Atelier.red, 0.6) : Atelier.outline
    Behavior on color { ColorAnimation { duration: Atelier.durFast } }
    // hover on a pop-up: a faint wash (its surface colour itself stays put)
    Rectangle {
        visible: root.popup
        anchors.fill: parent
        radius: parent.radius
        color: Atelier.text
        opacity: root.hovered ? 0.04 : 0
        Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
    }

    // the stack: two thin strips peeking out underneath
    Repeater {
        model: root.stacked ? 2 : 0
        Rectangle {
            required property int index
            z: -1 - index
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.height + index * 4
            width: root.width - (index + 1) * 18
            height: 4
            radius: 2
            color: root.popup ? Atelier.surface : Atelier.container
            border.width: root.popup ? 1 : 0
            border.color: Atelier.outline
            opacity: index === 0 ? 0.9 : 0.55
        }
    }

    Connections {
        target: root.notif
        function onClosed() { Notifs.hidePopup(root.notif); }
    }
    Timer {
        running: root.popup && Notifs.timeoutFor(root.notif) > 0 && !hover.hovered && !root.paused && !root.replyOpen && !root.expanded
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
            if (m.button === Qt.LeftButton) {
                if (root.stacked && !root.expanded) { root.expanded = true; return; }
                const n = root.notif; Notifs.activate(n); Notifs.dismissGroup(n);
            }
            else if (root.popup && m.button === Qt.RightButton) Notifs.hidePopup(root.notif);
            else Notifs.dismissGroup(root.notif);
        }
    }

    RowLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 14
        spacing: 12

        // ── app icon ──
        Item {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 36
            implicitHeight: 36
            ClippingRectangle {
                anchors.fill: parent
                radius: Atelier.radiusSm
                visible: root.icon !== ""
                color: "transparent"
                IconImage { anchors.fill: parent; source: root.icon; asynchronous: true }
            }
            Rectangle {
                anchors.fill: parent
                radius: Atelier.radiusSm
                visible: root.icon === ""
                color: Qt.alpha(root.critical ? Atelier.red : Atelier.accent, 0.16)
                Text {
                    anchors.centerIn: parent
                    text: root.critical ? "󰀦" : root.fromPhone ? "󰄜" : "󰂚"
                    font.family: Atelier.font
                    font.pixelSize: Atelier.fsXl
                    color: root.critical ? Atelier.red : Atelier.accent
                }
            }
        }

        // ── text ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 2

            // title · +N · time
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.notif ? (root.notif.summary || root.appLabel) : ""
                    font.family: Atelier.fontUi
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Atelier.text
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                Rectangle {
                    visible: root.stacked
                    implicitWidth: stackText.implicitWidth + 10
                    implicitHeight: 16
                    radius: Atelier.radiusSm
                    color: Qt.alpha(Atelier.accent, 0.16)
                    Text {
                        id: stackText
                        anchors.centerIn: parent
                        text: "+" + (root.stackCount - 1)
                        font.family: Atelier.font
                        font.pixelSize: Atelier.fsMicro
                        font.bold: true
                        color: Atelier.accent
                    }
                }
                Text {
                    text: root.notif ? Notifs.timeAgo(Notifs.receivedAt(root.notif)) : ""
                    font.family: Atelier.font
                    font.pixelSize: Atelier.fsMicro
                    color: Atelier.subtext
                    opacity: 0.8
                }
            }

            // message (+ picture on the right)
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: msg.visible || root.picture !== ""
                Text {
                    id: msg
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    visible: text.length > 0 && Settings.notifications.showBody
                    text: root.notif ? root.notif.body : ""
                    textFormat: Text.StyledText
                    font.family: Atelier.fontUi
                    font.pixelSize: Atelier.fsLg
                    lineHeight: 1.1
                    color: Atelier.text
                    opacity: 0.8
                    wrapMode: Text.Wrap
                    maximumLineCount: root.popup ? 2 : 3
                    elide: Text.ElideRight
                    linkColor: Atelier.accent
                    onLinkActivated: (link) => Quickshell.execDetached(["xdg-open", link])
                }
                ClippingRectangle {
                    visible: root.picture !== ""
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: Atelier.radiusSm
                    color: Atelier.containerHigh
                    Image {
                        anchors.fill: parent
                        source: root.picture
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 80
                        sourceSize.height: 80
                    }
                }
            }

            // the rest of the stack, when opened: one line each, click to open that one
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: root.expanded && root.older.length > 0
                spacing: 2
                Repeater {
                    model: root.expanded ? root.older : []
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: oldRow.implicitHeight + 10
                        radius: Atelier.radiusSm
                        color: oldMa.containsMouse ? Atelier.containerHigh : "transparent"
                        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                        RowLayout {
                            id: oldRow
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 6; anchors.rightMargin: 6
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: Settings.notifications.showBody ? (modelData.body || modelData.summary) : modelData.summary
                                textFormat: Text.StyledText
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd
                                color: Atelier.text; opacity: 0.75
                                elide: Text.ElideRight; maximumLineCount: 1
                            }
                            Text {
                                text: Notifs.timeAgo(Notifs.receivedAt(modelData))
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                                color: Atelier.subtext; opacity: 0.9
                            }
                        }
                        MouseArea { id: oldMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: Notifs.activate(modelData) }
                    }
                }
                Text {
                    Layout.leftMargin: 6
                    Layout.topMargin: 2
                    text: "Show less"
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; font.weight: Font.DemiBold
                    color: lessMa.containsMouse ? Atelier.accent : Atelier.subtext
                    MouseArea { id: lessMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor; onClicked: root.expanded = false }
                }
            }

            // inline reply
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: root.replyOpen
                implicitHeight: 34
                radius: Atelier.radiusLg
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
                        font.pixelSize: Atelier.fsMd
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
                    Rectangle {
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: 13
                        color: replyField.text.trim() ? Qt.alpha(Atelier.accent, 0.22) : Atelier.containerHigh
                        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                        Text {
                            anchors.centerIn: parent
                            text: "󰒊"
                            font.family: Atelier.font
                            font.pixelSize: Atelier.fsMd
                            color: replyField.text.trim() ? Atelier.accent : Atelier.subtext
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: replyField.send() }
                    }
                }
            }

            // source · actions on hover · Reply · ✕   (one fixed-height line: nothing jumps)
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: !root.replyOpen
                Layout.preferredHeight: 22
                Layout.minimumHeight: 22
                Layout.maximumHeight: 22
                spacing: 4

                Row {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 4
                    clip: true
                    Text {
                        visible: Settings.notifications.showSource
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.appLabel
                        font.family: Atelier.fontUi
                        font.pixelSize: Atelier.fsMicro
                        font.weight: Font.Medium
                        color: Atelier.subtext
                        opacity: 0.85
                    }
                    Text {
                        visible: root.fromPhone && Settings.notifications.showSource
                        anchors.verticalCenter: parent.verticalCenter
                        text: "· 󰄜 iPhone"
                        font.family: Atelier.fontUi
                        font.pixelSize: Atelier.fsMicro
                        color: Atelier.subtext
                        opacity: 0.7
                    }
                }
                // the app's own actions, only while hovered
                Repeater {
                    model: root.hovered ? root.extraActions : []
                    TextBtn {
                        required property var modelData
                        label: modelData.text
                        onClicked: { modelData.invoke(); Notifs.dismiss(root.notif); }
                    }
                }
                TextBtn {
                    visible: root.canReply
                    label: "Reply"
                    glyph: "󰑚"
                    accent: true
                    onClicked: { root.replyOpen = true; replyField.forceActiveFocus(); }
                }
                // clear (the whole stack)
                Rectangle {
                    visible: root.hovered
                    implicitWidth: 22
                    implicitHeight: 22
                    radius: 11
                    color: xMa.containsMouse ? Qt.alpha(Atelier.red, 0.18) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        font.family: Atelier.font
                        font.pixelSize: Atelier.fsMd
                        color: xMa.containsMouse ? Atelier.red : Atelier.subtext
                    }
                    MouseArea { id: xMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.dismissGroup(root.notif) }
                }
            }
        }
    }

    // a small text button; accent = the primary one (Reply), a soft accent tint
    component TextBtn: Rectangle {
        id: tb
        property string label
        property string glyph: ""
        property bool accent: false
        signal clicked()
        implicitWidth: tbRow.implicitWidth + 16
        implicitHeight: 22
        radius: 11
        color: accent ? Qt.alpha(Atelier.accent, (Atelier.isLight ? 0.14 : 0.2) + (tbMa.containsMouse ? 0.06 : 0))
             : (tbMa.containsMouse ? Atelier.containerHigh : "transparent")
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Row {
            id: tbRow
            anchors.centerIn: parent
            spacing: 4
            Text {
                visible: tb.glyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: tb.glyph
                font.family: Atelier.font
                font.pixelSize: Atelier.fsSm
                color: tb.accent ? Atelier.accent : Atelier.subtext
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tb.label
                font.family: Atelier.fontUi
                font.pixelSize: Atelier.fsSm
                font.weight: Font.DemiBold
                color: tb.accent ? Atelier.accent : Atelier.subtext
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 140)
            }
        }
        MouseArea { id: tbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked() }
    }
}
