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
    property real _startedAt: 0
    property int _exitCode: 0
    readonly property string elapsedText: Math.floor(elapsed / 60) + ":" + String(elapsed % 60).padStart(2, "0")

    signal finished(string path, int seconds)
    signal failed(string reason)

    function folder() { return Settings.expand(Settings.recorder.folder); }

    // monitor: output name; geometry: "x,y wxh" in global layout pixels, or "" for the whole monitor
    function start(monitor, geometry) {
        if (recording || proc.running) return;
        const file = folder() + "/Recording_" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".mp4";
        proc.command = [Quickshell.shellDir + "/scripts/record.sh", file, monitor, geometry || "",
                        Settings.recorder.audio, String(Settings.recorder.fps)];
        proc.running = true;
    }
    function stop() { if (proc.running) proc.signal(2); }   // SIGINT: wf-recorder finalises the file

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
