import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// Aurora: a night sky (from your theme's darkest colours), a mountain horizon and four slow aurora
// ribbons in your theme colours. The ribbons only move while really locked. Typing fades the clock
// and brings in a frosted-glass login in the middle of the sky.
Item {
    id: root
    required property var ph
    readonly property real u: ph.u
    readonly property bool a: ph.auth
    readonly property var lr: ph.lockRoot
    readonly property real dur: Atelier.durMedium
    readonly property bool moving: !ph.thumb && ph.lockRoot.active
    // the sky needs to be dark; light themes fall back to a fixed night blue
    readonly property color skyTop: Atelier.isLight ? "#04070f" : Qt.darker(Atelier.crust, 1.5)
    readonly property color skyMid: Atelier.isLight ? "#0a1228" : Atelier.crust
    readonly property color skyLow: Atelier.isLight ? "#0d1a2e" : Atelier.mantle
    readonly property color land: Atelier.isLight ? "#03060c" : Qt.darker(Atelier.crust, 2)
    readonly property color sky: "white"      // text colour over the sky
    readonly property bool round: Atelier.rounding > 0

    function rnd(i, k) { const x = Math.sin(i * 12.9898 + k * 78.233) * 43758.5453; return x - Math.floor(x); }

    Shaker { id: shaker; ph: root.ph }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: root.skyTop }
            GradientStop { position: 0.6; color: root.skyMid }
            GradientStop { position: 1; color: root.skyLow }
        }
    }

    Repeater {
        model: 110
        Rectangle {
            id: star
            required property int index
            x: root.rnd(index, 1) * root.width
            y: root.rnd(index, 2) * root.height * 0.78
            width: (1 + root.rnd(index, 3) * 2.4) * Math.max(1, root.u * 1.4); height: width; radius: width / 2
            color: "white"
            opacity: 0.25 + 0.65 * root.rnd(index, 4)
            SequentialAnimation on opacity {
                running: root.moving && star.index < 14
                loops: Animation.Infinite
                NumberAnimation { to: 0.15; duration: 1400 + star.index * 230; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.95; duration: 1400 + star.index * 170; easing.type: Easing.InOutSine }
            }
        }
    }

    Item {
        anchors.fill: parent
        opacity: root.a ? 0.85 : 1
        Behavior on opacity { NumberAnimation { duration: root.dur } }
        Repeater {
            model: [
                { c: Atelier.teal,   cx: 0.30, cy: 0.40, w: 0.85, dx: 0.06, d: 21000, a: -14 },
                { c: Atelier.green,  cx: 0.52, cy: 0.34, w: 0.75, dx: -0.07, d: 27000, a: -8 },
                { c: Atelier.accent, cx: 0.70, cy: 0.42, w: 0.80, dx: 0.05, d: 33000, a: -18 },
                { c: Atelier.mauve,  cx: 0.40, cy: 0.50, w: 0.65, dx: -0.05, d: 39000, a: -10 }
            ]
            Shape {
                id: rib
                required property var modelData
                readonly property real dia: modelData.w * root.width
                width: dia; height: dia
                x: modelData.cx * root.width - dia / 2
                y: modelData.cy * root.height - dia / 2
                transform: [
                    Scale { origin.x: rib.dia / 2; origin.y: rib.dia / 2; yScale: 0.26 },
                    Rotation { origin.x: rib.dia / 2; origin.y: rib.dia / 2; angle: rib.modelData.a }
                ]
                ShapePath {
                    strokeColor: "transparent"
                    fillGradient: RadialGradient {
                        centerX: rib.dia / 2; centerY: rib.dia / 2; centerRadius: rib.dia / 2
                        focalX: rib.dia / 2; focalY: rib.dia / 2
                        GradientStop { position: 0;    color: Qt.alpha(rib.modelData.c, 0.85) }
                        GradientStop { position: 0.45; color: Qt.alpha(rib.modelData.c, 0.38) }
                        GradientStop { position: 1;    color: Qt.alpha(rib.modelData.c, 0) }
                    }
                    PathAngleArc { centerX: rib.dia / 2; centerY: rib.dia / 2; radiusX: rib.dia / 2; radiusY: rib.dia / 2; startAngle: 0; sweepAngle: 360 }
                }
                SequentialAnimation on x {
                    running: root.moving
                    loops: Animation.Infinite
                    NumberAnimation { to: rib.modelData.cx * root.width - rib.dia / 2 + rib.modelData.dx * root.width; duration: rib.modelData.d; easing.type: Easing.InOutSine }
                    NumberAnimation { to: rib.modelData.cx * root.width - rib.dia / 2; duration: rib.modelData.d; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    Shape {
        anchors.fill: parent
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.land
            PathPolyline {
                path: [[0, 1], [0, 0.88], [0.07, 0.82], [0.14, 0.87], [0.24, 0.76], [0.33, 0.85], [0.44, 0.80], [0.53, 0.88],
                       [0.64, 0.78], [0.74, 0.86], [0.84, 0.79], [0.93, 0.85], [1, 0.81], [1, 1], [0, 1]]
                    .map(p => Qt.point(p[0] * root.width, p[1] * root.height))
            }
        }
    }

    // ── the normal screen: the clock, upper left ──
    Item {
        anchors.fill: parent
        opacity: root.a ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.dur } }
        Column {
            x: 0.07 * root.width; y: 0.1 * root.height
            spacing: 0
            Text {
                text: Qt.formatDate(ph.now, "dddd, d MMMM").toUpperCase()
                font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.5; font.weight: Font.Medium; font.letterSpacing: 8 * root.u
                color: Qt.rgba(1, 1, 1, 0.75)
            }
            Row {
                spacing: 16 * root.u
                Text {
                    text: ph.h1 + ":" + ph.mm
                    font.family: ph.display; font.pixelSize: 300 * root.u; font.weight: Font.ExtraLight; font.letterSpacing: -6 * root.u
                    renderType: Text.CurveRendering
                    color: root.sky
                }
                Text {
                    visible: ph.ampm !== ""
                    anchors.top: parent.top; anchors.topMargin: 62 * root.u
                    text: ph.ampm; font.family: ph.display; font.pixelSize: 44 * root.u; font.weight: Font.Medium; color: Qt.rgba(1, 1, 1, 0.75)
                }
            }
            Text {
                visible: ph.temp !== ""
                text: ph.temp + (ph.condition ? "   " + ph.condition : "")
                font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.5; color: Qt.rgba(1, 1, 1, 0.7)
            }
        }
        Text {
            visible: ph.notifs.length > 0
            anchors.right: parent.right; anchors.rightMargin: 0.07 * root.width
            anchors.top: parent.top; anchors.topMargin: 0.1 * root.height
            text: "󰂚  " + ph.countText
            font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.4; color: Qt.rgba(1, 1, 1, 0.8)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 0.04 * root.height
            text: "TYPE TO UNLOCK"
            font.family: ph.display; font.pixelSize: Atelier.fsMd * ph.ts; font.letterSpacing: 8 * root.u; color: Qt.rgba(1, 1, 1, 0.5)
        }
    }

    // ── the password screen: a frosted-glass login in the sky ──
    Item {
        anchors.fill: parent
        opacity: root.a ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.dur; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.emphasizedDecel } }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0.07 * root.height
            text: ph.h1 + ":" + ph.mm + (ph.ampm ? " " + ph.ampm : "")
            font.family: ph.display; font.pixelSize: 80 * root.u; font.weight: Font.ExtraLight; color: Qt.rgba(1, 1, 1, 0.8)
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0.28 * root.height
            spacing: 26 * root.u
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 150 * root.u; height: width
                // a soft glow behind the avatar, in the accent colour
                Rectangle {
                    anchors.centerIn: parent; width: parent.width * 1.5; height: width; radius: width / 2
                    gradient: Gradient { GradientStop { position: 0; color: Qt.alpha(Atelier.accent, 0.0) } GradientStop { position: 1; color: Qt.alpha(Atelier.accent, 0.0) } }
                }
                Rectangle { anchors.centerIn: parent; width: parent.width + 18 * root.u; height: width; radius: root.round ? width / 2 : 0; color: "transparent"; border.width: Math.max(2, 3 * root.u); border.color: Qt.alpha(Atelier.accent, 0.8) }
                ClippingRectangle {
                    anchors.fill: parent; radius: root.round ? width / 2 : 0; color: Qt.rgba(1, 1, 1, 0.12)
                    Image { id: pic; anchors.fill: parent; source: Profile.faceUrl; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 300; sourceSize.height: 300 }
                    Text { anchors.centerIn: parent; visible: pic.status !== Image.Ready; text: Atelier.userName.charAt(0).toUpperCase()
                        font.family: ph.display; font.pixelSize: 64 * root.u; color: "white" }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Atelier.userName
                font.family: ph.display; font.pixelSize: 56 * root.u; font.weight: Font.Medium; color: "white"
            }
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 520 * root.u; height: 76 * root.u
                transform: Translate { x: shaker.dx }
                Rectangle {
                    anchors.fill: parent
                    radius: root.round ? height / 2 : 0
                    color: Qt.rgba(1, 1, 1, 0.1)
                    border.width: Math.max(1, 2 * root.u)
                    border.color: root.lr.message ? Qt.alpha(Atelier.red, 0.9) : Qt.rgba(1, 1, 1, 0.3)
                    Behavior on border.color { CAnim {} }
                }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 32 * root.u; anchors.verticalCenter: parent.verticalCenter
                    visible: root.lr.buffer.length === 0
                    text: root.lr.checking ? "Checking…" : "Password"
                    font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.4; color: Qt.rgba(1, 1, 1, 0.55)
                }
                Row {
                    anchors.left: parent.left; anchors.leftMargin: 32 * root.u; anchors.verticalCenter: parent.verticalCenter
                    spacing: 12 * root.u
                    Repeater {
                        model: Math.min(root.lr.buffer.length, 18)
                        Rectangle {
                            width: 15 * root.u; height: width; radius: root.round ? width / 2 : 0; color: "white"
                            scale: 0
                            Component.onCompleted: scale = 1
                            Behavior on scale { Anim { type: "fastSpatial" } }
                        }
                    }
                }
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 10 * root.u; anchors.verticalCenter: parent.verticalCenter
                    width: 54 * root.u; height: width; radius: root.round ? width / 2 : 0
                    visible: root.lr.buffer.length > 0 || root.lr.checking
                    color: Atelier.accent
                    Text { anchors.centerIn: parent; text: root.lr.checking ? "󰑐" : "󰁔"; font.family: Atelier.font; font.pixelSize: Atelier.fsXl * ph.ts * 1.5; color: Atelier.contrast(Atelier.crust, Atelier.accent) >= Atelier.contrast(Atelier.text, Atelier.accent) ? Atelier.crust : Atelier.text
                        RotationAnimation on rotation { running: root.lr.checking; loops: Animation.Infinite; from: 0; to: 360; duration: 800 } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.lr.submit() }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.lr.message ? root.lr.message : ph.capsOn ? "Caps Lock is on" : ph.isPreview ? "Preview · Esc to go back" : "Enter to unlock · Esc to go back"
                font.family: ph.display; font.pixelSize: Atelier.fsLg * ph.ts * 1.1
                color: root.lr.message ? Qt.tint("white", Qt.alpha(Atelier.red, 0.8)) : ph.capsOn ? Qt.tint("white", Qt.alpha(Atelier.yellow, 0.7)) : Qt.rgba(1, 1, 1, 0.7)
                Behavior on color { CAnim {} }
            }
        }
        AuthPower {
            ph: root.ph
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 0.14 * root.height
            ink: "white"; fill: Qt.rgba(1, 1, 1, 0.12); btnRadius: root.round ? -1 : 0; family: ph.display
        }
    }
}
