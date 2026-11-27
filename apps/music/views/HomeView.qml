import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// Home, nothing shown twice: Your Mix (the For you list as one card), what you played before
// this song, then YouTube Music's shelves: song lists (Quick picks) as compact grids,
// albums / playlists as cards. The current song lives in the bar below.
// A song starts its radio; a playlist / album card plays it.
Item {
    id: root
    signal searchRequested()
    // a shelf of only songs reads better as a grid than as cards
    function songsOnly(items) { return items.length >= 6 && items.every(t => t.kind === "song"); }
    onVisibleChanged: if (visible && Music.online) Music.loadForYou(false)

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 2200
        maximumFlickVelocity: 6000
        SmoothWheel { flickable: flick }

        ColumnLayout {
            id: col
            x: 32
            y: 28
            width: flick.width - 64
            spacing: 26

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                ColumnLayout {
                    spacing: 2
                    Text {
                        text: {
                            const h = new Date().getHours();
                            return h < 5 ? "Late night listening" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
                        }
                        font.family: Atelier.fontUi; font.pixelSize: 24; font.weight: Font.Bold
                        color: Atelier.text
                    }
                    Text {
                        text: Music.forYou.length ? "Your mix is ready" : "What are we listening to?"
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg
                        color: Atelier.subtext
                    }
                }
                Item { Layout.fillWidth: true }      // title left, search + refresh right
                // search shortcut
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Math.min(340, col.width * 0.32); implicitHeight: 38; radius: Atelier.radiusMd
                    color: Atelier.container
                    border.width: 1; border.color: Atelier.outline
                    StateLayer { onClicked: root.searchRequested() }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 16
                        spacing: 10
                        SvgIcon { anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 18; color: Atelier.subtext }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Search songs, artists…"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: Atelier.subtext }
                    }
                }
                IconBtn {
                    icon: "refresh"; size: 42; iconSize: 20
                    enabled: !Music.homeLoading
                    onClicked: { Music.loadHome(); Music.loadForYou(true); }
                }
            }

            // ══ hero: Your Mix (what's playing lives in the bar below, not here) ══
            MixCard {
                Layout.fillWidth: true
                Layout.preferredHeight: 200
                tracks: Music.forYou
                onSearchRequested: root.searchRequested()
            }

            // offline: say so, and lead with what can play
            Rectangle {
                Layout.fillWidth: true
                visible: !Music.netOnline
                implicitHeight: 52
                radius: Atelier.radiusLg
                color: Qt.alpha(Atelier.peach, 0.12)
                border.width: 1
                border.color: Qt.alpha(Atelier.peach, 0.35)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16; anchors.rightMargin: 16
                    spacing: 12
                    Text { text: "󰖪"; font.family: Atelier.font; font.pixelSize: 18; color: Atelier.peach }
                    Text {
                        Layout.fillWidth: true
                        text: "You're offline. Songs saved on this computer still play."
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg
                        color: Atelier.text
                    }
                }
            }
            Shelf {
                visible: !Music.netOnline && Music.offlineTracks.length > 0
                title: "Saved on this computer"
                items: Music.offlineTracks.slice(0, 20).map(t => Object.assign({ kind: "song", playlistId: "" }, t))
                playAll: true
            }

            // what you played before: your listening history, minus the song that's on now
            Shelf {
                readonly property var recent: Music.history.filter(t => !Music.current || t.id !== Music.current.id).slice(0, 14)
                visible: recent.length > 0
                title: "Jump back in"
                items: recent.map(t => Object.assign({ kind: "song", playlistId: "" }, t))
            }

            Repeater {
                model: Music.shelves
                Loader {
                    required property var modelData
                    Layout.fillWidth: true
                    sourceComponent: root.songsOnly(modelData.items) ? gridShelf : cardShelf
                    Component { id: gridShelf; SongGrid { title: modelData.title; items: modelData.items } }
                    Component { id: cardShelf; Shelf { title: modelData.title; items: modelData.items } }
                }
            }

            // loading / empty
            Item {
                Layout.fillWidth: true
                implicitHeight: 220
                visible: Music.shelves.length === 0
                EmptyState {
                    anchors.centerIn: parent
                    icon: Music.homeLoading || !Music.online ? "󰑐" : "󰝚"
                    text: !Music.online ? "Starting…" : Music.homeLoading ? "Loading your home…" : "Nothing here yet. Try Search"
                }
            }
        }
    }

    component Shelf: ColumnLayout {
        id: shelf
        property string title
        property string subtitle: ""
        property var items: []
        property bool playAll: false       // "Play" + "Shuffle" for the whole shelf, in order
        property bool asList: false        // clicking a card plays the shelf from there (not the song's radio)
        Layout.fillWidth: true
        spacing: 12

        function playFrom(i) {
            if (shelf.asList) Music.playList(shelf.items, i, false);
            else Music.playItem(shelf.items[i]);
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: shelf.title
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsXl; font.weight: Font.DemiBold
                    color: Atelier.text
                }
                Text {
                    visible: shelf.subtitle !== ""
                    text: shelf.subtitle
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                    color: Atelier.subtext
                }
            }
            Chip {
                visible: shelf.playAll
                icon: "󰒟"; text: "Shuffle"
                tint: Atelier.overlay1
                interactive: true
                implicitHeight: 30
                onClicked: Music.playList(shelf.items, 0, true)
            }
            Chip {
                visible: shelf.playAll
                icon: "󰐊"; text: "Play"
                tint: Atelier.accent
                interactive: true
                implicitHeight: 30
                Layout.rightMargin: 6
                onClicked: Music.playList(shelf.items, 0, false)
            }
            IconButton { icon: "󰅁"; size: 30; glyphSize: 14; enabled: !strip.atXBeginning; onClicked: strip.page(-1) }
            IconButton { icon: "󰅂"; size: 30; glyphSize: 14; enabled: !strip.atXEnd; onClicked: strip.page(1) }
        }

        ListView {
            id: strip
            Layout.fillWidth: true
            implicitHeight: 222
            orientation: ListView.Horizontal
            spacing: 16
            clip: true
            interactive: false             // the vertical wheel goes to the page, not the shelf
            boundsBehavior: Flickable.StopAtBounds
            model: shelf.items
            SmoothWheel { flickable: strip; horizontal: true }
            function page(dir) {
                const to = Math.max(0, Math.min(contentWidth - width, contentX + dir * (width - 80)));
                pageAnim.to = to;
                pageAnim.restart();
            }
            NumberAnimation { id: pageAnim; target: strip; property: "contentX"; duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.emphasizedDecel }
            // cards ease in, one after another, when a shelf loads
            populate: Transition {
                id: pop
                SequentialAnimation {
                    PauseAnimation { duration: Math.min(pop.ViewTransition.index, 8) * 45 }
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.emphasizedDecel }
                        NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.spatial }
                    }
                }
            }
            delegate: Item {
                id: card
                required property var modelData
                required property int index
                width: 164
                height: 222
                readonly property bool isPlaying: Music.current && modelData.id && Music.current.id === modelData.id

                Cover {
                    id: art
                    width: 164; height: 164
                    radius: Atelier.radiusLg
                    decode: 328
                    source: card.modelData.art || card.modelData.thumb || ""
                    scale: cardMa.pressed ? 0.97 : cardMa.containsMouse ? 1.04 : 1
                    y: cardMa.containsMouse ? -4 : 0
                    Behavior on scale { Anim { type: "spatial" } }
                    Behavior on y { Anim { type: "spatial" } }
                }
                // saved for offline: a small badge on the art
                Rectangle {
                    readonly property string st: Music.fileState(card.modelData.id || "")
                    visible: st !== ""
                    anchors.left: art.left; anchors.top: art.top
                    anchors.margins: 8
                    width: 24; height: 24; radius: 12
                    color: Qt.alpha(Atelier.base, 0.8)
                    Text {
                        anchors.centerIn: parent
                        text: parent.st === "download" ? "󰗠" : "󰋊"
                        font.family: Atelier.font; font.pixelSize: 13
                        color: parent.st === "download" ? Atelier.accent : Atelier.subtext
                        Behavior on color { CAnim {} }
                    }
                }
                // hover: a play button on the art
                PlayButton {
                    anchors.right: art.right; anchors.bottom: art.bottom
                    anchors.margins: 10
                    size: 40
                    playing: card.isPlaying && Music.playing
                    opacity: cardMa.containsMouse || card.isPlaying ? 1 : 0
                    Behavior on opacity { Anim { type: "effects" } }
                    onClicked: card.isPlaying ? Music.toggle() : shelf.playFrom(card.index)
                }
                Text {
                    anchors.top: art.bottom; anchors.topMargin: 10
                    width: parent.width
                    text: card.modelData.title || ""
                    elide: Text.ElideRight
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold
                    color: card.isPlaying ? Atelier.accent : Atelier.text
                    Behavior on color { CAnim {} }
                }
                Text {
                    anchors.top: art.bottom; anchors.topMargin: 30
                    width: parent.width
                    text: card.modelData.artist || ""
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                    color: Atelier.subtext
                }
                MouseArea {
                    id: cardMa
                    anchors.fill: art
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (m) => {
                        if (m.button === Qt.RightButton) { if (card.modelData.id) Music.openMenu(card.modelData, cardMa, m.x, m.y, {}); }
                        else card.isPlaying ? Music.toggle() : shelf.playFrom(card.index);
                    }
                }
            }
        }
    }
}
