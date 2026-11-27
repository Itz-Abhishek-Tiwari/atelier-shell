import QtQuick
import qs.config
import qs.services

// ── the cover, crossfading when the track changes ──
Item {
    id: cf
    property real radius: Atelier.radiusLg
    property bool flip: false
    property string shown: ""
    readonly property string want: Music.currentArt
    onWantChanged: swap()
    Component.onCompleted: { a.source = want; shown = want; }
    function swap() {
        if (want === shown) return;
        shown = want;
        flip = !flip;
        if (flip) b.source = want;
        else a.source = want;
    }
    Cover {
        id: a
        anchors.fill: parent
        radius: cf.radius
        placeholder: Music.current !== null ? "󰎆" : "󰝛"
        opacity: cf.flip ? 0 : 1
        scale: cf.flip ? 0.96 : 1
        Behavior on opacity { Anim { type: "slowEffects" } }
        Behavior on scale { Anim { type: "spatial" } }
    }
    Cover {
        id: b
        anchors.fill: parent
        radius: cf.radius
        placeholder: Music.current !== null ? "󰎆" : "󰝛"
        opacity: cf.flip ? 1 : 0
        scale: cf.flip ? 1 : 0.96
        Behavior on opacity { Anim { type: "slowEffects" } }
        Behavior on scale { Anim { type: "spatial" } }
    }
}

// ── lyrics card ──
