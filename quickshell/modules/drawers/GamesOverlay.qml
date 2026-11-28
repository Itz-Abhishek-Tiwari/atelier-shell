import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// Game library (Super+G, IPC `games toggle`): a normal drawer from the bottom edge, styled like
// the wallpaper picker and the music drawer (frame colour, hairline `container` cards,
// `accentFill` chips). No fullscreen backdrop, no hero art behind the content.
// Header: title + count · search · source filters · Game mode. Then the selected game's card
// (cover, title, source chip, last played, Play), then a grid of posters. Sizes to the library.
//   ← → ↑ ↓  choose   Enter  play   Tab  next source   type  search   Esc  clear / close
// Library: scripts/games.py (Steam incl. /mnt/games, Heroic, Lutris, ~/.config/atelier/games.json)
// plus .desktop apps in the Game category. Rescanned on every open (~30 ms).
// IPC: `qs ipc call games toggle|open|close|search <text>`
// Launching closes the drawer; Perf's auto Game mode picks the game window up (or, with that
// setting off, Game mode is switched on here).
Item {
    id: gv
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool animActive: false
    signal closedSignal()

    property var all: []                 // every game, most recently played first
    property alias query: searchField.text
    property string source: ""           // "" = all sources
    property bool scanned: false
    property date now: new Date()

    readonly property var sources: {
        const seen = [];
        for (const g of all) if (seen.indexOf(g.source) < 0) seen.push(g.source);
        return seen;
    }
    readonly property var shown: {
        const q = query.toLowerCase().trim();
        return all.filter(g => (!source || g.source === source)
                               && (!q || g.title.toLowerCase().indexOf(q) >= 0));
    }
    readonly property var current: shown.length ? shown[Math.max(0, Math.min(grid.currentIndex, shown.length - 1))] : null

    // Super+G opens us while G is still held: ignore keys for a moment and all auto-repeats.
    property real openedAt: 0
    function fresh(e) { return e.isAutoRepeat || Date.now() - openedAt < 350; }

    function toggle() { if (visible && animActive) close(); else open(); }
    function open() {
        openedAt = Date.now();
        query = "";
        source = "";
        now = new Date();
        grid.currentIndex = 0;
        fetchArt.triedThisOpen = false;
        scan.running = true;
        visible = true;
        animActive = true;
        focusTimer.restart();
    }
    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }

    function tintFor(s) {
        return s === "Steam" ? Atelier.blue
             : s === "Epic" ? Atelier.lavender
             : s === "GOG" ? Atelier.mauve
             : s === "Heroic" ? Atelier.sapphire
             : s === "Lutris" ? Atelier.peach
             : s === "App" ? Atelier.green
             : Atelier.teal;
    }
    function sourceLabel(s) { return s === "App" ? "Apps" : s; }
    function ago(t) {
        if (!t) return "Not played yet";
        const d = Math.floor((gv.now.getTime() / 1000 - t) / 86400);
        return d <= 0 ? "Played today" : d === 1 ? "Played yesterday"
             : d < 30 ? "Played " + d + " days ago"
             : "Played " + new Date(t * 1000).toLocaleDateString(Qt.locale(), "d MMM yyyy");
    }
    function coverSrc(g) { return !g || !g.cover ? "" : (g.cover.startsWith("/") ? "file://" + g.cover : g.cover); }
    function nextSource() {
        const list = [""].concat(sources);
        source = list[(list.indexOf(source) + 1) % list.length];
    }

    function play(g) {
        if (!g) return;
        console.info("Games: launching", g.id);
        if (g.desktop) g.desktop.execute();
        else Quickshell.execDetached(g.launch);
        if (!Settings.behavior.autoGameMode) Perf.set("game");
        close();
    }

    // .desktop games (Categories=Game), minus launcher shortcuts the scanner already covers
    function desktopGames() {
        const skipExec = /steam:\/\/|heroic:\/\/|lutris:rungame/i;
        const skipId = /^(steam|com\.valvesoftware\.steam|heroic|com\.heroicgameslauncher\.hgl|net\.lutris\.lutris|lutris)(\.desktop)?$/i;
        return DesktopEntries.applications.values
            .filter(e => !e.noDisplay && e.categories.indexOf("Game") >= 0
                         && !skipExec.test(e.execString) && !skipId.test(e.id))
            .map(e => {
                const icon = e.icon || "";
                return {
                    id: "app:" + e.id, title: e.name, source: "App", launch: [], desktop: e,
                    cover: "", hero: "", lastPlayed: 0,
                    icon: icon.startsWith("/") ? "file://" + icon : (icon ? Quickshell.iconPath(icon, true) : "")
                };
            });
    }

    Process {
        id: scan
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/games.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [], pending = 0;
                try { const o = JSON.parse(text); list = o.games; pending = o.pending; }
                catch (e) { console.warn("Games: bad scanner output", e); }
                // missing artwork: download it in the background, then rescan (once per opening)
                if (pending > 0 && !fetchArt.triedThisOpen) { fetchArt.triedThisOpen = true; fetchArt.running = true; }
                const keep = gv.current ? gv.current.id : "";
                gv.all = list.concat(gv.desktopGames().sort((a, b) => a.title.localeCompare(b.title)));
                gv.scanned = true;
                const i = keep ? gv.shown.findIndex(g => g.id === keep) : -1;
                grid.currentIndex = Math.max(0, i);
            }
        }
    }

    Process {
        id: fetchArt
        property bool triedThisOpen: false
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/games.py", "--fetch"]
        onExited: if (gv.visible) scan.running = true
    }

    Timer { id: focusTimer; interval: 50; onTriggered: grid.forceActiveFocus() }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!gv.animActive) gv.visible = false }
    Timer { interval: 30000; repeat: true; running: gv.visible; onTriggered: gv.now = new Date() }

    onQueryChanged: grid.currentIndex = 0
    onSourceChanged: grid.currentIndex = 0

    // click outside closes
    MouseArea { anchors.fill: parent; enabled: gv.animActive; onClicked: gv.close() }

    EdgeDrawer {
        id: drawer
        edge: "bottom"
        open: gv.animActive
        bodyWidth: Math.min(1060, gv.width - 240)
        bodyHeight: Math.min(gv.height * 0.78, content.implicitHeight + 36)

        MouseArea { anchors.fill: parent }      // clicks on the body don't fall through and close it

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // ── header: title · search · sources · Game mode ────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    implicitWidth: 36; implicitHeight: 36; radius: Atelier.radiusMd
                    color: Qt.alpha(Atelier.accent, 0.14)
                    border.width: 1
                    border.color: Qt.alpha(Atelier.accent, 0.35)
                    Text { anchors.centerIn: parent; text: "󰊴"; font.family: Atelier.font; font.pixelSize: Atelier.iconMd; color: Atelier.accent }
                }
                ColumnLayout {
                    spacing: 0
                    Text { text: "Games"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsXl; font.weight: Font.DemiBold; color: Atelier.text }
                    Text {
                        text: !gv.scanned ? "Looking…"
                            : gv.shown.length === gv.all.length ? gv.all.length + (gv.all.length === 1 ? " game" : " games")
                            : gv.shown.length + " of " + gv.all.length
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
                    }
                }
                Item { implicitWidth: 4 }

                // search
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: Atelier.radiusLg
                    color: Atelier.container
                    border.width: 1
                    border.color: searchField.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                    Behavior on border.color { CAnim {} }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 8
                        Text { text: "󰍉"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: Atelier.subtext }
                        TextInput {
                            id: searchField
                            Layout.fillWidth: true
                            font.family: Atelier.fontUi
                            font.pixelSize: Atelier.fsLg
                            color: Atelier.text
                            clip: true
                            selectByMouse: true
                            Keys.onReturnPressed: { gv.play(gv.current); }
                            Keys.onEnterPressed: { gv.play(gv.current); }
                            Keys.onEscapePressed: { if (text) text = ""; else gv.close(); grid.forceActiveFocus(); }
                            Keys.onDownPressed: grid.forceActiveFocus()
                            Keys.onTabPressed: { gv.nextSource(); grid.forceActiveFocus(); }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !searchField.text
                                text: "Search your games"
                                font: searchField.font
                                color: Atelier.subtext
                                opacity: 0.7
                            }
                        }
                    }
                }

                // sources (only when there's more than one)
                Row {
                    visible: gv.sources.length > 1
                    spacing: 6
                    Pill { label: "All"; on: gv.source === ""; onClicked: gv.source = "" }
                    Repeater {
                        model: gv.sources
                        Pill {
                            required property string modelData
                            label: gv.sourceLabel(modelData)
                            on: gv.source === modelData
                            onClicked: gv.source = on ? "" : modelData
                        }
                    }
                }

                Pill {
                    icon: "󰊴"
                    label: "Game mode"
                    on: Perf.game
                    onClicked: Perf.toggleGame()
                }
            }

            // ── the selected game ───────────────────────────────────────────
            Rectangle {
                visible: !!gv.current
                Layout.fillWidth: true
                implicitHeight: 156
                radius: Atelier.radiusLg
                color: Atelier.container
                border.width: 1
                border.color: Atelier.outline

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 18

                    Poster {
                        Layout.preferredWidth: 85
                        Layout.preferredHeight: 128
                        game: gv.current
                        radius: Atelier.radiusMd
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: gv.current ? gv.current.title : ""
                            font.family: Atelier.fontUi
                            font.pixelSize: Atelier.iconLg
                            font.weight: Font.DemiBold
                            color: Atelier.text
                            elide: Text.ElideRight
                        }
                        RowLayout {
                            spacing: 10
                            Chip {
                                text: gv.current ? gv.sourceLabel(gv.current.source) : ""
                                icon: gv.current && gv.current.source === "App" ? "󰀻" : "󰓓"
                                tint: gv.current ? gv.tintFor(gv.current.source) : Atelier.accent
                            }
                            Text {
                                visible: !!gv.current && gv.current.source !== "App"
                                text: gv.current ? gv.ago(gv.current.lastPlayed) : ""
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
                            }
                        }
                    }

                    // Play
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: playRow.implicitWidth + 40
                        implicitHeight: 44
                        radius: height / 2
                        color: playMa.containsMouse ? Qt.lighter(Atelier.accentFill, 1.08) : Atelier.accentFill
                        scale: playMa.pressed ? 0.94 : (playMa.containsMouse ? 1.04 : 1)
                        Behavior on scale { Anim { type: "fastSpatial" } }
                        Behavior on color { CAnim {} }
                        RowLayout {
                            id: playRow
                            anchors.centerIn: parent
                            spacing: 8
                            Text { text: "󰐊"; font.family: Atelier.font; font.pixelSize: Atelier.iconMd; color: Atelier.onFill }
                            Text { text: "Play"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsXl; font.weight: Font.DemiBold; color: Atelier.onFill }
                        }
                        MouseArea {
                            id: playMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: gv.play(gv.current)
                        }
                    }
                }
            }

            // ── the library ─────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                readonly property int rows: Math.max(1, Math.min(2, Math.ceil(gv.shown.length / grid.cols)))
                implicitHeight: gv.shown.length === 0 ? 150 : grid.cellHeight * rows

                GridView {
                    id: grid
                    anchors.fill: parent
                    clip: true
                    focus: true
                    model: gv.shown
                    readonly property int cols: 7
                    cellWidth: Math.floor(width / cols)
                    cellHeight: Math.round((cellWidth - 12) * 3 / 2) + 12
                    keyNavigationWraps: false
                    highlightFollowsCurrentItem: false
                    boundsBehavior: Flickable.StopAtBounds
                    SmoothWheel { flickable: grid }

                    function go(i) {
                        if (count === 0) return;
                        currentIndex = Math.max(0, Math.min(count - 1, i));
                        const top = Math.floor(currentIndex / cols) * cellHeight;
                        const target = top < contentY ? top
                            : top + cellHeight > contentY + height ? top + cellHeight - height
                            : contentY;
                        scrollAnim.to = Math.max(0, Math.min(target, Math.max(0, contentHeight - height)));
                        scrollAnim.restart();
                    }
                    NumberAnimation { id: scrollAnim; target: grid; property: "contentY"; duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.emphasizedDecel }
                    Keys.onLeftPressed: go(currentIndex - 1)
                    Keys.onRightPressed: go(currentIndex + 1)
                    Keys.onUpPressed: { if (currentIndex < cols) searchField.forceActiveFocus(); else go(currentIndex - cols); }
                    Keys.onDownPressed: go(currentIndex + cols)
                    Keys.onReturnPressed: (e) => { if (!gv.fresh(e)) gv.play(gv.current); }
                    Keys.onEnterPressed: (e) => { if (!gv.fresh(e)) gv.play(gv.current); }
                    Keys.onTabPressed: gv.nextSource()
                    Keys.onPressed: (e) => {
                        if (e.key === Qt.Key_Escape) {
                            if (!e.isAutoRepeat) { if (gv.query) gv.query = ""; else gv.close(); }
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Home) { go(0); e.accepted = true; }
                        else if (e.key === Qt.Key_End) { go(count - 1); e.accepted = true; }
                        else if (e.key === Qt.Key_Backspace) { gv.query = gv.query.slice(0, -1); e.accepted = true; }
                        else if (!gv.fresh(e) && e.text && e.text.length === 1 && e.text >= " "
                                 && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                            searchField.forceActiveFocus();
                            searchField.text += e.text;
                            e.accepted = true;
                        }
                    }

                    delegate: Item {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: GridView.isCurrentItem
                        width: grid.cellWidth
                        height: grid.cellHeight

                        Item {
                            anchors.fill: parent
                            anchors.margins: 6
                            scale: tileMa.pressed ? 0.96 : (tileMa.containsMouse ? 1.03 : 1)
                            Behavior on scale { Anim { type: "fastSpatial" } }

                            Poster { anchors.fill: parent; game: tile.modelData; radius: Atelier.radiusMd }

                            // selection: a soft ring outside the poster
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -4
                                radius: Atelier.radiusLg
                                color: "transparent"
                                border.width: 2
                                border.color: Atelier.accent
                                opacity: tile.isCurrent ? 1 : 0
                                Behavior on opacity { Anim { type: "effects" } }
                            }
                        }
                        MouseArea {
                            id: tileMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // first click selects, a click on the selected poster plays
                            onClicked: { if (tile.isCurrent) gv.play(tile.modelData); else grid.currentIndex = tile.index; }
                        }
                    }
                }

                // empty / no match
                Column {
                    anchors.centerIn: parent
                    visible: gv.scanned && gv.shown.length === 0
                    spacing: 10
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: gv.query ? "󰍉" : "󰊴"
                        font.family: Atelier.font; font.pixelSize: 28
                        color: Atelier.overlay1
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: gv.query ? "Nothing matches “" + gv.query + "”"
                            : "No games yet. Install some with Steam, Heroic or Lutris (on /mnt/games) and they show up here."
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg
                        color: Atelier.subtext
                    }
                }
            }

            // ── status line ─────────────────────────────────────────────────
            Text {
                Layout.fillWidth: true
                text: "Arrows choose  ·  Enter or click to play  ·  " + (gv.sources.length > 1 ? "Tab switches source  ·  " : "") + "type to search"
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                color: Atelier.subtext
            }
        }
    }

    // ── pieces ──────────────────────────────────────────────────────────────
    component Pill: Rectangle {
        id: pl
        property string icon: ""
        property string label
        property bool on: false
        signal clicked()
        implicitWidth: plRow.implicitWidth + 22
        implicitHeight: 30
        radius: Atelier.radiusMd
        color: on ? Atelier.accentFill : Atelier.container
        Behavior on color { CAnim {} }
        StateLayer { mouseArea: plMa }
        Row {
            id: plRow
            anchors.centerIn: parent
            spacing: 6
            Text { visible: pl.icon !== ""; text: pl.icon; font.family: Atelier.font; font.pixelSize: Atelier.fsMd; color: pl.on ? Atelier.onFill : Atelier.subtext; anchors.verticalCenter: parent.verticalCenter }
            Text { text: pl.label; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; color: pl.on ? Atelier.onFill : Atelier.text; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: plMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pl.clicked() }
    }

    // a 2:3 cover with smooth rounded corners (MultiEffect mask; ClippingRectangle steps the
    // corners). Without artwork: the app icon or the title's initial on a container tile.
    component Poster: Item {
        id: po
        property var game: null
        property real radius: Atelier.radiusMd
        readonly property bool ready: poImg.status === Image.Ready

        Rectangle {
            anchors.fill: parent
            radius: po.radius
            color: Atelier.containerHigh
            border.width: 1
            border.color: Atelier.outline
            visible: !po.ready
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6
                Item { Layout.fillHeight: true }
                IconImage {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !!po.game && !!po.game.icon
                    implicitSize: Math.round(po.width * 0.42)
                    source: po.game && po.game.icon ? po.game.icon : ""
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !!po.game && !po.game.icon
                    text: po.game ? po.game.title.charAt(0).toUpperCase() : ""
                    font.family: Atelier.fontUi; font.pixelSize: Math.round(po.width * 0.36); font.weight: Font.DemiBold
                    color: po.game ? gv.tintFor(po.game.source) : Atelier.accent
                    Behavior on color { CAnim {} }
                }
                Text {
                    Layout.fillWidth: true
                    visible: po.height > 150
                    text: po.game ? po.game.title : ""
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
                }
                Item { Layout.fillHeight: true }
            }
        }
        Image {
            id: poImg
            anchors.fill: parent
            visible: false
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: true
            source: gv.coverSrc(po.game)
            sourceSize.width: 300
            sourceSize.height: 450
        }
        Item {
            id: poMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            layer.textureSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
            Rectangle { anchors.fill: parent; radius: po.radius; color: "black"; antialiasing: true }
        }
        MultiEffect {
            anchors.fill: parent
            source: poImg
            maskEnabled: true
            maskSource: poMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            opacity: po.ready ? 1 : 0
            Behavior on opacity { Anim { type: "slowEffects" } }
        }
    }
}
