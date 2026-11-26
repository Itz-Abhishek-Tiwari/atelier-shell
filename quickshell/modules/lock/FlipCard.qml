import QtQuick
import QtQuick.Effects
import qs.config

// One flip card (two digits). When `text` changes the top half folds down and the new bottom half
// folds into place, like a mechanical flip clock. `live: false` (settings miniatures) skips the
// animation and the shadow.
Item {
    id: card

    property string text
    property string tag: ""              // small label in the corner (AM / PM)
    property real u: 1
    property string family: "Inter Display"
    property bool live: true

    property string topText: text
    property string botText: text
    property string oldText: text
    property real aScale: 1              // the folding top flap
    property real bScale: 0              // the unfolding bottom flap

    readonly property real half: height / 2
    readonly property real gap: Math.max(2, 3 * u)
    property real corner: Atelier.rounding * 2 * u
    readonly property color faceTop: Atelier.surface1
    readonly property color faceMid: Atelier.surface0
    readonly property color faceBot: Qt.darker(Atelier.surface0, 1.3)

    width: 560 * u
    height: 620 * u

    onTextChanged: {
        if (!live) { topText = text; botText = text; oldText = text; return; }
        oldText = botText;
        topText = text;
        flip.restart();
    }

    SequentialAnimation {
        id: flip
        PropertyAction { target: card; property: "aScale"; value: 1 }
        PropertyAction { target: card; property: "bScale"; value: 0 }
        NumberAnimation { target: card; property: "aScale"; to: 0; duration: 170; easing.type: Easing.InQuad }
        NumberAnimation { target: card; property: "bScale"; to: 1; duration: 200; easing.type: Easing.OutQuad }
        ScriptAction { script: card.botText = card.text }
    }

    Item {
        id: body
        anchors.fill: parent
        layer.enabled: card.live
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "black"
            shadowOpacity: 0.55
            shadowBlur: 0.9
            shadowVerticalOffset: 16 * card.u
        }

        // ── top half (shows the new digits as soon as the flap lifts) ──
        Item {
            id: topHalf
            width: card.width; height: card.half - card.gap / 2
            clip: true
            Rectangle {
                width: card.width; height: card.height; radius: card.corner
                gradient: Gradient {
                    GradientStop { position: 0; color: card.faceTop }
                    GradientStop { position: 0.5; color: card.faceMid }
                    GradientStop { position: 1; color: card.faceMid }
                }
            }
            Text {
                width: card.width; height: card.height
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: card.topText
                font.family: card.family; font.pixelSize: 375 * card.u; font.weight: Font.Bold
                renderType: Text.CurveRendering
                color: Atelier.text
            }
        }

        // ── bottom half ──
        Item {
            id: botHalf
            y: card.half + card.gap / 2
            width: card.width; height: card.half - card.gap / 2
            clip: true
            Rectangle {
                y: -(card.half + card.gap / 2)
                width: card.width; height: card.height; radius: card.corner
                gradient: Gradient {
                    GradientStop { position: 0; color: card.faceBot }
                    GradientStop { position: 0.5; color: card.faceBot }
                    GradientStop { position: 1; color: Qt.darker(card.faceBot, 1.25) }
                }
            }
            Text {
                y: -(card.half + card.gap / 2)
                width: card.width; height: card.height
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: card.botText
                font.family: card.family; font.pixelSize: 375 * card.u; font.weight: Font.Bold
                renderType: Text.CurveRendering
                color: Atelier.text
            }
        }

        // ── the folding flaps ──
        Item {
            id: flapA
            visible: flip.running && card.aScale > 0.002
            width: card.width; height: topHalf.height
            clip: true
            transform: Scale { origin.y: flapA.height; yScale: card.aScale }
            Rectangle {
                width: card.width; height: card.height; radius: card.corner
                gradient: Gradient {
                    GradientStop { position: 0; color: card.faceTop }
                    GradientStop { position: 0.5; color: card.faceMid }
                    GradientStop { position: 1; color: card.faceMid }
                }
            }
            Text {
                width: card.width; height: card.height
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: card.oldText
                font.family: card.family; font.pixelSize: 375 * card.u; font.weight: Font.Bold
                renderType: Text.CurveRendering
                color: Atelier.text
            }
        }
        Item {
            id: flapB
            visible: flip.running && card.bScale > 0.002
            y: card.half + card.gap / 2
            width: card.width; height: botHalf.height
            clip: true
            transform: Scale { origin.y: 0; yScale: card.bScale }
            Rectangle {
                y: -(card.half + card.gap / 2)
                width: card.width; height: card.height; radius: card.corner
                gradient: Gradient {
                    GradientStop { position: 0; color: card.faceBot }
                    GradientStop { position: 1; color: Qt.darker(card.faceBot, 1.25) }
                }
            }
            Text {
                y: -(card.half + card.gap / 2)
                width: card.width; height: card.height
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: card.text
                font.family: card.family; font.pixelSize: 375 * card.u; font.weight: Font.Bold
                renderType: Text.CurveRendering
                color: Atelier.text
            }
        }

        // hinge and side notches
        Rectangle { y: card.half - card.gap / 2; width: card.width; height: card.gap; color: Atelier.crust }
        Rectangle { x: 0; y: card.half - 22 * card.u; width: 14 * card.u; height: 44 * card.u; radius: 6 * card.u; color: Atelier.crust }
        Rectangle { x: card.width - width; y: card.half - 22 * card.u; width: 14 * card.u; height: 44 * card.u; radius: 6 * card.u; color: Atelier.crust }

        Text {
            visible: card.tag !== ""
            x: 36 * card.u; y: 28 * card.u
            text: card.tag
            font.family: card.family; font.pixelSize: 40 * card.u; font.weight: Font.Bold; font.letterSpacing: 3 * card.u
            color: Atelier.subtext
        }
    }
}
