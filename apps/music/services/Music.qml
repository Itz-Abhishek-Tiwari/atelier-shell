pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The app's connection to the ytmd daemon (backend/ytmd.py): one Unix socket, kept open.
// Commands go out as {"id","cmd","args"}; replies come back with the same id, and the daemon
// pushes {"event":"status"} whenever playback or the queue changes, so nothing polls.
// The position between pushes is counted locally.
Singleton {
    id: root

    readonly property string backend: Quickshell.shellDir + "/backend/ytmd.py"
    readonly property string sockPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/atelier-music.sock"
    readonly property bool online: sock.connected

    // ── Playback state (from the daemon) ──
    property var current: null
    property var queue: []
    property string _queueKey: ""
    property int index: -1
    property bool playing: false
    property bool paused: false
    property bool loading: false
    property bool autoplay: true
    property bool shuffle: false
    property string loop: "none"         // none | queue | track
    property int volume: 100
    property bool netOnline: true        // the daemon could reach YouTube Music last time it tried
    property string notice: ""           // one-line message from the daemon (offline skips, failed downloads)
    property string localArt: ""         // file:// cover of the current track when it is saved
    readonly property string currentArt: current ? (localArt || current.art || current.thumb || "") : ""
    // a sharper cover for big views (Google image URLs take their size in the URL)
    function artAt(px) {
        const a = current ? (current.art || current.thumb || "") : "";
        return a.indexOf("googleusercontent.com") >= 0 ? a.replace(/=w\d+-h\d+[^/]*$/, "=w" + px + "-h" + px + "-l90-rj") : currentArt;
    }
    property real dur: 0
    property real pos: 0
    property real _basePos: 0
    property double _baseAt: 0

    // ── Browse state ──
    property var results: []
    property bool searching: false
    property string lastQuery: ""
    property var shelves: []
    property bool homeLoading: false
    property string error: ""

    // ── Library: offline files, "For you" ──
    property var files: ({})              // videoId → "download" | "cache"
    property var progress: ({})           // videoId → 0..1 while saving
    property var forYou: []
    property bool forYouLoading: false
    property var offlineTracks: []
    property var usage: ({})
    function fileState(id) { return files[id] || ""; }
    function progressOf(id) { return progress[id] === undefined ? -1 : progress[id]; }
    function download(t) { request("download", [slim(t)]); }
    function removeFile(id, kind) { request("remove_file", [id, kind], () => loadOffline()); }
    function loadForYou(force) {
        if (forYouLoading) return;
        forYouLoading = true;
        request("foryou", [!!force], r => { forYou = r || []; forYouLoading = false; }, () => { forYouLoading = false; });
    }
    // ── Likes, playlists, sleep timer ──
    property var likes: ({})                  // videoId → true
    property var liked: []                    // liked songs, newest first
    property var playlists: []                // [{pid, name, count, covers}]
    property real sleepAt: 0                  // epoch ms; 0 = off
    property bool sleepEndOfTrack: false
    function isLiked(id) { return !!likes[id]; }
    function toggleLike(t) { if (t) request("like", [slim(t)]); }
    function loadLiked() { request("liked", [], r => { liked = r || []; }); }
    function loadPlaylists() { request("playlists", [], r => { playlists = r || []; }); }
    function playlistTracks(pid, cb) { request("playlist_get", [pid], r => cb(r || [])); }
    function createPlaylist(name, t) { request("playlist_create", [name, t ? slim(t) : null]); }
    function addToPlaylist(pid, t) { request("playlist_add", [pid, slim(t)], ok => { notice = ok ? "Added to playlist" : "Already in that playlist"; noticeTimer.restart(); }); }
    function removeFromPlaylist(pid, id) { request("playlist_remove", [pid, id]); }
    function renamePlaylist(pid, name) { request("playlist_rename", [pid, name]); }
    function deletePlaylist(pid) { request("playlist_delete", [pid]); }
    function setSleep(arg) { request("sleep", [arg]); }     // minutes | "track" | 0
    Timer { id: noticeTimer; interval: 2500; onTriggered: root.notice = "" }

    // the song menu (right-click / ⋮): the window hosts one menu and opens it here
    signal menuRequested(var track, real x, real y, var context)
    function openMenu(t, item, x, y, context) {
        const p = item.mapToItem(null, x, y);
        menuRequested(t, p.x, p.y, context || ({}));
    }

    // what you played, newest first (the library's history; "Jump back in")
    property var history: []
    function loadHistory() { request("history", [], r => { history = r || []; }); }
    property string _histFor: ""
    Connections {
        target: root
        function onCurrentChanged() { if (root.current && root.current.id !== root._histFor) { root._histFor = root.current.id; historyTimer.restart(); } }
    }
    Timer { id: historyTimer; interval: 12000; onTriggered: root.loadHistory() }   // after it counted as a play
    function loadOffline() {
        request("offline", [], r => { offlineTracks = r || []; });
        request("usage", [], r => { usage = r || {}; });
    }
    function playList(tracks, start, shuffled) { request("playlist_tracks", [tracks.map(slim), start || 0, !!shuffled]); }
    function setShuffle(on) { request("shuffle", [on]); }
    function cycleLoop() { request("loop", []); }
    function setVolume(v) { volume = v; request("volume", [Math.round(v)]); }
    function bytes(n) {
        n = n || 0;
        return n >= 1073741824 ? (n / 1073741824).toFixed(1) + " GB" : n >= 1048576 ? Math.round(n / 1048576) + " MB" : Math.round(n / 1024) + " KB";
    }

    // ── Commands ──
    function search(q) {
        q = (q || "").trim();
        if (!q) return;
        lastQuery = q;
        searching = true;
        request("search", [q], r => { results = r || []; searching = false; }, (e) => { results = []; searching = false; });
    }
    function loadHome() {
        if (homeLoading) return;
        homeLoading = true;
        request("home", [], r => { shelves = r || []; homeLoading = false; }, () => { homeLoading = false; });
    }
    function slim(t) { return { id: t.id, title: t.title || "", artist: t.artist || "", duration: t.duration || "", thumb: t.thumb || "", art: t.art || "" }; }
    function play(t) { request("play", [slim(t)]); }
    function radio(t) { request("radio", [slim(t)]); }
    function playItem(it) {      // a home card: a song or a list (album / playlist / mix)
        if (it.kind === "list" || (!it.id && it.playlistId)) request("playlist", [it.playlistId, it.id || ""]);
        else radio(it);
    }
    function add(t) { request("add", [slim(t)]); }
    function playNext(t) { request("playnext", [slim(t)]); }
    function remove(i) { request("remove", [i]); }
    function jump(i) { request("jump", [i]); }
    function next() { request("next", []); }
    function prev() { request("prev", []); }
    function toggle() { request("toggle", []); }
    function seek(s) { _basePos = s; _baseAt = Date.now(); pos = s; request("seek", [Math.max(0, s)]); }
    function setAutoplay(on) { request("autoplay", [on]); }
    function clear() { request("clear", []); }

    // ── Socket + request/reply ──
    property int _nextId: 1
    property var _pending: ({})
    function request(cmd, args, ok, fail) {
        if (!sock.connected) { connectTimer.restart(); if (fail) fail(); return; }
        const id = _nextId++;
        if (ok || fail) _pending[id] = { ok: ok, fail: fail };
        sock.write(JSON.stringify({ id: id, cmd: cmd, args: args || [] }) + "\n");
        sock.flush();
    }
    function onLine(line) {
        let m;
        try { m = JSON.parse(line); } catch (e) { return; }
        if (m.event === "status") { applyStatus(m); return; }
        if (m.event === "library") {
            const o = {};
            for (const id of (m.likes || [])) o[id] = true;
            likes = o;
            loadLiked();
            return;
        }
        if (m.event === "playlists") { loadPlaylists(); return; }
        if (m.event === "files") {
            const had = Object.keys(files).length;
            files = m.files || {};
            progress = m.progress || {};
            if (Object.keys(files).length !== had) loadOffline();
            return;
        }
        const p = _pending[m.id];
        if (!p) return;
        delete _pending[m.id];
        if (m.error !== undefined) { error = m.error; if (p.fail) p.fail(m.error); }
        else { error = ""; if (p.ok) p.ok(m.result); }
    }
    function applyStatus(s) {
        current = s.current || null;
        // replace the queue only when it changed: a new array resets the list (scroll, animations)
        const q = s.queue || [];
        const key = q.length + ":" + q.map(t => t.id).join(",");
        if (key !== _queueKey) { _queueKey = key; queue = q; }
        index = s.index ?? -1;
        playing = !!s.playing;
        paused = !!s.paused;
        loading = !!s.loading;
        autoplay = s.autoplay !== false;
        shuffle = !!s.shuffle;
        loop = s.loop || "none";
        volume = s.volume ?? 100;
        netOnline = s.online !== false;
        notice = s.notice || "";
        localArt = s.art || "";
        sleepAt = (s.sleepAt || 0) * 1000;
        sleepEndOfTrack = !!s.sleepEndOfTrack;
        dur = s.dur || 0;
        _basePos = s.pos || 0;
        _baseAt = Date.now();
        pos = _basePos;
    }

    Socket {
        id: sock
        path: root.sockPath
        parser: SplitParser { onRead: (line) => root.onLine(line) }
        onConnectedChanged: {
            if (connected) {
                root.error = "";
                if (root.shelves.length === 0) root.loadHome();
                root.loadForYou(false);
                root.loadOffline();
                root.loadHistory();
                root.loadPlaylists();
            }
            else connectTimer.restart();
        }
    }
    // Start the daemon (no-op when it runs) and connect; retry while it comes up.
    property int _tries: 0
    Process {
        id: spawner
        command: ["python3", "-I", root.backend, "--spawn"]
        onExited: { sock.connected = true; connectTimer.restart(); }
    }
    Timer {
        id: connectTimer
        interval: 600
        onTriggered: {
            if (sock.connected) return;
            root._tries++;
            if (root._tries % 4 === 1 && !spawner.running) spawner.running = true;
            else sock.connected = true;
            if (root._tries > 30) root.error = "Can't reach the music backend";
            restart();
        }
    }
    Component.onCompleted: spawner.running = true

    // Local clock between pushes: only while something plays AND the window is on screen
    // (the shell sets uiVisible); it catches up the moment the window is back.
    property bool uiVisible: true
    Timer {
        interval: 250
        repeat: true
        triggeredOnStart: true
        running: root.playing && !root.loading && root.uiVisible
        onTriggered: root.pos = Math.min(root.dur || 1e9, root._basePos + (Date.now() - root._baseAt) / 1000)
    }

    // ── Lyrics (the shell's scripts/lyrics.py: lrclib.net, cached) ──
    property var lyrics: []
    property string plainLyrics: ""
    property string lyricsState: "idle"      // idle | loading | synced | plain | instrumental | none
    property string _lyricsFor: ""
    property bool wantLyrics: false
    function loadLyrics() {
        if (!wantLyrics || !current || _lyricsFor === current.id) return;
        _lyricsFor = current.id;
        lyrics = []; plainLyrics = ""; lyricsState = "loading";
        lyricsProc.running = false;
        lyricsProc.command = ["python3", "-I", Quickshell.shellDir + "/backend/lyrics.py",
                              current.artist || "", current.title || "", "", String(Math.round(dur || 0))];
        lyricsProc.running = true;
    }
    onCurrentChanged: loadLyrics()
    onWantLyricsChanged: loadLyrics()
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
    readonly property int lyricIndex: {
        if (lyricsState !== "synced") return -1;
        const t = pos + 0.25;
        let i = -1;
        for (let k = 0; k < lyrics.length; k++) { if (lyrics[k][0] <= t) i = k; else break; }
        return i;
    }

    function clock(s) {
        s = Math.max(0, Math.floor(s || 0));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60;
        return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(sec).padStart(2, "0");
    }
}
