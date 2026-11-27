import QtQuick
import QtQuick.Effects
import qs.config

// The backdrop of Home's hero cards: an image blurred into pure colour (decoded tiny, blurred
// hard, so no shapes or text survive), masked to the card's rounded corners in the same pass,
// with a wash from the left so text on top always reads.
Item {
    id: hb
    property string source: ""
    property real radius: Atelier.radiusLg
    anchors.fill: parent

    Rectangle { anchors.fill: parent; radius: hb.radius; color: Atelier.container }

    Image {
        id: src
        anchors.fill: parent
        visible: false
        source: hb.source
        sourceSize: Qt.size(48, 48)                 // tiny on purpose: only the colours matter
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    Item {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: hb.radius; color: "black"; antialiasing: true }
    }
    MultiEffect {
        anchors.fill: parent
        source: src
        autoPaddingEnabled: false
        blurEnabled: true; blur: 1.0; blurMax: 64; blurMultiplier: 2.0
        saturation: 0.35
        brightness: Atelier.isLight ? 0.05 : -0.18
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
        opacity: src.status === Image.Ready ? 0.6 : 0
        Behavior on opacity { Anim { type: "slowEffects"; duration: 600 } }
    }
    // readability wash: strong behind the text on the left, clear on the right
    Rectangle {
        anchors.fill: parent
        radius: hb.radius
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.alpha(Atelier.base, 0.78) }
            GradientStop { position: 0.55; color: Qt.alpha(Atelier.base, 0.45) }
            GradientStop { position: 1.0; color: Qt.alpha(Atelier.base, 0.12) }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: hb.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Atelier.text, 0.08)
    }
}
