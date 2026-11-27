import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.config
import qs.services

// The song menu (right-click or ⋮ on any song). One instance per window, opened through
// Music.openMenu(track, item, x, y, context). `context` adds actions where they make sense:
//   { pid: <playlist id> }   → "Remove from this playlist"
//   { queueIndex: <i> }      → "Remove from queue"
// "Add to playlist" switches the menu to your playlists, with a field to make a new one.
Item {
    id: root
    anchors.fill: parent
    visible: false

    property var track: null
    property var context: ({})
    property string mode: "main"            // main | playlists

    function open(t, x, y, ctx) {
        track = t; context = ctx || {}; mode = "main";
        Music.loadPlaylists();
        visible = true;
        panel.x = Math.max(8, Math.min(width - panel.width - 8, x));
        panel.y = Math.max(8, Math.min(height - panel.implicitHeight - 8, y));
        panel.opacity = 0; panel.scale = 0.94;
        panel.opacity = 1; panel.scale = 1;
        keys.forceActiveFocus();
    }
    function close() { visible = false; mode = "main"; newName.text = ""; }

    Connections {
        target: Music
        function onMenuRequested(t, x, y, ctx) { root.open(t, x, y, ctx); }
    }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.close() }
    Item { id: keys; focus: root.visible; Keys.onEscapePressed: root.mode === "playlists" ? root.mode = "main" : root.close() }

    Rectangle {
        id: panel
        width: 250
        implicitHeight: col.implicitHeight + 12
        height: implicitHeight
        radius: Atelier.radiusMd
        color: Atelier.surface0
        border.width: 1
        border.color: Atelier.outline
        transformOrigin: Item.TopLeft
        Behavior on opacity { Anim { type: "fastEffects" } }
        Behavior on scale { Anim { type: "fastSpatial" } }
        Behavior on height { Anim { type: "fastSpatial" } }
        clip: true
        RectangularShadow { anchors.fill: parent; z: -1; radius: parent.radius; offset.y: 8; blur: 26; color: Qt.rgba(0, 0, 0, 0.35) }
        MouseArea { anchors.fill: parent }    // clicks on the panel don't close it

        ColumnLayout {
            id: col
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 6
            spacing: 0

            // the song, as a header
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 6
                Layout.bottomMargin: 8
                spacing: 10
                Cover { implicitWidth: 38; implicitHeight: 38; radius: 8; source: root.track ? (root.track.thumb || root.track.art || "") : "" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { Layout.fillWidth: true; text: root.track ? root.track.title : ""; elide: Text.ElideRight; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold; color: Atelier.text }
                    Text { Layout.fillWidth: true; text: root.track ? (root.track.artist || "") : ""; elide: Text.ElideRight; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Atelier.outline; Layout.bottomMargin: 4 }

            // ── main ──
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.mode === "main"
                spacing: 0
                MenuRow { icon: "play"; label: "Play now"; onTriggered: { Music.play(root.track); root.close(); } }
                MenuRow { icon: "play_next"; label: "Play next"; onTriggered: { Music.playNext(root.track); root.close(); } }
                MenuRow { icon: "add"; label: "Add to queue"; onTriggered: { Music.add(root.track); root.close(); } }
                MenuRow { icon: "radio"; label: "Start radio"; onTriggered: { Music.radio(root.track); root.close(); } }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Atelier.outline; Layout.topMargin: 4; Layout.bottomMargin: 4 }
                MenuRow {
                    readonly property bool liked: root.track ? Music.isLiked(root.track.id) : false
                    icon: liked ? "heart_fill" : "heart"
                    tint: liked ? Atelier.red : Atelier.subtext1
                    label: liked ? "Remove from Liked" : "Like"
                    onTriggered: { Music.toggleLike(root.track); root.close(); }
                }
                MenuRow { icon: "playlist_add"; label: "Add to playlist"; chevron: true; onTriggered: root.mode = "playlists" }
                MenuRow {
                    readonly property string st: root.track ? Music.fileState(root.track.id) : ""
                    icon: st === "download" ? "delete" : "download"
                    label: st === "download" ? "Remove download" : "Download"
                    onTriggered: { if (st === "download") Music.removeFile(root.track.id, "download"); else Music.download(root.track); root.close(); }
                }
                MenuRow {
                    visible: root.context.pid !== undefined
                    icon: "close"; label: "Remove from this playlist"; tint: Atelier.red
                    onTriggered: { Music.removeFromPlaylist(root.context.pid, root.track.id); root.close(); }
                }
                MenuRow {
                    visible: root.context.queueIndex !== undefined
                    icon: "close"; label: "Remove from queue"; tint: Atelier.red
                    onTriggered: { Music.remove(root.context.queueIndex); root.close(); }
                }
            }

            // ── playlists ──
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.mode === "playlists"
                spacing: 0
                MenuRow { icon: "back"; label: "Back"; onTriggered: root.mode = "main" }
                // new playlist, named inline
                Rectangle {
                    Layout.fillWidth: true
                    Layout.margins: 4
                    implicitHeight: 34
                    radius: Atelier.radiusSm
                    color: Atelier.container
                    border.width: 1
                    border.color: newName.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 4
                        spacing: 8
                        SvgIcon { name: "add"; size: 16; color: Atelier.accent }
                        TextInput {
                            id: newName
                            Layout.fillWidth: true
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd
                            color: Atelier.text
                            clip: true
                            onAccepted: if (text.trim()) { Music.createPlaylist(text, root.track); root.close(); }
                            Text { visible: !newName.text; text: "New playlist…"; font: newName.font; color: Atelier.subtext }
                        }
                    }
                }
                Repeater {
                    model: Music.playlists
                    MenuRow {
                        required property var modelData
                        icon: "library"
                        label: modelData.name
                        hint: String(modelData.count)
                        onTriggered: { Music.addToPlaylist(modelData.pid, root.track); root.close(); }
                    }
                }
                Text {
                    visible: Music.playlists.length === 0
                    Layout.margins: 10
                    text: "No playlists yet: name one above"
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
                }
            }
        }
    }

    component MenuRow: Rectangle {
        id: row
        property string icon
        property string label
        property string hint: ""
        property bool chevron: false
        property color tint: Atelier.subtext1
        signal triggered()
        Layout.fillWidth: true
        implicitHeight: visible ? 34 : 0
        radius: Atelier.radiusSm
        color: "transparent"
        StateLayer { radius: Atelier.radiusSm; onClicked: row.triggered() }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10; anchors.rightMargin: 10
            spacing: 12
            SvgIcon { name: row.icon; size: 17; color: row.tint }
            Text { Layout.fillWidth: true; text: row.label; elide: Text.ElideRight; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.text }
            Text { visible: row.hint !== ""; text: row.hint; font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; color: Atelier.subtext }
            SvgIcon { visible: row.chevron; name: "chevron"; size: 16; color: Atelier.subtext }
        }
    }
}
