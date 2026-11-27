import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// Now playing's actions, always one centred row: ♥ Like · Download · Radio · Sleep · Fullscreen.
// Labelled pills when they fit, round icon buttons (label as a tooltip) when the column is
// narrow. Sleep opens a small chooser; while a timer runs the pill shows the time left.
Item {
    id: acts
    signal fullscreenRequested()
    readonly property bool compact: width < 560
    readonly property bool has: Music.current !== null
    implicitHeight: 36

    // countdown for the sleep pill (only ticks while a timer is set)
    property real now: Date.now()
    Timer { interval: 1000; repeat: true; running: Music.sleepAt > 0; onTriggered: acts.now = Date.now() }
    readonly property string sleepLabel: Music.sleepEndOfTrack ? "End of song"
        : Music.sleepAt > 0 ? Music.clock(Math.max(0, (Music.sleepAt - acts.now) / 1000)) : "Sleep"

    Row {
        anchors.centerIn: parent
        spacing: acts.compact ? 14 : 8
        Pill {
            readonly property bool liked: acts.has && Music.isLiked(Music.current.id)
            compact: acts.compact
            icon: liked ? "heart_fill" : "heart"
            label: liked ? "Liked" : "Like"
            on: liked
            onClicked: Music.toggleLike(Music.current)
        }
        Pill {
            readonly property string st: acts.has ? Music.fileState(Music.current.id) : ""
            readonly property real pr: acts.has ? Music.progressOf(Music.current.id) : -1
            compact: acts.compact
            icon: st === "download" ? "downloaded" : "download"
            label: pr >= 0 ? "Saving " + Math.round(pr * 100) + "%" : st === "download" ? "Downloaded" : "Download"
            on: st === "download"
            onClicked: if (st !== "download" && pr < 0) Music.download(Music.current)
        }
        Pill { compact: acts.compact; icon: "radio"; label: "Radio"; onClicked: Music.radio(Music.current) }
        Pill {
            id: sleepPill
            compact: acts.compact
            icon: "sleep"
            label: acts.sleepLabel
            on: Music.sleepAt > 0 || Music.sleepEndOfTrack
            onClicked: chooser.visible = !chooser.visible
        }
        Pill { compact: acts.compact; icon: "fullscreen"; label: "Fullscreen"; onClicked: acts.fullscreenRequested() }
    }

    // sleep chooser, above the pill
    Rectangle {
        id: chooser
        visible: false
        z: 20
        width: 180
        height: opts.implicitHeight + 12
        x: Math.max(0, Math.min(acts.width - width, sleepPill.mapToItem(acts, 0, 0).x + sleepPill.width / 2 - width / 2))
        y: -height - 8
        radius: Atelier.radiusMd
        color: Atelier.surface0
        border.width: 1
        border.color: Atelier.outline
        ColumnLayout {
            id: opts
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 6
            spacing: 0
            Repeater {
                model: [{ v: 0, l: "Off" }, { v: 15, l: "15 minutes" }, { v: 30, l: "30 minutes" },
                        { v: 45, l: "45 minutes" }, { v: 60, l: "1 hour" }, { v: "track", l: "End of this song" }]
                Rectangle {
                    required property var modelData
                    readonly property bool on: modelData.v === "track" ? Music.sleepEndOfTrack
                        : modelData.v === 0 ? (Music.sleepAt === 0 && !Music.sleepEndOfTrack) : false
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: Atelier.radiusSm
                    color: on ? Qt.alpha(Atelier.accent, 0.16) : "transparent"
                    StateLayer { radius: Atelier.radiusSm; onClicked: { Music.setSleep(modelData.v); chooser.visible = false; } }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 12
                        text: modelData.l
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd
                        font.weight: parent.on ? Font.DemiBold : Font.Normal
                        color: parent.on ? Atelier.accent : Atelier.text
                    }
                }
            }
        }
    }
}
