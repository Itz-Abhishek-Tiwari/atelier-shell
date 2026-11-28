import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// HUD: a thin-lined dashboard. Dark grid backdrop, corner brackets, and panels for the time,
// date, weather, power, network and notifications. Draws the whole screen.
Item {
    id: root
    required property var ph
    readonly property real u: ph.u
    readonly property color line: Qt.alpha(Atelier.accent, 0.55)
    readonly property color faint: Qt.alpha(Atelier.text, 0.05)
    readonly property string mono: Atelier.font
    readonly property bool a: ph.auth
    readonly property var lr: ph.lockRoot
    readonly property real dur: Atelier.durMedium
    property bool cursorOn: true

    Timer {
        interval: 550; repeat: true; running: !ph.thumb && ph.lockRoot.active
        onTriggered: root.cursorOn = !root.cursorOn
    }

    Shaker { id: shaker; ph: root.ph }

    Rectangle { anchors.fill: parent; color: Atelier.crust }

    // grid
    Repeater {
        model: Math.max(0, Math.ceil(root.width / Math.max(1, 96 * root.u)) + 1)
        Rectangle { required property int index; x: index * 96 * root.u; width: 1; height: root.height; color: root.faint }
    }
    Repeater {
        model: Math.max(0, Math.ceil(root.height / Math.max(1, 96 * root.u)) + 1)
        Rectangle { required property int index; y: index * 96 * root.u; height: 1; width: root.width; color: root.faint }
    }

    // corner brackets
    Repeater {
        model: [{ ax: 0, ay: 0 }, { ax: 1, ay: 0 }, { ax: 0, ay: 1 }, { ax: 1, ay: 1 }]
        Item {
            required property var modelData
            x: modelData.ax ? root.width - width - 34 * root.u : 34 * root.u
            y: modelData.ay ? root.height - height - 34 * root.u : 34 * root.u
            width: 70 * root.u; height: 70 * root.u
            Rectangle { x: modelData.ax ? parent.width - width : 0; y: modelData.ay ? parent.height - height : 0; width: parent.width; height: 3 * root.u; color: Atelier.accent }
            Rectangle { x: modelData.ax ? parent.width - width : 0; y: modelData.ay ? parent.height - height : 0; width: 3 * root.u; height: parent.height; color: Atelier.accent }
        }
    }

    // header strip
    Row {
        x: 0.07 * root.width; y: 0.075 * root.height
        spacing: 22 * root.u
        Text { text: "ATELIER // SESSION LOCKED"; font.family: root.mono; font.pixelSize: 22 * root.u; font.letterSpacing: 4 * root.u; color: Atelier.accent }
        Text { text: Atelier.userName.toUpperCase(); font.family: root.mono; font.pixelSize: 22 * root.u; font.letterSpacing: 4 * root.u; color: Qt.alpha(Atelier.text, 0.55) }
    }

    // ── time panel ──
    Rectangle {
        id: timeBox
        x: 0.07 * root.width; y: 0.15 * root.height
        width: 0.5 * root.width; height: 0.47 * root.height
        color: Qt.alpha(Atelier.accent, 0.05); border.width: Math.max(1, 2 * root.u); border.color: root.line
        Text { x: 20 * root.u; y: 14 * root.u; text: "[ LOCAL TIME ]"; opacity: root.a ? 0 : 1; font.family: root.mono; font.pixelSize: 20 * root.u; font.letterSpacing: 3 * root.u; color: Atelier.accent }
        Row {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 12 * root.u
            spacing: 12 * root.u
            opacity: root.a ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: root.dur } }
            Text {
                text: ph.hh + ":" + ph.mm
                font.family: root.mono; font.pixelSize: 290 * root.u; font.weight: Font.Light
                renderType: Text.CurveRendering
                color: Atelier.text
            }
            Column {
                anchors.bottom: parent.bottom; anchors.bottomMargin: 42 * root.u
                Text { text: Qt.formatTime(ph.now, "ss"); font.family: root.mono; font.pixelSize: 64 * root.u; color: Atelier.accent }
                Text { visible: ph.ampm !== ""; text: ph.ampm; font.family: root.mono; font.pixelSize: 30 * root.u; color: Qt.alpha(Atelier.text, 0.6) }
            }
        }
    }

    // ── the password screen, in the time panel ──
    Item {
        x: timeBox.x; y: timeBox.y; width: timeBox.width; height: timeBox.height
        opacity: root.a ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.dur } }
        Text { x: 20 * root.u; y: 14 * root.u; text: "[ AUTHENTICATE ]"; font.family: root.mono; font.pixelSize: 20 * root.u; font.letterSpacing: 3 * root.u; color: Atelier.accent }
        ClippingRectangle {
            anchors.right: parent.right; anchors.rightMargin: 40 * root.u; anchors.top: parent.top; anchors.topMargin: 70 * root.u
            width: 210 * root.u; height: width; radius: Atelier.rounding
            color: Qt.alpha(Atelier.accent, 0.1); border.width: Math.max(1, 2 * root.u); border.color: root.line
            Image { id: pic; anchors.fill: parent; source: Profile.faceUrl; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 400; sourceSize.height: 400 }
            Text { anchors.centerIn: parent; visible: pic.status !== Image.Ready; text: Atelier.userName.charAt(0).toUpperCase(); font.family: root.mono; font.pixelSize: 90 * root.u; color: Atelier.accent }
        }
        Column {
            x: 40 * root.u; y: 84 * root.u
            width: parent.width - 330 * root.u
            spacing: 30 * root.u
            Row {
                spacing: 26 * root.u
                Text { width: 150 * root.u; text: "USER"; font.family: root.mono; font.pixelSize: Atelier.fsXl * ph.ts * 1.6; color: Qt.alpha(Atelier.text, 0.5) }
                Text { text: Atelier.userName.toUpperCase(); font.family: root.mono; font.pixelSize: Atelier.fsXl * ph.ts * 2.2; font.letterSpacing: 3 * root.u; color: Atelier.text }
            }
            Row {
                spacing: 26 * root.u
                transform: Translate { x: shaker.dx }
                Text { width: 150 * root.u; text: "PASS"; font.family: root.mono; font.pixelSize: Atelier.fsXl * ph.ts * 1.6; color: Qt.alpha(Atelier.text, 0.5) }
                Rectangle {
                    width: 0.5 * timeBox.width - 80 * root.u; height: 76 * root.u
                    color: Qt.alpha(Atelier.accent, 0.08)
                    border.width: Math.max(1, 2 * root.u); border.color: root.lr.message ? Atelier.red : Atelier.accent
                    Behavior on border.color { CAnim {} }
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 18 * root.u; anchors.verticalCenter: parent.verticalCenter
                        text: "*".repeat(Math.min(root.lr.buffer.length, 20)) + (root.cursorOn ? "_" : " ")
                        font.family: root.mono; font.pixelSize: Atelier.fsXl * ph.ts * 2.2; font.letterSpacing: 4 * root.u; color: Atelier.accent
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 14 * root.u; anchors.verticalCenter: parent.verticalCenter
                        visible: root.lr.buffer.length > 0 && !root.lr.checking
                        text: "[ENTER]"; font.family: root.mono; font.pixelSize: Atelier.fsMd * ph.ts; color: Qt.alpha(Atelier.text, 0.6)
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.lr.submit() }
                    }
                }
            }
            Row {
                spacing: 26 * root.u
                Text { width: 150 * root.u; text: "STATE"; font.family: root.mono; font.pixelSize: Atelier.fsXl * ph.ts * 1.6; color: Qt.alpha(Atelier.text, 0.5) }
                Text {
                    text: root.lr.checking ? "VERIFYING..." : root.lr.message ? "ACCESS DENIED  (" + root.lr.failCount + ")"
                          : ph.capsOn ? "CAPS LOCK ON" : ph.isPreview ? "PREVIEW  /  ESC TO GO BACK" : "AWAITING INPUT"
                    font.family: root.mono; font.pixelSize: Atelier.fsXl * ph.ts * 1.6; font.letterSpacing: 2 * root.u
                    color: root.lr.message ? Atelier.red : ph.capsOn ? Atelier.yellow : Atelier.accent
                    Behavior on color { CAnim {} }
                }
            }
            // verification progress
            Rectangle {
                width: parent.width; height: 8 * root.u; color: Qt.alpha(Atelier.text, 0.08)
                Rectangle {
                    id: bar
                    height: parent.height; color: Atelier.accent
                    width: root.lr.checking ? parent.width : 0
                    Behavior on width { NumberAnimation { duration: root.lr.checking ? 1400 : 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.emphasizedDecel } }
                }
            }
        }
    }

    // ── date panel ──
    Rectangle {
        x: timeBox.x; y: timeBox.y + timeBox.height + 22 * root.u
        width: timeBox.width; height: 0.15 * root.height
        color: Qt.alpha(Atelier.accent, 0.05); border.width: Math.max(1, 2 * root.u); border.color: root.line
        Text { x: 20 * root.u; y: 12 * root.u; text: "[ DATE ]"; font.family: root.mono; font.pixelSize: 20 * root.u; font.letterSpacing: 3 * root.u; color: Atelier.accent }
        Text {
            anchors.centerIn: parent; anchors.verticalCenterOffset: 14 * root.u
            text: Qt.formatDate(ph.now, "dddd, d MMMM yyyy").toUpperCase()
            font.family: root.mono; font.pixelSize: 44 * root.u; font.letterSpacing: 4 * root.u; color: Atelier.text
        }
    }

    // ── right column ──
    Column {
        x: timeBox.x + timeBox.width + 26 * root.u
        y: timeBox.y
        width: root.width - x - 0.07 * root.width
        spacing: 22 * root.u

        Rectangle {   // weather
            width: parent.width; height: 0.2 * root.height
            color: Qt.alpha(Atelier.accent, 0.05); border.width: Math.max(1, 2 * root.u); border.color: root.line
            Text { x: 20 * root.u; y: 12 * root.u; text: "[ WEATHER ]"; font.family: root.mono; font.pixelSize: 20 * root.u; font.letterSpacing: 3 * root.u; color: Atelier.accent }
            Text {
                anchors.centerIn: parent; anchors.verticalCenterOffset: 12 * root.u
                text: ph.temp !== "" ? ph.temp : "--"
                font.family: root.mono; font.pixelSize: 96 * root.u; color: Atelier.text
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 24 * root.u; anchors.bottom: parent.bottom; anchors.bottomMargin: 16 * root.u
                text: ph.condition.toUpperCase(); font.family: root.mono; font.pixelSize: 22 * root.u; color: Qt.alpha(Atelier.text, 0.6)
            }
        }

        Rectangle {   // power
            width: parent.width; height: 0.23 * root.height
            color: Qt.alpha(Atelier.accent, 0.05); border.width: Math.max(1, 2 * root.u); border.color: root.line
            Text { x: 20 * root.u; y: 12 * root.u; text: "[ POWER ]"; font.family: root.mono; font.pixelSize: 20 * root.u; font.letterSpacing: 3 * root.u; color: Atelier.accent }
            Item {
                id: ring
                anchors.left: parent.left; anchors.leftMargin: 34 * root.u
                anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: 14 * root.u
                width: 128 * root.u; height: width
                Shape {
                    anchors.fill: parent
                    ShapePath {
                        strokeColor: Qt.alpha(Atelier.text, 0.14); strokeWidth: 10 * root.u; fillColor: "transparent"
                        PathAngleArc { centerX: ring.width / 2; centerY: ring.height / 2; radiusX: ring.width / 2 - 6 * root.u; radiusY: ring.height / 2 - 6 * root.u; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        strokeColor: ph.batPct <= 15 && !ph.charging ? Atelier.red : Atelier.accent
                        strokeWidth: 10 * root.u; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: ring.width / 2; centerY: ring.height / 2; radiusX: ring.width / 2 - 6 * root.u; radiusY: ring.height / 2 - 6 * root.u; startAngle: -90; sweepAngle: 360 * Math.max(0.02, ph.batPct / 100) }
                    }
                }
                Text { anchors.centerIn: parent; text: ph.hasBattery ? ph.batPct : "AC"; font.family: root.mono; font.pixelSize: 34 * root.u; color: Atelier.text }
            }
            Column {
                anchors.left: ring.right; anchors.leftMargin: 28 * root.u
                anchors.verticalCenter: ring.verticalCenter
                spacing: 4 * root.u
                Text { text: ph.hasBattery ? (ph.charging ? "CHARGING" : "ON BATTERY") : "MAINS"; font.family: root.mono; font.pixelSize: Atelier.iconLg * root.u; color: Atelier.text }
                Text { visible: ph.hasBattery; text: ph.batPct + " PERCENT"; font.family: root.mono; font.pixelSize: 20 * root.u; color: Qt.alpha(Atelier.text, 0.55) }
            }
        }

        Rectangle {   // network and notifications
            width: parent.width; height: 0.17 * root.height
            color: Qt.alpha(Atelier.accent, 0.05); border.width: Math.max(1, 2 * root.u); border.color: root.line
            Text { x: 20 * root.u; y: 12 * root.u; text: "[ LINK ]"; font.family: root.mono; font.pixelSize: 20 * root.u; font.letterSpacing: 3 * root.u; color: Atelier.accent }
            Column {
                anchors.left: parent.left; anchors.leftMargin: 24 * root.u
                anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: 14 * root.u
                spacing: 8 * root.u
                Text { text: SysState.wifiIcon + "  " + (SysState.wifiConnected ? SysState.ssid : "OFFLINE"); font.family: root.mono; font.pixelSize: Atelier.iconLg * root.u; color: Atelier.text }
                Text { text: "󰂚  " + ph.notifs.length + " UNREAD"; font.family: root.mono; font.pixelSize: Atelier.iconLg * root.u; color: ph.notifs.length > 0 ? Atelier.accent : Qt.alpha(Atelier.text, 0.55) }
            }
        }
    }

    // prompt
    Text {
        x: 0.07 * root.width
        anchors.bottom: parent.bottom; anchors.bottomMargin: 0.075 * root.height
        opacity: root.a ? 0 : 1
        text: "> AWAITING INPUT" + (root.cursorOn ? "_" : " ")
        font.family: root.mono; font.pixelSize: 28 * root.u; font.letterSpacing: 4 * root.u; color: Atelier.accent
    }

    AuthPower {
        ph: root.ph
        anchors.right: parent.right; anchors.rightMargin: 0.07 * root.width
        anchors.bottom: parent.bottom; anchors.bottomMargin: 0.07 * root.height
        opacity: root.a ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.dur } }
        ink: Atelier.accent; fill: Qt.alpha(Atelier.accent, 0.08); btnRadius: Atelier.rounding; family: root.mono; upper: true
    }
}
