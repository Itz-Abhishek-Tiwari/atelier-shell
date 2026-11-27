pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The Music drawer's line to Atelier Music (apps/music): its queue for the "Up next" tab.
// Playback itself goes over MPRIS like any player; this only adds what MPRIS can't carry.
// Connected only while `active` (the drawer is open on Atelier Music), so it costs nothing
// otherwise and never starts the music daemon.
Singleton {
    id: root

    property bool active: false
    readonly property bool connected: sock.connected
    property var queue: []
    property int index: -1
    property var files: ({})          // videoId → "download" | "cache"

    readonly property var upNext: index >= 0 ? queue.slice(index + 1, index + 31) : queue.slice(0, 30)

    function jump(i) { send("jump", [i]); }
    function playNext(i) { send("jump", [i]); }
    function openApp() { Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/atelier-music"]); }

    property int _id: 1
    function send(cmd, args) {
        if (!sock.connected) return;
        sock.write(JSON.stringify({ id: _id++, cmd: cmd, args: args || [] }) + "\n");
        sock.flush();
    }

    Socket {
        id: sock
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/atelier-music.sock"
        connected: root.active
        parser: SplitParser {
            onRead: (line) => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.event === "status") { root.queue = m.queue || []; root.index = m.index ?? -1; }
                else if (m.event === "files") root.files = m.files || {};
            }
        }
    }
    // the daemon may come up after the drawer opened: retry while wanted
    Timer {
        interval: 1500
        repeat: true
        running: root.active && !sock.connected
        onTriggered: { sock.connected = false; sock.connected = true; }
    }
}
