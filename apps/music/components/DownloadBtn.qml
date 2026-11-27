import QtQuick
import qs.config
import qs.services

// Download a track: arrow → a ring filling up while it saves → a check when it's downloaded.
Item {
    id: d
    property var track: null
    property int size: 36
    readonly property string st: track ? Music.fileState(track.id) : ""
    readonly property real pr: track ? Music.progressOf(track.id) : -1

    implicitWidth: size
    implicitHeight: size

    IconBtn {
        anchors.fill: parent
        size: d.size
        iconSize: Math.round(d.size * 0.55)
        icon: d.st === "download" ? "downloaded" : "download"
        active: d.st === "download"
        visible: d.pr < 0
        onClicked: if (d.st !== "download" && d.track) Music.download(d.track)
    }

    // saving: a progress ring (Canvas repaints only when the value changes)
    Canvas {
        id: ring
        anchors.centerIn: parent
        width: d.size * 0.62; height: width
        visible: d.pr >= 0
        property real p: Math.max(0.04, d.pr)
        onPChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const r = width / 2 - 2;
            ctx.lineWidth = 2.5;
            ctx.strokeStyle = Qt.alpha(Atelier.accent, 0.25);
            ctx.beginPath(); ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2); ctx.stroke();
            ctx.strokeStyle = Atelier.accent;
            ctx.lineCap = "round";
            ctx.beginPath(); ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * p); ctx.stroke();
        }
    }
}
