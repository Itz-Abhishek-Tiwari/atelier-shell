import QtQuick
import qs.config
import qs.services

// Bars from Cava.bars, rising from the bottom (or mirrored around the middle). Takes as many
// bars as fit (`barWidth` + `gap`), sampling cava's 48 evenly.
Item {
    id: vis
    property color color: Atelier.accent
    property real barWidth: 6
    property real gap: 4
    property bool mirrored: false
    property real minLevel: 0.02
    readonly property int n: Math.max(1, Math.min(Cava.count, Math.floor((width + gap) / (barWidth + gap))))
    // all 48 bars fit: widen them to span the whole width instead of bunching in the middle
    readonly property real bw: n === Cava.count ? Math.max(barWidth, (width - gap * (n - 1)) / n) : barWidth

    Row {
        anchors.bottom: vis.mirrored ? undefined : parent.bottom
        anchors.verticalCenter: vis.mirrored ? parent.verticalCenter : undefined
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: vis.gap
        Repeater {
            model: vis.n
            Rectangle {
                required property int index
                readonly property real level: {
                    const b = Cava.bars;
                    if (!b.length) return vis.minLevel;
                    return Math.max(vis.minLevel, b[Math.floor(index * Cava.count / vis.n)] || 0);
                }
                anchors.bottom: vis.mirrored ? undefined : parent.bottom
                anchors.verticalCenter: vis.mirrored ? parent.verticalCenter : undefined
                width: vis.bw
                height: Math.max(vis.bw, level * vis.height)
                radius: Math.min(vis.bw / 2, 6)
                color: vis.color
                // smooths the drop back to zero when playback stops (cava itself is smooth)
                Behavior on height { enabled: Cava.bars.length === 0; Anim { type: "effects"; duration: 400 } }
            }
        }
    }
}
