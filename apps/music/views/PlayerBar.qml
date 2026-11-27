import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// The bar along the bottom: the track (click → Now playing), the transport with the seek bar
// under it, and shortcuts to lyrics and the queue.
Rectangle {
    id: bar
    property string page: ""
    signal navigate(string page)
    signal fullscreenRequested()
    readonly property bool has: Music.current !== null

    implicitHeight: 80
    // a floating inset panel, like the sidebar
    color: Atelier.panel
    radius: Atelier.panelRadius
    border.width: 1
    border.color: Atelier.outline

    // Three anchored zones: the transport is pinned to the bar's centre, whatever the
    // track title or the shortcut buttons on either side need.
    // both sides as wide as the shortcut group needs, so the centre stays centred
    readonly property real sideW: Math.max(220, shortcuts.width + 20, Math.min(bar.width * 0.3, (bar.width - 420) / 2))

    // ── track ──
    Item {
        anchors.left: parent.left; anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: bar.sideW
        height: 60
        RowLayout {
            anchors.fill: parent
            spacing: 12
            Cover {
                implicitWidth: 56; implicitHeight: 56
                radius: Atelier.radiusMd
                placeholder: bar.has ? "󰎆" : "󰝛"
                source: Music.currentArt
            }
            ColumnLayout {
                // as wide as the title needs (capped), so the ♥ sits right after it
                // (explicit: a layout with stretching children would stretch too)
                Layout.fillWidth: false
                Layout.maximumWidth: bar.sideW - 56 - 34 - 40
                Layout.preferredWidth: Math.max(titleText.implicitWidth, artistText.implicitWidth) + 8
                spacing: 2
                Text {
                    id: titleText
                    Layout.fillWidth: true
                    text: bar.has ? Music.current.title : "Not playing"
                    elide: Text.ElideRight
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold
                    color: Atelier.text
                }
                Text {
                    id: artistText
                    Layout.fillWidth: true
                    text: bar.has ? (Music.loading ? "Loading…" : Music.current.artist || "") : ""
                    // (♥ sits to the right of the title block)
                    visible: text !== ""
                    elide: Text.ElideRight
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                    color: Music.loading ? Atelier.accent : Atelier.subtext
                    Behavior on color { CAnim {} }
                }
            }
            IconBtn {
                visible: bar.has
                z: 2
                icon: bar.has && Music.isLiked(Music.current.id) ? "heart_fill" : "heart"
                tint: bar.has && Music.isLiked(Music.current.id) ? Atelier.red : Atelier.text
                size: 32; iconSize: 16
                onClicked: Music.toggleLike(Music.current)
            }
            Item { Layout.fillWidth: true }
        }
        MouseArea {
            anchors.fill: parent
            anchors.rightMargin: 40
            enabled: bar.has
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (m) => m.button === Qt.RightButton ? Music.openMenu(Music.current, parent, m.x, m.y - 340, {}) : bar.navigate("now")
        }
    }

    // ── transport (exact centre) ──
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.max(300, Math.min(560, bar.width - 2 * bar.sideW - 80))
        spacing: 2
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12
            IconBtn { icon: "shuffle"; size: 34; iconSize: 15; dot: true; active: Music.shuffle; onClicked: Music.setShuffle(!Music.shuffle) }
            IconBtn { icon: "prev"; size: 40; iconSize: 18; enabled: bar.has; onClicked: Music.prev() }
            PlayButton {
                size: 46
                playing: Music.playing
                busy: Music.loading
                opacity: bar.has || Music.queue.length ? 1 : 0.4
                onClicked: Music.toggle()
            }
            IconBtn { icon: "next"; size: 40; iconSize: 18; enabled: bar.has; onClicked: Music.next() }
            IconBtn {
                icon: Music.loop === "track" ? "repeat_one" : "repeat"; size: 34; iconSize: 15; dot: true
                active: Music.loop !== "none"
                onClicked: Music.cycleLoop()
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text { Layout.preferredWidth: 34; horizontalAlignment: Text.AlignRight; text: Music.clock(Music.pos); font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; color: Atelier.subtext }
            SeekBar { Layout.fillWidth: true; showTimes: false }
            Text { Layout.preferredWidth: 34; text: Music.clock(Music.dur); font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; color: Atelier.subtext }
        }
    }

    // ── shortcuts ──
    Row {
        id: shortcuts
        anchors.right: parent.right; anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        VolumeControl { anchors.verticalCenter: parent.verticalCenter; compact: bar.width < 1100 }
        Item { width: 6; height: 1 }
        // save the current song: ✓ when downloaded, a ring while saving
        DownloadBtn { visible: bar.has; track: Music.current; size: 36 }
        IconBtn { icon: "lyrics"; size: 34; iconSize: 16; active: bar.page === "now"; onClicked: bar.navigate(bar.page === "now" ? "home" : "now") }
        IconBtn { icon: "queue"; size: 34; iconSize: 16; active: bar.page === "queue"; onClicked: bar.navigate(bar.page === "queue" ? "home" : "queue") }
        IconBtn { icon: "fullscreen"; size: 34; iconSize: 16; onClicked: bar.fullscreenRequested() }
    }
}
