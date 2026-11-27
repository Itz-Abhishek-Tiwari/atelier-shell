import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// Wallpaper picker: a normal drawer from the bottom edge, styled like the rest of the shell
// (frame colour, hairline cards, the accent). Local / Wallhaven tabs and a search box on top,
// then a grid of thumbnails, 4 across. Click (or Enter) applies at once; no apply animation,
// borders or filters on the pictures.
//   ← → ↑ ↓  move     Enter  apply     Tab  Local ⇄ Wallhaven     type  search     Esc  close
// Wallhaven: safe for work ONLY, enforced in scripts/wallpaper_service.py (SFW purity, no People
// category, excluded tags). Top / Hot / Random / New, topics, colour dots, optional Anime;
// searches are cached; downloads show progress on the tile; more results load as you scroll.
Item {
    id: wallRoot
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool isLight: Atelier.isLight
    property bool animActive: false
    property string activeTab: "local"            // "local" | "wallhaven"
    property var localWallpapers: []
    property var wallhavenWallpapers: []
    property bool isLoading: false
    property string downloading: ""
    readonly property string activeWallpaperPath: Wallpaper.current
    readonly property string script: Quickshell.shellDir + "/scripts/wallpaper_service.py"

    signal wallpaperApplied(string name)
    signal toastRequested(string msg, string icon, color clr)
    signal closedSignal()

    // ── Wallhaven search state ──────────────────────────────────────────────
    property string whSort: "toplist"              // toplist | hot | random | date_added
    property string whTopic: ""                    // a topic id, or ""
    property string whQuery: ""                    // typed search
    property string whColor: ""                    // rrggbb from Wallhaven's palette, or ""
    property bool whAnime: false                   // include the Anime category (General always)
    property int whPage: 1
    property int whLastPage: 1
    property string whSeed: ""
    property bool whLoading: false
    property bool whMore: false
    property string whError: ""
    property var whPendingArgs: null                // newest search waiting for the running one to end
    property var progress: ({})                    // id → 0..1 while a download runs

    readonly property var sorts: [
        { id: "toplist",    label: "Top",    icon: "󰓎" },
        { id: "hot",        label: "Hot",    icon: "󰈸" },
        { id: "random",     label: "Random", icon: "󱅖" },
        { id: "date_added", label: "New",    icon: "󰎔" }
    ]
    readonly property var topics: [
        { id: "nature",    label: "Nature",    q: "nature" },
        { id: "space",     label: "Space",     q: "space" },
        { id: "city",      label: "City",      q: "city" },
        { id: "ocean",     label: "Ocean",     q: "ocean" },
        { id: "night",     label: "Night",     q: "night" },
        { id: "minimal",   label: "Minimal",   q: "minimalism" },
        { id: "abstract",  label: "Abstract",  q: "abstract" },
        { id: "art",       label: "Art",       q: "digital art" },
        { id: "cyberpunk", label: "Cyberpunk", q: "cyberpunk" },
        { id: "winter",    label: "Winter",    q: "winter" },
        { id: "flowers",   label: "Flowers",   q: "flowers" },
        { id: "cars",      label: "Cars",      q: "car" },
        { id: "games",     label: "Games",     q: "video games" }
    ]
    readonly property var swatches: ["cc0000", "ff6600", "ffcc33", "77cc33", "66cccc", "0099cc", "333399", "993399", "ea4c88", "000000", "ffffff"]
    readonly property string whLabel: whQuery !== "" ? "“" + whQuery + "”"
        : whTopic !== "" ? (topics.find(t => t.id === whTopic) || {}).label || ""
        : (sorts.find(t => t.id === whSort) || {}).label || ""

    readonly property var items: {
        const q = searchField.text.toLowerCase().trim();
        if (activeTab === "wallhaven") return wallhavenWallpapers;
        return q ? localWallpapers.filter(w => w.name.toLowerCase().includes(q)) : localWallpapers;
    }
    readonly property bool loadingNow: activeTab === "wallhaven" ? whLoading : (isLoading && localWallpapers.length === 0)

    function thumbSrc(m) { return !m || !m.thumb ? "" : (m.thumb.startsWith("http") ? m.thumb : "file://" + m.thumb); }
    function resBadge(r) {
        const w = Number((r || "").split("x")[0]);
        return w >= 7680 ? "8K" : w >= 5120 ? "5K" : w >= 3840 ? "4K" : w >= 2560 ? "QHD" : w >= 1920 ? "FHD" : "";
    }

    // ── Data ────────────────────────────────────────────────────────────────
    Process {
        id: localProc
        command: ["python3", wallRoot.script, "list_local"]
        stdout: StdioCollector {
            onStreamFinished: {
                wallRoot.isLoading = false;
                try { wallRoot.localWallpapers = JSON.parse(text.trim()); } catch (e) {}
                if (wallRoot.activeTab === "local") wallRoot.selectCurrent();
            }
        }
    }

    Process {
        id: wallhavenProc
        // One search at a time, never killed mid-way (a killed one printed nothing, which showed up
        // as "Couldn't read Wallhaven's answer"): a newer search waits here until this one exits.
        onExited: {
            if (!wallRoot.whPendingArgs) return;
            command = wallRoot.whPendingArgs;
            wallRoot.whPendingArgs = null;
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (wallRoot.whPendingArgs) return;     // a newer search is queued: this answer is stale
                let d = null;
                try { d = JSON.parse(text.trim()); } catch (e) {}
                const more = wallRoot.whMore;
                wallRoot.whLoading = false;
                wallRoot.whMore = false;
                if (!d) {
                    wallRoot.whError = "Couldn't read Wallhaven's answer";
                    if (more && wallRoot.whPage > 1) wallRoot.whPage--;    // retry this page, don't skip it
                    return;
                }
                wallRoot.whError = d.error || "";
                if (more && d.error && wallRoot.whPage > 1) wallRoot.whPage--;
                wallRoot.whLastPage = d.last_page || 1;
                if (d.seed) wallRoot.whSeed = d.seed;
                if (more) {
                    // swapping the model resets a GridView to the top: put scroll and selection back
                    const y = grid.contentY, ci = grid.currentIndex;
                    scrollAnim.stop();
                    const seen = new Set(wallRoot.wallhavenWallpapers.map(w => w.id));
                    wallRoot.wallhavenWallpapers = wallRoot.wallhavenWallpapers.concat((d.items || []).filter(w => !seen.has(w.id)));
                    grid.currentIndex = ci;
                    grid.contentY = y;
                    if (!d.error) fillTimer.restart();
                } else {
                    wallRoot.wallhavenWallpapers = d.items || [];
                    if (wallRoot.activeTab === "wallhaven") { grid.currentIndex = 0; grid.positionViewAtBeginning(); }
                    if (!d.error) fillTimer.restart();
                }
            }
        }
    }

    Process {
        id: applyProc
        property string targetName: ""
        property string itemId: ""
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("P ")) {
                    const p = Object.assign({}, wallRoot.progress);
                    p[applyProc.itemId] = Number(line.slice(2));
                    wallRoot.progress = p;
                    return;
                }
                let r = null;
                try { r = JSON.parse(line); } catch (e) { return; }
                wallRoot.downloading = "";
                const p = Object.assign({}, wallRoot.progress); delete p[applyProc.itemId]; wallRoot.progress = p;
                if (r.status === "success" && r.path) {
                    Wallpaper.set(r.path);
                    wallRoot.wallpaperApplied(applyProc.targetName);
                    wallRoot.markOwned(applyProc.itemId);
                    wallRoot.refreshLocal();   // the download now lives in the local folder
                } else {
                    wallRoot.toastRequested("Download failed" + (r.message ? ": " + r.message : ""), "󰀦", Atelier.red);
                }
            }
        }
        onExited: (code) => {
            if (code !== 0 && wallRoot.downloading !== "") {
                wallRoot.downloading = "";
                wallRoot.toastRequested("Download failed", "󰀦", Atelier.red);
            }
        }
    }
    function markOwned(id) {
        wallhavenWallpapers = wallhavenWallpapers.map(w => w.id === id ? Object.assign({}, w, { owned: true }) : w);
    }

    function apply(item) {
        if (!item) return;
        if (activeTab === "local") {
            Wallpaper.set(item.path);
            wallpaperApplied(item.name);
        } else if (!downloading) {
            downloading = item.id;
            applyProc.itemId = item.id;
            applyProc.targetName = whLabel + " · " + item.id;
            applyProc.command = ["python3", script, "download", item.id, item.full_url];
            applyProc.running = true;
        }
    }

    function shuffle() {
        if (items.length < 2) return;
        let i = grid.currentIndex;
        while (i === grid.currentIndex) i = Math.floor(Math.random() * items.length);
        grid.currentIndex = i;
        grid.positionViewAtIndex(i, GridView.Contain);
        apply(items[i]);
    }

    // reset = a new search (page 1); otherwise the next page of the current one
    function searchWallhaven(reset) {
        if (reset) { whPage = 1; whSeed = ""; whError = ""; whLoading = true; whMore = false; wallhavenWallpapers = []; }
        else whMore = true;
        const topic = topics.find(t => t.id === whTopic);
        const q = whQuery !== "" ? whQuery : (topic ? topic.q : "");
        const args = ["python3", script, "search_wallhaven", "sorting=" + whSort, "page=" + whPage, "anime=" + (whAnime ? 1 : 0)];
        if (q) args.push("q=" + q);
        if (whColor) args.push("color=" + whColor);
        if (whSeed && !reset) args.push("seed=" + whSeed);
        if (wallhavenProc.running) { whPendingArgs = args; return; }
        wallhavenProc.command = args;
        wallhavenProc.running = true;
    }
    // a page that doesn't fill the view (or leaves it at the end) would never fire atYEnd again
    Timer {
        id: fillTimer
        interval: 120
        onTriggered: if (grid.contentHeight <= grid.height + 4 || grid.atYEnd) wallRoot.loadMore()
    }
    function loadMore() {
        if (activeTab === "wallhaven" && !whLoading && !whMore && whPage < whLastPage) { whPage++; searchWallhaven(false); }
    }

    function refreshLocal() {
        isLoading = true;
        localProc.running = true;
    }
    function selectCurrent() {
        const i = items.findIndex(w => w.path === activeWallpaperPath);
        grid.currentIndex = Math.max(0, i);
        if (i >= 0) grid.positionViewAtIndex(i, GridView.Center);
    }

    function setTab(t) {
        if (activeTab === t) return;
        activeTab = t;
        searchField.text = "";
        if (t === "wallhaven" && wallhavenWallpapers.length === 0 && !whLoading) searchWallhaven(true);
        else if (t === "local") selectCurrent();
        else { grid.currentIndex = 0; grid.positionViewAtBeginning(); }
    }

    Component.onCompleted: refreshLocal()

    function toggle() { if (visible && animActive) close(); else open(); }
    function open() {
        visible = true;
        animActive = true;
        refreshLocal();
        if (activeTab === "local") selectCurrent();
        // warm up Wallhaven in the background, so its tab is ready when you switch
        if (wallhavenWallpapers.length === 0 && !whLoading) searchWallhaven(true);
        focusTimer.restart();
    }
    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!wallRoot.animActive) wallRoot.visible = false }
    Timer { id: focusTimer; interval: 50; onTriggered: grid.forceActiveFocus() }

    // click outside closes
    MouseArea { anchors.fill: parent; enabled: wallRoot.animActive; onClicked: wallRoot.close() }

    EdgeDrawer {
        id: drawer
        edge: "bottom"
        open: wallRoot.animActive
        bodyWidth: Math.min(1060, wallRoot.width - 240)
        bodyHeight: Math.min(wallRoot.height * 0.72, content.implicitHeight + 36)

        MouseArea { anchors.fill: parent }      // clicks on the body don't fall through and close it

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // ── header: tabs · search · actions ─────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Local / Wallhaven
                Rectangle {
                    implicitWidth: 230
                    implicitHeight: 36
                    radius: Atelier.radiusLg
                    color: Atelier.container
                    Row {
                        id: tabRow
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 2
                        Repeater {
                            model: [{ id: "local", icon: "󰉋", label: "Local" }, { id: "wallhaven", icon: "󰖟", label: "Wallhaven" }]
                            Rectangle {
                                required property var modelData
                                readonly property bool on: wallRoot.activeTab === modelData.id
                                width: (tabRow.width - tabRow.spacing) / 2
                                height: tabRow.height
                                radius: height / 2
                                color: on ? Atelier.accentFill : "transparent"
                                Behavior on color { CAnim {} }
                                StateLayer { mouseArea: tabMa }
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text { text: modelData.icon; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: parent.parent.on ? Atelier.onFill : Atelier.subtext; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: modelData.label; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; color: parent.parent.on ? Atelier.onFill : Atelier.text; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea { id: tabMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wallRoot.setTab(modelData.id) }
                            }
                        }
                    }
                }

                // search
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: Atelier.radiusLg
                    color: Atelier.container
                    border.width: 1
                    border.color: searchField.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
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
                            onTextChanged: if (wallRoot.activeTab === "local") grid.currentIndex = 0
                            Keys.onReturnPressed: {
                                if (wallRoot.activeTab === "wallhaven") { wallRoot.whQuery = text.trim(); wallRoot.whTopic = ""; wallRoot.searchWallhaven(true); }
                                else wallRoot.apply(wallRoot.items[grid.currentIndex]);
                                grid.forceActiveFocus();
                            }
                            Keys.onEscapePressed: { if (text) text = ""; else wallRoot.close(); grid.forceActiveFocus(); }
                            Keys.onDownPressed: grid.forceActiveFocus()
                            Keys.onTabPressed: { wallRoot.setTab(wallRoot.activeTab === "local" ? "wallhaven" : "local"); grid.forceActiveFocus(); }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !searchField.text
                                text: wallRoot.activeTab === "local" ? "Filter your wallpapers" : "Search Wallhaven"
                                font: searchField.font
                                color: Atelier.subtext
                                opacity: 0.7
                            }
                        }
                    }
                }

                // safe for work only (enforced in the service script)
                Rectangle {
                    visible: wallRoot.activeTab === "wallhaven"
                    implicitWidth: sfwRow.implicitWidth + 18
                    implicitHeight: 28
                    radius: Atelier.radiusMd
                    color: Atelier.container
                    Row {
                        id: sfwRow
                        anchors.centerIn: parent
                        spacing: 5
                        Text { text: "󰕥"; font.family: Atelier.font; font.pixelSize: Atelier.fsMd; color: Atelier.green; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Safe for work"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; font.weight: Font.Medium; color: Atelier.subtext1; anchors.verticalCenter: parent.verticalCenter }
                    }
                }

                RoundBtn { icon: "󰒝"; visible: wallRoot.activeTab === "local"; onClicked: wallRoot.shuffle() }
                RoundBtn { icon: "󰉋"; onClicked: { Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/.config/hypr/wall"]); wallRoot.close(); } }
            }

            // ── Wallhaven: sort · topics · anime · colour (one scrolling row) ─
            Flickable {
                visible: wallRoot.activeTab === "wallhaven"
                Layout.fillWidth: true
                implicitHeight: 32
                contentWidth: chipRow.implicitWidth
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (e) => { const f = parent; f.contentX = Math.max(0, Math.min(f.contentWidth - f.width, f.contentX - (e.angleDelta.y || e.angleDelta.x) / 2)); }
                }
                Row {
                    id: chipRow
                    spacing: 6
                    Repeater {
                        model: wallRoot.sorts
                        Chip {
                            required property var modelData
                            icon: modelData.icon; label: modelData.label
                            on: wallRoot.whSort === modelData.id
                            onClicked: { wallRoot.whSort = modelData.id; wallRoot.searchWallhaven(true); }
                        }
                    }
                    Rectangle { width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: Atelier.outline }
                    Repeater {
                        model: wallRoot.topics
                        Chip {
                            required property var modelData
                            label: modelData.label
                            on: wallRoot.whTopic === modelData.id && wallRoot.whQuery === ""
                            onClicked: {
                                wallRoot.whQuery = "";
                                searchField.text = "";
                                wallRoot.whTopic = on ? "" : modelData.id;
                                wallRoot.searchWallhaven(true);
                            }
                        }
                    }
                    Rectangle { width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: Atelier.outline }
                    Chip {
                        label: "Anime"
                        on: wallRoot.whAnime
                        onClicked: { wallRoot.whAnime = !wallRoot.whAnime; wallRoot.searchWallhaven(true); }
                    }
                    Rectangle { width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: Atelier.outline }
                    // colour: small dots; click again to clear
                    Repeater {
                        model: wallRoot.swatches
                        Item {
                            id: sw
                            required property string modelData
                            readonly property bool on: wallRoot.whColor === modelData
                            width: 22; height: 30
                            Rectangle {
                                anchors.centerIn: parent
                                width: sw.on ? 20 : 14; height: width; radius: width / 2
                                color: "#" + sw.modelData
                                border.width: sw.on ? 2 : 1
                                border.color: sw.on ? Atelier.accent : Qt.alpha(Atelier.text, 0.2)
                                Behavior on width { Anim { type: "fastSpatial" } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { wallRoot.whColor = sw.on ? "" : sw.modelData; wallRoot.searchWallhaven(true); }
                            }
                        }
                    }
                }
            }

            // ── the grid ────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                implicitHeight: grid.cellHeight * 3 + 4

                GridView {
                    id: grid
                    anchors.fill: parent
                    clip: true
                    focus: true
                    model: wallRoot.items
                    readonly property int cols: 4
                    cellWidth: Math.floor(width / cols)
                    cellHeight: Math.round((cellWidth - 12) * 9 / 16) + 12
                    keyNavigationWraps: false
                    highlightFollowsCurrentItem: false
                    boundsBehavior: Flickable.StopAtBounds
                    SmoothWheel { flickable: grid }
                    onAtYEndChanged: if (atYEnd) wallRoot.loadMore()

                    // arrows move the selection; the grid scrolls to keep it in view
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
                    Keys.onUpPressed: (e) => { if (currentIndex < cols) { searchField.forceActiveFocus(); } else go(currentIndex - cols); }
                    Keys.onDownPressed: go(currentIndex + cols)
                    Keys.onPressed: (e) => {
                        if (e.key === Qt.Key_PageDown) { go(currentIndex + cols * 3); e.accepted = true; }
                        else if (e.key === Qt.Key_PageUp) { go(currentIndex - cols * 3); e.accepted = true; }
                        else if (e.key === Qt.Key_Home) { go(0); e.accepted = true; }
                        else if (e.key === Qt.Key_End) { go(count - 1); e.accepted = true; }
                        else if (e.text && /^[\w\- ]$/.test(e.text) && !(e.modifiers & Qt.ControlModifier)) {   // type to search
                            searchField.forceActiveFocus();
                            searchField.text += e.text;
                            e.accepted = true;
                        }
                    }
                    Keys.onReturnPressed: wallRoot.apply(wallRoot.items[currentIndex])
                    Keys.onEnterPressed: wallRoot.apply(wallRoot.items[currentIndex])
                    Keys.onEscapePressed: wallRoot.close()
                    Keys.onTabPressed: wallRoot.setTab(wallRoot.activeTab === "local" ? "wallhaven" : "local")
                    onCurrentIndexChanged: if (currentIndex >= count - 4) wallRoot.loadMore()

                    delegate: Item {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool wh: modelData.full_url !== undefined
                        readonly property bool active: !wh && modelData.path === wallRoot.activeWallpaperPath
                        readonly property bool current: GridView.isCurrentItem && grid.activeFocus
                        readonly property bool busy: wallRoot.downloading !== "" && wallRoot.downloading === modelData.id
                        readonly property real prog: wallRoot.progress[modelData.id] !== undefined ? wallRoot.progress[modelData.id] : -1
                        width: grid.cellWidth
                        height: grid.cellHeight

                        Item {
                            id: card
                            anchors.fill: parent
                            anchors.margins: 6
                            scale: tileMa.pressed ? 0.97 : 1
                            Behavior on scale { Anim { type: "fastSpatial" } }

                            RoundImage {
                                anchors.fill: parent
                                radius: Atelier.radiusMd
                                source: wallRoot.thumbSrc(tile.modelData)
                            }

                            // keyboard focus: a soft ring outside the picture
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -4
                                radius: Atelier.radiusLg
                                color: "transparent"
                                border.width: 2
                                border.color: Atelier.accent
                                visible: tile.current
                            }

                            // in use
                            Rectangle {
                                visible: tile.active
                                anchors.top: parent.top; anchors.right: parent.right
                                anchors.margins: 8
                                width: 24; height: 24; radius: Atelier.radiusMd
                                color: Atelier.accentFill
                                Text { anchors.centerIn: parent; text: "󰄬"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: Atelier.onFill }
                            }

                            // Wallhaven: already saved
                            Rectangle {
                                visible: tile.wh && !!tile.modelData.owned && !tile.busy
                                anchors.top: parent.top; anchors.right: parent.right
                                anchors.margins: 8
                                width: 24; height: 24; radius: Atelier.radiusMd
                                color: Qt.rgba(0, 0, 0, 0.5)
                                Text { anchors.centerIn: parent; text: "󰄬"; font.family: Atelier.font; font.pixelSize: Atelier.fsMd; color: "white" }
                            }

                            // Wallhaven info, on hover only
                            Rectangle {
                                visible: tile.wh && tileMa.containsMouse && !tile.busy
                                anchors.left: parent.left; anchors.bottom: parent.bottom
                                anchors.margins: 8
                                height: 22
                                width: infoT.implicitWidth + 16
                                radius: 11
                                color: Qt.rgba(0, 0, 0, 0.55)
                                Text {
                                    id: infoT
                                    anchors.centerIn: parent
                                    text: [wallRoot.resBadge(tile.modelData.resolution), "󰋑 " + (tile.modelData.favorites || 0)].filter(x => x).join("   ")
                                    font.family: Atelier.font; font.pixelSize: Atelier.fsMicro
                                    color: "white"
                                }
                            }

                            // downloading: progress ring
                            Item {
                                anchors.fill: parent
                                visible: tile.busy
                                Rectangle { anchors.fill: parent; radius: Atelier.radiusMd; color: Qt.rgba(0, 0, 0, 0.45) }
                                Item {
                                    anchors.centerIn: parent
                                    width: 44; height: 44
                                    Shape {
                                        anchors.fill: parent
                                        preferredRendererType: Shape.CurveRenderer
                                        ShapePath {
                                            strokeColor: Qt.alpha(Atelier.text, 0.25); strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                            PathAngleArc { centerX: 22; centerY: 22; radiusX: 19; radiusY: 19; startAngle: 0; sweepAngle: 360 }
                                        }
                                        ShapePath {
                                            strokeColor: "white"; strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                            PathAngleArc { centerX: 22; centerY: 22; radiusX: 19; radiusY: 19; startAngle: -90; sweepAngle: 360 * Math.max(0.03, tile.prog) }
                                        }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: tile.prog >= 0 ? Math.round(tile.prog * 100) + "%" : "…"
                                        font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; font.bold: true
                                        color: "white"
                                    }
                                }
                            }
                        }
                        MouseArea {
                            id: tileMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { grid.currentIndex = tile.index; wallRoot.apply(tile.modelData); }
                        }
                    }
                }

                // loading: placeholder tiles
                Grid {
                    anchors.fill: parent
                    visible: wallRoot.items.length === 0 && wallRoot.loadingNow
                    columns: 4
                    property real pulse: 0.6
                    SequentialAnimation on pulse {
                        running: parent.visible && wallRoot.visible && !Perf.saver
                        loops: Animation.Infinite
                        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.6; duration: 700; easing.type: Easing.InOutSine }
                    }
                    Repeater {
                        model: 12
                        Item {
                            width: grid.cellWidth; height: grid.cellHeight
                            Rectangle { anchors.fill: parent; anchors.margins: 6; radius: Atelier.radiusMd; color: Atelier.container; opacity: parent.parent.pulse }
                        }
                    }
                }

                // empty / error
                Column {
                    anchors.centerIn: parent
                    visible: wallRoot.items.length === 0 && !wallRoot.loadingNow
                    spacing: 10
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: wallRoot.activeTab === "wallhaven" && wallRoot.whError ? "󰀦" : "󰋹"
                        font.family: Atelier.font; font.pixelSize: 28
                        color: Atelier.overlay1
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: wallRoot.activeTab !== "wallhaven" ? (searchField.text ? "No wallpapers match" : "No wallpapers yet. Add some to the folder.")
                            : wallRoot.whError ? wallRoot.whError + "."
                            : "Nothing for that. Try another topic or colour."
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg
                        color: Atelier.subtext
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: wallRoot.activeTab === "wallhaven" && wallRoot.whError !== ""
                        implicitWidth: retryT.implicitWidth + 28; implicitHeight: 30; radius: Atelier.radiusLg
                        color: Atelier.container
                        StateLayer { mouseArea: retryMa }
                        Text { id: retryT; anchors.centerIn: parent; text: "Try again"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; color: Atelier.text }
                        MouseArea { id: retryMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wallRoot.searchWallhaven(true) }
                    }
                }
            }

            // ── status line ─────────────────────────────────────────────────
            Text {
                Layout.fillWidth: true
                text: wallRoot.activeTab === "local"
                    ? wallRoot.items.length + " wallpapers" + (searchField.text ? " match" : "") + "  ·  Enter or click to apply"
                    : wallRoot.whError && wallRoot.items.length > 0 ? wallRoot.whError + "  ·  showing saved results"
                    : (wallRoot.whLoading ? "Searching Wallhaven… (it can take a few seconds)"
                       : wallRoot.items.length + (wallRoot.whPage < wallRoot.whLastPage ? "+" : "") + " " + wallRoot.whLabel.toLowerCase() + " wallpapers"
                         + (wallRoot.whMore ? "  ·  loading more…" : "  ·  click to download and apply"))
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                color: Atelier.subtext
            }
        }
    }

    // ── pieces ──────────────────────────────────────────────────────────────
    component RoundBtn: Rectangle {
        id: rb
        property string icon
        signal clicked()
        implicitWidth: 36; implicitHeight: 36; radius: Atelier.radiusLg
        color: Atelier.container
        Behavior on color { CAnim {} }
        StateLayer { mouseArea: rbMa }
        Text { anchors.centerIn: parent; text: rb.icon; font.family: Atelier.font; font.pixelSize: Atelier.fsXl; color: rbMa.containsMouse ? Atelier.text : Atelier.subtext1 }
        MouseArea { id: rbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
    }
    component Chip: Rectangle {
        id: ch
        property string icon: ""
        property string label
        property bool on: false
        signal clicked()
        implicitWidth: chRow.implicitWidth + 22
        implicitHeight: 30
        radius: Atelier.radiusMd
        color: on ? Atelier.accentFill : Atelier.container
        Behavior on color { CAnim {} }
        StateLayer { mouseArea: chMa }
        Row {
            id: chRow
            anchors.centerIn: parent
            spacing: 6
            Text { visible: ch.icon !== ""; text: ch.icon; font.family: Atelier.font; font.pixelSize: Atelier.fsMd; color: ch.on ? Atelier.onFill : Atelier.subtext; anchors.verticalCenter: parent.verticalCenter }
            Text { text: ch.label; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; color: ch.on ? Atelier.onFill : Atelier.text; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: chMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
    }
    // a picture with smooth rounded corners (MultiEffect mask; ClippingRectangle steps the
    // corners). Static, so it renders once per image; a tile shows until the image loads.
    component RoundImage: Item {
        id: ri
        property alias source: riImg.source
        property real radius: Atelier.radiusMd
        readonly property bool ready: riImg.status === Image.Ready
        Rectangle { anchors.fill: parent; radius: ri.radius; color: Atelier.container; visible: !ri.ready }
        Image {
            id: riImg
            anchors.fill: parent
            visible: false
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            sourceSize.width: 480
            sourceSize.height: 270
        }
        Item {
            id: riMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            layer.textureSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
            Rectangle { anchors.fill: parent; radius: ri.radius; color: "black"; antialiasing: true }
        }
        MultiEffect {
            anchors.fill: parent
            source: riImg
            maskEnabled: true
            maskSource: riMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            opacity: ri.ready ? 1 : 0
            Behavior on opacity { Anim { type: "slowEffects" } }
        }
    }
}
