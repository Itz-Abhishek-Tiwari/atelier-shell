import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// Atelier Games (Super+G, IPC `games toggle`): a fullscreen, console-style game library.
// One row of covers along the bottom, the selected game's title large on the left, its
// artwork faint behind everything.
//   ←/→ or wheel choose · Enter / click play · type to search · Esc clear search / close
// Library: scripts/games.py (Steam incl. /mnt/games, Heroic, Lutris, ~/.config/atelier/games.json)
// plus .desktop apps in the Game category. Rescanned on every open (~30 ms).
// IPC: `qs ipc call games toggle|open|close|search <text>`
// Launching closes the overlay; Perf's auto Game mode picks the game window up (or, with that
// setting off, Game mode is switched on here).
Item {
    id: gv
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool animActive: false
    signal closedSignal()

    property var all: []                 // every game, most recently played first
    property string query: ""
    property int selected: 0
    property bool scanned: false
    property date now: new Date()

    readonly property var shown: {
        const q = query.toLowerCase();
        return q ? all.filter(g => g.title.toLowerCase().indexOf(q) >= 0 || g.source.toLowerCase() === q) : all;
    }
    readonly property var current: shown.length ? shown[Math.min(selected, shown.length - 1)] : null

    readonly property real cardH: Math.max(180, Math.min(height * 0.34, 330))
    readonly property real cardW: Math.round(cardH * 2 / 3)

    // Super+G opens us while G is still held: ignore keys for a moment and all auto-repeats.
    property real openedAt: 0
    function fresh(e) { return e.isAutoRepeat || Date.now() - openedAt < 350; }

    function open() {
        openedAt = Date.now();
        query = "";
        selected = 0;
        now = new Date();
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

    function tintFor(source) {
        return source === "Steam" ? Atelier.blue
             : source === "Epic" ? Atelier.lavender
             : source === "GOG" ? Atelier.mauve
             : source === "Lutris" ? Atelier.peach
             : source === "App" ? Atelier.green
             : Atelier.teal;
    }
    function ago(t) {
        if (!t) return "Not played yet";
        const d = Math.floor((gv.now.getTime() / 1000 - t) / 86400);
        return d <= 0 ? "Played today" : d === 1 ? "Played yesterday"
             : d < 30 ? "Played " + d + " days ago"
             : "Played " + new Date(t * 1000).toLocaleDateString(Qt.locale(), "d MMM yyyy");
    }
    function step(n) {
        if (shown.length) selected = (selected + n + shown.length) % shown.length;
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
                gv.selected = Math.max(0, i);
            }
        }
    }

    Process {
        id: fetchArt
        property bool triedThisOpen: false
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/games.py", "--fetch"]
        onExited: if (gv.visible) scan.running = true
    }

    Timer { id: focusTimer; interval: 40; onTriggered: keys.forceActiveFocus() }
    Timer {
        id: closeTimer
        interval: Atelier.durClose + 40
        onTriggered: if (!gv.animActive) gv.visible = false
    }
    Timer { interval: 30000; repeat: true; running: gv.visible; onTriggered: gv.now = new Date() }

    onQueryChanged: selected = 0

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onLeftPressed: gv.step(-1)
        Keys.onRightPressed: gv.step(1)
        Keys.onReturnPressed: (e) => { if (!gv.fresh(e)) gv.play(gv.current); }
        Keys.onEnterPressed: (e) => { if (!gv.fresh(e)) gv.play(gv.current); }
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Escape) {
                if (!e.isAutoRepeat) { if (gv.query) gv.query = ""; else gv.close(); }
                e.accepted = true;
            } else if (e.key === Qt.Key_Home) { gv.selected = 0; e.accepted = true; }
            else if (e.key === Qt.Key_End) { gv.selected = Math.max(0, gv.shown.length - 1); e.accepted = true; }
            else if (e.key === Qt.Key_Backspace) { gv.query = gv.query.slice(0, -1); e.accepted = true; }
            else if (!gv.fresh(e) && e.text && e.text.length === 1 && e.text >= " "
                     && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                gv.query += e.text;
                e.accepted = true;
            }
        }

        // ── Backdrop: near-solid, with the selected game's art faint behind ───
        Item {
            anchors.fill: parent
            opacity: gv.animActive ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: gv.animActive ? 260 : Atelier.durClose } }

            Rectangle { anchors.fill: parent; color: Atelier.crust }
            Image {
                id: hero
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                source: gv.visible && gv.current ? (gv.current.hero || gv.current.cover || "") : ""
                sourceSize.width: 1280
                opacity: status === Image.Ready ? 0.3 : 0
                Behavior on opacity { NumberAnimation { duration: Atelier.durMedium } }
            }
            // fade the art into the backdrop where the text and covers sit
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.alpha(Atelier.crust, 0.92) }
                    GradientStop { position: 0.6; color: Qt.alpha(Atelier.crust, 0.35) }
                    GradientStop { position: 1.0; color: Qt.alpha(Atelier.crust, 0.1) }
                }
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.45; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.alpha(Atelier.crust, 0.95) }
                }
            }
            MouseArea { anchors.fill: parent }      // swallow clicks; Esc closes
        }

        // ── Content ──────────────────────────────────────────────────────────
        Item {
            id: content
            anchors.fill: parent
            anchors.margins: Math.max(48, Atelier.maxInset + 40)
            opacity: gv.animActive ? 1 : 0
            scale: gv.animActive ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: gv.animActive ? 260 : Atelier.durClose } }
            Behavior on scale {
                NumberAnimation {
                    duration: gv.animActive ? Atelier.durOpen : Atelier.durClose
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: gv.animActive ? Atelier.curveOpen : Atelier.curveClose
                }
            }

            // header: name · count · search ............ mode · clock
            RowLayout {
                id: header
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: 12
                Text { text: "󰊴"; font.family: Atelier.font; font.pixelSize: 22; color: Atelier.accent }
                Text { text: "Games"; font.family: Atelier.fontUi; font.pixelSize: 20; font.weight: Font.DemiBold; color: Atelier.text }
                Text {
                    visible: gv.scanned && gv.all.length > 0
                    text: gv.shown.length + (gv.query ? " of " + gv.all.length : "")
                    font.family: Atelier.font; font.pixelSize: 14; color: Atelier.subtext
                }
                Chip { visible: gv.query !== ""; icon: "󰍉"; text: gv.query; tint: Atelier.accent }
                Item { Layout.fillWidth: true }
                Chip { visible: Perf.game; icon: "󰊴"; text: "Game mode"; tint: Atelier.green }
                Text {
                    text: Atelier.hour12(gv.now) + ":" + Qt.formatTime(gv.now, "mm")
                    font.family: Atelier.font; font.pixelSize: 20; color: Atelier.text
                }
                Chip { visible: text !== ""; text: Atelier.ampm(gv.now); tint: Atelier.blue; mono: true }
            }

            // the selected game, large
            ColumnLayout {
                visible: !!gv.current
                anchors { left: parent.left; bottom: row.top; bottomMargin: 40 }
                width: Math.min(parent.width * 0.6, 900)
                spacing: 14

                Text {
                    Layout.fillWidth: true
                    text: gv.current ? gv.current.title : ""
                    font.family: Atelier.fontUi
                    font.pixelSize: Math.round(Math.min(64, Math.max(36, gv.height * 0.055)))
                    font.weight: Font.Bold
                    color: Atelier.text
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                RowLayout {
                    spacing: 10
                    Chip { text: gv.current ? gv.current.source : ""; tint: gv.tintFor(text) }
                    Text {
                        text: gv.current && gv.current.source !== "App" ? gv.ago(gv.current.lastPlayed) : ""
                        font.family: Atelier.fontUi; font.pixelSize: 13; color: Atelier.subtext
                    }
                }
                // Play
                Rectangle {
                    Layout.topMargin: 6
                    implicitWidth: playRow.implicitWidth + 44
                    implicitHeight: 46
                    radius: height / 2
                    color: playMa.containsMouse ? Qt.lighter(Atelier.accentFill, 1.08) : Atelier.accentFill
                    scale: playMa.pressed ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    RowLayout {
                        id: playRow
                        anchors.centerIn: parent
                        spacing: 8
                        Text { text: "󰐊"; font.family: Atelier.font; font.pixelSize: 18; color: Atelier.onAccent }
                        Text { text: "Play"; font.family: Atelier.fontUi; font.pixelSize: 15; font.weight: Font.DemiBold; color: Atelier.onAccent }
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

            // empty / no-match state
            ColumnLayout {
                anchors.centerIn: parent
                visible: gv.scanned && gv.shown.length === 0
                spacing: 8
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: gv.query ? "Nothing matches “" + gv.query + "”" : "No games yet"
                    font.family: Atelier.fontUi; font.pixelSize: 28; font.weight: Font.DemiBold; color: Atelier.text
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: gv.query ? "Backspace to edit · Esc to clear"
                        : "Install games with Steam, Heroic or Lutris (put them on /mnt/games) and they appear here."
                    font.family: Atelier.fontUi; font.pixelSize: 14; color: Atelier.subtext
                }
            }

            // ── the row of covers ───────────────────────────────────────────
            ListView {
                id: row
                anchors { left: parent.left; right: parent.right; bottom: hints.top; bottomMargin: 28 }
                height: gv.cardH * 1.12
                orientation: ListView.Horizontal
                spacing: 18 + gv.cardW * 0.06      // room for the selected cover's 1.1× scale
                clip: false
                model: gv.shown
                currentIndex: Math.min(gv.selected, Math.max(0, count - 1))
                // the selected cover stays at the left, where the title is
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: 0
                preferredHighlightEnd: gv.cardW
                highlightMoveDuration: 280
                interactive: false
                cacheBuffer: gv.cardW * 4

                delegate: Item {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property bool isCurrent: index === gv.selected
                    width: gv.cardW
                    height: row.height

                    Item {
                        id: art
                        width: gv.cardW
                        height: gv.cardH
                        anchors.bottom: parent.bottom
                        transformOrigin: Item.Bottom
                        scale: card.isCurrent ? 1.1 : (cardMa.containsMouse ? 1.03 : 1)
                        opacity: card.isCurrent ? 1 : 0.62
                        Behavior on scale { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen } }
                        Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }

                        ClippingRectangle {
                            anchors.fill: parent
                            radius: 14
                            color: Atelier.container

                            Image {
                                id: cover
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                source: card.modelData.cover ? (card.modelData.cover.startsWith("/") ? "file://" + card.modelData.cover : card.modelData.cover) : ""
                                sourceSize.width: gv.cardW * 2
                                sourceSize.height: gv.cardH * 2
                                opacity: status === Image.Ready ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
                            }
                            // no artwork: a typographic card
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                visible: cover.status !== Image.Ready
                                spacing: 10
                                Item { Layout.fillHeight: true }
                                IconImage {
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: !!card.modelData.icon
                                    implicitSize: gv.cardW * 0.4
                                    source: card.modelData.icon || ""
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: !card.modelData.icon
                                    text: card.modelData.title.charAt(0).toUpperCase()
                                    font.family: Atelier.fontUi; font.pixelSize: gv.cardW * 0.42; font.weight: Font.Bold
                                    color: gv.tintFor(card.modelData.source)
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: card.modelData.title
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    font.family: Atelier.fontUi; font.pixelSize: 14; color: Atelier.subtext
                                }
                                Item { Layout.fillHeight: true }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -4
                            radius: 18
                            color: "transparent"
                            border.width: 2
                            border.color: Atelier.accent
                            opacity: card.isCurrent ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
                        }
                        MouseArea {
                            id: cardMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // first click selects, a click on the selected cover plays
                            onClicked: { if (card.isCurrent) gv.play(card.modelData); else gv.selected = card.index; }
                        }
                    }
                }

                // one wheel notch = one game
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    property real acc: 0
                    onWheel: (e) => {
                        acc += (e.angleDelta.y || -e.angleDelta.x);
                        while (acc <= -120) { gv.step(1); acc += 120; }
                        while (acc >= 120) { gv.step(-1); acc -= 120; }
                    }
                }
            }

            Text {
                id: hints
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                text: "←  →  choose   ·   Enter  play   ·   type to search   ·   Esc  " + (gv.query ? "clear" : "close")
                font.family: Atelier.fontUi; font.pixelSize: 12; color: Qt.alpha(Atelier.text, 0.45)
            }
        }
    }
}
