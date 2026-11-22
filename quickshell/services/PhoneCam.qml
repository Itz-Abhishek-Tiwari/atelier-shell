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
    readonly property bool running: proc.running || retryTimer.running
    readonly property bool live: state === "live"
    readonly property string linkLabel: ({ usb: "USB", hotspot: "Hotspot", wifi: "Wi-Fi" })[link] || ""
    readonly property string summary: state === "live" ? "Live · " + linkLabel
        : state === "connecting" && retries > 0 ? "Reconnecting (" + retries + "/" + maxRetries + ")"
        : state === "connecting" ? "Connecting" + (linkLabel ? " · " + linkLabel : "…")
        : state === "error" ? error : "Off"

    // auto-reconnect: a stream that was live and dropped (phone locked, Wi-Fi blip) is retried
    // a few times before giving up; `retries` > 0 while that's going on
    property int retries: 0
    readonly property int maxRetries: 3
    property bool _stopping: false
    property bool _wasLive: false

    function start(who: string): void {
        if (proc.running) return;
        _begin(who);
    }
    function _begin(who: string): void {
        owner = who || "user";
        error = "";
        link = "";
        state = "connecting";
        _stopping = false;
        _wasLive = false;
        persist.wasRunning = true;
        persist.wasOwner = owner;
        proc.command = [Quickshell.shellDir + "/scripts/iphonecam.sh", "run",
                        Settings.phone.mode || "auto", Settings.phone.wifiAddress || ""];
        proc.running = true;
    }
    function stop(): void {
        _stopping = true;
        retryTimer.stop();
        retries = 0;
        persist.wasRunning = false;
        if (proc.running) proc.signal(15);
        reaper.running = true;               // and anything orphaned by an earlier crash
        state = "off";
        owner = "";
    }
    // manual retry (drawer button): a fresh run with a fresh retry budget
    function retry(who: string): void {
        retries = 0;
        retryTimer.stop();
        if (proc.running) { _stopping = true; proc.signal(15); restartAfterExit.who = who || owner || "user"; restartAfterExit.pending = true; }
        else _begin(who || owner || "user");
    }
    function toggle(): void { if (proc.running || retryTimer.running) stop(); else start("user"); }
    // the drawer closing: stop only what the drawer itself started
    function release(who: string): void { if (owner === who) stop(); }

    // the stream survives a shell reload: Processes die with the old config, so remember it was on
    PersistentProperties {
        id: persist
        reloadableId: "phonecam"
        property bool wasRunning: false
        property string wasOwner: ""
    }
    QtObject { id: restartAfterExit; property bool pending: false; property string who: "" }
    Timer {
        id: retryTimer
        interval: 2500
        onTriggered: root._begin(root.owner || "user")
    }

    // a shell crash leaves the stream's iproxy/ffmpeg running and holding the phone: clear them
    Process { id: reaper; command: [Quickshell.shellDir + "/scripts/iphonecam.sh", "reap"] }
    // at start-up also clear an orphaned placeholder, then start ours (or resume the stream)
    Process {
        id: startReaper
        command: [Quickshell.shellDir + "/scripts/iphonecam.sh", "reap", "all"]
        onExited: {
            // start the stream before `ready`, so the placeholder never grabs /dev/video11 first
            if (persist.wasRunning) root._begin(persist.wasOwner === "drawer" ? "user" : (persist.wasOwner || "user"));
            root.ready = true;
        }
    }
    Component.onCompleted: startReaper.running = true
    property bool ready: false

    // Placeholder for /dev/video11 ("iPhone Camera (Atelier)", exclusive_caps=0): Qt lists a
    // loopback camera only if video is flowing when it first looks, and never looks again in a
    // running shell. So a dark 1280×720 frame twice a second (≈0 CPU) keeps it listed; the real
    // iPhone video replaces it while connected (same size/format, see iphonecam.sh).
    Process {
        id: placeholder
        running: root.ready && !root.running
        command: ["ffmpeg", "-hide_banner", "-loglevel", "error", "-re", "-f", "lavfi", "-i", "color=c=0x11111b:s=1280x720:r=2",
                  "-pix_fmt", "yuv420p", "-f", "v4l2", "/dev/video11"]
    }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("S connecting ")) { root.state = "connecting"; root.link = line.slice(13); }
                else if (line.startsWith("S live ")) { root.state = "live"; root.link = line.slice(7); root.error = ""; root._wasLive = true; root.retries = 0; }
                else if (line.startsWith("E ")) { root.state = "error"; root.error = line.slice(2); }
            }
        }
        onExited: {
            if (restartAfterExit.pending) {
                restartAfterExit.pending = false;
                root._begin(restartAfterExit.who);
                return;
            }
            if (root._stopping) { root.state = "off"; root.owner = ""; return; }
            // dropped (or never got there): retry while there's budget, keeping the owner
            if ((root._wasLive || root.retries > 0) && root.retries < root.maxRetries) {
                root.retries++;
                root.state = "connecting";
                root.error = "";
                retryTimer.restart();
                return;
            }
            if (root.state !== "error") { root.state = "error"; root.error = "Lost the iPhone: keep DroidCam open and the phone unlocked"; }
            root.retries = 0;
            root.owner = "";
            persist.wasRunning = false;
        }
    }
}
