import QtQuick
import Quickshell.Widgets
import qs.config
import qs.services

// Analog: a designer's wall clock. A "paper" background and "ink" hands taken from your theme (light
// themes: your base and text; dark themes: your text colour as paper, your darkest as ink), a big
// quiet dial, and a second hand in your accent. Typing slides the dial left and brings the login in.
Item {
    id: root
    required property var ph
    readonly property real u: ph.u
    readonly property bool a: ph.auth
    readonly property var lr: ph.lockRoot
    readonly property real dur: Atelier.durMedium

    readonly property color paper: Atelier.isLight ? Atelier.base : Atelier.text
    readonly property color ink: Atelier.isLight ? Atelier.text : Atelier.crust
    readonly property color mute: Qt.alpha(ink, 0.55)
    readonly property real dia: Math.min(height * 0.84, width * 0.5)
    readonly property real sec: ph.now.getSeconds()
    readonly property real minute: ph.now.getMinutes() + sec / 60
    readonly property real hour: (ph.now.getHours() % 12) + minute / 60

    Shaker { id: shaker; ph: root.ph }

    Rectangle { anchors.fill: parent; color: root.paper }

    Item {
        id: dial
        width: root.dia; height: root.dia
        x: root.a ? 0.05 * root.width : (root.width - width) / 2
        y: (root.height - height) / 2
        scale: root.a ? 0.8 : 1
        transformOrigin: Item.Left
        Behavior on x { NumberAnimation { duration: root.dur; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }
        Behavior on scale { NumberAnimation { duration: root.dur; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }

        Repeater {
            model: 60
            Item {
                required property int index
                readonly property bool five: index % 5 === 0
                width: dial.width; height: dial.height
                rotation: index * 6
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: dial.height * 0.015
                    width: parent.five ? dial.width * 0.008 : dial.width * 0.003
                    height: parent.five ? dial.height * 0.04 : dial.height * 0.02
                    color: root.ink
                    opacity: parent.five ? 1 : 0.6
                }
            }
        }
        Repeater {
            model: 12
            Text {
                required property int index
                readonly property real ang: (index + 1) * Math.PI / 6
                readonly property real r: dial.width * 0.375
                x: dial.width / 2 + r * Math.sin(ang) - width / 2
                y: dial.height / 2 - r * Math.cos(ang) - height / 2
                text: index + 1
                font.family: ph.display; font.pixelSize: dial.width * 0.075; font.weight: Font.Medium
                color: root.ink
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: dial.height * 0.3
            text: "ATELIER"
            font.family: ph.display; font.pixelSize: dial.width * 0.026; font.weight: Font.Bold; font.letterSpacing: dial.width * 0.01
            color: root.mute
        }
        Rectangle {   // hour
            x: dial.width / 2 - width / 2; y: dial.height / 2 - height
            width: dial.width * 0.026; height: dial.height * 0.24; radius: Atelier.rounding > 0 ? width / 2 : 0; color: root.ink
            transform: Rotation { origin.x: dial.width * 0.013; origin.y: dial.height * 0.24; angle: root.hour * 30 }
        }
        Rectangle {   // minute
            x: dial.width / 2 - width / 2; y: dial.height / 2 - height
            width: dial.width * 0.017; height: dial.height * 0.36; radius: Atelier.rounding > 0 ? width / 2 : 0; color: root.ink
            transform: Rotation { origin.x: dial.width * 0.0085; origin.y: dial.height * 0.36; angle: root.minute * 6 }
        }
        Item {        // second
            x: dial.width / 2 - width / 2; y: dial.height / 2 - dial.height * 0.42
            width: dial.width * 0.008; height: dial.height * 0.5
            transform: Rotation { origin.x: dial.width * 0.004; origin.y: dial.height * 0.42; angle: root.sec * 6 }
            Rectangle { anchors.fill: parent; color: Atelier.accent }
        }
        Rectangle { anchors.centerIn: parent; width: dial.width * 0.045; height: width; radius: width / 2; color: root.ink }
        Rectangle { anchors.centerIn: parent; width: dial.width * 0.018; height: width; radius: width / 2; color: Atelier.accent }
    }

    // ── the normal screen: date on the left, weather on the right ──
    Item {
        anchors.fill: parent
        opacity: root.a ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.dur } }
        Column {
            anchors.left: parent.left; anchors.leftMargin: 0.05 * root.width
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4 * root.u
            Text { text: Qt.formatDate(ph.now, "dddd"); font.family: ph.display; font.pixelSize: 64 * root.u; font.weight: Font.DemiBold; color: root.ink }
            Text { text: Qt.formatDate(ph.now, "d MMMM"); font.family: ph.display; font.pixelSize: 40 * root.u; color: root.mute }
            Text { text: Qt.formatDate(ph.now, "yyyy"); font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.7; color: root.mute }
        }
        Column {
            anchors.right: parent.right; anchors.rightMargin: 0.05 * root.width
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * root.u
            Text { anchors.right: parent.right; visible: ph.temp !== ""; text: ph.temp; font.family: ph.display; font.pixelSize: 64 * root.u; font.weight: Font.DemiBold; color: root.ink }
            Text { anchors.right: parent.right; visible: ph.condition !== ""; text: ph.condition; font.family: ph.display; font.pixelSize: 36 * root.u; color: root.mute }
            Text { anchors.right: parent.right; visible: ph.hasBattery; text: ph.batPct + "% " + (ph.charging ? "charging" : "battery"); font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.7; color: root.mute }
            Text { anchors.right: parent.right; visible: ph.notifs.length > 0; text: ph.countText; font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.7; color: root.mute }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 0.03 * root.height
            text: "type to unlock"
            font.family: ph.display; font.pixelSize: Atelier.fsMd * ph.ts; font.letterSpacing: 6 * root.u; color: root.mute
        }
    }

    // ── the password screen, to the right of the dial ──
    Item {
        anchors.fill: parent
        opacity: root.a ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.dur } }
        Column {
            x: 0.6 * root.width
            anchors.verticalCenter: parent.verticalCenter
            width: 0.3 * root.width
            spacing: 24 * root.u
            ClippingRectangle {
                width: 130 * root.u; height: width
                radius: Atelier.rounding > 0 ? width / 2 : 0
                color: Qt.alpha(root.ink, 0.12)
                border.width: Math.max(1, 3 * root.u); border.color: Atelier.accent
                Image { id: pic; anchors.fill: parent; source: Profile.faceUrl; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 260; sourceSize.height: 260 }
                Text { anchors.centerIn: parent; visible: pic.status !== Image.Ready; text: Atelier.userName.charAt(0).toUpperCase()
                    font.family: ph.display; font.pixelSize: 56 * root.u; color: root.ink }
            }
            Text { text: Atelier.userName; font.family: ph.display; font.pixelSize: 64 * root.u; font.weight: Font.DemiBold; color: root.ink }
            Item {
                width: parent.width; height: 70 * root.u
                transform: Translate { x: shaker.dx }
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    visible: root.lr.buffer.length === 0
                    text: root.lr.checking ? "Checking…" : "Password"
                    font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.5; color: root.mute
                }
                Row {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    spacing: 12 * root.u
                    Repeater {
                        model: Math.min(root.lr.buffer.length, 16)
                        Rectangle {
                            width: 16 * root.u; height: width; radius: Atelier.rounding > 0 ? width / 2 : 0; color: root.ink
                            scale: 0
                            Component.onCompleted: scale = 1
                            Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutBack } }
                        }
                    }
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    visible: root.lr.buffer.length > 0 || root.lr.checking
                    text: root.lr.checking ? "󰑐" : "󰁔"
                    font.family: Atelier.font; font.pixelSize: Atelier.fsXl * ph.ts * 2; color: Atelier.accent
                    RotationAnimation on rotation { running: root.lr.checking; loops: Animation.Infinite; from: 0; to: 360; duration: 800 }
                    MouseArea { anchors.fill: parent; anchors.margins: -12; cursorShape: Qt.PointingHandCursor; onClicked: root.lr.submit() }
                }
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 3 * root.u
                    color: root.lr.message ? Atelier.red : root.ink
                    Behavior on color { ColorAnimation { duration: Atelier.durFast } } }
            }
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: root.lr.message ? root.lr.message : ph.capsOn ? "Caps Lock is on" : ph.isPreview ? "Preview · Esc to go back" : "Enter to unlock · Esc to go back"
                font.family: ph.display; font.pixelSize: Atelier.fsLg * ph.ts * 1.1
                color: root.lr.message ? Atelier.red : root.mute
            }
        }
        AuthPower {
            ph: root.ph
            x: 0.6 * root.width
            anchors.bottom: parent.bottom; anchors.bottomMargin: 0.06 * root.height
            ink: root.ink; fill: Qt.alpha(root.ink, 0.1); btnRadius: Atelier.rounding; family: ph.display
        }
    }
}
