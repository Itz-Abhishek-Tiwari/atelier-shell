import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config

// Time-synced lyrics for the lock screen's Now playing card: the line being sung, bright,
// with the next one dimmed below, crossfading as the song moves on. Uses the Music drawer's
// lrclib.net fetcher (scripts/lyrics.py, cached). Only works while `active` (locked + playing);
// hides itself when the song has no synced lyrics. On the login screen there is no player,
// so it stays empty.
ColumnLayout {
    id: ll
    property var player: null
    property bool active: false
    // look (the glass lock uses the theme; the phone faces pass white text in their font)
    property color textColor: Atelier.text
    property color dimColor: Atelier.subtext
    property string fontFamily: Atelier.fontUi
    property real fontSize: 17
    property bool divider: true
    spacing: 4
    visible: lines.length > 0 && index >= -1

    property var lines: []                 // [[seconds, "text"], …]
    property string loadedFor: ""
    readonly property string key: player ? (player.trackTitle || "") + "\n" + (player.trackArtist || "") : ""

    function load() {
        if (!active || !player || !player.trackTitle || key === loadedFor) return;
        loadedFor = key;
        lines = [];
        proc.running = false;
        proc.command = ["python3", "-I", Quickshell.shellDir + "/scripts/lyrics.py",
                        player.trackArtist || "", player.trackTitle || "", player.trackAlbum || "",
                        String(player.lengthSupported ? Math.round(player.length) : 0)];
        proc.running = true;
    }
    onActiveChanged: load()
    onKeyChanged: load()
    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text); } catch (e) {}
                ll.lines = d.synced || [];
            }
        }
    }

    // MprisPlayer.position doesn't tick by itself: poke it while shown (lines change often)
    Timer {
        interval: 250
        repeat: true
        running: ll.active && ll.lines.length > 0 && !!ll.player && ll.player.isPlaying
        onTriggered: ll.player.positionChanged()
    }
    readonly property int index: {
        if (!player || lines.length === 0) return -1;
        const t = player.position + 0.25;
        let i = -1;
        for (let k = 0; k < lines.length; k++) { if (lines[k][0] <= t) i = k; else break; }
        return i;
    }
    function lineAt(i) {
        if (i < 0 || i >= lines.length) return "";
        return lines[i][1] === "" ? "♪" : lines[i][1];
    }

    // crossfade: fade out, swap the text, fade in
    property string shown: lineAt(index)
    property string shownNext: lineAt(index + 1)
    onIndexChanged: swap.restart()
    SequentialAnimation {
        id: swap
        Anim { target: current; property: "opacity"; to: 0; type: "fastEffects" }
        ScriptAction { script: { ll.shown = ll.lineAt(ll.index); ll.shownNext = ll.lineAt(ll.index + 1); } }
        Anim { target: current; property: "opacity"; to: 1; type: "effects" }
    }

    Rectangle { visible: ll.divider; Layout.fillWidth: true; implicitHeight: 1; color: Atelier.outline; Layout.bottomMargin: 6 }
    Text {
        id: current
        Layout.fillWidth: true
        text: ll.shown || "♪"
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        font.family: ll.fontFamily; font.pixelSize: ll.fontSize; font.weight: Font.Bold
        color: ll.textColor
    }
    Text {
        Layout.fillWidth: true
        visible: text !== ""
        text: ll.shownNext
        opacity: current.opacity * 0.5
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        font.family: ll.fontFamily; font.pixelSize: Math.round(ll.fontSize * 0.78); font.weight: Font.DemiBold
        color: ll.dimColor
    }
}
