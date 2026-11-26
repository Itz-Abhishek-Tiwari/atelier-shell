pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Install and remove software (pacman + the AUR through yay/paru). Used by Settings → Install & remove
// and by the Software drawer, so both show the same search, the same installed list and the same state.
// Data from scripts/packages.py (read-only). Installing and removing run in the terminal
// (Settings.behavior.terminal): sudo / yay ask for the password there and pacman shows what will change.
// When that terminal's command finishes it calls `qs ipc call packages refresh`, so the lists update.
Singleton {
    id: root

    readonly property string script: Quickshell.shellDir + "/scripts/packages.py"

    // ── Find ────────────────────────────────────────────────────────────────
    property string query: ""
    property var repoHits: []
    property var aurHits: []
    property bool searchingRepo: false
    property bool searchingAur: false
    property bool searched: false
    property string helper: ""                 // yay | paru | "" (no AUR without one)
    property bool helperChecked: false
    // repo first (official, signed), then the AUR; one entry per name
    readonly property var hits: {
        const seen = {}, out = [];
        for (const p of repoHits.concat(aurHits)) { if (!seen[p.name]) { seen[p.name] = true; out.push(p); } }
        return out;
    }

    // ── Popular (shown before you search) ───────────────────────────────────
    readonly property var featuredNames: ["firefox", "vlc", "gimp", "obs-studio", "libreoffice-fresh", "steam",
        "inkscape", "blender", "telegram-desktop", "krita", "audacity", "kdenlive"]
    property var featured: []
    // browse tiles: a search each
    readonly property var categories: [
        { label: "Browsers",    icon: "󰖟", tint: "blue",     q: "browser" },
        { label: "Video",       icon: "󰕧", tint: "pink",     q: "video player" },
        { label: "Music",       icon: "󰝚", tint: "mauve",    q: "music player" },
        { label: "Graphics",    icon: "󰋩", tint: "peach",    q: "image editor" },
        { label: "Code",        icon: "󰅩", tint: "green",    q: "code editor" },
        { label: "Terminals",   icon: "󰆍", tint: "teal",     q: "terminal emulator" },
        { label: "Games",       icon: "󰊴", tint: "red",      q: "game" },
        { label: "Chat",        icon: "󰭹", tint: "sapphire", q: "chat" },
        { label: "Office",      icon: "󰈙", tint: "yellow",   q: "office" },
        { label: "Downloads",   icon: "󰇚", tint: "sky",      q: "torrent" },
        { label: "Notes",       icon: "󰎞", tint: "lavender", q: "notes" },
        { label: "System tools",icon: "󰒓", tint: "accent",   q: "system monitor" }
    ]

    // ── Installed ───────────────────────────────────────────────────────────
    property var installed: []
    property bool loadingInstalled: false
    readonly property var installedByName: {
        const m = {};
        for (const p of installed) m[p.name] = p;
        return m;
    }

    // ── Feedback ────────────────────────────────────────────────────────────
    property string busy: ""                   // just sent to the terminal
    property string confirmRemove: ""          // a second click removes

    function validName(n) { return /^[a-z0-9@._+-]+$/.test(n); }

    function search(q) {
        query = q;
        const t = q.trim();
        if (t.length < 2) { repoHits = []; aurHits = []; searched = false; repoProc.running = false; aurProc.running = false; return; }
        const words = t.split(/\s+/).slice(0, 4);
        searched = true;
        repoProc.running = false; aurProc.running = false;
        repoProc.command = ["python3", "-I", script, "search"].concat(words);
        searchingRepo = true; repoProc.running = true;
        if (helper) {
            aurProc.command = ["python3", "-I", script, "aur"].concat(words);
            searchingAur = true; aurProc.running = true;
        } else searchingAur = false;
    }
    function loadFeatured() { featProc.running = false; featProc.command = ["python3", "-I", script, "info"].concat(featuredNames); featProc.running = true; }
    function refreshInstalled() { loadingInstalled = true; instProc.running = false; instProc.running = true; }
    function refresh() { refreshInstalled(); loadFeatured(); if (searched) search(query); }
    // call when a page / drawer opens
    function ensureReady() {
        if (!helperChecked && !helperProc.running) helperProc.running = true;
        refreshInstalled();
        if (featured.length === 0) loadFeatured();
        if (searched) search(query);
    }

    // install / remove in a terminal, fully detached: a Settings drawer closing (or a restart) must never
    // kill a running pacman.
    function act(pkg, remove) {
        if (!validName(pkg.name)) return;
        const tail = "; qs ipc call packages refresh >/dev/null 2>&1; echo; printf 'Done. Press Enter to close… '; read _";
        const cmd = remove ? "sudo pacman -Rns " + pkg.name
                  : pkg.aur ? helper + " -S --needed " + pkg.name
                  : "sudo pacman -S --needed " + pkg.name;
        busy = pkg.name;
        confirmRemove = "";
        busyReset.restart();
        Quickshell.execDetached([Settings.behavior.terminal || "kitty", "-e", "sh", "-c", cmd + tail]);
    }
    function askRemove(name) { confirmRemove = name; confirmReset.restart(); }

    // ── Icons ───────────────────────────────────────────────────────────────
    // The app's own icon when we know it: the .desktop file of an installed package (from packages.py),
    // otherwise a theme icon named like the package (firefox, vlc, gimp …; "-bin"/"-git" … stripped).
    // Packages you have not installed have no .desktop file on disk to read, so a name that matches no
    // theme icon gets a glyph instead. Returns "" when there is none.
    function iconSource(name) {
        if (!name) return "";
        return name.startsWith("/") ? "file://" + name : Quickshell.iconPath(name, true);
    }
    function iconFor(pkg) {
        if (!pkg) return "";
        const own = pkg.icon || (installedByName[pkg.name] ? installedByName[pkg.name].icon : "");
        let s = iconSource(own);
        if (s) return s;
        const tried = {};
        let n = pkg.name;
        for (let i = 0; i < 4 && n; i++) {
            if (!tried[n]) { tried[n] = true; s = iconSource(n); if (s) return s; }
            const stripped = n.replace(/-(bin|git|svn|hg|appimage|nightly|beta|stable|dev|desktop|electron|wayland|x11|qt\d?|gtk\d?|cli|launcher|app)$/, "");
            if (stripped === n) break;
            n = stripped;
        }
        return "";
    }

    Timer { id: confirmReset; interval: 4000; onTriggered: root.confirmRemove = "" }
    Timer { id: busyReset; interval: 6000; onTriggered: root.busy = "" }

    Process {
        id: helperProc
        command: ["python3", "-I", root.script, "helper"]
        stdout: StdioCollector { onStreamFinished: { root.helper = text.trim(); root.helperChecked = true; } }
    }
    Process {
        id: repoProc
        stdout: StdioCollector {
            onStreamFinished: { try { root.repoHits = JSON.parse(text); } catch (e) { root.repoHits = []; } root.searchingRepo = false; }
        }
    }
    Process {
        id: aurProc
        stdout: StdioCollector {
            onStreamFinished: { try { root.aurHits = JSON.parse(text); } catch (e) { root.aurHits = []; } root.searchingAur = false; }
        }
    }
    Process {
        id: featProc
        stdout: StdioCollector {
            onStreamFinished: { try { root.featured = JSON.parse(text); } catch (e) { root.featured = []; } }
        }
    }
    Process {
        id: instProc
        command: ["python3", "-I", root.script, "installed"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.installed = JSON.parse(text); } catch (e) { console.warn("packages:", e); } root.loadingInstalled = false; }
        }
    }

    IpcHandler {
        target: "packages"
        function refresh(): void { root.refresh(); }
    }
}
