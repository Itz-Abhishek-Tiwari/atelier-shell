pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.config

// Privacy: which apps are using the microphone, the camera or the screen, read from PipeWire
// streams and from /dev/video* (modules/drawers/PrivacyOverlay.qml shows them; the bar pill lights up).
//
//   entries : [{ kind: "mic"|"camera"|"screen", name, pid, nodeId, muted }]
//   mic / camera / screen / any : what is in use
//
//   mic    : an app has an audio capture stream open
//   screen : a screencast stream exists (xdg-desktop-portal), or Atelier is recording
//   camera : an app has a camera open (a PipeWire video stream, or the V4L2 device itself) and no
//            screencast is running (a screen share is also a video stream, so they can't be told
//            apart while one is active)
Singleton {
    id: root

    readonly property var nodes: Pipewire.nodes.values.filter(n => n.isStream)
    // node properties (media.class, app name) are only filled in for bound nodes
    PwObjectTracker { objects: root.nodes }

    function cls(n) { return (n.properties || {})["media.class"] || ""; }
    function prop(n, k) { return (n.properties || {})[k] || ""; }
    // "PipeWire ALSA [code]" / "ALSA plug-in [firefox]" are the compatibility layer's names: use the real binary
    readonly property var pretty: ({ code: "VS Code", "code-oss": "VS Code", codium: "VSCodium", firefox: "Firefox",
        chrome: "Chrome", "google-chrome": "Chrome", chromium: "Chromium", vesktop: "Discord", discord: "Discord",
        spotify: "Spotify", obs: "OBS Studio", zoom: "Zoom", teams: "Teams" })
    function app(n) {
        const raw = prop(n, "application.name"), bin = prop(n, "application.process.binary");
        let name = raw || bin || n.description || n.name || "App";
        const m = raw.match(/\[(.+)\]/);
        if (/alsa|pulseaudio|pipewire/i.test(raw)) name = bin || (m ? m[1] : name);
        const base = name.split("/").pop();
        return pretty[base.toLowerCase()] || (base === base.toLowerCase() ? base.charAt(0).toUpperCase() + base.slice(1) : base);
    }
    function entry(kind, n) {
        return { kind: kind, name: app(n), pid: parseInt(prop(n, "application.process.id") || prop(n, "pipewire.sec.pid")) || 0,
                 nodeId: n.id, muted: !!(n.audio && n.audio.muted) };
    }

    // capture streams that only draw a level meter (volume controls) aren't listening
    readonly property var micList: nodes.filter(n => cls(n) === "Stream/Input/Audio"
        && prop(n, "stream.monitor") !== "true").map(n => entry("mic", n))
    readonly property var screenList: nodes.filter(n => cls(n) === "Stream/Output/Video").map(n => entry("screen", n))
        .concat(Recorder.recording ? [{ kind: "screen", name: "Atelier recorder", pid: 0, nodeId: -1, muted: false }] : [])

    // Apps that open a camera straight through V4L2 (Atelier's own camera drawer, ffmpeg, …) never
    // appear in PipeWire, so /dev/video* is polled with fuser. The ffmpeg that feeds the iPhone
    // placeholder picture into the loopback device is a writer, not a viewer, and is skipped.
    property var v4lList: []
    readonly property var cameraList: {
        const seen = {}, out = [];
        const add = e => { const k = e.pid || e.name; if (!seen[k]) { seen[k] = true; out.push(e); } };
        v4lList.forEach(add);
        if (screenList.length === 0) nodes.filter(n => cls(n) === "Stream/Input/Video").forEach(n => add(entry("camera", n)));
        return out;
    }

    readonly property var entries: micList.concat(cameraList, screenList)
    readonly property bool mic: micList.length > 0
    readonly property bool screen: screenList.length > 0
    readonly property bool camera: cameraList.length > 0
    readonly property bool any: entries.length > 0

    // one line per kind in use, for the bar tooltip
    function names(list) { return list.map(e => e.name).filter((a, i, l) => l.indexOf(a) === i).join(", "); }
    readonly property string summary: [
        mic ? "Microphone: " + names(micList) : "",
        camera ? "Camera: " + names(cameraList) : "",
        screen ? "Screen: " + names(screenList) : ""
    ].filter(l => l).join("\n")

    // ── controls ────────────────────────────────────────────────────────────
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: root.source ? [root.source] : [] }
    readonly property bool micMuted: !!(source && source.audio && source.audio.muted)
    function toggleMicMute() { if (source && source.audio) source.audio.muted = !source.audio.muted; }

    // silence one app's capture stream without closing the app
    function toggleStreamMute(e) {
        const n = Pipewire.nodes.values.find(x => x.id === e.nodeId);
        if (n && n.audio) n.audio.muted = !n.audio.muted;
    }
    // close the app using it (Atelier's own camera / recorder are stopped the proper way)
    function quit(e) {
        if (e.name === "Atelier recorder") Recorder.stop();
        else if (e.pid === Quickshell.processId) Quickshell.execDetached(["qs", "ipc", "call", "camera", "close"]);
        else if (e.pid > 0) Quickshell.execDetached(["kill", "-TERM", String(e.pid)]);
    }
    function canQuit(e) { return e.pid > 0 || e.name === "Atelier recorder"; }

    Process {
        id: v4lProbe
        command: ["sh", "-c", "for d in /dev/video*; do fuser \"$d\" 2>/dev/null; done | tr -s ' ' '\\n' | sort -un | while read p; do [ -n \"$p\" ] && echo \"$p $(cat /proc/$p/comm 2>/dev/null)\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").filter(l => l.trim()).map(l => {
                    const i = l.indexOf(" "), pid = parseInt(l.slice(0, i)), comm = l.slice(i + 1).trim();
                    return { kind: "camera", name: comm === "quickshell" ? "Atelier camera" : comm, pid: pid, nodeId: -1, muted: false, comm: comm };
                }).filter(e => e.comm !== "ffmpeg");
                if (JSON.stringify(list) !== JSON.stringify(root.v4lList)) root.v4lList = list;
            }
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: Settings.bar.showPrivacy
        triggeredOnStart: true
        onTriggered: if (!v4lProbe.running) v4lProbe.running = true
    }
}
