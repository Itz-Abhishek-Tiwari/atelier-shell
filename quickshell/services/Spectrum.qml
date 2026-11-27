pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Audio spectrum for the edge visualizer (modules/spectrum/EdgeSpectrum.qml): `bars` is a list
// of 0..1 levels at 60 fps while `active`. cava (scripts/cava-spectrum.conf) runs only then:
// about 3 % of one core while music plays and the strip is shown, nothing otherwise.
Singleton {
    id: root

    property bool active: false
    property var bars: []
    property string _last: ""
    readonly property int count: 64

    Process {
        id: proc
        running: root.active
        command: ["cava", "-p", Quickshell.shellDir + "/scripts/cava-spectrum.conf"]
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
