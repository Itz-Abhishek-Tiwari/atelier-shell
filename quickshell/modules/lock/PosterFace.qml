import QtQuick
import Quickshell.Widgets
import qs.config
import qs.services

// Poster: the time is the artwork. A flat field of your accent colour, huge stacked numerals and a
// few quiet details. Its password screen is part of the poster: a big "PASSWORD" line you type on.
Item {
    id: root
    required property var ph

    readonly property real u: ph.u
    readonly property bool a: ph.auth
    readonly property var lr: ph.lockRoot
    readonly property color bg: Atelier.accent
    readonly property color ink: Atelier.contrast(Atelier.crust, bg) >= Atelier.contrast(Atelier.text, bg) ? Atelier.crust : Atelier.text
    readonly property real digit: 640 * u
    readonly property real dur: Atelier.durMedium

    Shaker { id: shaker; ph: root.ph }

    Rectangle { anchors.fill: parent; color: root.bg }

    // hours over minutes, set tight like a poster; the minutes step back while you type
    Column {
        x: 0.05 * root.width
        y: 0.02 * root.height
        spacing: -root.digit * 0.2
        Text {
            text: ph.hh
            font.family: ph.display; font.pixelSize: root.digit; font.weight: Font.Black
            font.letterSpacing: -root.digit * 0.04
            renderType: Text.CurveRendering
            color: root.ink
        }
        Text {
            text: ph.mm
            font.family: ph.display; font.pixelSize: root.digit; font.weight: Font.Black
            font.letterSpacing: -root.digit * 0.04
            renderType: Text.CurveRendering
            color: Qt.alpha(root.ink, root.a ? 0.1 : 0.28)
            Behavior on color { ColorAnimation { duration: root.dur } }
        }
    }

    // ── the poster details (fade out while typing) ──
    Item {
        anchors.fill: parent
        opacity: root.a ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }

        Column {
            anchors.right: parent.right; anchors.rightMargin: 0.05 * root.width
            anchors.bottom: parent.bottom; anchors.bottomMargin: 0.1 * root.height
            spacing: 10 * root.u
            Text {
                anchors.right: parent.right
                text: Qt.formatDate(ph.now, "dddd").toUpperCase()
                font.family: ph.display; font.pixelSize: 120 * root.u; font.weight: Font.Black
                font.letterSpacing: -2 * root.u
                renderType: Text.CurveRendering
                color: root.ink
            }
            Text {
                anchors.right: parent.right
                text: Qt.formatDate(ph.now, "d MMMM yyyy").toUpperCase()
                font.family: ph.display; font.pixelSize: 44 * root.u; font.weight: Font.Bold
                font.letterSpacing: 6 * root.u
                color: root.ink
            }
            Rectangle { anchors.right: parent.right; width: 260 * root.u; height: 8 * root.u; color: root.ink }
            Text {
                anchors.right: parent.right
                visible: ph.temp !== ""
                text: ph.temp + (ph.condition ? "   " + ph.condition.toUpperCase() : "")
                font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.5; font.weight: Font.Bold; font.letterSpacing: 4 * root.u
                color: root.ink
            }
            Text {
                anchors.right: parent.right
                visible: ph.hasBattery
                text: (ph.charging ? "CHARGING  " : "BATTERY  ") + ph.batPct + "%"
                font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.5; font.weight: Font.Bold; font.letterSpacing: 4 * root.u
                color: Qt.alpha(root.ink, 0.7)
            }
        }
        Column {
            anchors.right: parent.right; anchors.rightMargin: 0.05 * root.width
            anchors.top: parent.top; anchors.topMargin: 0.06 * root.height
            spacing: 8 * root.u
            Text {
                anchors.right: parent.right
                visible: ph.ampm !== ""
                text: ph.ampm
                font.family: ph.display; font.pixelSize: 64 * root.u; font.weight: Font.Black; color: root.ink
            }
            Text {
                anchors.right: parent.right
                visible: ph.notifs.length > 0
                text: "󰂚  " + ph.notifs.length
                font.family: Atelier.font; font.pixelSize: Atelier.fsXl * ph.ts * 2; color: root.ink
            }
        }
        Text {
            x: 0.05 * root.width; y: 0.055 * root.height
            text: "TYPE TO UNLOCK  ↵"
            font.family: ph.display; font.pixelSize: Atelier.fsMd * ph.ts; font.weight: Font.Bold; font.letterSpacing: 6 * root.u
            color: Qt.alpha(root.ink, 0.75)
        }
    }

    // ── the password screen ──
    Item {
        id: authBox
        anchors.right: parent.right; anchors.rightMargin: 0.05 * root.width
        anchors.bottom: parent.bottom; anchors.bottomMargin: 0.14 * root.height
        width: Math.min(0.55 * root.width, 980 * root.u); height: 640 * root.u
        opacity: root.a ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }
        transform: Translate { y: root.a ? 0 : 50 * root.u; Behavior on y { NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } } }

        Column {
            anchors.right: parent.right; anchors.bottom: parent.bottom
            spacing: 26 * root.u

            Row {
                anchors.right: parent.right
                layoutDirection: Qt.RightToLeft
                spacing: 28 * root.u
                ClippingRectangle {
                    width: 150 * root.u; height: width
                    radius: Atelier.rounding
                    color: Qt.alpha(root.ink, 0.2)
                    Image { id: pic; anchors.fill: parent; source: Profile.faceUrl; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 300; sourceSize.height: 300 }
                    Text { anchors.centerIn: parent; visible: pic.status !== Image.Ready; text: Atelier.userName.charAt(0).toUpperCase()
                        font.family: ph.display; font.pixelSize: 80 * root.u; font.weight: Font.Black; color: root.ink }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Atelier.userName.toUpperCase()
                    font.family: ph.display; font.pixelSize: 96 * root.u; font.weight: Font.Black; font.letterSpacing: -2 * root.u
                    renderType: Text.CurveRendering
                    color: root.ink
                }
            }
            Text {
                anchors.right: parent.right
                text: "PASSWORD"
                font.family: ph.display; font.pixelSize: Atelier.fsMd * ph.ts; font.weight: Font.Bold; font.letterSpacing: 8 * root.u
                color: Qt.alpha(root.ink, 0.7)
            }
            // the field: big dots on a thick rule
            Item {
                anchors.right: parent.right
                width: authBox.width; height: 120 * root.u
                transform: Translate { x: shaker.dx }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 16 * root.u; anchors.verticalCenter: parent.verticalCenter
                    visible: root.lr.buffer.length === 0
                    text: root.lr.checking ? "CHECKING…" : "TYPE HERE"
                    font.family: ph.display; font.pixelSize: 56 * root.u; font.weight: Font.Black; font.letterSpacing: 2 * root.u
                    color: Qt.alpha(root.ink, 0.4)
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 90 * root.u; anchors.verticalCenter: parent.verticalCenter
                    spacing: 16 * root.u
                    Repeater {
                        model: Math.min(root.lr.buffer.length, 16)
                        Rectangle {
                            width: 42 * root.u; height: width; radius: width / 2; color: root.ink
                            scale: 0
                            Component.onCompleted: scale = 1
                            Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutBack } }
                        }
                    }
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    visible: root.lr.buffer.length > 0 || root.lr.checking
                    text: root.lr.checking ? "…" : "↵"
                    font.family: ph.display; font.pixelSize: 64 * root.u; font.weight: Font.Black; color: root.ink
                    MouseArea { anchors.fill: parent; anchors.margins: -16; cursorShape: Qt.PointingHandCursor; onClicked: root.lr.submit() }
                }
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 10 * root.u; color: root.ink }
            }
            Text {
                anchors.right: parent.right
                text: (root.lr.message ? "✕  " + root.lr.message
                      : ph.capsOn ? "CAPS LOCK IS ON"
                      : ph.isPreview ? "PREVIEW · ESC TO GO BACK" : "ENTER TO UNLOCK · ESC TO GO BACK").toUpperCase()
                font.family: ph.display; font.pixelSize: Atelier.fsLg * ph.ts; font.weight: Font.Bold; font.letterSpacing: 4 * root.u
                color: root.ink
                opacity: root.lr.message ? 1 : 0.7
            }
        }
    }

    AuthPower {
        ph: root.ph
        anchors.left: parent.left; anchors.leftMargin: 0.05 * root.width
        anchors.bottom: parent.bottom; anchors.bottomMargin: 0.05 * root.height
        opacity: root.a ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.dur } }
        ink: root.ink; fill: Qt.alpha(root.ink, 0.14); btnRadius: Atelier.rounding; family: ph.display; upper: true
    }
}
