import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.config
import qs.services

// Home's hero: "Your Mix", the For you list as one playable card. Text and buttons on the left
// over the mix's own colours; a fanned stack of three covers on the right. Without listening
// history it invites a search instead.
Item {
    id: card
    property var tracks: []
    signal searchRequested()
    readonly property bool ready: tracks.length > 0
    readonly property var picks: tracks.slice(0, 3)

    HeroBackground { radius: Atelier.radiusLg; source: card.ready ? (card.tracks[0].art || card.tracks[0].thumb || "") : "" }
    StateLayer { radius: Atelier.radiusLg; onClicked: card.ready ? Music.playList(card.tracks, 0, false) : card.searchRequested() }

    // ── fanned cover stack (right) ──
    Item {
        id: stack
        visible: card.ready && card.width > 560
        anchors.right: parent.right
        anchors.rightMargin: 40
        anchors.verticalCenter: parent.verticalCenter
        readonly property real side: Math.min(140, card.height - 52)
        width: side * 2.1
        height: side
        Repeater {
            model: card.picks.length
            Item {
                required property int index
                // back to front: 2, 1, 0 (the first song sits on top, in the middle)
                readonly property int slot: [1, 2, 0][index] ?? index
                readonly property real fan: [0, 1, -1][index] ?? 0
                width: stack.side; height: stack.side
                x: (stack.width - width) / 2 + fan * stack.side * 0.52
                y: Math.abs(fan) * 8
                z: 3 - Math.abs(fan)
                rotation: fan * 7
                scale: (stackMa.containsMouse ? 1.04 : 1) * (fan === 0 ? 1 : 0.9)
                Behavior on scale { Anim { type: "spatial" } }
                Behavior on x { Anim { type: "spatial" } }
                RectangularShadow {
                    anchors.fill: parent
                    radius: 14
                    offset.y: 10
                    blur: 28
                    color: Qt.rgba(0, 0, 0, 0.45)
                }
                Cover {
                    anchors.fill: parent
                    radius: 14
                    source: { const t = card.picks[index]; return t ? (t.art || t.thumb || "") : ""; }
                }
            }
        }
        MouseArea { id: stackMa; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
    }

    // ── text + buttons (left) ──
    ColumnLayout {
        anchors.left: parent.left
        anchors.leftMargin: 30
        anchors.right: stack.visible ? stack.left : parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Text {
            text: "YOUR MIX"
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; font.weight: Font.Bold
            font.letterSpacing: 1.8
            color: Atelier.accent
        }
        Text {
            Layout.fillWidth: true
            text: card.ready ? "Made for you" : "Your mix starts here"
            elide: Text.ElideRight
            font.family: Atelier.fontUi; font.pixelSize: 24; font.weight: Font.Bold
            color: Atelier.text
        }
        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: card.ready
                ? card.tracks.length + " songs  ·  " + [...new Set(card.tracks.slice(0, 8).map(t => t.artist).filter(a => a))].slice(0, 3).join(", ")
                : "Play a few songs: a mix built from what you finish and skip shows up here"
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg
            color: Atelier.subtext1
        }
        Item { implicitHeight: 12 }
        Row {
            spacing: 10
            PlayButton { visible: card.ready; size: 48; onClicked: Music.playList(card.tracks, 0, false) }
            Pill {
                anchors.verticalCenter: parent.verticalCenter
                icon: card.ready ? "shuffle" : "search"
                label: card.ready ? "Shuffle" : "Find music"
                onClicked: card.ready ? Music.playList(card.tracks, 0, true) : card.searchRequested()
            }
        }
    }
}
