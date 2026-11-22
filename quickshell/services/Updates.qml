pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// System updates: scripts/updates.sh (no root) a couple of minutes after login and then every
// Settings.updates.hours. The control center shows a strip while there are any; "Update"
// opens scripts/update-system.sh in the terminal, which calls `qs ipc call updates check`
// when it's done.
Singleton {
    id: root

    property var repo: []          // [{ name, from, to }]
    property var aur: []
    readonly property int count: repo.length + aur.length
    property real checkedAt: 0     // ms; 0 = not yet
    readonly property bool checking: proc.running

    function check(): void { if (!proc.running) proc.running = true; }
    function run(): void {
        Quickshell.execDetached([Settings.behavior.terminal, "-e", Quickshell.shellDir + "/scripts/update-system.sh"]);
    }

    function parse(text: string): void {
        const r = [], a = [];
        for (const line of text.split("\n")) {
            const m = line.trim().match(/^(repo|aur)\s+(\S+)\s+(\S+)\s+->\s+(\S+)/);
            if (m) (m[1] === "aur" ? a : r).push({ name: m[2], from: m[3], to: m[4] });
        }
        repo = r;
        aur = a;
        checkedAt = Date.now();
    }

    Process {
        id: proc
        command: [Quickshell.shellDir + "/scripts/updates.sh"]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }

    // first look shortly after login (the network is up by then), then every few hours
    Timer {
        running: Settings.updates.check
        interval: 120000
        onTriggered: root.check()
    }
    Timer {
        running: Settings.updates.check
        interval: Math.max(1, Settings.updates.hours) * 3600000
        repeat: true
        onTriggered: root.check()
    }
}
