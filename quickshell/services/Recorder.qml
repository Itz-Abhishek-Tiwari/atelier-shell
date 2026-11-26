pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Screen recording with wf-recorder (scripts/record.sh: VAAPI on the integrated GPU, software
// fallback). Started from the screenshot picker's Record toggle, Super+Shift+R, the control
// center or IPC; while it runs the bar shows a red dot + timer (click to stop).
//
//   qs ipc call record toggle|region|window|screen|stop|isRecording|last
Singleton {
    id: root

    property bool recording: false
    property bool available: true          // false once wf-recorder turned out to be missing
    property string lastPath: ""
    property int elapsed: 0                // seconds
    property bool gifNext: false           // the next recording is converted to a GIF (bug reports) and copied
    property bool _gif: false
    property string _src: ""
    property real _startedAt: 0
    property int _exitCode: 0
    readonly property string elapsedText: Math.floor(elapsed / 60) + ":" + String(elapsed % 60).padStart(2, "0")

    signal finished(string path, int seconds)
    signal failed(string reason)

    function folder() { return Settings.expand(Settings.recorder.folder); }

    // monitor: output name; geometry: "x,y wxh" in global layout pixels, or "" for the whole monitor
    function start(monitor, geometry) {
        if (recording || proc.running) return;
        _gif = gifNext;
        gifNext = false;
        const file = _gif ? Quickshell.cachePath("gif-source.mp4")
                          : folder() + "/Recording_" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".mp4";
        _src = file;
        proc.command = [Quickshell.shellDir + "/scripts/record.sh", file, monitor, geometry || "",
                        _gif ? "none" : Settings.recorder.audio, _gif ? "30" : String(Settings.recorder.fps)];
        proc.running = true;
    }
    function stop() { if (proc.running) proc.signal(2); }   // SIGINT: wf-recorder finalises the file

    // mp4 → GIF (15 fps, max 960 px wide, per-clip palette), copied to the clipboard as a file
    function toGif(src) {
        const dst = folder() + "/Recording_" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".gif";
        gifProc.dst = dst;
        gifProc.command = ["sh", "-c",
            'mkdir -p "$(dirname "$2")" && ffmpeg -y -loglevel error -i "$1" -vf "fps=15,scale=\'min(960,iw)\':-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" "$2" && rm -f "$1" && ' +
            'printf "file://%s\\n" "$2" | wl-copy -t text/uri-list; echo "$2"', "sh", src, dst];
        gifProc.running = true;
    }
    Process {
        id: gifProc
        property string dst: ""
        stdout: StdioCollector { id: gifOut }
        onExited: (code) => {
            const p = gifOut.text.trim().split("\n").pop();
            if (code === 0 && p) { root.lastPath = p; root.finished(p, root.elapsed); }
            else root.failed("GIF conversion failed (is ffmpeg installed?)");
        }
    }

    Process {
        id: proc
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onStarted: { root._startedAt = Date.now(); root.elapsed = 0; root.recording = true; }
        onExited: (code) => { root._exitCode = code; root.recording = false; report.restart(); }
    }
    // give the collectors a moment to flush after the exit
    Timer {
        id: report
        interval: 120
        onTriggered: {
            const path = out.text.trim().split("\n").pop();
            if (path) {
                root.available = true;
                if (root._gif) { root.toGif(path); return; }
                root.lastPath = path;
                root.finished(path, root.elapsed);
            } else if (root._exitCode === 127) {
                root.available = false;
                root.failed("Install wf-recorder to record the screen");
            } else {
                root.failed((err.text.trim().split("\n").pop() || "Recording failed").slice(0, 80));
            }
        }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.elapsed = Math.round((Date.now() - root._startedAt) / 1000)
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v wf-recorder"]
        onExited: (code) => root.available = code === 0
    }
}
