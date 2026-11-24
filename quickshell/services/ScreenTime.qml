pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config

// Screen time: how long the screen was in use each day, and in which app (the focused window).
// Event-driven: it adds up time when the focused app changes, plus one tick a minute; it stops
// counting while the screen is locked (shell.qml sets `locked`) or after 2 minutes without input
// (video players and games that inhibit idle keep counting). Kept 35 days in statePath
// screen-time.json: { "2026-11-24": { t: seconds, a: { appId: seconds } } }.
// Shown in the system monitor's Screen time tab; Settings.behavior.screenTime turns it off.
Singleton {
    id: root

    property bool locked: false
    readonly property bool enabled: Settings.behavior.screenTime
    readonly property int idleAfter: 120                 // seconds without input = away
    readonly property string app: ToplevelManager.activeToplevel ? (ToplevelManager.activeToplevel.appId || "") : ""
    readonly property bool counting: enabled && _loaded && !locked && !idle.isIdle

    property var days: ({})
    property int revision: 0                             // bumps on every change, for views to re-read
    property bool _loaded: false
    property double _since: 0
    property string _app: ""
    property bool _dirty: false

    function dayKey(d) { return Qt.formatDate(d || new Date(), "yyyy-MM-dd"); }

    // add the time since the last flush (up to `until`) to today and the app that had focus
    function flush(until) {
        if (_since <= 0) return;
        // one tick is a minute; a longer gap means the laptop slept, which isn't screen time
        const secs = Math.max(0, Math.min(75, (until - _since) / 1000));
        _since = Date.now();
        if (secs < 1) return;
        const k = dayKey(), d = days[k] || { t: 0, a: {} };
        d.t = Math.round((d.t + secs) * 10) / 10;
        if (_app) d.a[_app] = Math.round(((d.a[_app] || 0) + secs) * 10) / 10;
        days[k] = d;
        _dirty = true;
        revision++;
    }
    function flushNow() { if (counting) flush(Date.now()); }

    onCountingChanged: {
        if (counting) { _since = Date.now(); _app = app; }
        else flush(idle.isIdle ? Date.now() - idleAfter * 1000 : Date.now());   // the idle wait wasn't use
        if (!counting) { _since = 0; save(); }
    }
    onAppChanged: { if (counting) flush(Date.now()); _app = app; }

    IdleMonitor { id: idle; enabled: root.enabled; timeout: root.idleAfter; respectInhibitors: true }

    Timer { interval: 60000; repeat: true; running: root.counting; onTriggered: root.flush(Date.now()) }
    Timer { interval: 300000; repeat: true; running: root.counting; onTriggered: root.save() }   // a reload/crash loses ≤5 min
    Component.onDestruction: { flushNow(); save(); }

    function save() {
        if (!_loaded || !_dirty) return;
        const keep = {}, cutoff = dayKey(new Date(Date.now() - 35 * 86400000));
        for (const k in days) if (k >= cutoff) keep[k] = days[k];
        days = keep;
        file.setText(JSON.stringify(keep));
        _dirty = false;
    }
    function clear() { days = {}; _dirty = true; save(); revision++; }

    // ── for the views ──────────────────────────────────────────────────────────
    // the 7 days ending today, oldest first: { key, date, t }
    function week() {
        const out = [], now = new Date();
        for (let i = 6; i >= 0; i--) {
            const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
            const k = dayKey(d);
            out.push({ key: k, date: d, t: days[k] ? days[k].t : 0 });
        }
        return out;
    }
    // apps for some days, most used first: [{ id, secs }]
    function apps(keys) {
        const sum = {};
        for (const k of keys) {
            const a = days[k] ? days[k].a : {};
            for (const id in a) sum[id] = (sum[id] || 0) + a[id];
        }
        return Object.keys(sum).map(id => ({ id: id, secs: sum[id] })).sort((x, y) => y.secs - x.secs);
    }
    function entry(id) { return id ? DesktopEntries.heuristicLookup(id) : null; }
    function appName(id) {
        const e = entry(id);
        if (e && e.name) return e.name;
        const s = (id || "Other").split(".").pop().replace(/[-_]/g, " ");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }
    function appIcon(id) { const e = entry(id); return e && e.icon ? Quickshell.iconPath(e.icon, true) : ""; }
    function fmt(secs) {
        const m = Math.round(secs / 60), h = Math.floor(m / 60);
        return h ? h + "h " + (m % 60) + "m" : m < 1 && secs > 0 ? "<1m" : m + "m";
    }

    FileView {
        id: file
        printErrors: false
        path: Quickshell.statePath("screen-time.json")
        onLoaded: { try { root.days = JSON.parse(text()) || {}; } catch (e) {} root._loaded = true; root.revision++; }
        onLoadFailed: root._loaded = true
    }
}
