import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// One song in a list (search results, queue). Click plays; the buttons on the right appear
// on hover: play next, add to queue (or remove, in the queue). The playing track is accented.
Rectangle {
    id: row
    property var track: ({})
    property int number: -1                 // shows a position number instead of nothing
    property bool isCurrent: false
    property bool inQueue: false
    property bool inLibrary: false          // Offline tab: offer "remove from this computer"
    property string when: ""                // History: "2 h ago" in place of the duration
    property var menuContext: ({})          // extra song-menu actions (TrackMenu.qml)
    readonly property bool liked: Music.isLiked(track.id || "")
    readonly property string saved: Music.fileState(track.id || "")
    readonly property real saving: Music.progressOf(track.id || "")
    signal activated()
    signal removeRequested()

    implicitHeight: 56
    radius: Atelier.radiusMd
    readonly property bool hovered: rowHover.hovered
    color: hovered ? Atelier.containerHigh : (isCurrent ? Atelier.container : "transparent")
    Behavior on color { CAnim {} }

    HoverHandler { id: rowHover }   // passive: still true while the pointer is over the buttons
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (m) => {
            if (m.button === Qt.RightButton) row.openMenu(m.x, m.y);
            else row.activated();
        }
    }
    function openMenu(x, y, from) {
        const ctx = Object.assign({}, row.menuContext);
        if (row.inQueue && row.number >= 0 && !row.isCurrent) ctx.queueIndex = row.number;
        Music.openMenu(row.track, from || row, x, y, ctx);
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 10
        spacing: 12

        Text {
            visible: row.number >= 0
            Layout.preferredWidth: 22
            horizontalAlignment: Text.AlignRight
            text: row.isCurrent ? (Music.playing ? "󰝚" : "󰏤") : String(row.number + 1)
            font.family: Atelier.font
            font.pixelSize: row.isCurrent ? 14 : Atelier.fsSm
            color: row.isCurrent ? Atelier.accent : Atelier.subtext
            Behavior on color { CAnim {} }
        }
        Cover {
            implicitWidth: 40; implicitHeight: 40
            radius: Atelier.radiusSm
            decode: 80
            source: row.track.thumb || ""
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                Layout.fillWidth: true
                text: row.track.title || ""
                elide: Text.ElideRight
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg
                font.weight: row.isCurrent ? Font.DemiBold : Font.Medium
                color: row.isCurrent ? Atelier.accent : Atelier.text
                Behavior on color { CAnim {} }
            }
            Text {
                Layout.fillWidth: true
                text: row.track.artist || ""
                visible: text !== ""
                elide: Text.ElideRight
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                color: Atelier.subtext
            }
        }
        // saved state: ✓ downloaded · drive = cached for offline · % while saving
        Text {
            visible: row.saving >= 0 || (row.saved !== "" && !row.hovered)
            text: row.saving >= 0 ? Math.round(row.saving * 100) + "%" : row.saved === "download" ? "󰗠" : "󰋊"
            font.family: Atelier.font
            font.pixelSize: row.saving >= 0 ? Atelier.fsSm : 14
            color: row.saving >= 0 || row.saved === "download" ? Atelier.accent : Atelier.overlay1
            Behavior on color { CAnim {} }
        }
        // ♥: always shown once liked, on hover otherwise
        IconBtn {
            visible: row.liked || row.hovered
            icon: row.liked ? "heart_fill" : "heart"
            size: 30; iconSize: 16
            tint: row.liked ? Atelier.red : Atelier.text
            onClicked: Music.toggleLike(row.track)
        }
        Row {
            spacing: 2
            visible: row.hovered
            IconBtn {
                visible: row.saved !== "download" && row.saving < 0 && !row.inLibrary
                icon: "download"; size: 30; iconSize: 16
                onClicked: Music.download(row.track)
            }
            IconBtn {
                visible: row.inLibrary
                icon: "delete"; size: 30; iconSize: 16; tint: Atelier.red
                onClicked: Music.removeFile(row.track.id, row.saved || "cache")
            }
            IconBtn {
                visible: row.inQueue && !row.isCurrent
                icon: "close"; size: 30; iconSize: 15
                onClicked: row.removeRequested()
            }
            IconBtn { id: moreBtn; icon: "more"; size: 30; iconSize: 17; onClicked: row.openMenu(0, moreBtn.height, moreBtn) }
        }
        Text {
            visible: (!!row.track.duration || row.when !== "") && !row.hovered
            text: row.when !== "" ? row.when : (row.track.duration || "")
            font.family: Atelier.font; font.pixelSize: Atelier.fsSm
            color: Atelier.subtext
        }
    }
}
