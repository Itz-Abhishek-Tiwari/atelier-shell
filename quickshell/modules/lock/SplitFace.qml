import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// Split: a slanted panel on the left, your wallpaper left clear on the right. Typing turns the
// panel into the login: avatar, name and an underlined password line, wallpaper still sharp.
Item {
    id: root
    required property var ph
    readonly property real u: ph.u
    readonly property bool a: ph.auth
    readonly property var lr: ph.lockRoot
    readonly property real dur: Atelier.durMedium
    readonly property real edgeTop: 0.47 * width       // where the slanted edge meets the top
    readonly property real edgeBot: 0.39 * width       // ... and the bottom
    readonly property real padX: 0.065 * width

    Shaker { id: shaker; ph: root.ph }

    Shape {
        anchors.fill: parent
        ShapePath {
            strokeColor: "transparent"
            fillColor: Qt.alpha(Atelier.base, 0.97)
            startX: 0; startY: 0
            PathLine { x: root.edgeTop; y: 0 }
            PathLine { x: root.edgeBot; y: root.height }
            PathLine { x: 0; y: root.height }
            PathLine { x: 0; y: 0 }
        }
        ShapePath {
            strokeColor: Atelier.accent
            strokeWidth: 7 * root.u
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            startX: root.edgeTop; startY: 0
            PathLine { x: root.edgeBot; y: root.height }
        }
    }

    // ── the normal screen ──
    Column {
        x: root.padX
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        opacity: root.a ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.dur; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.emphasizedDecel } }
        Text {
            text: Qt.formatDate(ph.now, "dddd").toUpperCase()
            font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.6; font.weight: Font.Bold; font.letterSpacing: 10 * root.u
            color: Atelier.accent
        }
        Item { width: 1; height: 6 * root.u }
        Row {
            spacing: 18 * root.u
            Text {
                text: ph.h1 + ":" + ph.mm
                font.family: ph.display; font.pixelSize: 330 * root.u; font.weight: Font.Light; font.letterSpacing: -8 * root.u
                renderType: Text.CurveRendering
                color: Atelier.text
            }
            Text {
                visible: ph.ampm !== ""
                anchors.top: parent.top; anchors.topMargin: 96 * root.u
                text: ph.ampm
                font.family: ph.display; font.pixelSize: 52 * root.u; font.weight: Font.Medium
                color: Atelier.subtext1
            }
        }
        Text {
            text: Qt.formatDate(ph.now, "d MMMM yyyy")
            font.family: ph.display; font.pixelSize: 54 * root.u; font.weight: Font.Medium
            color: Atelier.text
        }
        Item { width: 1; height: 38 * root.u }
        Rectangle { width: 120 * root.u; height: 5 * root.u; radius: Atelier.rounding > 0 ? height / 2 : 0; color: Atelier.accent }
        Item { width: 1; height: 34 * root.u }
        Column {
            spacing: 18 * root.u
            Row {
                visible: ph.temp !== ""; spacing: 18 * root.u
                Text { text: "󰖐"; font.family: Atelier.font; font.pixelSize: Atelier.fsXl * ph.ts * 1.7; color: Atelier.accent }
                Text { text: ph.temp + (ph.condition ? "   " + ph.condition : ""); font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.6; color: Atelier.subtext1 }
            }
            Row {
                visible: ph.hasBattery; spacing: 18 * root.u
                Text { text: ph.charging ? "󰂄" : "󰁹"; font.family: Atelier.font; font.pixelSize: Atelier.fsXl * ph.ts * 1.7; color: Atelier.accent }
                Text { text: ph.batPct + "%" + (ph.charging ? "   charging" : ""); font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.6; color: Atelier.subtext1 }
            }
            Row {
                visible: SysState.wifiConnected; spacing: 18 * root.u
                Text { text: SysState.wifiIcon; font.family: Atelier.font; font.pixelSize: Atelier.fsXl * ph.ts * 1.7; color: Atelier.accent }
                Text { text: SysState.ssid; font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.6; color: Atelier.subtext1 }
            }
            Row {
                visible: ph.notifs.length > 0; spacing: 18 * root.u
                Text { text: "󰂚"; font.family: Atelier.font; font.pixelSize: Atelier.fsXl * ph.ts * 1.7; color: Atelier.accent }
                Text { text: ph.countText; font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.6; color: Atelier.subtext1 }
            }
        }
    }
    Text {
        x: root.padX
        anchors.bottom: parent.bottom; anchors.bottomMargin: 0.055 * root.height
        opacity: root.a ? 0 : 1
        text: "TYPE TO UNLOCK  ↵"
        font.family: ph.display; font.pixelSize: Atelier.fsMd * ph.ts; font.weight: Font.Medium; font.letterSpacing: 7 * root.u
        color: Qt.alpha(Atelier.subtext, 0.8)
        Behavior on opacity { NumberAnimation { duration: root.dur } }
    }

    // ── the password screen, on the panel ──
    Item {
        anchors.fill: parent
        opacity: root.a ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.dur; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.emphasizedDecel } }

        // the time, small, at the top of the panel
        Row {
            x: root.padX; y: 0.08 * root.height
            spacing: 14 * root.u
            Text { text: ph.h1 + ":" + ph.mm; font.family: ph.display; font.pixelSize: 84 * root.u; font.weight: Font.Light; color: Atelier.subtext1 }
            Text { visible: ph.ampm !== ""; anchors.baseline: parent.children[0].baseline; text: ph.ampm; font.family: ph.display; font.pixelSize: 28 * root.u; color: Atelier.subtext }
        }

        Column {
            x: root.padX
            anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: 20 * root.u
            width: root.edgeBot - root.padX - 70 * root.u
            spacing: 22 * root.u
            ClippingRectangle {
                width: 128 * root.u; height: width
                radius: Atelier.rounding
                color: Atelier.surface0
                Image { id: pic; anchors.fill: parent; source: Profile.faceUrl; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 256; sourceSize.height: 256 }
                Text { anchors.centerIn: parent; visible: pic.status !== Image.Ready; text: Atelier.userName.charAt(0).toUpperCase()
                    font.family: ph.display; font.pixelSize: 56 * root.u; color: Atelier.text }
            }
            Text {
                text: Atelier.userName
                font.family: ph.display; font.pixelSize: 64 * root.u; font.weight: Font.Medium; color: Atelier.text
            }
            // the field: dots on an underline, an arrow at the end
            Item {
                width: parent.width; height: 76 * root.u
                transform: Translate { x: shaker.dx }
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    visible: root.lr.buffer.length === 0
                    text: root.lr.checking ? "Checking…" : "Password"
                    font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.5; color: Atelier.subtext
                }
                Row {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    spacing: 12 * root.u
                    Repeater {
                        model: Math.min(root.lr.buffer.length, 16)
                        Rectangle {
                            width: 16 * root.u; height: width; radius: Atelier.rounding > 0 ? width / 2 : 0; color: Atelier.text
                            scale: 0
                            Component.onCompleted: scale = 1
                            Behavior on scale { Anim { type: "fastSpatial" } }
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
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 4 * root.u
                    color: root.lr.message ? Atelier.red : Atelier.accent
                    Behavior on color { CAnim {} } }
            }
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: root.lr.message ? root.lr.message : ph.capsOn ? "Caps Lock is on" : ph.isPreview ? "Preview · Esc to go back" : "Enter to unlock · Esc to go back"
                font.family: ph.display; font.pixelSize: Atelier.fsLg * ph.ts * 1.1
                color: root.lr.message ? Atelier.red : ph.capsOn ? Atelier.yellow : Atelier.subtext1
                Behavior on color { CAnim {} }
            }
        }
    }

    AuthPower {
        ph: root.ph
        x: root.padX
        anchors.bottom: parent.bottom; anchors.bottomMargin: 0.05 * root.height
        opacity: root.a ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.dur } }
        ink: Atelier.text; fill: Atelier.surface0; btnRadius: Atelier.rounding; family: ph.display
    }
}
