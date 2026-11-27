pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Audio visualizer data from cava (backend/cava.conf): `bars` is a list of 0..1 levels,
// updated at 60 fps while `active`. cava only runs while something shows it (Now playing or
// fullscreen, with music playing); otherwise the bars ease back to zero and the process stops.
Singleton {
    id: root

    property bool active: false
    property var bars: []
    property string _last: ""
    readonly property int count: 48

    Process {
        id: proc
        running: root.active
        command: ["cava", "-p", Quickshell.shellDir + "/backend/cava.conf"]
        stdout: SplitParser {
            onRead: (line) => {
                // an unchanged frame (silence, a held note) would redraw for nothing: skip it
                if (line === root._last) return;
                root._last = line;
                const parts = line.split(";");
                const out = new Array(root.count);
                for (let i = 0; i < root.count; i++) out[i] = (parseInt(parts[i]) || 0) / 100;
                root.bars = out;
            }
        }
    }
    onActiveChanged: if (!active) { bars = []; _last = ""; }
}
