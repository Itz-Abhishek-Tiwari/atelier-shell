pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Live numbers for the system monitor drawer. scripts/sysmon.py streams one JSON line a second;
// it runs only while a consumer sets `active`, so it costs nothing when the drawer is closed.
Singleton {
    id: root

    property bool active: false
    property var d: ({})
    readonly property bool ready: d.mem !== undefined

    // short history for the sparklines (60 samples)
    property var cpuHist: []
    property var netHist: []
    function _push(arr, v) { const a = arr.slice(-59); a.push(v); return a; }

    Process {
        id: feed
        running: root.active
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/sysmon.py"]
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    const j = JSON.parse(line);
                    root.d = j;
                    root.cpuHist = root._push(root.cpuHist, j.cpu);
                    root.netHist = root._push(root.netHist, j.down + j.up);
                } catch (e) {}
            }
        }
    }

    function kill(pid: int): void { Quickshell.execDetached(["kill", String(pid)]); }

    // charge limit (Battery tab): kernel charge_types Standard ⇄ Long_Life
    property bool limitBusy: false
    function setChargeLimit(on: bool): void {
        limitBusy = true;
        limitProc.command = [Quickshell.shellDir + "/scripts/battery-limit.sh", on ? "on" : "off"];
        limitProc.running = true;
    }
    Process {
        id: limitProc
        stdout: StdioCollector {}
        onExited: { root.limitBusy = false; }
    }

    function fmtBytes(b: real): string {
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB";
        if (b >= 1048576) return Math.round(b / 1048576) + " MB";
        return Math.round(b / 1024) + " KB";
    }
    function fmtRate(b: real): string {
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB/s";
        if (b >= 1024) return Math.round(b / 1024) + " KB/s";
        return Math.round(b) + " B/s";
    }
    function fmtUptime(s: real): string {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return (d ? d + "d " : "") + (h || d ? h + "h " : "") + m + "m";
    }
}
