pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Settings profiles: named snapshots of settings.json (+ the theme and wallpaper) in
// ~/.config/atelier/profiles/<name>.json, as { name, saved, theme, wallpaper, settings }.
// auto.json there holds the hot-plug rules: { enabled, rules: [{ output, profile }], fallback }.
// When the set of connected outputs changes, the first rule whose output is connected wins,
// else the fallback. A profile is only applied when that choice CHANGES (remembered in the
// shell's state dir), so a restart never overwrites tweaks you made since.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.config/atelier/profiles"
    property var list: []                         // [{ name, saved, theme, wallpaper, settings }]
    property var auto: ({ enabled: false, rules: [], fallback: "" })
    property string active: ""                   // last profile applied (by hand or automatically)
    property bool ready: false

    function safe(name) { return String(name).trim().replace(/[^A-Za-z0-9 _.-]/g, "").slice(0, 40); }

    // ── reading ─────────────────────────────────────────────────────────────
    Process {
        id: lister
        command: ["sh", "-c", 'mkdir -p "$1"; cd "$1" || exit 0; for f in *.json; do [ -f "$f" ] || continue; [ "$f" = auto.json ] && continue; tr -d "\\n" < "$f"; echo; done', "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    if (!line.trim()) continue;
                    try { const p = JSON.parse(line); if (p && p.name && p.settings) out.push(p); } catch (e) {}
                }
                root.list = out.sort((a, b) => a.name.localeCompare(b.name));
            }
        }
    }
    function refresh() { lister.running = true; }

    FileView {
        id: autoFile
        path: root.dir + "/auto.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { const a = JSON.parse(text()); root.auto = { enabled: !!a.enabled, rules: a.rules || [], fallback: a.fallback || "" }; } catch (e) {}
            root.ready = true;
            hotplug.restart();
        }
        onLoadFailed: { root.ready = true; }
    }
    FileView {
        id: stateFile
        path: Quickshell.statePath("profile-state.json")
        printErrors: false
        onLoaded: { try { const s = JSON.parse(text()); root.active = s.active || ""; root._lastAuto = s.lastAuto || ""; } catch (e) {} }
    }
    property string _lastAuto: ""
    function _saveState() { stateFile.setText(JSON.stringify({ active: root.active, lastAuto: root._lastAuto })); }

    // ── writing ─────────────────────────────────────────────────────────────
    Process { id: writer; onExited: root.refresh() }
    // write a file in the profiles folder (content via argv; nothing goes through a shell string)
    function _write(file, content) {
        writer.command = ["sh", "-c", 'mkdir -p "$1" && printf "%s\\n" "$3" > "$1/$2"', "sh", root.dir, file, content];
        writer.running = true;
    }

    function save(name: string): string {
        const n = safe(name);
        if (!n || n === "auto") return "";
        let settings = {};
        try { settings = JSON.parse(Settings.snapshot() || "{}"); } catch (e) { return ""; }
        const p = { name: n, saved: new Date().toISOString(), theme: Atelier.themeId || "", wallpaper: Wallpaper.current || "", settings: settings };
        _write(n + ".json", JSON.stringify(p));
        return n;
    }
    function remove(name: string): void {
        writer.command = ["rm", "-f", root.dir + "/" + safe(name) + ".json"];
        writer.running = true;
        if (root.auto.rules.some(r => r.profile === name) || root.auto.fallback === name)
            setAuto(root.auto.enabled, root.auto.rules.filter(r => r.profile !== name), root.auto.fallback === name ? "" : root.auto.fallback);
    }

    Process { id: themer }
    function apply(name: string): bool {
        const p = root.list.find(x => x.name === name);
        if (!p) return false;
        Settings.load(JSON.stringify(p.settings, null, 2));
        if (p.theme && p.theme !== Atelier.themeId) {
            themer.command = [Quickshell.env("HOME") + "/.local/bin/atelier-theme", "apply", p.theme];
            themer.running = true;
        }
        if (p.wallpaper && p.wallpaper !== Wallpaper.current) Wallpaper.set(p.wallpaper);
        root.active = p.name;
        _saveState();
        return true;
    }

    // ── export / import (a single portable file) ────────────────────────────
    Process { id: exporter }
    function exportTo(name: string, path: string): void {
        const p = root.list.find(x => x.name === name);
        if (!p) return;
        exporter.command = ["sh", "-c", 'printf "%s\\n" "$2" > "$1"', "sh", Settings.expand(path), JSON.stringify(p, null, 2)];
        exporter.running = true;
    }
    signal imported(string name, bool ok)
    Process {
        id: importer
        property string src: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let p = null;
                try { p = JSON.parse(text); } catch (e) {}
                // a bare settings.json works too
                if (p && !p.settings && (p.general || p.appearance || p.windows)) p = { name: "", settings: p };
                if (!p || !p.settings) { root.imported("", false); return; }
                const base = importer.src.split("/").pop().replace(/\.json$/i, "").replace(/^atelier-profile-/, "");
                p.name = root.safe(p.name || base) || "Imported";
                p.saved = p.saved || new Date().toISOString();
                root._write(p.name + ".json", JSON.stringify(p));
                root.imported(p.name, true);
            }
        }
    }
    function importFrom(path: string): void {
        importer.src = Settings.expand(path);
        importer.command = ["cat", importer.src];
        importer.running = true;
    }

    // ── hot-plug ────────────────────────────────────────────────────────────
    function setAuto(enabled, rules, fallback) {
        root.auto = { enabled: enabled, rules: rules, fallback: fallback };
        _write("auto.json", JSON.stringify(root.auto, null, 2));
        // changing the rules never overwrites what you have now: they act on the next plug/unplug
        root._lastAuto = root.choose();
        _saveState();
    }
    readonly property var outputs: Quickshell.screens.map(s => s.name)
    function choose() {
        for (const r of root.auto.rules) if (root.outputs.indexOf(r.output) >= 0) return r.profile;
        return root.auto.fallback;
    }
    onOutputsChanged: hotplug.restart()
    Timer {
        id: hotplug
        interval: 1500                            // let the display settle (and the shell start)
        onTriggered: {
            if (!root.ready || !root.auto.enabled || !Settings.ready) return;
            const want = root.choose();
            if (!want || want === root._lastAuto) return;
            if (!root.list.some(x => x.name === want)) { root.refresh(); return; }
            root._lastAuto = want;
            if (root.apply(want)) console.info("Profiles: switched to", want, "for outputs", root.outputs.join(","));
        }
    }
    onListChanged: if (root.auto.enabled) hotplug.restart()

    Component.onCompleted: refresh()
}
