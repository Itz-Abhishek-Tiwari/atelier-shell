pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Plugged-in (hotplug) drives: USB sticks, external disks, SD cards in a USB reader.
//  - `drives` lists their filesystems; the control center shows them with Open / Eject
//  - a newly plugged one gets a notification with Open / Eject (Settings.drives.notify)
// udevadm reports plugs/unplugs; while any drive is listed it also re-reads every few
// seconds, since mounting from a file manager sends no udev event.
Singleton {
    id: root

    signal toast(string msg, string icon, color clr)

    property var drives: []        // [{ path, disk, label, size, mount }]
    property bool seeded: false    // the first scan only records what's already there
    readonly property string script: Quickshell.shellDir + "/scripts/drive.sh"

    function human(bytes): string {
        const b = Number(bytes) || 0;
        const u = ["B", "KB", "MB", "GB", "TB"];
        let i = 0, v = b;
        while (v >= 1000 && i < u.length - 1) { v /= 1000; i++; }
        return (v >= 10 || i === 0 ? Math.round(v) : v.toFixed(1)) + " " + u[i];
    }

    function parse(text: string): void {
        let devs = [];
        try { devs = JSON.parse(text).blockdevices || []; } catch (e) { return; }
        const models = {};
        for (const d of devs) if (d.type === "disk") models[d.name] = (d.model || "").trim();
        const list = devs.filter(d => (d.hotplug === true || d.hotplug === "1")
                                   && d.fstype && d.fstype !== "swap"
                                   && (d.type === "part" || d.type === "disk"))
            .map(d => ({ path: d.name, disk: d.pkname || d.name,
                         label: d.label || models[d.pkname || d.name] || "USB drive",
                         size: root.human(d.size), mount: d.mountpoint || "" }));
        if (seeded && Settings.drives.notify) {
            const before = drives.map(d => d.path);
            for (const d of list) if (before.indexOf(d.path) < 0)
                Quickshell.execDetached([root.script, "notify", d.path, d.label, d.size]);
        }
        drives = list;
        seeded = true;
    }

    function rescan(): void { if (!lsblk.running) lsblk.running = true; else again.restart(); }
    function open(d): void { Quickshell.execDetached([root.script, "open", d.path]); refresh.restart(); }
    function eject(d): void {
        if (ejecter.running) return;
        ejecter.label = d.label;
        ejecter.command = [root.script, "eject", d.path];
        ejecter.running = true;
    }

    Process {
        id: lsblk
        command: ["lsblk", "-J", "-l", "-p", "-b", "-o", "NAME,PKNAME,LABEL,SIZE,FSTYPE,MOUNTPOINT,HOTPLUG,TYPE,MODEL"]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }
    Process {
        id: ejecter
        property string label
        onExited: (code) => {
            if (code === 0) root.toast(label + " can be removed", "󱊞", Atelier.green);
            else if (code === 2) root.toast(label + " is still in use", "󰀦", Atelier.peach);
            else root.toast("Couldn't eject " + label, "󰀦", Atelier.red);
            root.rescan();
        }
    }
    // block-device events: debounce, then re-read (one plug fires several)
    Process {
        id: watch
        running: true
        // exits with the shell: a bare udevadm outlived a killed/crashed shell (reparented to init)
        command: ["sh", "-c", 'udevadm monitor --udev --subsystem-match=block & m=$!; while kill -0 "$PPID" 2>/dev/null; do sleep 5; done; kill "$m"']
        stdout: SplitParser { onRead: (line) => { if (/\b(add|remove|change)\b/.test(line)) again.restart(); } }
        onExited: restartWatch.restart()
    }
    Timer { id: restartWatch; interval: 5000; onTriggered: watch.running = true }
    Timer { id: again; interval: 700; onTriggered: root.rescan() }
    Timer { id: refresh; interval: 1500; onTriggered: root.rescan() }
    Timer { running: root.drives.length > 0; interval: 5000; repeat: true; onTriggered: root.rescan() }
    Component.onCompleted: rescan()
}
