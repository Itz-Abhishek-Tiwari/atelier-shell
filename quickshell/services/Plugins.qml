pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// User plugins: folders in ~/.config/atelier/plugins/<id>/ with a plugin.json (see docs/plugins.md).
// Extension points: lockStyles, desktopWidgets, settingsPages, barItems, launcherActions, controlTiles.
// A plugin runs only when it is switched on AND approved (its files hash matches .trusted).
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.config/atelier/plugins"
    property var all: []                       // every plugin found, enabled or not
    readonly property var active: all.filter(p => p.enabled && p.trusted && !p.error)
    property string status: ""                 // result line of the last install / remove / approve
    property var loadErrors: ({})              // plugin id -> reason one of its QML files failed to load

    function collect(kind) {
        const out = [];
        for (const p of active) for (const e of p[kind]) out.push(Object.assign({ plugin: p.id, pluginName: p.name, pluginDir: p.dir }, e));
        return out;
    }
    readonly property var lockStyles: collect("lockStyles").map(e => ({
        id: e.uid, name: e.name || e.id, note: e.note || (e.pluginName + " plugin"), file: e.file, plugin: true, pluginId: e.plugin, entry: e }))
    readonly property var desktopWidgets: collect("desktopWidgets")
    readonly property var barItems: collect("barItems")
    readonly property var launcherActions: collect("launcherActions").map(e => ({
        key: "plugin:" + e.uid, title: e.title, subtitle: e.subtitle || e.pluginName, glyph: e.glyph || "󰐱",
        color: Atelier.accent, words: (e.words || "") + " " + e.pluginName + " plugin",
        overlay: e.overlay, cmd: e.cmd, toast: e.toast }))
    readonly property var controlTiles: collect("controlTiles").map(e => ({
        id: e.overlay || "", cmd: e.cmd || "", label: e.label, icon: e.icon || "󰐱" }))
    readonly property var settingsPages: collect("settingsPages").map(e => ({
        id: "plugin:" + e.uid, group: "Plugins", icon: e.icon || "󰐱", label: e.label || e.name || e.id,
        sub: e.sub || e.pluginName, keys: (e.label || "") + " " + e.pluginName + " plugin", file: e.file, entry: e }))

    function lockFile(uid) { const s = lockStyles.find(x => x.id === uid); return s ? "file://" + s.file : ""; }
    function reload() { scan.running = false; scan.running = true; }

    // ── What a plugin's QML can call (import qs.services → Plugins.…) ─────────────
    // hand the loaded root its identity: declare `property var plugin` and it is set to {id, name, dir}
    function attach(item, entry) {
        if (item && "plugin" in item) item.plugin = { id: entry.plugin, name: entry.pluginName, dir: entry.pluginDir };
    }
    function reportError(pluginId, msg) {
        const e = Object.assign({}, loadErrors);
        e[pluginId] = msg;
        loadErrors = e;
    }
    // where the user moved a plugin's desktop widget: {h, v, margin, x, y}, any key may be missing (Settings → Plugins)
    function layoutOf(uid) { return get("_layout", uid, null) || ({}); }
    function setLayout(uid, patch) {
        const cur = Object.assign({}, layoutOf(uid), patch);
        for (const k in cur) if (cur[k] === undefined) delete cur[k];
        set("_layout", uid, Object.keys(cur).length ? cur : null);
    }
    function run(cmd) { Quickshell.execDetached(cmd); }
    function notify(title, body) { Quickshell.execDetached(["notify-send", "-a", "Plugin", title, body || ""]); }

    // small per-plugin key/value store, one file for all plugins (survives updating a plugin)
    property var data: ({})
    function get(pluginId, key, fallback) {
        const d = data[pluginId];
        return d && d[key] !== undefined ? d[key] : fallback;
    }
    function set(pluginId, key, value) {
        const d = Object.assign({}, data);
        d[pluginId] = Object.assign({}, d[pluginId] || {}, { [key]: value });
        data = d;
        store.setText(JSON.stringify(d, null, 1));
    }
    FileView {
        id: store
        path: Quickshell.env("HOME") + "/.config/atelier/plugin-data.json"
        printErrors: false
        onLoaded: { try { root.data = JSON.parse(text()); } catch (e) { root.data = ({}); } }
    }

    // ── Managing plugins ──────────────────────────────────────────────────────────
    function setEnabled(id, on) {
        const p = all.find(x => x.id === id);
        if (!p) return;
        // approving is part of switching a plugin on: Settings shows what it contains first
        if (on && !p.trusted) ctl(["trust", id]);
        else {
            Quickshell.execDetached(on ? ["rm", "-f", p.dir + "/.disabled"] : ["touch", p.dir + "/.disabled"]);
            reloadSoon.restart();
        }
    }
    function install(src) { if (src.trim() !== "") ctl(["install", src.trim()]); }
    function remove(id) { ctl(["remove", id]); }
    function ctl(args) {
        status = "Working…";
        ctlProc.command = [Quickshell.shellDir + "/scripts/plugins-install.py"].concat(args, [dir]);
        ctlProc.running = true;
    }
    function openFolder() { Quickshell.execDetached(["sh", "-c", "mkdir -p '" + dir + "' && xdg-open '" + dir + "'"]); }

    Timer { id: reloadSoon; interval: 250; onTriggered: root.reload() }

    Process {
        id: ctlProc
        stdout: StdioCollector { onStreamFinished: root.status = text.trim().replace(/^(ok|error): /, m => m === "ok: " ? "" : "Failed: ") }
        onExited: root.reload()
    }

    Process {
        id: scan
        command: [Quickshell.shellDir + "/scripts/plugins-scan.py", root.dir]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.all = JSON.parse(text); root.loadErrors = ({}); } catch (e) { console.warn("plugins: bad scan output", e); }
            }
        }
    }

    IpcHandler {
        target: "plugins"
        function reload(): void { root.reload(); }
        function list(): string {
            return root.all.map(p => (p.enabled && p.trusted ? "on  " : "off ") + p.id
                + (p.error ? "  ! " + p.error : !p.trusted ? "  (not approved)" : "")).join("\n");
        }
        function enable(id: string): void { root.setEnabled(id, true); }
        function disable(id: string): void { root.setEnabled(id, false); }
        function install(source: string): void { root.install(source); }
        function remove(id: string): void { root.remove(id); }
    }
}
