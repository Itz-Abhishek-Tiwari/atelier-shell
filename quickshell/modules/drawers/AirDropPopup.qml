import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// AirDrop card (services/AirDrop.qml), macOS-style: drops out of the top edge, centred.
//   asking     sender + what they're sharing · Decline / Accept · "always accept"
//   receiving  slim progress bar with time left
//   done       the photo itself · Open / Show in folder
//   sending    looking → sending → sent / failed
Item {
    id: root

    anchors { top: parent.top; left: parent.left; right: parent.right }
    height: drawer.bodyHeight + 60 + Atelier.maxInset
    readonly property bool showing: AirDrop.phase !== "idle" || AirDrop.sendPhase !== "idle"
    visible: drawer.visible || showing
    readonly property Item inputItem: drawer      // the host makes only this clickable

    // receiving wins over sending if both happen at once
    readonly property bool sendView: AirDrop.phase === "idle" && AirDrop.sendPhase !== "idle"
    property bool always: false
    Connections { target: AirDrop; function onPhaseChanged() { if (AirDrop.phase === "asking") root.always = false; } }

    readonly property string thumb: {
        if (AirDrop.phase !== "done") return "";
        const p = AirDrop.saved.find(s => /\.(jpe?g|png|webp|gif|bmp)$/i.test(s));
        return p ? "file://" + p : "";
    }

    // keep the last size while retracting so the drawer doesn't collapse before it closes
    property real heldHeight: 96
    onWantChanged: if (showing && want > 30) heldHeight = want
    readonly property real want: col.implicitHeight + 32

    EdgeDrawer {
        id: drawer
        edge: "top"
        open: root.showing
        bodyWidth: 400
        bodyHeight: root.heldHeight
        Behavior on bodyHeight {
            NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard }
        }

        ColumnLayout {
            id: col
            x: 16; y: 16
            width: parent.width - 32
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                // the photo when it's here, else the AirDrop mark
                Item {
                    Layout.preferredWidth: 56; Layout.preferredHeight: 56
                    Layout.alignment: Qt.AlignTop
                    Rectangle {
                        anchors.fill: parent
                        radius: 28
                        visible: root.thumb === ""
                        color: Qt.alpha(mark.tint, 0.14)
                        border.width: 1; border.color: Qt.alpha(mark.tint, 0.35)
                        Text {
                            id: mark
                            readonly property color tint: AirDrop.phase === "failed" || (root.sendView && AirDrop.sendPhase === "failed") ? Atelier.red
                                : AirDrop.phase === "done" || (root.sendView && AirDrop.sendPhase === "sent") ? Atelier.green
                                : Atelier.blue
                            anchors.centerIn: parent
                            // access-point (AirDrop-like waves), check, alert
                            text: tint === Atelier.green ? "\u{F012C}" : tint === Atelier.red ? "\u{F0028}" : "\u{F0003}"
                            font.family: Atelier.font; font.pixelSize: 26
                            color: tint
                        }
                        // pulse while waiting / receiving / looking
                        Rectangle {
                            id: pulse
                            anchors.centerIn: parent
                            width: parent.width; height: width; radius: width / 2
                            color: "transparent"; border.width: 2; border.color: Atelier.blue
                            readonly property bool busy: AirDrop.phase === "asking" || AirDrop.phase === "receiving"
                                || (root.sendView && (AirDrop.sendPhase === "looking" || AirDrop.sendPhase === "sending" || AirDrop.browsing))
                            visible: busy
                            opacity: 0
                            SequentialAnimation on scale {
                                running: pulse.busy && root.visible; loops: Animation.Infinite
                                NumberAnimation { from: 1; to: 1.35; duration: 1400; easing.type: Easing.OutCubic }
                            }
                            SequentialAnimation on opacity {
                                running: pulse.busy && root.visible; loops: Animation.Infinite
                                NumberAnimation { from: 0.6; to: 0; duration: 1400; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                    ClippingRectangle {
                        anchors.fill: parent
                        radius: Atelier.radiusMd
                        visible: root.thumb !== ""
                        color: Atelier.container
                        Image {
                            anchors.fill: parent
                            source: root.thumb
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 112; sourceSize.height: 112
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: AirDrop.openSaved() }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 3

                    Text {   // small app line, like macOS
                        text: "AIRDROP"
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMicro; font.weight: Font.DemiBold; font.letterSpacing: 1.4
                        color: Atelier.subtext
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.sendView
                            ? (AirDrop.sendPhase === "choose" ? "Choose a device"
                               : AirDrop.sendPhase === "looking" ? "Reaching " + AirDrop.sendTarget + "…"
                               : AirDrop.sendPhase === "sending" ? "Sending to " + AirDrop.sendTarget + "…"
                               : AirDrop.sendPhase === "sent" ? "Sent to " + AirDrop.sendTarget : "Couldn't send")
                            : AirDrop.phase === "asking" ? AirDrop.sender
                            : AirDrop.phase === "receiving" ? "Receiving from " + AirDrop.sender
                            : AirDrop.phase === "done" ? "Received from " + AirDrop.sender
                            : AirDrop.phase === "declined" ? "Declined"
                            : "AirDrop failed"
                        font.family: Atelier.fontUi; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: Atelier.text
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: root.sendView
                            ? (AirDrop.sendPhase === "failed" ? AirDrop.sendError
                               : (AirDrop.sendCount > 1 ? AirDrop.sendCount + " items" : AirDrop.sendName)
                                 + (AirDrop.sendPhase === "looking" ? " · keep it unlocked" : ""))
                            : AirDrop.phase === "asking" ? "would like to share " + AirDrop.kindOf(AirDrop.files) + " · " + Fmt.bytes(AirDrop.totalBytes)
                            : AirDrop.phase === "receiving" ? AirDrop.kindOf(AirDrop.files) + " · " + Fmt.bytes(AirDrop.totalBytes)
                                + " · about " + (AirDrop.secondsLeft >= 60 ? Math.ceil(AirDrop.secondsLeft / 60) + " min" : AirDrop.secondsLeft + " s") + " left"
                            : AirDrop.phase === "done" ? (AirDrop.saved.length === 1 ? AirDrop.saved[0].split("/").pop() : AirDrop.saved.length + " items")
                                + " · " + AirDrop.folder.replace(Quickshell.env("HOME"), "~")
                            : AirDrop.phase === "failed" ? (AirDrop.error || "Something went wrong")
                            : ""
                        visible: text !== ""
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd
                        color: AirDrop.phase === "failed" || (root.sendView && AirDrop.sendPhase === "failed") ? Atelier.red : Atelier.subtext
                    }
                }

                // close
                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 26; implicitHeight: 26; radius: 13
                    visible: AirDrop.phase !== "asking" && AirDrop.phase !== "receiving"
                    color: xMa.containsMouse ? Atelier.containerHigh : "transparent"
                    Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                    Text { anchors.centerIn: parent; text: "\u{F0156}"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: Atelier.subtext }
                    MouseArea { id: xMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AirDrop.dismiss() }
                }
            }

            // progress (receiving / sending)
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 6; radius: 3
                visible: AirDrop.phase === "receiving" || (root.sendView && AirDrop.sendPhase === "sending")
                color: Atelier.containerHigh
                Rectangle {
                    height: parent.height; radius: 3
                    readonly property bool sendKnown: AirDrop.phase !== "receiving" && AirDrop.sendProgress >= 0
                    width: AirDrop.phase === "receiving" ? Math.max(6, parent.width * AirDrop.progress)
                         : sendKnown ? Math.max(6, parent.width * AirDrop.sendProgress) : parent.width * 0.35
                    Behavior on width { NumberAnimation { duration: 240 } }
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.alpha(Atelier.blue, 0.55) }
                        GradientStop { position: 1; color: Atelier.blue }
                    }
                    // sending before owly reports bytes (the phone is still deciding): a bar that slides
                    property real slide: 0
                    x: sendKnown || AirDrop.phase === "receiving" ? 0 : slide
                    SequentialAnimation on slide {
                        running: root.sendView && AirDrop.sendPhase === "sending" && !parent.sendKnown && root.visible; loops: Animation.Infinite
                        NumberAnimation { from: 0; to: parent.width * 0.65; duration: 1100; easing.type: Easing.InOutSine }
                        NumberAnimation { from: parent.width * 0.65; to: 0; duration: 1100; easing.type: Easing.InOutSine }
                    }
                }
            }

            // choose: nearby receivers, like the macOS share sheet
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.sendView && AirDrop.sendPhase === "choose"
                spacing: 4

                Repeater {
                    model: AirDrop.devices
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: Atelier.radiusMd
                        color: dMa.containsMouse ? Atelier.containerHigh : Atelier.container
                        border.width: 1; border.color: Atelier.outline
                        scale: dMa.pressed ? 0.97 : 1
                        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                        Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 14
                            spacing: 12
                            Rectangle {
                                implicitWidth: 34; implicitHeight: 34; radius: Atelier.radiusLg
                                color: Qt.alpha(Atelier.blue, 0.14)
                                border.width: 1; border.color: Qt.alpha(Atelier.blue, 0.35)
                                Text {
                                    anchors.centerIn: parent
                                    readonly property string n: modelData.name.toLowerCase()
                                    // cellphone · tablet · laptop · generic
                                    text: n.indexOf("iphone") >= 0 ? "\u{F011C}" : n.indexOf("ipad") >= 0 ? "\u{F04F7}"
                                        : n.indexOf("mac") >= 0 ? "\u{F0322}" : "\u{F0003}"
                                    font.family: Atelier.font; font.pixelSize: 17; color: Atelier.blue
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                elide: Text.ElideRight
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.Medium
                                color: Atelier.text
                            }
                            Text { text: "\u{F0142}"; font.family: Atelier.font; font.pixelSize: 16; color: Atelier.subtext }
                        }
                        MouseArea { id: dMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: AirDrop.sendTo(modelData.name) }
                    }
                }

                // nothing yet
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    visible: AirDrop.devices.length === 0
                    wrapMode: Text.WordWrap
                    text: AirDrop.browsing
                        ? "Searching for nearby devices… On the iPhone: unlocked, AirDrop set to Everyone for 10 minutes."
                        : "No one found. Unlock the iPhone, set AirDrop to Everyone for 10 minutes, then search again."
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; lineHeight: 1.15
                    color: Atelier.subtext
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 8
                    Text {
                        visible: AirDrop.browsing && AirDrop.devices.length > 0
                        text: "Searching…"
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
                    }
                    Item { Layout.fillWidth: true }
                    Btn { label: "Search again"; visible: !AirDrop.browsing; onClicked: AirDrop.browse() }
                    Btn { label: "Cancel"; onClicked: AirDrop.cancelSend() }
                }
            }

            // asking: always-accept + Decline / Accept
            RowLayout {
                Layout.fillWidth: true
                visible: AirDrop.phase === "asking"
                spacing: 8

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18; radius: 6
                            color: root.always ? Atelier.accentFill : "transparent"
                            border.width: root.always ? 0 : 1.5; border.color: Atelier.overlay0
                            Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                            Text { anchors.centerIn: parent; visible: root.always; text: "\u{F012C}"; font.family: Atelier.font; font.pixelSize: Atelier.fsMd; color: Atelier.onFill }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Always accept"
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
                        }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.always = !root.always }
                }
                Btn { label: "Decline"; onClicked: AirDrop.decline() }
                Btn { label: "Accept"; primary: true; onClicked: AirDrop.accept(root.always) }
            }

            // done: Open / Show in folder
            RowLayout {
                Layout.fillWidth: true
                visible: AirDrop.phase === "done"
                spacing: 8
                Item { Layout.fillWidth: true }
                Btn { label: "Show in folder"; onClicked: AirDrop.showSaved() }
                Btn { label: "Open"; primary: true; onClicked: AirDrop.openSaved() }
            }
        }
    }

    component Btn: Rectangle {
        id: b
        property string label
        property bool primary: false
        signal clicked()
        implicitWidth: bt.implicitWidth + 32
        implicitHeight: 34
        radius: Atelier.radiusLg
        color: primary ? (bMa.containsMouse ? Qt.lighter(Atelier.accentFill, 1.1) : Atelier.accentFill)
             : (bMa.containsMouse ? Atelier.containerHigh : Atelier.container)
        border.width: primary ? 0 : 1; border.color: Atelier.outline
        scale: bMa.pressed ? 0.94 : 1
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
        Text {
            id: bt
            anchors.centerIn: parent
            text: b.label
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold
            color: b.primary ? Atelier.onFill : Atelier.text
        }
        MouseArea { id: bMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
}
