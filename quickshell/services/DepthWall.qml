pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Subject cut-out of the current wallpaper, for the "Depth" lock screen (Samsung-style: the
// clock sits behind the wallpaper's subject). scripts/depth.py does the work (IS-Net on
// onnxruntime, cached per wallpaper in ~/.cache/atelier/depth), so the lock itself never waits:
// the cut-out is made in the background whenever the wallpaper changes while Depth is in use.
Singleton {
    id: root

    readonly property bool wanted: Settings.lock.theme === "depth"
    readonly property string script: Quickshell.shellDir + "/scripts/depth.py"

    // result for Wallpaper.current
    property string forWall: ""
    property bool ok: false
    property string cutout: ""             // RGBA png, same aspect as the wallpaper
    property var profile: []               // 64 columns: top of the subject (0..1 of height), 1 = none
    property string error: ""
    property string hint: ""
    property string ink: ""                // clock colour picked from the wallpaper ("" = theme ink)
    property bool inkDark: false           // true = a dark ink (bright sky behind the clock)
    readonly property bool busy: cutProc.running

    // what's installed
    property bool hasRuntime: false
    property bool hasModel: false
    readonly property bool installed: hasRuntime && hasModel
    property bool settingUp: false
    property string setupStep: ""          // runtime | model
    property real setupProgress: 0

    function refresh(): void {
        if (!statusProc.running) statusProc.running = true;
    }
    function rebuild(): void {
        if (!wanted || !Wallpaper.current) return;
        if (cutProc.running) { pending = true; return; }
        cutProc.wall = Wallpaper.current;
        cutProc.command = ["nice", "-n", "15", script, "cutout", Wallpaper.current];
        cutProc.running = true;
    }
    function setup(): void {
        if (settingUp) return;
        settingUp = true;
        setupStep = "";
        setupProgress = 0;
        error = "";
        setupProc.running = true;
    }

    property bool pending: false
    Component.onCompleted: { refresh(); if (wanted) rebuild(); }
    onWantedChanged: if (wanted) { refresh(); rebuild(); }
    Connections {
        target: Wallpaper
        function onCurrentChanged() { if (root.wanted) wallDebounce.restart(); }
    }
    // a wallpaper change animates for a moment: don't fight it for the CPU
    Timer { id: wallDebounce; interval: 1500; onTriggered: root.rebuild() }

    Process {
        id: statusProc
        command: [root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.hasRuntime = !!d.onnxruntime;
                    root.hasModel = !!d.model;
                } catch (e) {}
            }
        }
    }

    Process {
        id: cutProc
        property string wall: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(text.trim().split("\n").pop()); } catch (e) {}
                root.forWall = cutProc.wall;
                root.ok = !!(d && d.ok);
                root.cutout = root.ok ? d.cutout : "";
                root.profile = root.ok ? d.profile : [];
                root.error = d ? (d.error || "") : "depth.py failed";
                root.hint = d ? (d.hint || "") : "";
                root.ink = d && d.ink ? d.ink : "";
                root.inkDark = !!(d && d.inkDark);
            }
        }
        onExited: if (root.pending) { root.pending = false; root.rebuild(); }
    }

    Process {
        id: setupProc
        command: [root.script, "setup"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("S ")) root.setupStep = line.slice(2);
                else if (line.startsWith("P ")) root.setupProgress = parseFloat(line.slice(2)) || 0;
                else if (line.startsWith("{")) {
                    try { const d = JSON.parse(line); if (!d.ok) { root.error = d.error || ""; root.hint = d.hint || ""; } } catch (e) {}
                }
            }
        }
        onExited: {
            root.settingUp = false;
            root.refresh();
            root.rebuild();
        }
    }
}
