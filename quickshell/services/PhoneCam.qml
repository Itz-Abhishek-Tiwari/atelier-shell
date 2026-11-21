pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// iPhone as a webcam ("iPhone Camera", /dev/video10), run by scripts/iphonecam.sh.
// Started from the camera drawer, the control center or IPC (`phonecam`); the link is picked
// automatically: USB cable → iPhone hotspot → the phone on Wi-Fi (Settings.phone.mode).
// `owner` lets the camera drawer stop it on close only when the drawer was what started it,
// so a stream started for OBS/Discord from the control center keeps running.
Singleton {
    id: root

    readonly property string device: "/dev/video10"
    readonly property string deviceName: "iPhone Camera"
    property string state: "off"       // off | connecting | live | error
    property string link: ""           // usb | hotspot | wifi
    property string error: ""
    property string owner: ""
    readonly property bool running: proc.running
    readonly property bool live: state === "live"
    readonly property string linkLabel: ({ usb: "USB", hotspot: "Hotspot", wifi: "Wi-Fi" })[link] || ""
    readonly property string summary: state === "live" ? "Live · " + linkLabel
        : state === "connecting" ? "Connecting" + (linkLabel ? " · " + linkLabel : "…")
        : state === "error" ? error : "Off"

    function start(who: string): void {
        if (proc.running) return;
        owner = who || "user";
        error = "";
        link = "";
        state = "connecting";
        proc.command = [Quickshell.shellDir + "/scripts/iphonecam.sh", "run",
                        Settings.phone.mode || "auto", Settings.phone.wifiAddress || ""];
        proc.running = true;
    }
    function stop(): void {
        if (proc.running) proc.signal(15);
        reaper.running = true;               // and anything orphaned by an earlier crash
        state = "off";
        owner = "";
    }
    function toggle(): void { if (proc.running) stop(); else start("user"); }
    // the drawer closing: stop only what the drawer itself started
    function release(who: string): void { if (owner === who) stop(); }

    // a shell crash leaves the stream's iproxy/ffmpeg running and holding the phone: clear them
    Process { id: reaper; command: [Quickshell.shellDir + "/scripts/iphonecam.sh", "reap"] }
    // at start-up also clear an orphaned placeholder, then start ours
    Process {
        id: startReaper
        command: [Quickshell.shellDir + "/scripts/iphonecam.sh", "reap", "all"]
        onExited: root.ready = true
    }
    Component.onCompleted: startReaper.running = true
    property bool ready: false

    // Placeholder for /dev/video11 ("iPhone Camera (Atelier)", exclusive_caps=0): Qt lists a
    // loopback camera only if video is flowing when it first looks, and never looks again in a
    // running shell. So a dark 1280×720 frame twice a second (≈0 CPU) keeps it listed; the real
    // iPhone video replaces it while connected (same size/format, see iphonecam.sh).
    Process {
        id: placeholder
        running: root.ready && !proc.running
        command: ["ffmpeg", "-hide_banner", "-loglevel", "error", "-re", "-f", "lavfi", "-i", "color=c=0x11111b:s=1280x720:r=2",
                  "-pix_fmt", "yuv420p", "-f", "v4l2", "/dev/video11"]
    }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("S connecting ")) { root.state = "connecting"; root.link = line.slice(13); }
                else if (line.startsWith("S live ")) { root.state = "live"; root.link = line.slice(7); root.error = ""; }
                else if (line.startsWith("E ")) { root.state = "error"; root.error = line.slice(2); }
            }
        }
        onExited: {
            if (root.state !== "error") root.state = "off";
            root.owner = "";
        }
    }
}
