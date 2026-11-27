import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// Library: what's yours. Liked songs (kept offline automatically), your playlists, and the
// history of what you played. Right-click or ⋮ on any song for more.
Item {
    id: root
    property string tab: "liked"          // liked | playlists | history
    property var openPl: null             // the playlist being viewed ({pid, name, …})
    property var plTracks: []
    property bool renaming: false

    function showPlaylist(p) { openPl = p; plTracks = []; renaming = false; Music.playlistTracks(p.pid, r => plTracks = r); }
    onVisibleChanged: if (visible) { Music.loadLiked(); Music.loadPlaylists(); Music.loadHistory(); }
    Connections {
        target: Music
        function onPlaylistsChanged() {
            if (!root.openPl) return;
            const p = Music.playlists.find(x => x.pid === root.openPl.pid);
            if (!p) { root.openPl = null; return; }
            root.openPl = p;
            Music.playlistTracks(p.pid, r => root.plTracks = r);
        }
    }

    function ago(ts) {
        const d = Date.now() / 1000 - ts;
        return d < 60 ? "now" : d < 3600 ? Math.floor(d / 60) + " min ago" : d < 86400 ? Math.floor(d / 3600) + " h ago"
             : d < 604800 ? Math.floor(d / 86400) + " d ago" : new Date(ts * 1000).toLocaleDateString(Qt.locale(), "d MMM");
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        anchors.topMargin: 28
        spacing: 16

        // header + tabs
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: "Library"; font.family: Atelier.fontUi; font.pixelSize: 24; font.weight: Font.Bold; color: Atelier.text }
                Text {
                    text: Music.liked.length + " liked  ·  " + Music.playlists.length + (Music.playlists.length === 1 ? " playlist" : " playlists")
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
                }
            }
            Segmented {
                current: root.tab
                model: [{ id: "liked", label: "Liked" }, { id: "playlists", label: "Playlists" }, { id: "history", label: "History" }]
                onPicked: (id) => { root.tab = id; root.openPl = null; }
            }
        }

        // ══ Liked ══
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tab === "liked"
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                visible: Music.liked.length > 0
                spacing: 8
                Text { Layout.fillWidth: true; text: "Liked songs are saved offline automatically"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                Pill { icon: "shuffle"; label: "Shuffle"; onClicked: Music.playList(Music.liked, 0, true) }
                Pill { icon: "play"; label: "Play"; on: true; onClicked: Music.playList(Music.liked, 0, false) }
            }
            TrackList {
                Layout.fillWidth: true
                Layout.fillHeight: true
                tracks: Music.liked
                emptyIcon: "heart"
                emptyText: "Songs you ♥ show up here"
                onPlay: (i) => Music.playList(Music.liked, i, false)
            }
        }

        // ══ Playlists ══
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tab === "playlists"

            // grid of playlists
            GridView {
                id: plGrid
                anchors.fill: parent
                visible: root.openPl === null
                clip: true
                cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 190)))
                cellHeight: 236
                boundsBehavior: Flickable.StopAtBounds
                model: [{ pid: -1, name: "New playlist" }].concat(Music.playlists)
                SmoothWheel { flickable: plGrid }
                delegate: Item {
                    id: pc
                    required property var modelData
                    width: plGrid.cellWidth
                    height: plGrid.cellHeight
                    readonly property bool isNew: modelData.pid === -1
                    Item {
                        id: art
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 4
                        width: plGrid.cellWidth - 26; height: width
                        // new: a dashed-looking tile with a +
                        Rectangle {
                            anchors.fill: parent
                            visible: pc.isNew
                            radius: Atelier.radiusLg
                            color: Atelier.container
                            border.width: 1
                            border.color: Qt.alpha(Atelier.accent, 0.4)
                            SvgIcon { anchors.centerIn: parent; name: "add"; size: 40; color: Atelier.accent }
                        }
                        // a 2×2 collage of its first covers (or one cover)
                        Grid {
                            anchors.fill: parent
                            visible: !pc.isNew
                            columns: (pc.modelData.covers || []).length >= 4 ? 2 : 1
                            spacing: 2
                            Repeater {
                                model: (pc.modelData.covers || []).length >= 4 ? pc.modelData.covers.slice(0, 4) : (pc.modelData.covers || []).slice(0, 1)
                                Cover {
                                    required property var modelData
                                    width: (art.width - (parent.columns - 1) * 2) / parent.columns
                                    height: width
                                    radius: parent.columns === 2 ? 6 : Atelier.radiusLg
                                    source: modelData
                                }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            visible: !pc.isNew && (pc.modelData.covers || []).length === 0
                            radius: Atelier.radiusLg
                            color: Atelier.containerHigh
                            SvgIcon { anchors.centerIn: parent; name: "library"; size: 40; color: Atelier.subtext }
                        }
                        StateLayer {
                            radius: Atelier.radiusLg
                            onClicked: pc.isNew ? Music.createPlaylist("Playlist " + (Music.playlists.length + 1), null) : root.showPlaylist(pc.modelData)
                        }
                    }
                    Text {
                        anchors.top: art.bottom; anchors.topMargin: 8
                        anchors.left: art.left; anchors.right: art.right
                        text: pc.modelData.name
                        elide: Text.ElideRight
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold
                        color: pc.isNew ? Atelier.accent : Atelier.text
                    }
                    Text {
                        visible: !pc.isNew
                        anchors.top: art.bottom; anchors.topMargin: 26
                        anchors.left: art.left
                        text: (pc.modelData.count || 0) + ((pc.modelData.count || 0) === 1 ? " song" : " songs")
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                        color: Atelier.subtext
                    }
                }
            }

            // one playlist
            ColumnLayout {
                anchors.fill: parent
                visible: root.openPl !== null
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    IconBtn { icon: "back"; size: 36; iconSize: 20; onClicked: root.openPl = null }
                    // name, editable
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !root.renaming
                            text: root.openPl ? root.openPl.name : ""
                            font.family: Atelier.fontUi; font.pixelSize: 20; font.weight: Font.Bold
                            color: Atelier.text
                        }
                        Rectangle {
                            anchors.fill: parent
                            visible: root.renaming
                            radius: Atelier.radiusSm
                            color: Atelier.container
                            border.width: 1; border.color: Qt.alpha(Atelier.accent, 0.6)
                            TextInput {
                                id: rename
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: Atelier.fontUi; font.pixelSize: 16; font.weight: Font.DemiBold
                                color: Atelier.text
                                onAccepted: { Music.renamePlaylist(root.openPl.pid, text); root.renaming = false; }
                                Keys.onEscapePressed: root.renaming = false
                            }
                        }
                    }
                    Text {
                        visible: !root.renaming
                        text: root.plTracks.length + (root.plTracks.length === 1 ? " song" : " songs")
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
                    }
                    IconBtn { icon: "edit"; size: 34; iconSize: 17; onClicked: { rename.text = root.openPl.name; root.renaming = true; rename.forceActiveFocus(); rename.selectAll(); } }
                    IconBtn { icon: "delete"; size: 34; iconSize: 17; tint: Atelier.red; onClicked: { Music.deletePlaylist(root.openPl.pid); root.openPl = null; } }
                    Pill { visible: root.plTracks.length > 0; icon: "shuffle"; label: "Shuffle"; onClicked: Music.playList(root.plTracks, 0, true) }
                    Pill { visible: root.plTracks.length > 0; icon: "play"; label: "Play"; on: true; onClicked: Music.playList(root.plTracks, 0, false) }
                }
                TrackList {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    tracks: root.plTracks
                    context: root.openPl ? { pid: root.openPl.pid } : ({})
                    emptyIcon: "playlist_add"
                    emptyText: "Right-click any song → Add to playlist"
                    onPlay: (i) => Music.playList(root.plTracks, i, false)
                }
            }
        }

        // ══ History ══
        TrackList {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tab === "history"
            tracks: Music.history
            showWhen: true
            emptyIcon: "history"
            emptyText: "Songs you play show up here"
            onPlay: (i) => Music.radio(Music.history[i])
        }
    }

    // a list of songs: rows with ♥, ⋮ and the song menu on right-click
    component TrackList: Item {
        id: tl
        property var tracks: []
        property var context: ({})
        property bool showWhen: false
        property string emptyIcon: "library"
        property string emptyText: ""
        signal play(int i)
        ListView {
            id: lv
            anchors.fill: parent
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: tl.tracks
            SmoothWheel { flickable: lv }
            delegate: TrackRow {
                required property var modelData
                required property int index
                width: ListView.view.width
                track: modelData
                number: index
                when: tl.showWhen ? root.ago(modelData.played || 0) : ""
                menuContext: tl.context
                isCurrent: Music.current !== null && Music.current.id === modelData.id
                onActivated: tl.play(index)
            }
            footer: Item { height: 16 }
        }
        ColumnLayout {
            anchors.centerIn: parent
            visible: tl.tracks.length === 0
            spacing: 10
            SvgIcon { Layout.alignment: Qt.AlignHCenter; name: tl.emptyIcon; size: 34; color: Atelier.overlay1 }
            Text { Layout.alignment: Qt.AlignHCenter; text: tl.emptyText; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: Atelier.subtext }
        }
    }
}
