pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Countdown timers, a stopwatch and a pomodoro, all in one place (drawer: TimerOverlay.qml).
// They keep counting while the drawer is closed; the 250 ms tick only runs while something is
// running. A finished timer sends a notification, a toast and a sound.
// Timers and the pomodoro survive a shell restart (statePath timers.json); the stopwatch doesn't.
//
//   qs ipc call timers start 10m [label]   |  stop <id>  |  clear  |  pomodoro  |  stopwatch
Singleton {
    id: root

    signal toast(string msg, string icon, color clr)

    property double now: Date.now()
    // ── countdown timers: { id, label, total, end (ms epoch while running), left (ms while paused), running, done }
    property var timers: []
    property int _nextId: 1
    // ── stopwatch
    property bool swRunning: false
    property double swStart: 0
    property double swBase: 0
    property var laps: []
    readonly property double swElapsed: swRunning ? swBase + (now - swStart) : swBase
    // ── pomodoro
    property string phase: "focus"          // focus | short | long
    property bool pomoRunning: false
    property double pomoEnd: 0
    property double pomoPaused: -1          // ms left while paused (-1 = not started this phase)
    property int rounds: 0                  // focus rounds finished in this cycle
    readonly property double phaseMs: (phase === "focus" ? Settings.behavior.pomoFocus
                                     : phase === "short" ? Settings.behavior.pomoShort : Settings.behavior.pomoLong) * 60000
    readonly property double pomoLeft: pomoRunning ? Math.max(0, pomoEnd - now) : (pomoPaused >= 0 ? pomoPaused : phaseMs)

    readonly property int runningCount: timers.filter(t => t.running).length + (swRunning ? 1 : 0) + (pomoRunning ? 1 : 0)
    // shortest running countdown, for a bar chip / control center (−1 when none)
    readonly property double nextLeft: {
        let m = -1;
        for (const t of timers) if (t.running) { const l = Math.max(0, t.end - now); if (m < 0 || l < m) m = l; }
        return m;
    }

    function fmt(ms: real, withTenths: bool): string {
        const s = Math.max(0, ms) / 1000;
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = Math.floor(s % 60);
        const p = (n) => String(n).padStart(2, "0");
        const base = (h ? h + ":" + p(m) : p(m)) + ":" + p(sec);
        return withTenths ? base + "." + Math.floor(s * 10 % 10) : base;
    }
    // "10m", "1h30", "90s", "25" (minutes), "1:30" (h:mm) → seconds; 0 if not understood
    function parse(text: string): int {
        const t = text.trim().toLowerCase();
        let m = t.match(/^(\d+):(\d+)$/);
        if (m) return (+m[1]) * 3600 + (+m[2]) * 60;
        m = t.match(/^(?:(\d+)\s*h)?\s*(?:(\d+)\s*m(?:in)?)?\s*(?:(\d+)\s*s(?:ec)?)?$/);
        if (m && (m[1] || m[2] || m[3])) return (+(m[1] || 0)) * 3600 + (+(m[2] || 0)) * 60 + (+(m[3] || 0));
        m = t.match(/^(\d+)h(\d+)$/);
        if (m) return (+m[1]) * 3600 + (+m[2]) * 60;
        m = t.match(/^(\d+)$/);
        return m ? (+m[1]) * 60 : 0;
    }

    // ── timers ───────────────────────────────────────────────────────────────
    function add(seconds: int, label: string): int {
        if (seconds <= 0) return -1;
        const id = _nextId++;
        const ms = seconds * 1000;
        timers = timers.concat([{ id: id, label: label || "", total: ms, end: Date.now() + ms, left: ms, running: true, done: false }]);
        _changed();
        return id;
    }
    function _patch(id, fn) { timers = timers.map(t => t.id === id ? Object.assign({}, t, fn(t)) : t); _changed(); }
    function toggle(id: int): void {
        _patch(id, t => t.done ? { done: false, running: true, end: Date.now() + t.total, left: t.total }
            : t.running ? { running: false, left: Math.max(0, t.end - Date.now()) }
            : { running: true, end: Date.now() + t.left });
    }
    function restart(id: int): void { _patch(id, t => ({ done: false, running: true, end: Date.now() + t.total, left: t.total })); }
    function remove(id: int): void { timers = timers.filter(t => t.id !== id); _changed(); }
    function clearFinished(): void { timers = timers.filter(t => !t.done); _changed(); }
    function clearAll(): void { timers = []; _changed(); }

    function _alarm(title: string, body: string, icon: string, clr: color): void {
        Quickshell.execDetached(["notify-send", "-a", "Timer", "-i", "alarm-symbolic", title, body]);
        Quickshell.execDetached(["sh", "-c", "command -v canberra-gtk-play >/dev/null && canberra-gtk-play -i alarm-clock-elapsed -d atelier || true"]);
        toast(title + (body ? " · " + body : ""), icon, clr);
    }

    // ── stopwatch ────────────────────────────────────────────────────────────
    function swToggle(): void {
        if (swRunning) { swBase += Date.now() - swStart; swRunning = false; }
        else { swStart = Date.now(); swRunning = true; }
        now = Date.now();
    }
    function swLap(): void { if (swElapsed > 0) laps = [swElapsed].concat(laps).slice(0, 50); }
    function swReset(): void { swRunning = false; swBase = 0; laps = []; }

    // ── pomodoro ─────────────────────────────────────────────────────────────
    function pomoToggle(): void {
        if (pomoRunning) { pomoPaused = Math.max(0, pomoEnd - Date.now()); pomoRunning = false; }
        else { pomoEnd = Date.now() + (pomoPaused >= 0 ? pomoPaused : phaseMs); pomoPaused = -1; pomoRunning = true; }
        now = Date.now(); _changed();
    }
    function pomoSkip(): void { _nextPhase(false); }
    function pomoReset(): void { pomoRunning = false; pomoPaused = -1; phase = "focus"; rounds = 0; _changed(); }
    function pomoSetPhase(p: string): void { pomoRunning = false; pomoPaused = -1; phase = p; _changed(); }
    function _nextPhase(auto: bool): void {
        const every = Math.max(1, Settings.behavior.pomoEvery);
        let next;
        if (phase === "focus") { rounds += 1; next = rounds % every === 0 ? "long" : "short"; }
        else next = "focus";
        if (auto) {
            if (phase === "focus") _alarm("Focus round done", next === "long" ? "Time for a long break" : "Take a short break", "󰔟", Atelier.green);
            else _alarm("Break over", "Back to focus", "󰔟", Atelier.accent);
        }
        phase = next;
        pomoPaused = -1;
        pomoRunning = auto;                              // a finished phase flows into the next one
        if (auto) pomoEnd = Date.now() + phaseMs;
        _changed();
    }

    // ── tick ─────────────────────────────────────────────────────────────────
    Timer {
        interval: 250
        running: root.runningCount > 0
        repeat: true
        onTriggered: {
            root.now = Date.now();
            let fired = false;
            for (const t of root.timers) {
                if (t.running && t.end <= root.now) {
                    fired = true;
                    root._alarm("Timer done", t.label || root.fmt(t.total, false), "󱎫", Atelier.peach);
                }
            }
            if (fired) {
                root.timers = root.timers.map(t => (t.running && t.end <= root.now) ? Object.assign({}, t, { running: false, done: true, left: 0 }) : t);
                root._changed();
            }
            if (root.pomoRunning && root.pomoEnd <= root.now) root._nextPhase(true);
        }
    }

    // ── persistence ──────────────────────────────────────────────────────────
    property bool _loaded: false
    function _changed() { if (_loaded) save.restart(); }
    Timer { id: save; interval: 400; onTriggered: file.setText(JSON.stringify({
        timers: root.timers, nextId: root._nextId, phase: root.phase, rounds: root.rounds,
        pomoRunning: root.pomoRunning, pomoEnd: root.pomoEnd, pomoPaused: root.pomoPaused })) }
    FileView {
        id: file
        printErrors: false
        path: Quickshell.statePath("timers.json")
        onLoaded: {
            try {
                const j = JSON.parse(text());
                root._nextId = j.nextId || 1;
                // finished-while-away timers show as done instead of ringing late
                root.timers = (j.timers || []).map(t => (t.running && t.end <= Date.now()) ? Object.assign({}, t, { running: false, done: true, left: 0 }) : t);
                root.phase = j.phase || "focus"; root.rounds = j.rounds || 0;
                root.pomoPaused = j.pomoPaused !== undefined ? j.pomoPaused : -1;
                if (j.pomoRunning && j.pomoEnd > Date.now()) { root.pomoEnd = j.pomoEnd; root.pomoRunning = true; }
                else if (j.pomoRunning) root.pomoPaused = 0;
            } catch (e) {}
            root._loaded = true;
        }
        onLoadFailed: root._loaded = true
    }
}
