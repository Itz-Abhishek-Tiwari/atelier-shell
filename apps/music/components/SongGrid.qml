import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// A shelf of songs as a compact grid (YouTube Music's "Quick picks"): columns of `rows` rows,
// each a small cover + title + artist, scrolling sideways. Much denser than cards for lists.
//   asList: clicking plays the shelf from that song (For you); otherwise the song's radio.
ColumnLayout {
    id: grid
    property string title
    property string subtitle: ""
    property var items: []
    property int rows: 4
    property bool asList: false
    property bool playAll: false
    spacing: 12

    function playAt(i) {
        if (asList) Music.playList(items, i, false);
        else Music.radio(items[i]);
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text { text: grid.title; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsXl; font.weight: Font.DemiBold; color: Atelier.text }
            Text {
                visible: grid.subtitle !== ""
                text: grid.subtitle
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                color: Atelier.subtext
            }
        }
        Pill { visible: grid.playAll; icon: "shuffle"; label: "Shuffle"; onClicked: Music.playList(grid.items, 0, true) }
        Pill { visible: grid.playAll; icon: "play"; label: "Play"; on: true; onClicked: Music.playList(grid.items, 0, false) }
        Item { implicitWidth: 6 }
        IconBtn { icon: "prev"; size: 32; iconSize: 18; enabled: !cols.atXBeginning; onClicked: cols.page(-1) }
        IconBtn { icon: "next"; size: 32; iconSize: 18; enabled: !cols.atXEnd; onClicked: cols.page(1) }
    }

    ListView {
        id: cols
        Layout.fillWidth: true
        implicitHeight: grid.rows * 60
        orientation: ListView.Horizontal
        spacing: 14
        clip: true
        interactive: false
        model: Math.ceil(grid.items.length / grid.rows)
        readonly property real colWidth: Math.max(260, Math.min(360, (width - 2 * spacing) / 3))
        SmoothWheel { flickable: cols; horizontal: true }
        function page(dir) {
            pageAnim.to = Math.max(0, Math.min(contentWidth - width, contentX + dir * (width - 60)));
            pageAnim.restart();
        }
        Anim { id: pageAnim; target: cols; property: "contentX"; type: "emphasizedDecel"; duration: 520 }
        populate: Transition {
            id: pop
            SequentialAnimation {
                PauseAnimation { duration: Math.min(pop.ViewTransition.index, 6) * 50 }
                // fade only: animating x would pin columns to positions computed before the
                // grid knew its width
                Anim { property: "opacity"; from: 0; to: 1; type: "effects"; duration: 380 }
            }
        }
        delegate: Column {
            id: column
            required property int index
            width: cols.colWidth
            Repeater {
                model: Math.min(grid.rows, grid.items.length - column.index * grid.rows)
                Rectangle {
                    id: tile
                    required property int index
                    readonly property int i: column.index * grid.rows + index
                    readonly property var t: grid.items[i] || ({})
                    readonly property bool isCurrent: Music.current !== null && Music.current.id === t.id
                    width: column.width
                    height: 60
                    radius: Atelier.radiusMd
                    color: isCurrent ? Atelier.container : "transparent"
                    StateLayer {
                        id: tileLayer
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (m) => {
                            if (m.button === Qt.RightButton) Music.openMenu(tile.t, tileLayer, m.x, m.y, {});
                            else tile.isCurrent ? Music.toggle() : grid.playAt(tile.i);
                        }
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6; anchors.rightMargin: 8
                        spacing: 12
                        Item {
                            implicitWidth: 46; implicitHeight: 46
                            Cover { anchors.fill: parent; radius: 8; source: tile.t.thumb || tile.t.art || "" }
                            Rectangle {
                                anchors.fill: parent; radius: 8
                                color: Qt.rgba(0, 0, 0, 0.45)
                                visible: tile.isCurrent
                                SvgIcon { anchors.centerIn: parent; name: Music.playing ? "pause" : "play"; size: 20; color: "white" }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: tile.t.title || ""
                                elide: Text.ElideRight
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold
                                color: tile.isCurrent ? Atelier.accent : Atelier.text
                                Behavior on color { CAnim {} }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: tile.t.artist || ""
                                elide: Text.ElideRight
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                                color: Atelier.subtext
                            }
                        }
                    }
                }
            }
        }
    }
}
