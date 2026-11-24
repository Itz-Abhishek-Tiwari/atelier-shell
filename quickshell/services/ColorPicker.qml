pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Screen colour picker: slurp point → grim pixel (scripts/colorpick.py, no extra packages).
// The picked colour is copied as #hex and kept in a short history (statePath colors.json).
//
//   qs ipc call colorpicker pick | toggle (history drawer) | last
Singleton {
    id: root

    signal picked(string hex)
    signal toast(string msg, string icon, color clr)

    property bool picking: false
    property var history: []            // newest first, #rrggbb
    readonly property string last: history.length ? history[0] : ""

    function pick(): void {
        if (picking) return;
        picking = true;
        toast("Click any pixel to pick its colour  ·  Esc cancels", "󰈈", Atelier.pink);
        proc.running = true;
    }
    function copy(hex: string): void {
        Quickshell.execDetached(["wl-copy", hex]);
    }
    function remember(hex: string): void {
        history = [hex].concat(history.filter(h => h !== hex)).slice(0, 24);
        save.restart();
    }
    function clear(): void { history = []; save.restart(); }

    function rgb(hex: string): var {
        return [parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16)];
    }
    function hsl(hex: string): string {
        const [r, g, b] = rgb(hex).map(v => v / 255);
        const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, d = mx - mn;
        let h = 0, s = 0;
        if (d) {
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
            h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
            h *= 60;
        }
        return "hsl(" + Math.round(h) + ", " + Math.round(s * 100) + "%, " + Math.round(l * 100) + "%)";
    }
    function rgbText(hex: string): string { return "rgb(" + rgb(hex).join(", ") + ")"; }

    Process {
        id: proc
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/colorpick.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.picking = false;
                const hex = text.trim();
                if (/^#[0-9a-f]{6}$/.test(hex)) {
                    root.remember(hex);
                    root.copy(hex);
                    root.picked(hex);
                    root.toast(hex + " copied", "󰈈", hex);
                } else {
                    root.toast("Colour pick cancelled", "󰈈", Atelier.subtext);
                }
            }
        }
        onExited: root.picking = false
    }

    Timer { id: save; interval: 300; onTriggered: file.setText(JSON.stringify(root.history)) }
    FileView {
        id: file
        printErrors: false
        path: Quickshell.statePath("colors.json")
        onLoaded: { try { root.history = JSON.parse(text()).filter(h => /^#[0-9a-f]{6}$/.test(h)); } catch (e) {} }
    }
}
