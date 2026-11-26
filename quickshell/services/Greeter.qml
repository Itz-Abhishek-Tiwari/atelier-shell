pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// The login screen (greeter/shell.qml, run by greetd as the `greeter` user) cannot read $HOME,
// so this service mirrors what it needs into /var/lib/atelier-greeter, which
// greeter/install.sh hands to you (no root needed afterwards):
//   settings.json  <- Settings.greeter (+ clock format, weather place)   written live
//   colors.json, wallpaper.jpg, faces/$USER, fonts/  <- scripts/greeter-sync.sh
// With Settings.greeter.autoSync the theme, wallpaper and avatar follow along automatically.
// Changing the greeter's own files (/etc/greetd/...) still needs `sudo greeter/install.sh`.
Singleton {
    id: root

    readonly property string dataDir: "/var/lib/atelier-greeter"
    readonly property string installDir: "/etc/greetd/atelier-greeter"

    // ── status (refresh() re-reads it) ──────────────────────────────────────
    property bool installed: false       // greeter files in /etc/greetd
    property bool upToDate: false        // installed files == the repo's greeter/
    property bool active: false          // greetd.service is the enabled login manager
    property bool writable: false        // we can write the data folder
    property bool quietBoot: false       // kernel cmdline has `quiet`
    property string repoDir: ""          // the repo (from the ~/.config/quickshell symlink)
    property int syncedAt: 0             // unix time of the last asset sync
    property bool syncing: false
    property string lastSyncResult: ""

    function refresh(): void { statusProc.running = true; }
    Process {
        id: statusProc
        command: ["sh", "-c",
            "repo=$(dirname \"$(readlink -f \"$1\")\"); echo \"repo=$repo\"; "
            + "[ -f \"$2/shell.qml\" ] && echo installed=1; "
            + "cmp -s \"$repo/greeter/shell.qml\" \"$2/shell.qml\" && cmp -s \"$repo/greeter/session.sh\" \"$2/session.sh\" "
            + "&& grep -q QT_WAYLAND_DISABLE_WINDOWDECORATION /etc/greetd/config.toml 2>/dev/null && echo uptodate=1; "
            + "[ \"$(systemctl is-enabled greetd.service 2>/dev/null)\" = enabled ] && echo active=1; "
            + "[ -d \"$3\" ] && [ -w \"$3\" ] && echo writable=1; "
            + "grep -qw quiet /proc/cmdline && echo quiet=1; "
            + "echo \"synced=$(cat \"$3/.synced\" 2>/dev/null || echo 0)\"",
            "sh", Quickshell.shellDir, root.installDir, root.dataDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const kv = {};
                text.trim().split("\n").forEach(l => { const i = l.indexOf("="); if (i > 0) kv[l.slice(0, i)] = l.slice(i + 1); });
                root.repoDir = kv.repo || "";
                root.installed = kv.installed === "1";
                root.upToDate = kv.uptodate === "1";
                root.active = kv.active === "1";
                root.quietBoot = kv.quiet === "1";
                root.syncedAt = parseInt(kv.synced) || 0;
                const wasWritable = root.writable;
                root.writable = kv.writable === "1";
                if (root.writable && !wasWritable) { writeTimer.restart(); if (Settings.greeter.autoSync) root.sync(); }
            }
        }
    }
    Component.onCompleted: refresh()

    // ── options → settings.json ─────────────────────────────────────────────
    readonly property string json: {
        const g = Settings.greeter;
        return JSON.stringify({
            layout: g.layout,
            greeting: g.greeting,
            clock24: Settings.general.clock24,
            showWeather: g.showWeather,
            weatherLocation: Settings.widgets.weatherLocation,
            weatherUnits: Settings.widgets.weatherUnits,
            showSystem: g.showSystem,
            showPower: g.showPower,
            blur: Math.round(g.blur * 100) / 100,
            dim: Math.round(g.dim * 100) / 100
        }, null, 2) + "\n";
    }
    FileView { id: optsFile; path: root.dataDir + "/settings.json"; printErrors: false }
    Timer {
        id: writeTimer
        interval: 300
        onTriggered: if (root.writable && Settings.ready) optsFile.setText(root.json)
    }
    onJsonChanged: writeTimer.restart()

    // ── theme / wallpaper / avatar → data folder ────────────────────────────
    function sync(): void {
        if (!writable || syncProc.running) return;
        syncing = true;
        syncProc.running = true;
    }
    Process {
        id: syncProc
        command: [Quickshell.shellDir + "/scripts/greeter-sync.sh", root.dataDir]
        stdout: StdioCollector { onStreamFinished: root.lastSyncResult = text.trim().split("\n").join(" · ") }
        onExited: { root.syncing = false; root.refresh(); }
    }
    Timer { id: autoTimer; interval: 1500; onTriggered: root.sync() }
    function autoSync(): void { if (Settings.greeter.autoSync && writable) autoTimer.restart(); }
    Connections { target: Atelier; function onThemeIdChanged() { root.autoSync(); } function onIsLightChanged() { root.autoSync(); } }
    Connections { target: Wallpaper; function onCurrentChanged() { root.autoSync(); } }
    // the login screen uses your lock-screen style: follow its options
    readonly property string _lockKey: JSON.stringify([Settings.lock.theme, Settings.lock.clock,
        JSON.stringify(Settings.lockStyle), Settings.general.clock24])
    on_LockKeyChanged: autoSync()

    // ── actions ─────────────────────────────────────────────────────────────
    // Preview the repo's greeter in demo mode (fullscreen, password "demo", Esc closes)
    function preview(): void {
        if (writable) optsFile.setText(json);
        Quickshell.execDetached(["quickshell", "-p", repoDir + "/greeter/shell.qml"]);
    }
    // Things that need root run greeter/install.sh in a terminal (sudo asks for the password)
    function runInstaller(args: string): void {
        const cmd = "sudo '" + repoDir + "/greeter/install.sh' " + args
            + "; echo; printf 'Press Enter to close… '; read _";
        Quickshell.execDetached([Settings.behavior.terminal || "ghostty", "-e", "sh", "-c", cmd]);
    }
}
