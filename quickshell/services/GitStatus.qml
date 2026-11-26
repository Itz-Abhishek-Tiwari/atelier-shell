pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.config

// Git state of the focused window's project (scripts/gitstatus.sh walks the window's process tree
// for a repo), for the bar chip. Refreshes on focus change and every 6 s while a repo is focused.
Singleton {
    id: root

    readonly property bool enabled: Settings.bar.showGit
    property string repo: ""
    property string branch: ""
    property int dirty: 0
    property int ahead: 0
    property int behind: 0
    readonly property bool active: repo !== ""
    readonly property string name: repo.split("/").pop()

    readonly property int pid: {
        const t = Hyprland.activeToplevel;
        const o = t ? t.lastIpcObject : null;
        return o && o.pid ? o.pid : 0;
    }
    onPidChanged: refresh()
    onEnabledChanged: refresh()

    function refresh() {
        if (!enabled || pid <= 0) { repo = ""; return; }
        if (!proc.running) { proc.command = [Quickshell.shellDir + "/scripts/gitstatus.sh", String(pid)]; proc.running = true; }
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("\t");
                if (f.length < 5) { root.repo = ""; return; }
                root.repo = f[0]; root.branch = f[1];
                root.dirty = parseInt(f[2]) || 0; root.ahead = parseInt(f[3]) || 0; root.behind = parseInt(f[4]) || 0;
            }
        }
    }
    Timer { interval: 6000; repeat: true; running: root.enabled && root.active; onTriggered: root.refresh() }
}
