import QtQuick
import qs.config
import qs.services

// Flip: two big flip cards (hours, minutes) on a dark backdrop. While you type, the cards shrink
// up and a row of small flip tiles shows one dot per character, like a split-flap board.
Item {
    id: root
    required property var ph
    readonly property real u: ph.u
    readonly property bool a: ph.auth
    readonly property var lr: ph.lockRoot
    readonly property real dur: Atelier.durMedium

    Shaker { id: shaker; ph: root.ph }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Atelier.mantle }
            GradientStop { position: 1; color: Atelier.crust }
        }
    }

    // the clock cards: centred normally, small at the top while typing
    Row {
        id: cards
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.a ? 0.07 * root.height : root.height / 2 - height / 2 - 70 * root.u
        spacing: 48 * root.u
        scale: root.a ? 0.42 : 1
        transformOrigin: Item.Top
        Behavior on y { NumberAnimation { duration: root.dur; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }
        Behavior on scale { NumberAnimation { duration: root.dur; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }
        FlipCard { u: root.u; live: !ph.thumb; family: ph.display; text: ph.hh; tag: ph.ampm; corner: Atelier.rounding * 2 * root.u }
        FlipCard { u: root.u; live: !ph.thumb; family: ph.display; text: ph.mm; corner: Atelier.rounding * 2 * root.u }
    }

    // ── the normal screen ──
    Item {
        anchors.fill: parent
        opacity: root.a ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.height / 2 - cards.height / 2 - 70 * root.u + cards.height + 56 * root.u
            text: Qt.formatDate(ph.now, "dddd  ·  d MMMM yyyy").toUpperCase()
            font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.9; font.weight: Font.Medium; font.letterSpacing: 9 * root.u
            color: Atelier.subtext
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.height / 2 - cards.height / 2 - 70 * root.u + cards.height + 120 * root.u
            spacing: 40 * root.u
            Text { visible: ph.temp !== ""; text: "󰖐  " + ph.temp; font.family: Atelier.font; font.pixelSize: Atelier.fsLg * ph.ts * 1.5; color: Atelier.subtext1 }
            Text { visible: ph.hasBattery; text: (ph.charging ? "󰂄  " : "󰁹  ") + ph.batPct + "%"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg * ph.ts * 1.5; color: Atelier.subtext1 }
            Text { visible: ph.notifs.length > 0; text: "󰂚  " + ph.notifs.length; font.family: Atelier.font; font.pixelSize: Atelier.fsLg * ph.ts * 1.5; color: Atelier.subtext1 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 0.045 * root.height
            text: "TYPE TO UNLOCK"
            font.family: ph.display; font.pixelSize: Atelier.fsMd * ph.ts; font.weight: Font.Medium; font.letterSpacing: 8 * root.u
            color: Qt.alpha(Atelier.subtext, 0.7)
        }
    }

    // ── the password screen: name, a row of flip tiles, a message ──
    Item {
        anchors.fill: parent
        opacity: root.a ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0.36 * root.height
            spacing: 34 * root.u
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Atelier.userName.toUpperCase()
                font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 2; font.weight: Font.Medium; font.letterSpacing: 12 * root.u
                color: Atelier.text
            }
            // tiles: one per typed character, plus the next empty one
            Row {
                id: tiles
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14 * root.u
                transform: Translate { x: shaker.dx }
                Repeater {
                    model: Math.min(root.lr.buffer.length + 1, 14)
                    Item {
                        id: tile
                        required property int index
                        readonly property bool filled: index < root.lr.buffer.length
                        width: 92 * root.u; height: 128 * root.u
                        // top and bottom halves of the tile
                        Rectangle {
                            width: parent.width; height: parent.height / 2 - 1.5 * root.u
                            radius: Atelier.rounding; color: tile.filled ? Atelier.surface1 : Qt.alpha(Atelier.surface0, 0.55)
                            Rectangle { visible: Atelier.rounding > 0; anchors.bottom: parent.bottom; width: parent.width; height: parent.radius; color: parent.color }
                        }
                        Rectangle {
                            y: parent.height / 2 + 1.5 * root.u
                            width: parent.width; height: parent.height / 2 - 1.5 * root.u
                            radius: Atelier.rounding; color: tile.filled ? Qt.darker(Atelier.surface0, 1.2) : Qt.alpha(Qt.darker(Atelier.surface0, 1.3), 0.55)
                            Rectangle { visible: Atelier.rounding > 0; anchors.top: parent.top; width: parent.width; height: parent.radius; color: parent.color }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: tile.filled
                            text: "●"
                            font.family: ph.display; font.pixelSize: 40 * root.u; color: Atelier.text
                            scale: 0
                            Component.onCompleted: scale = 1
                            Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutBack } }
                        }
                        Rectangle { y: parent.height / 2 - 1.5 * root.u; width: parent.width; height: 3 * root.u; color: Atelier.crust }
                        // the empty tile blinks like a cursor
                        Rectangle {
                            visible: !tile.filled
                            anchors.centerIn: parent; width: 30 * root.u; height: 5 * root.u; color: Atelier.accent
                            SequentialAnimation on opacity { running: !tile.filled && root.a && !ph.thumb; loops: Animation.Infinite
                                NumberAnimation { to: 0.2; duration: 520 } NumberAnimation { to: 1; duration: 520 } }
                        }
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (root.lr.checking ? "CHECKING…" : root.lr.message ? root.lr.message
                      : ph.capsOn ? "CAPS LOCK IS ON"
                      : ph.isPreview ? "PREVIEW · ESC TO GO BACK" : "ENTER TO UNLOCK · ESC TO GO BACK").toUpperCase()
                font.family: ph.display; font.pixelSize: Atelier.fsMd * ph.ts * 1.15; font.weight: Font.Medium; font.letterSpacing: 6 * root.u
                color: root.lr.message ? Atelier.red : ph.capsOn ? Atelier.yellow : Atelier.subtext
            }
        }
    }

    AuthPower {
        ph: root.ph
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 0.06 * root.height
        opacity: root.a ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.dur } }
        ink: Atelier.text; fill: Atelier.surface0; btnRadius: Atelier.rounding; family: ph.display; upper: true
    }
}
