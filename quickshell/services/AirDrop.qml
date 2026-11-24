pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// AirDrop with iPhones through owly (github.com/t4t5/owly, AUR `owly`): owlyd runs the AWDL
// radio on the card named in /etc/owly/radio.toml (here the RTL8188FTV USB stick, exclusive
// mode, channel 6: the built-in ath10k drops AWDL action frames). This service holds
// `owly radio up` (the radio lease) and `owly receive` (interactive: it prints the request and
// waits for y/n on stdin), and runs `owly send`. modules/drawers/AirDropPopup.qml is the card.
//
// owly receive output (0.4.x):
//   "Abhishek’s iPhone" ("iPhone") wants to send:
//     "IMG.JPG" public.jpeg 2249275 bytes        (one line per file)
//   accept? [y/N]                                 (no newline: we act after the file lines)
//   /home/…/Downloads/AirDrop/IMG.JPG             (one line per saved file)
Singleton {
    id: root

    readonly property bool available: owlyCheck.found
    readonly property bool enabled: Settings.airdrop.enabled
    readonly property string folder: (Settings.airdrop.folder || "~/Downloads/AirDrop").replace(/^~/, Quickshell.env("HOME"))

    // radio: off | starting | up | error
    property string radioState: "off"
    property string error: ""
    property bool peerNearby: false        // an Apple device is talking AWDL with us right now

    // the current incoming request / transfer
    // phase: idle | asking | receiving | done | declined | failed
    property string phase: "idle"
    property string sender: ""
    property string senderModel: ""
    property var files: []                 // [{ name, type, bytes }]
    property var saved: []                 // paths written so far
    property double startedAt: 0
    property real progress: 0
    readonly property double totalBytes: files.reduce((a, f) => a + f.bytes, 0)
    // a 2.4 GHz-only stick gets 1-2 of the iPhone's 16 AWDL slots: ~35 kB/s
    readonly property real rate: 38000

    // sending: idle | choose | looking | sending | sent | failed
    //   choose: the card lists nearby receivers (owly browse) and waits for a click
    property string sendPhase: "idle"
    property string sendName: ""           // what's being sent (first file name)
    property int sendCount: 0
    property string sendError: ""
    property bool _radioForSend: false
    property var sendPaths: []             // files waiting for a device to be picked
    property var devices: []               // [{ mac, name }] answering /Discover, newest browse
    readonly property bool browsing: browseProc.running || (sendPhase === "choose" && radioState === "starting")

    readonly property string summary: !available ? "Install owly (AUR)"
        : radioState === "error" ? error
        : !enabled ? "Off"
        : radioState === "starting" ? "Starting…"
        : peerNearby ? "Receiving · iPhone nearby" : "Receiving from everyone"

    // ── words ──
    function kindOf(list) {
        const img = list.every(f => /^public\.(jpeg|png|heic|heif|tiff)|image/.test(f.type));
        const vid = list.every(f => /movie|mpeg-4|video|quicktime/.test(f.type));
        const n = list.length;
        if (img) return n === 1 ? "a photo" : n + " photos";
        if (vid) return n === 1 ? "a video" : n + " videos";
        return n === 1 ? "a file" : n + " items";
    }
    function sizeText(b) {
        return b >= 1e9 ? (b / 1e9).toFixed(1) + " GB" : b >= 1e6 ? (b / 1e6).toFixed(1) + " MB"
             : b >= 1e3 ? Math.round(b / 1e3) + " KB" : b + " B";
    }
    readonly property int secondsLeft: phase === "receiving"
        ? Math.max(1, Math.round(totalBytes * (1 - progress) / rate)) : 0

    // ── on / off ──
    function setEnabled(on: bool): void { Settings.airdrop.enabled = on; }
    function toggle(): void { setEnabled(!enabled); }
    onEnabledChanged: if (ready) _apply()
    // a shell restart leaves the previous instance's `owly radio up` / `owly receive` running,
    // holding the radio lease, and the new radio then never comes up ("Starting…" forever):
    // stop leftovers first (SIGINT gives the radio back cleanly), then start
    property bool ready: false
    Component.onCompleted: reaper.running = true
    Process {
        id: reaper
        command: ["sh", "-c", "pkill -INT -f '^(/usr/bin/)?owly (radio up|receive)' && sleep 3; true"]
        onExited: { root.ready = true; root._apply(); }
    }
    function _apply() {
        if (!available) return;
        if (enabled) { error = ""; retries = 0; _startRadio(); }
        else {
            receiver.running = false;
            if (!_radioForSend) _stopRadio();
            if (phase === "asking") phase = "idle";
        }
    }
    property int retries: 0
    function _startRadio() {
        if (radio.running) { if (radioState === "up") _startReceiver(); return; }
        radioState = "starting";
        radio.running = true;
    }
    function _stopRadio() {
        if (radio.running) radio.signal(2);   // SIGINT: owly gives the radio back cleanly
        else radioState = "off";
        peerNearby = false;
    }
    function _startReceiver() {
        if (!enabled || receiver.running) return;
        const cmd = ["owly", "receive", "--dir", folder];
        if (Settings.airdrop.name) cmd.push("--name", Settings.airdrop.name);
        receiver.command = cmd;
        mk.running = true;
        receiver.running = true;
    }

    // ── answering a request ──
    function accept(always: bool): void {
        if (phase !== "asking") return;
        if (always && sender && !(Settings.airdrop.trusted || []).includes(sender))
            Settings.airdrop.trusted = (Settings.airdrop.trusted || []).concat([sender]);
        receiver.write("y\n");
        phase = "receiving";
        startedAt = Date.now();
        progress = 0;
    }
    function decline(): void {
        if (phase !== "asking") return;
        receiver.write("n\n");
        phase = "declined";
        hideTimer.interval = 1600; hideTimer.restart();
    }
    function dismiss(): void {
        if (phase === "asking") { decline(); return; }
        if (phase !== "receiving") phase = "idle";
        if (sendPhase === "choose") cancelSend();
        else if (sendPhase !== "looking" && sendPhase !== "sending") sendPhase = "idle";
    }
    function openSaved(): void {
        if (saved.length === 1) Quickshell.execDetached(["xdg-open", saved[0]]);
        else showSaved();
        dismiss();
    }
    function showSaved(): void {
        // select the file in the file manager when it can, else open the folder
        const p = saved.length ? saved[0] : folder;
        Quickshell.execDetached(["sh", "-c",
            'dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 /org/freedesktop/FileManager1 '
            + 'org.freedesktop.FileManager1.ShowItems array:string:"file://$1" string:"" >/dev/null 2>&1 || xdg-open "$2"',
            "sh", p, folder]);
        dismiss();
    }

    // ── sending ──
    // pick a device first (the card shows the list), like the macOS share sheet
    function send(paths: var): void {
        if (!available || !paths || !paths.length) return;
        if (sendProc.running) return;
        sendPaths = paths;
        sendName = paths[0].split("/").pop();
        sendCount = paths.length;
        sendError = "";
        devices = [];
        sendPhase = "choose";
        browse();
    }
    function browse(): void {
        if (radioState === "up") { if (!browseProc.running) browseProc.running = true; }
        else { _radioForSend = true; _startRadio(); }      // browses once the radio is up
    }
    function sendTo(name: string): void {
        if (sendPhase !== "choose" || !sendPaths.length) return;
        browseProc.running = false;
        sendTarget = name;
        sendProgress = -1;
        sendError = "";
        sendPhase = "looking";
        sendProc.command = ["owly", "send", "--seconds", "40", "--to", name].concat(sendPaths);
        sendProc.running = true;
    }
    property string sendTarget: ""
    property real sendProgress: -1      // 0..1 while the upload runs, -1 before it starts
    // owly's upload progress ("65536 / 5326370 bytes") is \r-separated on ONE line, so it
    // arrives glued together; split it, and keep it out of sendError (it showed as the error).
    function _sendLine(line) {
        for (const part of line.split("\r")) {
            const s = part.trim();
            if (!s) continue;
            const p = s.match(/(\d+)\s*\/\s*(\d+)\s*bytes/);
            if (p) { sendPhase = "sending"; sendProgress = Math.min(1, +p[1] / Math.max(1, +p[2])); }
            else if (/error|fail|refus|declin|denied|timed? ?out|reset|closed/i.test(s)) sendError = s.replace(/^error:\s*/i, "");
            else if (/send|upload|accept|ask/i.test(s)) sendPhase = "sending";
        }
    }
    function cancelSend(): void {
        browseProc.running = false;
        if (sendProc.running) sendProc.signal(2);
        sendPhase = "idle";
        sendPaths = [];
        if (_radioForSend) { _radioForSend = false; if (!enabled) _stopRadio(); }
    }

    // ── processes ──
    Process {
        id: owlyCheck
        property bool found: false
        command: ["sh", "-c", "command -v owly"]
        running: true
        onExited: (code) => { found = code === 0; if (found && root.ready) Qt.callLater(root._apply); }
    }
    Process { id: mk; command: ["mkdir", "-p", root.folder] }

    Process {
        id: radio
        command: ["owly", "radio", "up"]
        stdout: SplitParser { onRead: (line) => root._radioLine(line) }
        stderr: SplitParser { onRead: (line) => root._radioLine(line) }
        onExited: (code) => root._radioExited(code)
    }
    function _radioLine(line) {
                if (line.indexOf("awdl0 is up") >= 0) {
                    root.radioState = "up"; root.retries = 0;
                    root._startReceiver();
                    if (root.sendPhase === "choose" && !browseProc.running) browseProc.running = true;
                } else if (line.startsWith("peers:")) {
                    root.peerNearby = line.indexOf("none") < 0;
                    peerTimer.restart();
                } else if (/doesn't exist|does not exist|no such device/i.test(line)) {
                    // the USB stick is unplugged (or its driver didn't attach after a reconnect)
                    root.error = "Plug in the AirDrop Wi-Fi stick";
                    root.stickPresent = false;
                } else if (/error|fail|can't|cannot|not found|denied/i.test(line)) {
                    root.error = line.trim().replace(/^error:\s*/i, "");
                }
    }
    function _radioExited(code) {
            receiver.running = false;
            root.peerNearby = false;
            if (root.enabled && root.retries < 3 && root.radioState !== "off") {
                // the stick was replugged, owlyd restarted…: try again a few times
                root.retries++;
                root.radioState = "starting";
                radioRetry.restart();
            } else {
                root.radioState = root.enabled && code !== 0 ? "error" : "off";
                if (root.radioState === "error" && !root.error) root.error = "The AirDrop radio stopped";
                if (root._radioForSend && (root.sendPhase === "looking" || root.sendPhase === "choose")) { root.sendPhase = "failed"; root.sendError = root.error || "The radio didn't start"; }
                root._radioForSend = false;
            }
    }
    // a retry first looks for the stick, and only starts the radio when it's there
    Timer { id: radioRetry; interval: 4000; onTriggered: if (root.enabled) stickCheck.running = true }
    // gave up while the stick IS there (owlyd hiccup…): try again now and then
    Timer {
        interval: 20000; repeat: true
        running: root.enabled && root.available && root.radioState === "error" && root.stickPresent
        onTriggered: { root.retries = 0; root.error = ""; root._startRadio(); }
    }

    // ── the USB stick coming and going ──
    // While the stick is unplugged, don't poke owly at all: a radio start that lands while
    // rtl8xxxu is still probing a just-replugged stick froze the driver until a reboot
    // (2026-11-22). Only watch for the interface (a sysfs test, touches nothing), and once it's
    // back give the driver a few seconds to settle before starting the radio.
    // "airdrop0" = station in /etc/owly/radio.toml (fixed name from 10-atelier-airdrop.link).
    property bool stickPresent: true
    Process {
        id: stickCheck
        command: ["test", "-e", "/sys/class/net/airdrop0"]
        onExited: (code) => {
            const there = code === 0;
            if (there && !root.stickPresent) { root.stickPresent = true; stickSettle.restart(); }
            else if (there) { if (root.enabled) radio.running = true; }
            else { root.stickPresent = false; root.radioState = "error"; root.error = "Plug in the AirDrop Wi-Fi stick"; }
        }
    }
    Timer {
        interval: 3000; repeat: true
        running: root.enabled && !root.stickPresent && !stickSettle.running
        onTriggered: stickCheck.running = true
    }
    Timer {
        id: stickSettle
        interval: 5000
        onTriggered: if (root.enabled) { root.retries = 0; root.error = ""; root._startRadio(); }
    }
    Timer { id: peerTimer; interval: 15000; onTriggered: root.peerNearby = false }

    Process {
        id: receiver
        stdinEnabled: true
        stdout: SplitParser { onRead: (line) => root._recvLine(line) }
        stderr: SplitParser { onRead: (line) => root._recvLine(line) }
        onExited: root._recvExited()
    }
    function _recvLine(line) {
                let m = line.match(/^"(.*)" \("(.*)"\) wants to send/);
                if (m) {
                    root.sender = m[1]; root.senderModel = m[2];
                    root.files = []; root.saved = []; root.progress = 0;
                    hideTimer.stop();
                    askTimer.restart();
                    return;
                }
                m = line.match(/^\s+"(.*)" (\S+) (\d+) bytes/);
                if (m && askTimer.running) {
                    root.files = root.files.concat([{ name: m[1], type: m[2], bytes: parseInt(m[3]) }]);
                    askTimer.restart();
                    return;
                }
                if (line.startsWith("/") && (root.phase === "receiving" || root.phase === "asking")) {
                    root.saved = root.saved.concat([line.trim()]);
                    if (root.saved.length >= Math.max(1, root.files.length)) {
                        root.phase = "done"; root.progress = 1;
                        hideTimer.interval = 12000; hideTimer.restart();
                    }
                    return;
                }
                if (root.phase === "receiving" && /error|fail|cancel|timed out/i.test(line)) {
                    root.phase = "failed"; root.error = line.trim();
                    hideTimer.interval = 6000; hideTimer.restart();
                }
    }
    function _recvExited() {
            if (root.phase === "asking" || root.phase === "receiving") { root.phase = "failed"; root.error = "The receiver stopped"; }
            // keep receiving while AirDrop is on and the radio is up
            if (root.enabled && root.radioState === "up") recvRetry.restart();
    }
    Timer { id: recvRetry; interval: 1500; onTriggered: root._startReceiver() }

    // the file list is done when no new line has come for a moment: ask (or trust)
    Timer {
        id: askTimer
        interval: 300
        onTriggered: {
            if ((Settings.airdrop.trusted || []).includes(root.sender)) {
                root.phase = "asking";
                root.accept(false);
            } else {
                root.phase = "asking";
                askExpire.restart();
            }
        }
    }
    // the iPhone gives up after about a minute; so do we
    Timer { id: askExpire; interval: 60000; onTriggered: if (root.phase === "asking") root.decline() }
    Timer {
        interval: 250; repeat: true
        running: root.phase === "receiving"
        onTriggered: {
            const t = (Date.now() - root.startedAt) / 1000;
            root.progress = Math.min(0.95, t * root.rate / Math.max(1, root.totalBytes));
            // nothing after 3× the estimate + a minute: call it stalled
            if (t > 60 + 3 * root.totalBytes / root.rate) { root.phase = "failed"; root.error = "The transfer stalled"; hideTimer.interval = 6000; hideTimer.restart(); }
        }
    }
    Timer { id: hideTimer; interval: 12000; onTriggered: if (root.phase !== "asking" && root.phase !== "receiving") root.phase = "idle" }

    // `owly browse`: one line per receiver, e.g.  ea:af:90:c0:8e:63 "Abhishek’s iPhone" ([fe80::…]:8770)
    Process {
        id: browseProc
        command: ["owly", "browse", "--seconds", "15"]
        stdout: SplitParser { onRead: (line) => root._browseLine(line) }
        stderr: SplitParser { onRead: (line) => root._browseLine(line) }
    }
    function _browseLine(line) {
        const m = line.match(/^([0-9a-f]{2}(?::[0-9a-f]{2}){5}) "(.*)"/i);
        if (!m || devices.some(d => d.name === m[2])) return;
        devices = devices.concat([{ mac: m[1], name: m[2] }]);
    }

    Process {
        id: sendProc
        stdout: SplitParser { onRead: (line) => root._sendLine(line) }
        stderr: SplitParser { onRead: (line) => root._sendLine(line) }
        onExited: (code) => {
            root.sendPhase = code === 0 ? "sent" : "failed";
            if (code !== 0 && !root.sendError)
                root.sendError = root.sendProgress >= 0 ? "The transfer stopped at " + Math.round(root.sendProgress * 100) + "%" : "No one accepted it";
            console.warn("airdrop send exited", code, "progress", root.sendProgress, "error:", root.sendError);
            sendHide.restart();
            if (root._radioForSend) { root._radioForSend = false; if (!root.enabled) root._stopRadio(); }
        }
    }
    Timer { id: sendHide; interval: 6000; onTriggered: if (root.sendPhase === "sent" || root.sendPhase === "failed") root.sendPhase = "idle" }
}
