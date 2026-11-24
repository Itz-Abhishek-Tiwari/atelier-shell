import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.components
import qs.config
import qs.services

// Music drawer: grows out of the top frame edge. Opens when the pointer rests on the middle of
// the top edge (Frame.qml sensor, "Open on hover", only while something can play), with
// Super+M, or `qs ipc call media toggle`. Hover-opened it closes when the pointer leaves;
// clicking the edge or the drawer keeps it open. Styled like the control center (theme
// surfaces, hairline cards, the accent colour), no art backgrounds.
//
//   Now playing   cover · app · title · artist · seek bar · shuffle / prev / play / next / repeat
//   Lyrics        time-synced from lrclib.net (scripts/lyrics.py, cached), current line
//                 highlighted and kept centred; click a line to jump there
//   Output        every audio output (speakers, headphones, Bluetooth, HDMI): tap to switch
//   Recent        tracks played in any app (kept in the shell's state dir); click to search
//   Timer         sleep timer (pause after N minutes / at the end of the track) and playback
//                 speed when the player supports it
Item {
    id: root
    visible: false
    anchors.fill: parent
    readonly property Item bodyItem: drawer      // input area when opened by hover (DrawerHost mask)

    property bool isLight: false
    property bool animActive: false
    signal closedSignal()

    property string tab: "lyrics"                 // lyrics | output | recent | timer (kept while the shell runs)

    // ── Players ─────────────────────────────────────────────────────────────
    readonly property var players: Mpris.players.values
    property int pickedId: -1                     // uniqueId of a player chosen with the chips
    readonly property var player: {
        const ps = root.players;
        return ps.find(p => p.uniqueId === root.pickedId) || ps.find(p => p.isPlaying) || ps[0] || null;
    }
    readonly property bool hasPlayer: player !== null
    readonly property bool playing: hasPlayer && player.isPlaying
    readonly property string title: hasPlayer ? (player.trackTitle || "") : ""
    readonly property string artist: hasPlayer ? (player.trackArtist || "") : ""
    readonly property string trackKey: title + "\n" + artist

    function open() { visible = true; animActive = true; }
    function close() { animActive = false; closeTimer.restart(); closedSignal(); }
    function hideNow() { animActive = false; closeTimer.stop(); visible = false; }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!root.animActive) root.visible = false }

    // MprisPlayer.position isn't reactive: poke it while visible and playing (faster for lyrics)
    Timer {
        interval: root.tab === "lyrics" ? 250 : 1000
        repeat: true
        running: root.visible && root.playing
        onTriggered: root.player.positionChanged()
    }
    function fmt(s) {
        s = Math.max(0, Math.floor(s || 0));
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), ss = String(s % 60).padStart(2, "0");
        return h > 0 ? h + ":" + String(m).padStart(2, "0") + ":" + ss : m + ":" + ss;
    }
    function appIcon(p) {
        if (!p) return "";
        const e = (p.desktopEntry && DesktopEntries.heuristicLookup(p.desktopEntry)) || DesktopEntries.heuristicLookup(p.identity);
        return e && e.icon ? Quickshell.iconPath(e.icon, true) : "";
    }
    function ago(ms) {
        const m = Math.round((Date.now() - ms) / 60000);
        if (m < 1) return "just now";
        if (m < 60) return m + " min ago";
        const h = Math.round(m / 60);
        if (h < 24) return h + " h ago";
        const d = Math.round(h / 24);
        return d === 1 ? "yesterday" : d + " days ago";
    }

    // ══ Lyrics ═══════════════════════════════════════════════════════════════
    property var lyrics: []                       // [[seconds, line], ...] when synced
    property string plainLyrics: ""
    property string lyricsState: "idle"           // idle | loading | synced | plain | instrumental | none
    property string lyricsKey: ""
    function loadLyrics() {
        if (!root.hasPlayer || root.title === "" || root.lyricsKey === root.trackKey) return;
        root.lyricsKey = root.trackKey;
        root.lyrics = []; root.plainLyrics = ""; root.lyricsState = "loading";
        lyricsProc.running = false;
        lyricsProc.command = ["python3", "-I", Quickshell.shellDir + "/scripts/lyrics.py",
                              root.artist, root.title, root.player.trackAlbum || "",
                              String(root.player.lengthSupported ? Math.round(root.player.length) : 0)];
        lyricsProc.running = true;
    }
    readonly property bool wantLyrics: visible && tab === "lyrics"
    onWantLyricsChanged: if (wantLyrics) loadLyrics()
    onTrackKeyChanged: { if (wantLyrics) loadLyrics(); rememberTimer.restart(); }
    Process {
        id: lyricsProc
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text); } catch (e) { d = { none: true }; }
                if (d.synced) { root.lyrics = d.synced; root.lyricsState = "synced"; }
                else if (d.plain) { root.plainLyrics = d.plain; root.lyricsState = "plain"; }
                else root.lyricsState = d.instrumental ? "instrumental" : "none";
            }
        }
    }
    // the line being sung (a hair early, so the highlight lands with the voice)
    readonly property int lyricIndex: {
        if (root.lyricsState !== "synced" || !root.hasPlayer) return -1;
        const t = root.player.position + 0.25;
        let i = -1;
        for (let k = 0; k < root.lyrics.length; k++) { if (root.lyrics[k][0] <= t) i = k; else break; }
        return i;
    }

    // ══ Output devices ══════════════════════════════════════════════════════
    // only while the drawer is open (a frozen node copy can hold deleted objects; see SoundPage.qml)
    readonly property var sinks: root.visible ? Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio) : []
    function sinkName(n) { return n ? (n.description || n.nickname || n.name) : ""; }   // n: may be a node that just went away
    function sinkIcon(n) {
        if (!n) return "󰓃";
        const s = (n.name + " " + n.description).toLowerCase();
        if (s.includes("bluez") || s.includes("bluetooth")) return "󰂯";
        if (s.includes("hdmi") || s.includes("displayport")) return "󰡁";
        if (s.includes("headphone") || s.includes("headset")) return "󰋋";
        if (s.includes("usb")) return "󰕓";
        return "󰓃";
    }

    // ══ Recently played (shell state dir, newest first, 40 max) ════════════
    property var history: []
    FileView {
        id: historyFile
        path: Quickshell.statePath("media-history.json")
        printErrors: false
        onLoaded: { try { root.history = JSON.parse(text()) || []; } catch (e) { root.history = []; } }
    }
    // a cover that no longer loads: drop it from the history so it isn't requested again
    function forgetArt(url) {
        if (!url || !root.history.some(x => x.art === url)) return;
        root.history = root.history.map(x => x.art === url ? Object.assign({}, x, { art: "" }) : x);
        historyFile.setText(JSON.stringify(root.history));
    }
    function remember() {
        if (!root.playing || root.title === "") return;
        const h = root.history.slice();
        if (h.length > 0 && h[0].title === root.title && h[0].artist === root.artist) return;
        let art = root.player.trackArtUrl || "";
        // players like Firefox hand out temporary cover files that are deleted on the next track:
        // keep our own copy, or the Recent list keeps asking for files that are gone
        if (art.startsWith("file://")) {
            let hsh = 0;
            for (const ch of root.title + "\u0001" + root.artist) hsh = (hsh * 31 + ch.charCodeAt(0)) | 0;
            const dest = Quickshell.cachePath("media-history/" + (hsh >>> 0).toString(16) + ".img");
            Quickshell.execDetached(["sh", "-c", 'mkdir -p "${2%/*}" && cp -f -- "$1" "$2"', "sh",
                                     decodeURIComponent(art.slice(7)), dest]);
            art = "file://" + dest;
        }
        const item = { title: root.title, artist: root.artist, app: root.player.identity,
                       art: art, at: Date.now() };
        const rest = h.filter(x => !(x.title === item.title && x.artist === item.artist));
        root.history = [item].concat(rest).slice(0, 40);
        historyFile.setText(JSON.stringify(root.history));
    }
    // count a track once it has played for a few seconds (skipping through doesn't fill the list)
    Timer { id: rememberTimer; interval: 8000; onTriggered: root.remember() }
    onPlayingChanged: if (playing) rememberTimer.restart()
    function searchTrack(item) {
        Quickshell.execDetached(["xdg-open", "https://www.youtube.com/results?search_query="
                                 + encodeURIComponent((item.artist + " " + item.title).trim())]);
        root.close();
    }

    // ══ Sleep timer + speed ═════════════════════════════════════════════════
    property real sleepAt: 0                      // ms epoch; 0 = off
    property bool sleepEndOfTrack: false
    property int sleepLeft: 0                     // seconds, for the label
    function setSleep(min) { sleepEndOfTrack = false; sleepAt = min > 0 ? Date.now() + min * 60000 : 0; tickSleep(); }
    function tickSleep() { sleepLeft = sleepAt > 0 ? Math.max(0, Math.round((sleepAt - Date.now()) / 1000)) : 0; }
    function sleepNow() {
        for (const p of root.players) if (p.isPlaying && p.canPause) p.pause();
        sleepAt = 0; sleepEndOfTrack = false; sleepLeft = 0;
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.sleepAt > 0
        onTriggered: { root.tickSleep(); if (Date.now() >= root.sleepAt) root.sleepNow(); }
    }
    // "end of this track": pause as soon as the next one starts
    property string _sleepTrack: ""
    onSleepEndOfTrackChanged: _sleepTrack = sleepEndOfTrack ? trackKey : ""
    Connections {
        target: root
        function onTrackKeyChanged() { if (root.sleepEndOfTrack && root.trackKey !== root._sleepTrack) root.sleepNow(); }
    }
    readonly property bool canRate: hasPlayer && player.maxRate > player.minRate && player.maxRate > 1
    readonly property var speeds: [0.75, 1, 1.25, 1.5, 2].filter(r => !hasPlayer || (r >= player.minRate && r <= player.maxRate))

    // click outside closes (only reachable when opened by keyboard/click: hover mode masks to the body)
    MouseArea { anchors.fill: parent; enabled: root.animActive; onClicked: root.close() }

    Item {
        focus: root.animActive
        Keys.onEscapePressed: root.close()
        Keys.onSpacePressed: if (root.hasPlayer) root.player.togglePlaying()
        Keys.onLeftPressed: if (root.hasPlayer && root.player.canGoPrevious) root.player.previous()
        Keys.onRightPressed: if (root.hasPlayer && root.player.canGoNext) root.player.next()
        Keys.onTabPressed: root.tab = ["lyrics", "output", "recent", "timer"][(["lyrics", "output", "recent", "timer"].indexOf(root.tab) + 1) % 4]
    }

    EdgeDrawer {
        id: drawer
        edge: "top"
        open: root.animActive
        bodyWidth: 540
        bodyHeight: content.implicitHeight + 36
        Behavior on bodyHeight { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }

        MouseArea { anchors.fill: parent }      // clicks on the body don't fall through and close it

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 18
            spacing: 14

            // ══ Now playing ══════════════════════════════════════════════════
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                RoundImage {
                    id: cover
                    implicitWidth: 84; implicitHeight: 84
                    radius: 16
                    decode: 168
                    source: root.hasPlayer ? (root.player.trackArtUrl || "") : ""
                    placeholder: root.hasPlayer ? "󰎆" : "󰝛"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    RowLayout {
                        spacing: 6
                        IconImage {
                            readonly property string src: root.appIcon(root.player)
                            visible: src !== ""
                            source: src
                            implicitSize: 14
                        }
                        Text {
                            text: root.hasPlayer ? root.player.identity : "Music"
                            font.family: Atelier.fontUi; font.pixelSize: 11; font.weight: Font.Medium
                            color: Atelier.subtext
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.hasPlayer ? (root.title || "Unknown track") : "Nothing playing"
                        font.family: Atelier.fontUi; font.pixelSize: 17; font.weight: Font.DemiBold
                        color: Atelier.text
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.hasPlayer ? root.artist : "Start music in any app and it shows up here"
                        visible: text !== ""
                        font.family: Atelier.fontUi; font.pixelSize: 13
                        color: Atelier.subtext
                        elide: Text.ElideRight
                    }
                }

                // open the player's window
                RoundBtn {
                    Layout.alignment: Qt.AlignTop
                    visible: root.hasPlayer && root.player.canRaise
                    icon: "󰏌"; size: 30; glyphSize: 14
                    onClicked: { root.player.raise(); root.close(); }
                }
            }

            // seek
            ColumnLayout {
                visible: root.hasPlayer && root.player.lengthSupported && root.player.length > 0
                Layout.fillWidth: true
                spacing: 4
                Item {
                    id: seek
                    Layout.fillWidth: true
                    implicitHeight: 14
                    readonly property real len: root.hasPlayer ? root.player.length : 0
                    property real dragFrac: -1
                    readonly property bool active: seekMa.containsMouse || dragFrac >= 0
                    readonly property real frac: dragFrac >= 0 ? dragFrac
                        : (len > 0 && root.hasPlayer ? Math.max(0, Math.min(1, root.player.position / len)) : 0)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: seek.active ? 6 : 4; radius: height / 2
                        color: Atelier.containerHigh
                        Behavior on height { NumberAnimation { duration: Atelier.durFast } }
                        Rectangle {
                            width: Math.max(height, parent.width * seek.frac); height: parent.height; radius: parent.radius
                            color: Atelier.accent
                        }
                    }
                    Rectangle {
                        x: Math.max(0, Math.min(seek.width - width, seek.width * seek.frac - width / 2))
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12; height: 12; radius: 6
                        color: Atelier.accent
                        scale: seek.active ? 1 : 0
                        Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutBack } }
                    }
                    MouseArea {
                        id: seekMa
                        anchors.fill: parent
                        anchors.topMargin: -4
                        anchors.bottomMargin: -4
                        enabled: root.hasPlayer && root.player.canSeek
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        function at(x) { return Math.max(0, Math.min(1, x / width)); }
                        onPressed: (m) => seek.dragFrac = at(m.x)
                        onPositionChanged: (m) => { if (pressed) seek.dragFrac = at(m.x); }
                        onReleased: { if (root.hasPlayer) root.player.position = seek.dragFrac * seek.len; seek.dragFrac = -1; }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: root.fmt(seek.frac * seek.len); font.family: Atelier.font; font.pixelSize: 10; color: Atelier.subtext }
                    Item { Layout.fillWidth: true }
                    Text { text: root.fmt(seek.len); font.family: Atelier.font; font.pixelSize: 10; color: Atelier.subtext }
                }
            }

            // controls
            RowLayout {
                visible: root.hasPlayer
                Layout.alignment: Qt.AlignHCenter
                spacing: 14
                RoundBtn {
                    visible: root.hasPlayer && root.player.shuffleSupported
                    icon: "󰒟"; size: 34; glyphSize: 15
                    on: root.hasPlayer && root.player.shuffle
                    onClicked: root.player.shuffle = !root.player.shuffle
                }
                RoundBtn {
                    icon: "󰒮"; size: 40; glyphSize: 18
                    enabled: root.hasPlayer && root.player.canGoPrevious
                    onClicked: root.player.previous()
                }
                Rectangle {
                    implicitWidth: 50; implicitHeight: 50; radius: 25
                    color: Atelier.accentFill
                    scale: playMa.pressed ? 0.9 : (playMa.containsMouse ? 1.06 : 1)
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: root.playing ? 0 : 2
                        text: root.playing ? "󰏤" : "󰐊"
                        font.family: Atelier.font; font.pixelSize: 22
                        color: Atelier.onFill
                    }
                    MouseArea { id: playMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (root.hasPlayer) root.player.togglePlaying() }
                }
                RoundBtn {
                    icon: "󰒭"; size: 40; glyphSize: 18
                    enabled: root.hasPlayer && root.player.canGoNext
                    onClicked: root.player.next()
                }
                RoundBtn {
                    visible: root.hasPlayer && root.player.loopSupported
                    readonly property int loop: root.hasPlayer ? root.player.loopState : MprisLoopState.None
                    icon: loop === MprisLoopState.Track ? "󰑘" : "󰑖"; size: 34; glyphSize: 15
                    on: loop !== MprisLoopState.None
                    onClicked: root.player.loopState = loop === MprisLoopState.None ? MprisLoopState.Playlist
                        : loop === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None
                }
            }

            // player chips (only with more than one)
            Flow {
                visible: root.players.length > 1
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: Mpris.players         // live model (see Waybar's tray): players vanish with their app
                    Rectangle {
                        required property var modelData
                        readonly property bool on: root.player === modelData
                        implicitWidth: chipRow.implicitWidth + 20
                        implicitHeight: 28
                        radius: 14
                        color: on ? Atelier.accentFill : (chipMa.containsMouse ? Atelier.containerHigh : Atelier.container)
                        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6
                            IconImage {
                                readonly property string src: root.appIcon(modelData)
                                anchors.verticalCenter: parent.verticalCenter
                                visible: src !== ""
                                source: src
                                implicitSize: 14
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.identity
                                font.family: Atelier.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold
                                color: parent.parent.on ? Atelier.onFill : Atelier.text
                            }
                        }
                        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pickedId = modelData.uniqueId }
                    }
                }
            }

            // ══ Tabs ═════════════════════════════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: 18
                color: Atelier.container
                Row {
                    id: tabsRow
                    anchors.fill: parent
                    anchors.margins: 3
                    spacing: 2
                    Repeater {
                        model: [
                            { id: "lyrics", icon: "󰍡", label: "Lyrics" },
                            { id: "output", icon: "󰓃", label: "Output" },
                            { id: "recent", icon: "󰋚", label: "Recent" },
                            { id: "timer",  icon: "󰔛", label: "Timer" }
                        ]
                        Rectangle {
                            required property var modelData
                            readonly property bool on: root.tab === modelData.id
                            width: (tabsRow.width - 3 * tabsRow.spacing) / 4
                            height: tabsRow.height
                            radius: height / 2
                            color: on ? Atelier.accentFill : (tabMa.containsMouse ? Atelier.containerHigh : "transparent")
                            Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Text { text: modelData.icon; font.family: Atelier.font; font.pixelSize: 13; color: parent.parent.on ? Atelier.onFill : Atelier.subtext; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: modelData.id === "timer" && root.sleepAt > 0 ? root.fmt(root.sleepLeft) : modelData.label
                                    font.family: modelData.id === "timer" && root.sleepAt > 0 ? Atelier.font : Atelier.fontUi
                                    font.pixelSize: 12; font.weight: Font.DemiBold
                                    color: parent.parent.on ? Atelier.onFill : Atelier.text
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            MouseArea { id: tabMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = modelData.id }
                        }
                    }
                }
            }

            // ══ Tab panel ════════════════════════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 236
                radius: 18
                color: Atelier.container
                border.width: 1
                border.color: Atelier.outline
                clip: true

                // ── Lyrics ──
                Item {
                    anchors.fill: parent
                    visible: root.tab === "lyrics"

                    Placeholder {
                        visible: root.lyricsState !== "synced" && root.lyricsState !== "plain"
                        icon: root.lyricsState === "loading" ? "󰑐" : root.lyricsState === "instrumental" ? "󰝚" : "󰍡"
                        text: !root.hasPlayer ? "Play a song to see its lyrics"
                            : root.lyricsState === "loading" ? "Looking for lyrics…"
                            : root.lyricsState === "instrumental" ? "Instrumental"
                            : "No lyrics found for this song"
                    }

                    ListView {
                        id: lyricView
                        anchors.fill: parent
                        anchors.margins: 6
                        visible: root.lyricsState === "synced"
                        clip: true
                        model: root.lyricsState === "synced" ? root.lyrics : []
                        currentIndex: root.lyricIndex
                        highlightRangeMode: ListView.ApplyRange
                        preferredHighlightBegin: height / 2 - 22
                        preferredHighlightEnd: height / 2 + 22
                        highlightMoveDuration: 420
                        highlightFollowsCurrentItem: true
                        highlight: Item {}
                        spacing: 2
                        header: Item { height: lyricView.height / 2 - 22 }
                        footer: Item { height: lyricView.height / 2 - 22 }
                        SmoothWheel { flickable: lyricView }
                        delegate: Item {
                            id: ln
                            required property var modelData
                            required property int index
                            readonly property bool current: index === root.lyricIndex
                            readonly property int dist: Math.abs(index - root.lyricIndex)
                            width: lyricView.width
                            height: lt.implicitHeight + 10
                            Text {
                                id: lt
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 28
                                x: 14
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: ln.modelData[1] === "" ? "♪" : ln.modelData[1]
                                font.family: Atelier.fontUi
                                font.pixelSize: ln.current ? 17 : 14
                                font.weight: ln.current ? Font.DemiBold : Font.Normal
                                color: ln.current ? Atelier.accent : (lnMa.containsMouse ? Atelier.text : Atelier.subtext)
                                opacity: ln.current ? 1 : Math.max(0.35, 1 - ln.dist * 0.16)
                                Behavior on font.pixelSize { NumberAnimation { duration: 220 } }
                                Behavior on color { ColorAnimation { duration: 220 } }
                            }
                            MouseArea {
                                id: lnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.hasPlayer && root.player.canSeek) root.player.position = ln.modelData[0]
                            }
                        }
                    }

                    Flickable {
                        id: plainView
                        anchors.fill: parent
                        anchors.margins: 16
                        visible: root.lyricsState === "plain"
                        clip: true
                        contentHeight: plainText.implicitHeight
                        SmoothWheel { flickable: plainView }
                        Text {
                            id: plainText
                            width: plainView.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: root.plainLyrics
                            lineHeight: 1.25
                            font.family: Atelier.fontUi; font.pixelSize: 14
                            color: Atelier.text
                        }
                    }
                }

                // ── Output ──
                ListView {
                    id: outView
                    anchors.fill: parent
                    anchors.margins: 6
                    visible: root.tab === "output"
                    clip: true
                    spacing: 2
                    model: root.sinks
                    SmoothWheel { flickable: outView }
                    delegate: Rectangle {
                        id: od
                        // modelData via context, not `required` (see SoundPage.qml)
                        readonly property bool on: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.id === modelData.id
                        width: outView.width
                        height: 50
                        radius: 14
                        color: odMa.containsMouse ? Atelier.containerHigh : "transparent"
                        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 14
                            spacing: 12
                            Rectangle {
                                implicitWidth: 32; implicitHeight: 32; radius: 16
                                color: od.on ? Atelier.accentFill : Atelier.containerHigh
                                Text { anchors.centerIn: parent; text: root.sinkIcon(od.modelData); font.family: Atelier.font; font.pixelSize: 15; color: od.on ? Atelier.onFill : Atelier.text }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.sinkName(od.modelData)
                                font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: od.on ? Font.DemiBold : Font.Normal
                                color: Atelier.text
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: od.on
                                text: "󰄬"
                                font.family: Atelier.font; font.pixelSize: 16
                                color: Atelier.accent
                            }
                        }
                        MouseArea { id: odMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Pipewire.preferredDefaultAudioSink = od.modelData }
                    }
                    Placeholder { visible: root.sinks.length === 0; icon: "󰓄"; text: "No audio outputs found" }
                }

                // ── Recent ──
                ListView {
                    id: recentView
                    anchors.fill: parent
                    anchors.margins: 6
                    visible: root.tab === "recent"
                    clip: true
                    spacing: 2
                    model: root.history
                    SmoothWheel { flickable: recentView }
                    delegate: Rectangle {
                        id: rd
                        required property var modelData
                        width: recentView.width
                        height: 52
                        radius: 14
                        color: rdMa.containsMouse ? Atelier.containerHigh : "transparent"
                        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 12
                            spacing: 12
                            RoundImage {
                                implicitWidth: 38; implicitHeight: 38
                                radius: 10
                                decode: 76
                                tile: Atelier.containerHigh
                                source: rd.modelData.art || ""
                                onFailed: root.forgetArt(rd.modelData.art)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { Layout.fillWidth: true; text: rd.modelData.title; elide: Text.ElideRight; font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: Font.Medium; color: Atelier.text }
                                Text { Layout.fillWidth: true; text: [rd.modelData.artist, rd.modelData.app].filter(x => x).join("  ·  "); elide: Text.ElideRight; font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext }
                            }
                            Text {
                                text: rdMa.containsMouse ? "󰍉" : root.ago(rd.modelData.at)
                                font.family: rdMa.containsMouse ? Atelier.font : Atelier.fontUi
                                font.pixelSize: rdMa.containsMouse ? 15 : 11
                                color: rdMa.containsMouse ? Atelier.accent : Atelier.subtext
                            }
                        }
                        MouseArea { id: rdMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.searchTrack(rd.modelData) }
                    }
                    Placeholder { visible: root.history.length === 0; icon: "󰋚"; text: "Songs you play will show up here" }
                }

                // ── Timer ──
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    visible: root.tab === "timer"
                    spacing: 10

                    Text { text: "Sleep timer"; font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: Atelier.text }
                    Text {
                        text: root.sleepEndOfTrack ? "Music pauses when this track ends"
                            : root.sleepAt > 0 ? "Music pauses in " + root.fmt(root.sleepLeft)
                            : "Pause the music after a while"
                        font.family: Atelier.fontUi; font.pixelSize: 11
                        color: root.sleepAt > 0 || root.sleepEndOfTrack ? Atelier.accent : Atelier.subtext
                        Layout.topMargin: -6
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: [{ m: 0, l: "Off" }, { m: 15, l: "15 min" }, { m: 30, l: "30 min" }, { m: 45, l: "45 min" }, { m: 60, l: "1 hour" }, { m: -1, l: "End of track" }]
                            Chip2 {
                                required property var modelData
                                label: modelData.l
                                on: modelData.m === -1 ? root.sleepEndOfTrack
                                  : modelData.m === 0 ? (root.sleepAt === 0 && !root.sleepEndOfTrack)
                                  : false
                                onClicked: {
                                    if (modelData.m === -1) { root.sleepAt = 0; root.sleepEndOfTrack = true; }
                                    else root.setSleep(modelData.m);
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Atelier.outline; Layout.topMargin: 4; Layout.bottomMargin: 2 }

                    Text { text: "Playback speed"; font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: Atelier.text }
                    Text {
                        visible: !root.canRate
                        text: root.hasPlayer ? root.player.identity + " doesn't support changing the speed" : "Play something first"
                        font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext
                        Layout.topMargin: -6
                    }
                    Flow {
                        visible: root.canRate
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: root.speeds
                            Chip2 {
                                required property var modelData
                                label: modelData + "×"
                                mono: true
                                on: root.hasPlayer && Math.abs(root.player.rate - modelData) < 0.01
                                onClicked: root.player.rate = modelData
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    // ── pieces ──────────────────────────────────────────────────────────────
    component RoundBtn: Rectangle {
        id: rb
        property string icon
        property int size: 34
        property int glyphSize: 15
        property bool on: false
        signal clicked()
        implicitWidth: size; implicitHeight: size; radius: size / 2
        opacity: enabled ? 1 : 0.35
        color: on ? Qt.alpha(Atelier.accent, 0.16) : (rbMa.containsMouse ? Atelier.containerHigh : "transparent")
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Text {
            anchors.centerIn: parent
            text: rb.icon
            font.family: Atelier.font; font.pixelSize: rb.glyphSize
            color: rb.on ? Atelier.accent : (rbMa.containsMouse ? Atelier.text : Atelier.subtext1)
        }
        MouseArea { id: rbMa; anchors.fill: parent; enabled: rb.enabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
    }
    component Chip2: Rectangle {
        id: c2
        property string label
        property bool on: false
        property bool mono: false
        signal clicked()
        implicitWidth: c2t.implicitWidth + 24
        implicitHeight: 30
        radius: 15
        color: on ? Atelier.accentFill : (c2Ma.containsMouse ? Atelier.containerHigh : Atelier.container)
        border.width: on ? 0 : 1
        border.color: Atelier.outline
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Text {
            id: c2t
            anchors.centerIn: parent
            text: c2.label
            font.family: c2.mono ? Atelier.font : Atelier.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold
            color: c2.on ? Atelier.onFill : Atelier.text
        }
        MouseArea { id: c2Ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: c2.clicked() }
    }
    // A cover with smooth rounded corners: the image is masked by an anti-aliased rounded
    // rectangle through MultiEffect (feathered edge). ClippingRectangle cut it with hard, stepped
    // corners. Static content, so the effect renders once per image. A tile + glyph shows until
    // the image has loaded.
    component RoundImage: Item {
        id: ri
        property alias source: riImg.source
        property real radius: 12
        property int decode: 128
        property string placeholder: "󰎆"
        property color tile: Atelier.container
        readonly property bool ready: riImg.status === Image.Ready
        signal failed()
        Rectangle {
            anchors.fill: parent
            radius: ri.radius
            color: ri.tile
            visible: !ri.ready
            Text { anchors.centerIn: parent; text: ri.placeholder; font.family: Atelier.font; font.pixelSize: Math.round(ri.height * 0.36); color: Atelier.subtext }
        }
        Image {
            id: riImg
            anchors.fill: parent
            visible: false
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: true
            sourceSize.width: ri.decode
            sourceSize.height: ri.decode
            onStatusChanged: if (status === Image.Error) ri.failed()
        }
        Item {
            id: riMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))   // 2× for a finer edge
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
            Behavior on opacity { NumberAnimation { duration: Atelier.durMedium } }
        }
    }
    component Placeholder: ColumnLayout {
        id: ph
        property string icon
        property string text
        anchors.centerIn: parent
        spacing: 8
        Text { Layout.alignment: Qt.AlignHCenter; text: ph.icon; font.family: Atelier.font; font.pixelSize: 26; color: Atelier.overlay1 }
        Text { Layout.alignment: Qt.AlignHCenter; text: ph.text; font.family: Atelier.fontUi; font.pixelSize: 13; color: Atelier.subtext }
    }
}
