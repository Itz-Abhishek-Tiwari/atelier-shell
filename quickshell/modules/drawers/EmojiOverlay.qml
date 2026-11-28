import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.components
import qs.config

// Emoji picker + GIF finder: one drawer out of the bottom edge with two tabs.
//   Emoji: search (names + CLDR keywords, "lol" finds 😂), categories, recent, skin tone.
//          Pick = copy, and type it into the window you were in (Settings.emoji.typeOnPick, wtype).
//          Shift+click / Shift+Enter = copy only and keep the drawer open (pick several).
//   GIFs:  GIPHY or Tenor (free API key in Settings → Tools), safe search, trending + recent.
//          Click = copy the link (Discord, Telegram, Slack… embed it); right-click = copy the GIF file.
// Data: scripts/emoji.py (Unicode emoji-test.txt + CLDR, cached) and scripts/gifs.py.
// Keys: type to search · arrows move · Enter pick · Tab switch tab · Esc clear / close
Item {
    id: root
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool isLight: Atelier.isLight
    property bool animActive: false
    property string tab: "emoji"          // emoji | gifs
    property real openedAt: 0
    signal closedSignal()
    signal toastRequested(string msg, string icon, color clr)

    readonly property string scripts: Quickshell.shellDir + "/scripts/"
    readonly property string query: search.text.trim().toLowerCase()

    // ── Open / close ────────────────────────────────────────────────────────
    function toggle(t) { if (visible && animActive && (!t || t === tab)) close(); else open(t); }
    function open(t) {
        if (t) tab = t;
        if (!animActive) { openedAt = Date.now(); search.text = ""; }
        visible = true;
        animActive = true;
        if (!emojiLoaded && !emojiProc.running) emojiProc.running = true;
        if (tab === "gifs") loadGifs();
        focusTimer.restart();
    }
    function close() {
        if (!animActive) return;
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }
    function setTab(t) {
        if (tab === t) return;
        tab = t;
        search.text = "";
        if (t === "gifs") loadGifs();
        search.forceActiveFocus();
    }
    function openSearch(t, q) { open(t); search.text = q; }
    Timer { id: focusTimer; interval: 40; onTriggered: search.forceActiveFocus() }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!root.animActive) root.visible = false }

    // ── Emoji data ──────────────────────────────────────────────────────────
    property var groups: []
    property var emojis: []                 // [{e, n, g, k?, t?}]
    property bool emojiLoaded: false
    property string emojiError: ""
    property int group: -1                  // -1 = recent
    property var recent: []                 // base emoji, newest first

    Process {
        id: emojiProc
        command: [root.scripts + "emoji.py", "data"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.groups = d.groups || [];
                    root.emojis = d.items || [];
                    root.emojiError = d.error || "";
                    root.emojiLoaded = root.emojis.length > 0;
                    if (root.recent.length === 0 && root.group < 0) root.group = 0;
                } catch (e) { root.emojiError = "offline"; }
            }
        }
    }
    FileView {
        id: recentFile
        path: Quickshell.statePath("emoji-recent.json")
        printErrors: false
        onLoaded: { try { root.recent = JSON.parse(text()) || []; } catch (e) { root.recent = []; } }
    }

    readonly property var byEmoji: {
        const m = {};
        for (const it of emojis) m[it.e] = it;
        return m;
    }
    readonly property var shownEmoji: {
        if (tab !== "emoji") return [];
        const q = query;
        if (q) {
            const words = q.split(/\s+/);
            const hits = [];
            for (const it of emojis) {
                const hay = it.n + " " + (it.k || "");
                if (!words.every(w => hay.includes(w))) continue;
                // names that start with the query first, then names containing it, then keywords
                hits.push({ it: it, s: it.n.startsWith(q) ? 0 : it.n.includes(q) ? 1 : 2 });
            }
            hits.sort((a, b) => a.s - b.s);
            return hits.slice(0, 360).map(h => h.it);
        }
        if (group < 0) return recent.map(e => byEmoji[e]).filter(x => !!x);
        return emojis.filter(it => it.g === group);
    }
    // a sample emoji per category tab (fallback: the group's first emoji)
    readonly property var groupIcons: ({ Smileys: "😀", People: "👋", Nature: "🌿", Food: "🍔", Travel: "✈️",
                                         Activities: "⚽", Objects: "💡", Symbols: "❤️", Flags: "🏁" })

    readonly property var toneSwatches: ["✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿"]
    function glyph(it) {
        const t = Settings.emoji.tone;
        return it && t > 0 && it.t ? it.t[t - 1] : (it ? it.e : "");
    }

    // ── Picking an emoji ────────────────────────────────────────────────────
    property bool hasWtype: false
    Process {
        command: ["sh", "-c", "command -v wtype >/dev/null 2>&1"]
        running: true
        onExited: (code) => root.hasWtype = code === 0
    }
    property string pendingType: ""
    // type only after the drawer has let go of the keyboard and focus is back in the window
    Timer {
        id: typeTimer
        interval: Atelier.durClose + 160
        onTriggered: if (root.pendingType !== "") { Quickshell.execDetached(["wtype", "--", root.pendingType]); root.pendingType = ""; }
    }
    function pickEmoji(it, keepOpen) {
        if (!it) return;
        const g = glyph(it);
        recent = [it.e].concat(recent.filter(x => x !== it.e)).slice(0, 36);
        recentFile.setText(JSON.stringify(recent));
        Quickshell.execDetached(["wl-copy", "--", g]);
        if (keepOpen) { toastRequested(g + "  copied", "󰞅", Atelier.yellow); return; }
        if (Settings.emoji.typeOnPick && hasWtype) { pendingType = g; typeTimer.restart(); }
        else toastRequested(g + "  copied", "󰞅", Atelier.yellow);
        close();
    }

    // ── GIFs ────────────────────────────────────────────────────────────────
    property var gifs: []
    property string gifError: ""
    property string gifMode: "trending"     // trending | recent (when the search is empty)
    property var gifRecent: []
    property bool gifAgain: false
    property bool editingKey: false
    readonly property bool hasKey: Settings.emoji.gifKey !== ""
    readonly property var shownGifs: query === "" && gifMode === "recent" ? gifRecent : gifs

    FileView {
        id: gifRecentFile
        path: Quickshell.statePath("gif-recent.json")
        printErrors: false
        onLoaded: { try { root.gifRecent = JSON.parse(text()) || []; } catch (e) { root.gifRecent = []; } }
    }
    Process {
        id: gifProc
        environment: ({ ATELIER_GIF_PROVIDER: Settings.emoji.gifProvider, ATELIER_GIF_KEY: Settings.emoji.gifKey })
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.gifs = d.items || [];
                    root.gifError = d.error || "";
                } catch (e) { root.gifError = "offline"; }
                gifGrid.currentIndex = 0;
            }
        }
        onExited: if (root.gifAgain) { root.gifAgain = false; root.loadGifs(); }
    }
    Timer { id: gifDebounce; interval: 420; onTriggered: root.loadGifs() }
    function loadGifs() {
        if (!hasKey || tab !== "gifs") return;
        if (gifProc.running) { gifAgain = true; return; }
        const q = search.text.trim();
        if (q === "" && gifMode === "recent") return;
        gifProc.command = q ? [scripts + "gifs.py", "search", q] : [scripts + "gifs.py", "trending"];
        gifProc.running = true;
    }
    function rememberGif(g) {
        gifRecent = [g].concat(gifRecent.filter(x => x.id !== g.id)).slice(0, 36);
        gifRecentFile.setText(JSON.stringify(gifRecent));
    }
    function pickGif(g) {
        if (!g) return;
        rememberGif(g);
        Quickshell.execDetached(["wl-copy", "--", g.url]);
        toastRequested("GIF link copied · paste it in a chat", "󰵸", Atelier.pink);
        close();
    }
    Process {
        id: gifFileProc
        onExited: (code) => root.toastRequested(code === 0 ? "GIF copied as a file" : "Couldn't download the GIF",
                                                code === 0 ? "󰵸" : "󰅙", code === 0 ? Atelier.pink : Atelier.red)
    }
    function copyGifFile(g) {
        if (!g || gifFileProc.running) return;
        rememberGif(g);
        gifFileProc.command = ["sh", "-c", 'p=$("$1" fetch "$2") && [ -s "$p" ] && wl-copy --type image/gif < "$p"', "sh",
                               scripts + "gifs.py", g.gif];
        gifFileProc.running = true;
        close();
    }
    function openUrl(u) { Quickshell.execDetached(["xdg-open", u]); close(); }
    readonly property string keyUrl: Settings.emoji.gifProvider === "tenor"
        ? "https://console.cloud.google.com/apis/library/tenor.googleapis.com"
        : "https://developers.giphy.com/dashboard/"

    // ── Keyboard ────────────────────────────────────────────────────────────
    readonly property GridView activeGrid: tab === "emoji" ? emojiGrid : gifGrid
    function pickCurrent(keepOpen) {
        if (tab === "emoji") pickEmoji(shownEmoji[emojiGrid.currentIndex], keepOpen);
        else if (hasKey && !editingKey) pickGif(shownGifs[gifGrid.currentIndex]);
    }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    // ── Drawer ──────────────────────────────────────────────────────────────
    EdgeDrawer {
        id: drawer
        edge: "bottom"
        open: root.animActive
        bodyWidth: 620
        bodyHeight: Math.min(root.height * 0.7, 476)

        MouseArea { anchors.fill: parent }       // clicks inside never reach the closer

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // header: tabs · search · tone / key
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {           // segmented tabs
                    implicitWidth: tabRow.implicitWidth + 8
                    implicitHeight: 34
                    radius: Atelier.radiusLg
                    color: Atelier.container
                    border.width: 1
                    border.color: Atelier.outline
                    RowLayout {
                        id: tabRow
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: [{ id: "emoji", icon: "󰞅", label: "Emoji", tint: Atelier.yellow },
                                    { id: "gifs", icon: "󰵸", label: "GIFs", tint: Atelier.pink }]
                            Rectangle {
                                required property var modelData
                                readonly property bool on: root.tab === modelData.id
                                implicitWidth: tRow.implicitWidth + 22
                                implicitHeight: 26
                                radius: Math.min(height / 2, Atelier.radiusSm)
                                color: on ? Qt.alpha(modelData.tint, 0.18) : "transparent"
                                Behavior on color { CAnim {} }
                                StateLayer { mouseArea: tMa }
                                RowLayout {
                                    id: tRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text { text: modelData.icon; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: parent.parent.on ? modelData.tint : Atelier.subtext }
                                    Text { text: modelData.label; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; color: parent.parent.on ? Atelier.text : Atelier.subtext }
                                }
                                MouseArea { id: tMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setTab(modelData.id) }
                            }
                        }
                    }
                }

                Rectangle {           // search
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: Atelier.radiusLg
                    color: Atelier.container
                    border.width: 1
                    border.color: search.activeFocus ? Qt.alpha(Atelier.accent, 0.5) : Atelier.outline
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 8
                        Text { text: "󰍉"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: Atelier.subtext }
                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            font.family: Atelier.fontUi
                            font.pixelSize: Atelier.fsMd
                            color: Atelier.text
                            clip: true
                            selectByMouse: true
                            onTextChanged: {
                                emojiGrid.currentIndex = 0;
                                if (root.tab === "gifs") gifDebounce.restart();
                            }
                            Keys.onPressed: (e) => {
                                const g = root.activeGrid;
                                if (e.key === Qt.Key_Escape) {
                                    if (e.isAutoRepeat || Date.now() - root.openedAt < 350) { e.accepted = true; return; }
                                    if (text) text = ""; else if (root.editingKey) root.editingKey = false; else root.close();
                                } else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
                                    root.setTab(root.tab === "emoji" ? "gifs" : "emoji");
                                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                    root.pickCurrent(e.modifiers & Qt.ShiftModifier);
                                } else if (e.key === Qt.Key_Down) g.moveCurrentIndexDown();
                                else if (e.key === Qt.Key_Up) g.moveCurrentIndexUp();
                                else if (e.key === Qt.Key_Right && (text === "" || cursorPosition === text.length)) g.moveCurrentIndexRight();
                                else if (e.key === Qt.Key_Left && (text === "" || cursorPosition === 0)) g.moveCurrentIndexLeft();
                                else return;
                                e.accepted = true;
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !search.text
                                text: root.tab === "emoji" ? "Search emoji…  try “party” or “lol”"
                                    : Settings.emoji.gifProvider === "tenor" ? "Search Tenor…" : "Search GIPHY…"
                                font.family: Atelier.fontUi
                                font.pixelSize: Atelier.fsMd
                                color: Atelier.subtext
                                opacity: 0.6
                            }
                        }
                    }
                }

                Rectangle {           // skin tone (emoji) — click cycles
                    visible: root.tab === "emoji"
                    implicitWidth: 34; implicitHeight: 34; radius: Atelier.radiusLg
                    color: Atelier.container
                    StateLayer { mouseArea: toneMa }
                    border.width: 1
                    border.color: Atelier.outline
                    Text { anchors.centerIn: parent; text: root.toneSwatches[Settings.emoji.tone] || "✋"; font.family: Atelier.fontEmoji; font.pixelSize: Atelier.iconMd }
                    MouseArea {
                        id: toneMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: Settings.emoji.tone = (Settings.emoji.tone + 1) % 6
                    }
                }
                Rectangle {           // API key (GIFs)
                    visible: root.tab === "gifs" && root.hasKey
                    implicitWidth: 34; implicitHeight: 34; radius: Atelier.radiusLg
                    color: keyMa.containsMouse || root.editingKey ? Atelier.containerHigh : Atelier.container
                    border.width: 1
                    border.color: Atelier.outline
                    Text { anchors.centerIn: parent; text: "󰌆"; font.family: Atelier.font; font.pixelSize: Atelier.iconSm; color: Atelier.subtext }
                    MouseArea { id: keyMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.editingKey = !root.editingKey }
                }
            }

            // ── Emoji tab ───────────────────────────────────────────────────
            RowLayout {           // categories
                visible: root.tab === "emoji" && root.query === ""
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: [{ g: -1, icon: "󰄉" }].concat(root.groups.map((name, i) => ({ g: i, name: name })))
                    Rectangle {
                        required property var modelData
                        readonly property bool on: root.group === modelData.g
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: Atelier.radiusSm
                        color: on ? Qt.alpha(Atelier.yellow, 0.16) : "transparent"
                        StateLayer { mouseArea: cMa }
                        border.width: on ? 1 : 0
                        border.color: Qt.alpha(Atelier.yellow, 0.4)
                        Behavior on color { CAnim {} }
                        Text {
                            anchors.centerIn: parent
                            text: modelData.g < 0 ? modelData.icon : (root.groupIcons[modelData.name] || "•")
                            font.family: modelData.g < 0 ? Atelier.font : "Noto Color Emoji"
                            font.pixelSize: modelData.g < 0 ? 15 : 17
                            color: parent.on ? Atelier.yellow : Atelier.subtext
                            Behavior on color { CAnim {} }
                            opacity: parent.on || cMa.containsMouse ? 1 : 0.7
                        }
                        MouseArea {
                            id: cMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { root.group = modelData.g; emojiGrid.currentIndex = 0; emojiGrid.positionViewAtBeginning(); }
                        }
                    }
                }
            }

            GridView {
                id: emojiGrid
                visible: root.tab === "emoji"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                readonly property int cols: Math.max(1, Math.floor(width / 46))
                cellWidth: Math.floor(width / cols)
                cellHeight: 46
                model: root.shownEmoji
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationWraps: false
                highlightMoveDuration: 0
                cacheBuffer: 200
                SmoothWheel { flickable: emojiGrid }
                delegate: Item {
                    id: ec
                    required property var modelData
                    required property int index
                    width: emojiGrid.cellWidth
                    height: emojiGrid.cellHeight
                    readonly property bool current: emojiGrid.currentIndex === index
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Atelier.radiusSm
                        color: ec.current ? Qt.alpha(Atelier.yellow, 0.18) : "transparent"
                        StateLayer { mouseArea: eMa }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: root.glyph(ec.modelData)
                        font.family: Atelier.fontEmoji
                        font.pixelSize: 26
                        scale: eMa.pressed ? 0.86 : (eMa.containsMouse ? 1.15 : 1)
                        Behavior on scale { Anim { type: "fastSpatial" } }
                    }
                    MouseArea {
                        id: eMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: emojiGrid.currentIndex = ec.index
                        onClicked: (m) => root.pickEmoji(ec.modelData, m.modifiers & Qt.ShiftModifier)
                    }
                }

                Text {                 // empty states
                    anchors.centerIn: parent
                    visible: emojiGrid.count === 0
                    horizontalAlignment: Text.AlignHCenter
                    text: !root.emojiLoaded ? (root.emojiError ? "Couldn't download the emoji list.\nCheck the connection and open this again."
                                                                : "Loading emoji…")
                        : root.query ? "No emoji for “" + search.text.trim() + "”"
                        : "Emoji you pick show up here"
                    font.family: Atelier.fontUi
                    font.pixelSize: Atelier.fsMd
                    color: Atelier.subtext
                }
            }

            // ── GIFs tab ────────────────────────────────────────────────────
            RowLayout {           // trending / recent
                visible: root.tab === "gifs" && root.hasKey && !root.editingKey && root.query === ""
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [{ id: "trending", icon: "󰈸", label: "Trending" }, { id: "recent", icon: "󰄉", label: "Recent" }]
                    Chip {
                        required property var modelData
                        icon: modelData.icon
                        text: modelData.label
                        tint: root.gifMode === modelData.id ? Atelier.pink : Atelier.overlay1
                        interactive: true
                        implicitHeight: 28
                        onClicked: { root.gifMode = modelData.id; gifGrid.currentIndex = 0; root.loadGifs(); }
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "Powered by " + (Settings.emoji.gifProvider === "tenor" ? "Tenor" : "GIPHY")
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMicro; color: Atelier.subtext; opacity: 0.7
                }
            }

            GridView {
                id: gifGrid
                visible: root.tab === "gifs" && root.hasKey && !root.editingKey
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: Math.floor(width / 4)
                cellHeight: 112
                model: root.shownGifs
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                SmoothWheel { flickable: gifGrid }
                delegate: Item {
                    id: gifCell
                    required property var modelData
                    required property int index
                    width: gifGrid.cellWidth
                    height: gifGrid.cellHeight
                    readonly property bool current: gifGrid.currentIndex === index
                    readonly property bool live: gMa.containsMouse && root.animActive
                    ClippingRectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: Atelier.radiusMd
                        color: Atelier.container
                        Image {             // still frame: cheap, the grid never animates as a whole
                            anchors.fill: parent
                            source: gifCell.modelData.still
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 160
                            sourceSize.height: 112
                            visible: !(anim.status === AnimatedImage.Ready && gifCell.live)
                        }
                        AnimatedImage {     // plays only while the pointer is on it
                            id: anim
                            anchors.fill: parent
                            source: gifCell.live ? gifCell.modelData.preview : ""
                            playing: gifCell.live
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: gifCell.live && status === AnimatedImage.Ready
                        }
                    }
                    Rectangle {             // selection ring (outside the clip, so the picture never shifts)
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: Atelier.radiusMd
                        color: "transparent"
                        border.width: 2
                        border.color: Atelier.pink
                        visible: gifCell.current
                    }
                    MouseArea {
                        id: gMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: gifGrid.currentIndex = gifCell.index
                        onClicked: (m) => m.button === Qt.RightButton ? root.copyGifFile(gifCell.modelData) : root.pickGif(gifCell.modelData)
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: gifGrid.count === 0
                    horizontalAlignment: Text.AlignHCenter
                    text: gifProc.running ? "Searching…"
                        : root.gifError === "badkey" ? "The API key was refused. Check it with the key button above."
                        : root.gifError === "offline" ? "No connection to " + (Settings.emoji.gifProvider === "tenor" ? "Tenor" : "GIPHY") + "."
                        : root.gifError ? "Something went wrong: " + root.gifError
                        : root.gifMode === "recent" && root.query === "" ? "GIFs you pick show up here"
                        : "No GIFs found"
                    font.family: Atelier.fontUi
                    font.pixelSize: Atelier.fsMd
                    color: Atelier.subtext
                }
            }

            // GIF setup: provider + key (first use, or the key button)
            ColumnLayout {
                visible: root.tab === "gifs" && (!root.hasKey || root.editingKey)
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12
                Item { Layout.fillHeight: true }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰵸"
                    font.family: Atelier.font; font.pixelSize: 30; color: Atelier.pink
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 440
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "GIF search needs a free API key from GIPHY or Tenor. Get one, paste it here, and it stays on this computer (in ~/.config/atelier/settings.json)."
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    Repeater {
                        model: [{ id: "giphy", label: "GIPHY" }, { id: "tenor", label: "Tenor" }]
                        Chip {
                            required property var modelData
                            text: modelData.label
                            tint: Settings.emoji.gifProvider === modelData.id ? Atelier.pink : Atelier.overlay1
                            interactive: true
                            implicitHeight: 30
                            onClicked: Settings.emoji.gifProvider = modelData.id
                        }
                    }
                    Chip { icon: "󰖟"; text: "Get a free key"; tint: Atelier.blue; interactive: true; implicitHeight: 30; onClicked: root.openUrl(root.keyUrl) }
                }
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 440
                    implicitHeight: 34
                    radius: Atelier.radiusLg
                    color: Atelier.container
                    border.width: 1
                    border.color: keyIn.activeFocus ? Qt.alpha(Atelier.pink, 0.6) : Atelier.outline
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 4
                        spacing: 8
                        Text { text: "󰌆"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: Atelier.subtext }
                        TextInput {
                            id: keyIn
                            Layout.fillWidth: true
                            text: Settings.emoji.gifKey
                            font.family: Atelier.font; font.pixelSize: Atelier.fsSm
                            color: Atelier.text
                            clip: true
                            selectByMouse: true
                            echoMode: activeFocus ? TextInput.Normal : TextInput.Password
                            Keys.onReturnPressed: saveKey.clicked()
                            Keys.onEscapePressed: { root.editingKey = false; search.forceActiveFocus(); }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !keyIn.text
                                text: "Paste your API key"
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext; opacity: 0.6
                            }
                        }
                        Chip {
                            id: saveKey
                            text: "Save"; icon: "󰄬"; tint: Atelier.pink; interactive: true; implicitHeight: 26
                            onClicked: {
                                Settings.emoji.gifKey = keyIn.text.trim();
                                root.editingKey = false;
                                root.gifError = "";
                                root.gifs = [];
                                Qt.callLater(root.loadGifs);
                                search.forceActiveFocus();
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }

            // footer: the emoji under the cursor, and the keys
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                readonly property var cur: root.tab === "emoji" ? root.shownEmoji[emojiGrid.currentIndex] : null
                Text {
                    visible: !!parent.cur
                    text: root.glyph(parent.cur)
                    font.family: Atelier.fontEmoji; font.pixelSize: Atelier.iconMd
                }
                Text {
                    Layout.fillWidth: true
                    text: parent.cur ? parent.cur.n : root.tab === "gifs" && root.hasKey && !root.editingKey
                        ? (gifGrid.currentIndex >= 0 && root.shownGifs[gifGrid.currentIndex] ? root.shownGifs[gifGrid.currentIndex].title : "") : ""
                    elide: Text.ElideRight
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.text
                }
                Text {
                    text: root.tab === "emoji"
                        ? (Settings.emoji.typeOnPick && root.hasWtype ? "Enter type it" : "Enter copy") + "  ·  ⇧ copy, keep open  ·  Tab GIFs"
                        : "Click copy link  ·  Right-click copy GIF  ·  Tab emoji"
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMicro; color: Atelier.subtext; opacity: 0.6
                }
            }
        }
    }
}
