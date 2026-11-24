import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// Camera drawer (Super+Shift+C, IPC `camera`): grows out of the top edge, under the webcam.
// Phone-camera layout: the picture fills the drawer, controls float over it on soft fades.
//   top     Laptop / iPhone switch · format badge / REC timer · adjust, timer, grid, mirror, help
//   bottom  gallery · zoom pills · PHOTO / VIDEO · shutter · switch camera
//   Keys: Space/Enter shutter · Tab mode · I iPhone/laptop · A gallery · +/- zoom · 0 reset zoom
//         B brightness & quality · T timer · G grid · M mirror · O folder · ? shortcuts · Esc
// The camera lives in a Loader that's only active while the drawer is visible (webcam light off
// when closed, and while the gallery is open). iPhone: services/PhoneCam.qml → "iPhone Camera
// (Atelier)" (/dev/video11). Zoom is digital: the preview scales, and a photo is cropped to match
// afterwards (scripts/camera-gallery.sh zoom); video is never zoomed, so zoom is photo-only.
// Brightness / resolution apply to the laptop camera (v4l2 controls); the iPhone's are in DroidCam.
// Photos/videos go to ~/Pictures/Camera; a photo is also copied to the clipboard.
Item {
    id: camRoot
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool isLight: Atelier.isLight
    property bool animActive: false
    signal closedSignal()

    readonly property string dir: (Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")) + "/Camera"
    readonly property string helper: Quickshell.shellDir + "/scripts/camera-gallery.sh"
    property string lastShot: ""            // newest photo/video path (kept across openings)
    property bool lastIsVideo: false
    property double shotStamp: 0            // bumps image caches when a file is rewritten (zoom crop)
    property bool grid: false               // rule-of-thirds overlay (kept across openings)
    property int laptopWidth: 0             // chosen laptop resolution width, 0 = best
    property bool gallery: false            // gallery view instead of the camera

    property double openedAt: 0
    function fresh() { return Date.now() - openedAt < 350; }
    function toggle() { if (visible && animActive) close(); else open(); }
    function open() {
        openedAt = Date.now();
        gallery = false;
        visible = true;
        animActive = true;
    }
    // straight to the gallery (IPC `camera gallery`); the camera never starts
    function showGallery() {
        gallery = true;
        if (cam.item) cam.item.loadShots();
    }
    function close() {
        PhoneCam.release("drawer");          // stop the iPhone stream if this drawer started it
        if (cam.item && cam.item.recording) cam.item.stopRecording();
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }

    // rebuild the camera part when the iPhone goes live/stops, so the new device is picked up
    property bool rebuilding: false
    property int rebuildTries: 0
    Connections {
        target: PhoneCam
        function onLiveChanged() { camRoot.rebuildTries = 0; if (camRoot.visible && !camRoot.gallery) camRoot.rebuild(); }
    }
    Timer { id: rebuildTimer; interval: 900; onTriggered: camRoot.rebuilding = false }
    function rebuild() { rebuilding = true; rebuildTimer.restart(); }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!camRoot.animActive) camRoot.visible = false }

    // click outside closes
    MouseArea { anchors.fill: parent; onClicked: camRoot.close() }

    EdgeDrawer {
        id: drawer
        edge: "top"
        open: camRoot.animActive
        bodyWidth: Math.min(camRoot.width - 160, 960)
        bodyHeight: Math.min(camRoot.height - 120, Math.round((bodyWidth - 16) * 9 / 16) + 16)

        MouseArea { anchors.fill: parent }      // clicks inside stay inside

        Loader {
            id: cam
            anchors.fill: parent
            anchors.margins: 8
            active: camRoot.visible && !camRoot.rebuilding
            focus: true
            sourceComponent: Component {
                Item {
                    id: win
                    function stopRecording() { recorder.stop(); }

                    // ── state ──
                    property string mode: "photo"          // photo | video
                    property int timer: 0                  // 0 | 3 | 10 s
                    property string source: PhoneCam.live ? "iphone" : "laptop"
                    property bool mirror: source !== "iphone"   // selfie cam mirrored, the iPhone's back camera not
                    property int countdown: 0
                    property string status: ""
                    property bool statusBad: false
                    property bool showHelp: false
                    property bool showAdjust: false
                    property string camError: ""           // laptop camera failed (busy in another app, …)
                    property bool slow: false              // laptop camera hasn't started after a while
                    property real zoom: 1
                    property real pinchBase: 1
                    readonly property bool canZoom: mode === "photo" && !recording
                    readonly property bool recording: recorder.recorderState === MediaRecorder.RecordingState

                    // modprobe may leave quotes, and card_label can't hold spaces, so the labels are
                    // "iPhone_Camera" / "iPhone_Camera_Atelier": compare as "iPhone Camera [Atelier]"
                    function clean(d) { return d.description.replace(/["()]/g, "").replace(/_/g, " ").replace(/\s+/g, " ").trim(); }
                    readonly property var phoneDev: devices.videoInputs.find(d => clean(d) === PhoneCam.deviceName + " Atelier")
                                                  || devices.videoInputs.find(d => clean(d) === PhoneCam.deviceName)
                    readonly property var laptopDev: devices.videoInputs.find(d => !clean(d).startsWith(PhoneCam.deviceName)) || devices.defaultVideoInput
                    readonly property var activeDev: source === "iphone" ? phoneDev : laptopDev
                    readonly property bool showing: camera.active && (source === "laptop" || PhoneCam.live) && !camRoot.gallery
                    // the iPhone is live but its video never showed up in Qt, even after rebuilding
                    readonly property bool stuck: source === "iphone" && PhoneCam.live && camRoot.rebuildTries > 4 && !showing
                    onShowingChanged: if (showing) { slow = false; camError = ""; }

                    function setZoom(z) {
                        if (!canZoom) return;
                        zoom = Math.max(1, Math.min(4, Math.round(z * 100) / 100));
                    }
                    onModeChanged: if (mode === "video") zoom = 1

                    function pickSource(s) {
                        if (recording || s === source) return;
                        source = s;
                        mirror = s === "laptop";
                        zoom = 1;
                        showAdjust = false;
                        if (s === "iphone" && !PhoneCam.running) PhoneCam.start("drawer");
                    }
                    function retry() {
                        camError = ""; slow = false;
                        camRoot.rebuildTries = 0;
                        if (source === "iphone" && (!PhoneCam.live || stuck)) PhoneCam.retry("drawer");
                        else camRoot.rebuild();
                    }
                    function stamp() { return Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss"); }
                    function shutter() {
                        if (countdown > 0) { countdown = 0; countTimer.stop(); return; }   // cancel a countdown
                        if (mode === "video" && recording) { recorder.stop(); return; }
                        if (!showing) return;
                        if (timer > 0) { countdown = timer; countTimer.start(); return; }
                        fire();
                    }
                    property real shotZoom: 1
                    function fire() {
                        if (mode === "photo") {
                            flash.restart();
                            shotZoom = zoom;
                            imageCapture.captureToFile(camRoot.dir + "/Photo_" + stamp() + ".jpg");
                        } else {
                            recorder.outputLocation = "file://" + camRoot.dir + "/Video_" + stamp() + ".mp4";
                            recorder.record();
                        }
                    }
                    function photoDone(path) {
                        camRoot.lastShot = path; camRoot.lastIsVideo = false;
                        camRoot.shotStamp = Date.now();
                        thumbPop.restart();
                        Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/jpeg < "$1"', "sh", path]);
                        say("Saved · copied to clipboard");
                        loadShots();
                    }
                    function say(t, bad) { status = t; statusBad = !!bad; statusTimer.restart(); }

                    // ── gallery data ──
                    property var shots: []                 // [{ type, path, thumb }], newest first
                    property int shotIndex: 0
                    readonly property var shot: shots.length ? shots[Math.min(shotIndex, shots.length - 1)] : null
                    function loadShots() { if (!listProc.running) listProc.running = true; else listAgain = true; }
                    property bool listAgain: false
                    function openGallery(i) {
                        if (recording) return;
                        countdown = 0; countTimer.stop();
                        showHelp = false; showAdjust = false;
                        shotIndex = i || 0;
                        camRoot.gallery = true;
                        loadShots();
                    }
                    function closeGallery() { camRoot.gallery = false; }
                    function step(d) { if (shots.length) shotIndex = (shotIndex + d + shots.length) % shots.length; }
                    function copyShot() {
                        if (!shot) return;
                        if (shot.type === "photo")
                            Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/jpeg < "$1"', "sh", shot.path]);
                        else
                            Quickshell.execDetached(["sh", "-c", 'printf "file://%s\\n" "$1" | wl-copy --type text/uri-list', "sh", shot.path]);
                        say(shot.type === "photo" ? "Photo copied" : "Video copied as a file");
                    }
                    function trashShot() {
                        if (!shot) return;
                        trashProc.command = ["gio", "trash", "--", shot.path];
                        trashProc.running = true;
                    }

                    Process {
                        id: listProc
                        command: [camRoot.helper, "list", camRoot.dir]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                const out = [];
                                for (const l of text.split("\n")) {
                                    const p = l.split("\t");
                                    if (p.length >= 3 && p[1]) out.push({ type: p[0], path: p[1], thumb: p[2] });
                                }
                                win.shots = out;
                                if (win.shotIndex >= out.length) win.shotIndex = Math.max(0, out.length - 1);
                                if (out.length) {
                                    if (camRoot.lastShot === "" || !out.some(s => s.path === camRoot.lastShot)) {
                                        camRoot.lastShot = out[0].path; camRoot.lastIsVideo = out[0].type === "video";
                                    }
                                } else { camRoot.lastShot = ""; }
                                if (camRoot.gallery && !out.length) win.closeGallery();
                            }
                        }
                        onExited: if (win.listAgain) { win.listAgain = false; running = true; }
                    }
                    Process {
                        id: trashProc
                        onExited: (code) => { win.say(code === 0 ? "Moved to trash" : "Couldn't delete it", code !== 0); win.loadShots(); }
                    }
                    Process {
                        id: zoomProc
                        property string path: ""
                        onExited: win.photoDone(path)
                    }

                    Process { running: true; command: ["mkdir", "-p", camRoot.dir]; onExited: win.loadShots() }
                    Timer { id: countTimer; interval: 1000; repeat: true
                        onTriggered: { win.countdown--; if (win.countdown <= 0) { stop(); win.fire(); } } }
                    Timer { id: statusTimer; interval: 2600; onTriggered: win.status = "" }
                    // iPhone live but not listed yet / camera didn't start: rebuild (bounded)
                    Timer {
                        interval: 1800; repeat: true
                        running: win.source === "iphone" && PhoneCam.live && !camRoot.gallery && (!win.phoneDev || !camera.active)
                        onTriggered: { if (++camRoot.rebuildTries <= 4) camRoot.rebuild(); }
                    }
                    // laptop camera taking too long (another app may hold it)
                    Timer {
                        interval: 7000
                        running: win.source === "laptop" && !win.showing && !camRoot.gallery && win.camError === "" && !win.slow
                        onTriggered: win.slow = true
                    }

                    // ── laptop camera controls (v4l2) ──
                    readonly property string laptopPath: laptopDev && laptopDev.id ? laptopDev.id.toString() : ""
                    property int brMin: 0
                    property int brMax: 255
                    property int brDef: 128
                    property int brVal: -1                 // -1 = not read yet / no control
                    Process {
                        id: brRead
                        command: ["sh", "-c", 'v4l2-ctl -d "$1" -l 2>/dev/null | grep -E "^ *brightness "', "sh", win.laptopPath]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                const g = k => { const m = text.match(new RegExp(k + "=(-?\\d+)")); return m ? parseInt(m[1]) : NaN; };
                                if (isNaN(g("value"))) { win.brVal = -1; return; }
                                win.brMin = g("min"); win.brMax = g("max"); win.brDef = g("default"); win.brVal = g("value");
                            }
                        }
                    }
                    Timer {
                        id: brWrite
                        interval: 70
                        onTriggered: if (win.laptopPath && win.brVal >= 0)
                            Quickshell.execDetached(["v4l2-ctl", "-d", win.laptopPath, "-c", "brightness=" + win.brVal])
                    }
                    function setBrightness(v) {
                        brVal = Math.round(Math.max(brMin, Math.min(brMax, v)));
                        brWrite.restart();
                    }
                    onShowAdjustChanged: if (showAdjust && source === "laptop" && laptopPath) brRead.running = true

                    // ── camera ──
                    MediaDevices { id: devices }
                    // resolutions worth offering: ≥ 640 wide at ≥ 24 fps, one entry per width, largest first
                    readonly property var sizes: {
                        const dev = laptopDev, seen = {}, out = [];
                        if (!dev) return out;
                        for (const f of dev.videoFormats) {
                            const w = f.resolution.width, h = f.resolution.height;
                            if (w < 640 || w > 1920 || f.maxFrameRate < 24 || seen[w]) continue;
                            seen[w] = true;
                            out.push({ w: w, h: h, fps: Math.round(f.maxFrameRate) });
                        }
                        return out.sort((a, b) => b.w - a.w);
                    }
                    function pickFormat(dev, wantW) {     // largest ≤ wantW (or 1920) at ≥ 24 fps; defaults are often 640×480
                        if (!dev) return undefined;
                        const cap = wantW > 0 ? wantW : 1920;
                        let best = undefined;
                        for (const f of dev.videoFormats) {
                            const w = f.resolution.width;
                            if (w > cap || f.maxFrameRate < 24) continue;
                            if (!best || w > best.resolution.width || (w === best.resolution.width && f.maxFrameRate > best.maxFrameRate)) best = f;
                        }
                        return best;
                    }
                    CaptureSession {
                        camera: Camera {
                            id: camera
                            cameraDevice: win.activeDev
                            cameraFormat: win.pickFormat(win.activeDev, win.source === "laptop" ? camRoot.laptopWidth : 0)
                            active: !!win.activeDev && (win.source === "laptop" || PhoneCam.live) && !camRoot.gallery
                            onErrorOccurred: (error, errorString) => {
                                if (win.source === "laptop") win.camError = errorString || "The camera couldn't start";
                                else win.say(errorString || "Camera error", true);
                            }
                        }
                        imageCapture: ImageCapture {
                            id: imageCapture
                            onImageSaved: (requestId, path) => {
                                if (win.shotZoom > 1.01) {
                                    zoomProc.path = path;
                                    zoomProc.command = [camRoot.helper, "zoom", path, win.shotZoom.toFixed(2)];
                                    zoomProc.running = true;
                                } else win.photoDone(path);
                            }
                            onErrorOccurred: (requestId, error, message) => win.say(message || "Couldn't take the photo", true)
                        }
                        recorder: MediaRecorder {
                            id: recorder
                            mediaFormat {
                                fileFormat: MediaFormat.MPEG4
                                videoCodec: MediaFormat.VideoCodec.H264
                                audioCodec: MediaFormat.AudioCodec.AAC
                            }
                            quality: MediaRecorder.HighQuality
                            onRecorderStateChanged: {
                                if (recorderState === MediaRecorder.StoppedState && actualLocation.toString() !== "") {
                                    camRoot.lastShot = actualLocation.toString().replace(/^file:\/\//, "");
                                    camRoot.lastIsVideo = true;
                                    thumbPop.restart();
                                    win.say("Video saved");
                                    win.loadShots();
                                }
                            }
                            onErrorOccurred: (error, errorString) => win.say(errorString || "Recording failed", true)
                        }
                        audioInput: win.mode === "video" ? mic : null
                        videoOutput: preview
                    }
                    AudioInput { id: mic }

                    // ── keys ──
                    focus: true
                    Component.onCompleted: forceActiveFocus()
                    Keys.onPressed: (e) => {
                        if (e.isAutoRepeat && !(e.key === Qt.Key_Left || e.key === Qt.Key_Right)) return;
                        if (camRoot.fresh()) return;   // the opening shortcut may still be held
                        const k = e.key;
                        if (camRoot.gallery) {
                            if (k === Qt.Key_Escape || k === Qt.Key_A) win.closeGallery();
                            else if (k === Qt.Key_Left) win.step(-1);
                            else if (k === Qt.Key_Right) win.step(1);
                            else if (k === Qt.Key_Delete) win.trashShot();
                            else if (k === Qt.Key_C) win.copyShot();
                            else if (k === Qt.Key_O && win.shot) Quickshell.execDetached(["xdg-open", win.shot.path]);
                            else if ((k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) && viewer.item && viewer.item.toggle) viewer.item.toggle();
                            else return;
                        } else if (k === Qt.Key_Escape) {
                            if (win.showHelp) win.showHelp = false;
                            else if (win.showAdjust) win.showAdjust = false;
                            else camRoot.close();
                        }
                        else if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) win.shutter();
                        else if (k === Qt.Key_Tab && !win.recording) win.mode = win.mode === "photo" ? "video" : "photo";
                        else if (k === Qt.Key_I) win.pickSource(win.source === "iphone" ? "laptop" : "iphone");
                        else if (k === Qt.Key_A) win.openGallery(0);
                        else if (k === Qt.Key_Plus || k === Qt.Key_Equal) win.setZoom(win.zoom * 1.25);
                        else if (k === Qt.Key_Minus) win.setZoom(win.zoom / 1.25);
                        else if (k === Qt.Key_0) win.setZoom(1);
                        else if (k === Qt.Key_B) win.showAdjust = !win.showAdjust;
                        else if (k === Qt.Key_T) win.timer = win.timer === 0 ? 3 : (win.timer === 3 ? 10 : 0);
                        else if (k === Qt.Key_G) camRoot.grid = !camRoot.grid;
                        else if (k === Qt.Key_M) win.mirror = !win.mirror;
                        else if (k === Qt.Key_O) Quickshell.execDetached(["xdg-open", camRoot.dir]);
                        else if (k === Qt.Key_Question || k === Qt.Key_Slash) win.showHelp = !win.showHelp;
                        else return;
                        e.accepted = true;
                    }

                    // ═══ the picture, filling the drawer ═══
                    ClippingRectangle {
                        id: frame
                        anchors.fill: parent
                        radius: Math.max(14, Atelier.rounding - 6)
                        color: "#0b0b0f"

                        Item {
                            anchors.fill: parent
                            visible: !camRoot.gallery

                            VideoOutput {
                                id: preview
                                anchors.fill: parent
                                fillMode: VideoOutput.PreserveAspectCrop
                                opacity: win.showing ? 1 : 0
                                scale: win.zoom
                                Behavior on opacity { NumberAnimation { duration: Atelier.durMedium } }
                                Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutCubic } }
                                transform: Scale { origin.x: preview.width / 2; xScale: win.mirror ? -1 : 1 }
                            }

                            // zoom: wheel / pinch on the picture
                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: (ev) => { if (ev.angleDelta.y !== 0) win.setZoom(win.zoom * (ev.angleDelta.y > 0 ? 1.08 : 1 / 1.08)); }
                            }
                            PinchHandler {
                                target: null
                                onActiveChanged: if (active) win.pinchBase = win.zoom
                                onActiveScaleChanged: if (active) win.setZoom(win.pinchBase * activeScale)
                            }

                            // rule of thirds
                            Item {
                                anchors.fill: parent
                                visible: camRoot.grid && win.showing
                                Repeater {
                                    model: 2
                                    Rectangle { x: parent.width * (index + 1) / 3; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.28) }
                                }
                                Repeater {
                                    model: 2
                                    Rectangle { y: parent.height * (index + 1) / 3; height: 1; width: parent.width; color: Qt.rgba(1, 1, 1, 0.28) }
                                }
                            }

                            // soft fades so the controls read on any picture
                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                height: 96
                                gradient: Gradient {
                                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.5) }
                                    GradientStop { position: 1; color: "transparent" }
                                }
                            }
                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: 190
                                gradient: Gradient {
                                    GradientStop { position: 0; color: "transparent" }
                                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.62) }
                                }
                            }

                            // ── no picture yet: starting / connecting / failed ──
                            Column {
                                id: waitBox
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -30
                                spacing: 10
                                visible: !win.showing
                                readonly property bool iph: win.source === "iphone"
                                readonly property bool failed: iph ? (PhoneCam.state === "error" || win.stuck) : (win.camError !== "" || win.slow)
                                readonly property bool idle: iph && PhoneCam.state === "off"
                                readonly property string title: !iph
                                    ? (devices.videoInputs.length === 0 ? "No camera found"
                                       : win.camError !== "" ? "The camera couldn't start"
                                       : win.slow ? "The camera is taking a while"
                                       : "Starting the camera…")
                                    : win.stuck ? "Couldn't open the iPhone video"
                                    : PhoneCam.state === "error" ? PhoneCam.error
                                    : PhoneCam.state === "connecting" && PhoneCam.retries > 0 ? "Reconnecting to your iPhone (" + PhoneCam.retries + "/" + PhoneCam.maxRetries + ")…"
                                    : PhoneCam.state === "connecting" ? "Connecting to your iPhone" + (PhoneCam.linkLabel ? " · " + PhoneCam.linkLabel : "") + "…"
                                    : PhoneCam.live ? "Starting the iPhone camera…"
                                    : "Use your iPhone as the camera"
                                readonly property string hint: !iph
                                    ? (win.camError !== "" || win.slow ? "Another app may be using it. Close it, then retry." : "")
                                    : win.stuck ? "The stream is up but no video arrived. Retry, or reopen DroidCam."
                                    : PhoneCam.state === "error" || PhoneCam.state === "connecting" || idle
                                      ? "Open DroidCam on the iPhone and keep it unlocked · USB, hotspot or Wi-Fi"
                                    : ""

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 72; height: 72; radius: 36
                                    color: Qt.rgba(1, 1, 1, 0.07)
                                    border.width: 1; border.color: waitBox.failed ? Qt.alpha(Atelier.peach, 0.5) : Qt.rgba(1, 1, 1, 0.12)
                                    Text { anchors.centerIn: parent
                                        text: waitBox.failed ? "\u{F0028}" : (waitBox.iph ? "󰄜" : "󰌢")
                                        font.family: Atelier.font; font.pixelSize: 30
                                        color: waitBox.failed ? Atelier.peach : Qt.rgba(1, 1, 1, 0.75) }
                                    // spinner ring while connecting/starting
                                    Rectangle {
                                        anchors.fill: parent; anchors.margins: -5; radius: width / 2
                                        color: "transparent"; border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.12)
                                        visible: !waitBox.failed && !waitBox.idle && devices.videoInputs.length > 0
                                        Rectangle {
                                            width: 10; height: 10; radius: 5; color: "white"
                                            x: parent.width / 2 - 5; y: -4
                                        }
                                        RotationAnimation on rotation { running: parent.visible && waitBox.visible && camRoot.visible; loops: Animation.Infinite; from: 0; to: 360; duration: 1100 }
                                    }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(460, implicitWidth); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                                    text: waitBox.title
                                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsXl; font.weight: Font.Medium; color: "white"
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: text !== ""
                                    width: Math.min(460, implicitWidth); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                                    text: waitBox.hint
                                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Qt.rgba(1, 1, 1, 0.6)
                                }
                                Item { width: 1; height: 2 }
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: waitBox.failed || (waitBox.iph && !PhoneCam.running)
                                    width: cbRow.implicitWidth + 36; height: 38; radius: 19
                                    color: cbMa.containsMouse ? Qt.lighter(Atelier.accentFill, 1.1) : Atelier.accentFill
                                    scale: cbMa.pressed ? 0.94 : 1
                                    Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
                                    Row {
                                        id: cbRow
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: waitBox.failed ? "\u{F0450}" : "󰄜"
                                            font.family: Atelier.font; font.pixelSize: Atelier.fsXl; color: Atelier.onFill }
                                        Text { anchors.verticalCenter: parent.verticalCenter
                                            text: waitBox.failed ? "Try again" : "Connect iPhone"
                                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold; color: Atelier.onFill }
                                    }
                                    MouseArea { id: cbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: waitBox.failed ? win.retry() : PhoneCam.start("drawer") }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: waitBox.iph && !win.recording
                                    text: "or use the laptop camera"
                                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.underline: lcMa.containsMouse
                                    color: Qt.rgba(1, 1, 1, 0.7)
                                    MouseArea { id: lcMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor; onClicked: win.pickSource("laptop") }
                                }
                            }

                            // countdown: big number
                            Item {
                                anchors.centerIn: parent
                                width: 180; height: 180
                                visible: win.countdown > 0
                                Text {
                                    anchors.centerIn: parent
                                    text: win.countdown
                                    font.family: Atelier.fontDisplay; font.pixelSize: 120; font.weight: Font.Bold
                                    color: "white"
                                    scale: 1
                                    SequentialAnimation on scale {
                                        running: win.countdown > 0; loops: Animation.Infinite
                                        NumberAnimation { from: 1.25; to: 1; duration: 350; easing.type: Easing.OutCubic }
                                        PauseAnimation { duration: 650 }
                                    }
                                }
                            }

                            // shutter flash
                            Rectangle {
                                anchors.fill: parent; color: "white"; opacity: 0
                                NumberAnimation on opacity { id: flash; running: false; from: 0.85; to: 0; duration: 380; easing.type: Easing.OutCubic }
                            }

                            // ═══ top bar ═══
                            Item {
                                id: topBar
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                anchors.margins: 14
                                height: 36

                                // source switch (segmented)
                                Rectangle {
                                    id: seg
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    width: segRow.implicitWidth + 8; height: 36; radius: Atelier.radiusLg
                                    color: Qt.rgba(0, 0, 0, 0.42)
                                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                                    opacity: win.recording ? 0.45 : 1
                                    // sliding highlight
                                    Rectangle {
                                        y: 4; height: 28; radius: Atelier.radiusMd; color: "white"
                                        x: 4 + (win.source === "iphone" ? lapSeg.width : 0)
                                        width: win.source === "iphone" ? iphSeg.width : lapSeg.width
                                        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    }
                                    Row {
                                        id: segRow
                                        x: 4; y: 4
                                        SegBtn { id: lapSeg; key: "laptop"; glyph: "󰌢"; label: "Laptop" }
                                        SegBtn { id: iphSeg; key: "iphone"; glyph: "󰄜"; label: PhoneCam.live && win.source === "iphone" ? "iPhone · " + PhoneCam.linkLabel : "iPhone" }
                                    }
                                }

                                // format badge (what's actually being captured), or the REC pill
                                Rectangle {
                                    anchors.centerIn: parent
                                    visible: !win.recording && win.showing && fmtText.text !== ""
                                    width: fmtText.implicitWidth + 22; height: 26; radius: 13
                                    color: Qt.rgba(0, 0, 0, 0.42)
                                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                                    Text {
                                        id: fmtText
                                        anchors.centerIn: parent
                                        readonly property var f: camera.cameraFormat
                                        text: f && f.resolution.width > 0
                                            ? f.resolution.width + "×" + f.resolution.height + " · " + Math.round(f.maxFrameRate) + " fps"
                                              + (win.zoom > 1.01 ? " · " + win.zoom.toFixed(1) + "×" : "")
                                            : ""
                                        font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: Qt.rgba(1, 1, 1, 0.85)
                                    }
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    visible: win.recording
                                    width: recRow.implicitWidth + 24; height: 32; radius: Atelier.radiusLg
                                    color: Atelier.red
                                    Row {
                                        id: recRow
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 8; height: 8; radius: 4; color: "white"
                                            SequentialAnimation on opacity {
                                                running: win.recording; loops: Animation.Infinite
                                                NumberAnimation { to: 0.25; duration: 600 } NumberAnimation { to: 1; duration: 600 }
                                            }
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            readonly property int s: Math.floor(recorder.duration / 1000)
                                            text: String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0")
                                            font.family: Atelier.font; font.pixelSize: 14; font.bold: true; color: "white"
                                        }
                                    }
                                }

                                // tools
                                Row {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    ToolBtn { glyph: "\u{F00DF}"; on: win.showAdjust; tip: "Adjust (B)"; onClicked: win.showAdjust = !win.showAdjust }
                                    ToolBtn { glyph: "󰔛"; on: win.timer > 0; badge: win.timer ? win.timer + "s" : ""
                                        tip: "Timer (T)"; onClicked: win.timer = win.timer === 0 ? 3 : (win.timer === 3 ? 10 : 0) }
                                    ToolBtn { glyph: "󰋁"; on: camRoot.grid; tip: "Grid (G)"; onClicked: camRoot.grid = !camRoot.grid }
                                    ToolBtn { glyph: "󰯎"; on: win.mirror; tip: "Mirror (M)"; onClicked: win.mirror = !win.mirror }
                                    ToolBtn { glyph: "\u{F02D7}"; on: win.showHelp; tip: "Shortcuts (?)"; onClicked: win.showHelp = !win.showHelp }
                                }
                            }

                            // ── adjust panel: brightness + resolution (laptop) / where the iPhone's live ──
                            Rectangle {
                                id: adjust
                                anchors.right: parent.right; anchors.top: topBar.bottom
                                anchors.rightMargin: 14; anchors.topMargin: 10
                                width: 300
                                height: adjCol.implicitHeight + 28
                                radius: Atelier.radiusLg
                                color: Qt.rgba(0, 0, 0, 0.62)
                                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                                visible: opacity > 0
                                opacity: win.showAdjust ? 1 : 0
                                scale: win.showAdjust ? 1 : 0.94
                                transformOrigin: Item.TopRight
                                Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
                                Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutCubic } }
                                MouseArea { anchors.fill: parent }     // don't let clicks reach the picture

                                Column {
                                    id: adjCol
                                    x: 14; y: 14
                                    width: parent.width - 28
                                    spacing: 12

                                    Text {
                                        text: win.source === "iphone" ? "iPhone camera" : "Laptop camera"
                                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold; color: "white"
                                    }

                                    // brightness
                                    Column {
                                        width: parent.width
                                        spacing: 8
                                        visible: win.source === "laptop" && win.brVal >= 0
                                        RowLayout {
                                            width: parent.width
                                            Text { text: "\u{F00DF}"; font.family: Atelier.font; font.pixelSize: 14; color: Atelier.yellow }
                                            Text { text: "Brightness"; Layout.fillWidth: true
                                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Qt.rgba(1, 1, 1, 0.85) }
                                            Text {
                                                visible: win.brVal !== win.brDef
                                                text: "Reset"
                                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; font.underline: rsMa.containsMouse; color: Qt.rgba(1, 1, 1, 0.65)
                                                MouseArea { id: rsMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor; onClicked: win.setBrightness(win.brDef) }
                                            }
                                        }
                                        Item {
                                            id: brTrack
                                            width: parent.width; height: 18
                                            readonly property real frac: win.brMax > win.brMin ? (win.brVal - win.brMin) / (win.brMax - win.brMin) : 0
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width; height: 6; radius: 3
                                                color: Qt.rgba(1, 1, 1, 0.16)
                                                Rectangle {
                                                    width: Math.max(6, parent.width * brTrack.frac); height: parent.height; radius: 3
                                                    gradient: Gradient {
                                                        orientation: Gradient.Horizontal
                                                        GradientStop { position: 0; color: Qt.alpha(Atelier.yellow, 0.55) }
                                                        GradientStop { position: 1; color: Atelier.yellow }
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                width: 16; height: 16; radius: Atelier.radiusSm; color: "white"
                                                anchors.verticalCenter: parent.verticalCenter
                                                x: (parent.width - width) * brTrack.frac
                                                scale: brMa.pressed ? 1.2 : 1
                                                Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
                                            }
                                            MouseArea {
                                                id: brMa
                                                anchors.fill: parent; anchors.margins: -6
                                                cursorShape: Qt.PointingHandCursor
                                                function set(mx) { win.setBrightness(win.brMin + Math.max(0, Math.min(1, (mx - 6) / brTrack.width)) * (win.brMax - win.brMin)); }
                                                onPressed: (m) => set(m.x)
                                                onPositionChanged: (m) => { if (pressed) set(m.x); }
                                            }
                                        }
                                    }

                                    // resolution
                                    Column {
                                        width: parent.width
                                        spacing: 8
                                        visible: win.source === "laptop" && win.sizes.length > 1
                                        Text { text: "Resolution"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Qt.rgba(1, 1, 1, 0.85) }
                                        Flow {
                                            width: parent.width
                                            spacing: 6
                                            Repeater {
                                                model: win.sizes
                                                Rectangle {
                                                    readonly property bool on: (camRoot.laptopWidth === 0 && index === 0) || camRoot.laptopWidth === modelData.w
                                                    width: rsText.implicitWidth + 20; height: 28; radius: Atelier.radiusMd
                                                    color: on ? "white" : (rsChip.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08))
                                                    border.width: on ? 0 : 1; border.color: Qt.rgba(1, 1, 1, 0.14)
                                                    Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                                                    Text { id: rsText; anchors.centerIn: parent
                                                        text: modelData.h + "p" + (modelData.fps !== 30 ? " " + modelData.fps : "")
                                                        font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: parent.on ? "#141414" : "white" }
                                                    MouseArea { id: rsChip; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        enabled: !win.recording
                                                        onClicked: camRoot.laptopWidth = index === 0 ? 0 : modelData.w }
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        width: parent.width; wrapMode: Text.WordWrap
                                        visible: win.source === "iphone"
                                        text: "Lens, resolution, focus and exposure are set in the DroidCam app on the iPhone."
                                            + (PhoneCam.live ? "\nConnected over " + PhoneCam.linkLabel + "." : "")
                                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; lineHeight: 1.15; color: Qt.rgba(1, 1, 1, 0.75)
                                    }
                                    Text {
                                        width: parent.width; wrapMode: Text.WordWrap
                                        visible: win.source === "laptop" && win.brVal < 0 && win.sizes.length <= 1
                                        text: "This camera has no adjustable settings."
                                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Qt.rgba(1, 1, 1, 0.75)
                                    }
                                }
                            }

                            // status toast
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top; anchors.topMargin: 62
                                visible: win.status !== "" && !camRoot.gallery
                                width: stRow.implicitWidth + 26; height: 34; radius: Atelier.radiusLg
                                color: Qt.rgba(0, 0, 0, 0.6)
                                border.width: 1; border.color: win.statusBad ? Qt.alpha(Atelier.red, 0.6) : Qt.rgba(1, 1, 1, 0.12)
                                Row {
                                    id: stRow
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: win.statusBad ? "󰀦" : "󰄬"; font.family: Atelier.font; font.pixelSize: 14
                                        color: win.statusBad ? Atelier.red : Atelier.green }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: win.status; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: "white" }
                                }
                            }

                            // ═══ bottom bar ═══
                            Item {
                                id: bottomBar
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                anchors.leftMargin: 22; anchors.rightMargin: 22; anchors.bottomMargin: 16
                                height: 118

                                // zoom pills (iPhone-camera style), photo mode only
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.top; anchors.bottomMargin: 4
                                    visible: opacity > 0
                                    opacity: win.canZoom && win.showing ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
                                    width: zRow.implicitWidth + 8; height: 34; radius: Atelier.radiusLg
                                    color: Qt.rgba(0, 0, 0, 0.38)
                                    Row {
                                        id: zRow
                                        anchors.centerIn: parent
                                        spacing: 2
                                        Repeater {
                                            model: [1, 2, 3]
                                            Rectangle {
                                                // the pill nearest the current zoom shows the exact value
                                                readonly property bool near: modelData === (win.zoom < 1.5 ? 1 : win.zoom < 2.5 ? 2 : 3)
                                                width: near ? 40 : 28; height: 28; radius: Atelier.radiusMd
                                                color: near ? Qt.rgba(0, 0, 0, 0.55) : "transparent"
                                                Behavior on width { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutCubic } }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: parent.near ? (Math.abs(win.zoom - Math.round(win.zoom)) < 0.05 ? Math.round(win.zoom) : win.zoom.toFixed(1)) + "×" : modelData
                                                    font.family: Atelier.font; font.pixelSize: parent.near ? 12 : 11; font.bold: parent.near
                                                    color: parent.near ? Atelier.yellow : "white"
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.setZoom(modelData) }
                                            }
                                        }
                                    }
                                }

                                // PHOTO · VIDEO
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    spacing: 22
                                    opacity: win.recording ? 0 : 1
                                    Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
                                    Repeater {
                                        model: [{ id: "photo", label: "PHOTO" }, { id: "video", label: "VIDEO" }]
                                        Text {
                                            text: modelData.label
                                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; font.letterSpacing: 1.6
                                            color: win.mode === modelData.id ? Atelier.yellow : Qt.rgba(1, 1, 1, 0.75)
                                            MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor
                                                enabled: !win.recording; onClicked: win.mode = modelData.id }
                                        }
                                    }
                                }

                                // last shot → gallery
                                Item {
                                    id: thumb
                                    anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                                    width: 54; height: 54
                                    visible: camRoot.lastShot !== ""
                                    opacity: win.recording ? 0.4 : 1
                                    scale: thMa.pressed ? 0.9 : (thMa.containsMouse ? 1.06 : 1)
                                    Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutCubic } }
                                    ClippingRectangle {
                                        anchors.fill: parent
                                        radius: Atelier.radiusMd
                                        color: Qt.rgba(1, 1, 1, 0.1)
                                        border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.85)
                                        Image {
                                            anchors.fill: parent
                                            readonly property var hit: win.shots.find(s => s.path === camRoot.lastShot)
                                            readonly property string src: camRoot.lastIsVideo ? (hit ? hit.thumb : "") : camRoot.lastShot
                                            source: src ? "file://" + src + "?t=" + camRoot.shotStamp : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            sourceSize.width: 108; sourceSize.height: 108
                                        }
                                        Text { anchors.centerIn: parent; visible: camRoot.lastIsVideo; text: "\u{F040A}"; font.family: Atelier.font; font.pixelSize: 20; color: "white"
                                            style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.4) }
                                    }
                                    SequentialAnimation on scale {
                                        id: thumbPop; running: false
                                        NumberAnimation { from: 0.6; to: 1.08; duration: 220; easing.type: Easing.OutCubic }
                                        NumberAnimation { to: 1; duration: Atelier.durFast }
                                    }
                                    MouseArea { id: thMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: win.openGallery(0) }
                                }

                                // shutter
                                Item {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    width: 76; height: 76
                                    opacity: win.showing || win.recording ? 1 : 0.4
                                    Rectangle {
                                        anchors.fill: parent; radius: width / 2
                                        color: "transparent"; border.width: 4; border.color: "white"
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: win.recording ? 28 : 60; height: width
                                        radius: win.recording ? 7 : width / 2
                                        color: win.mode === "video" ? Atelier.red : "white"
                                        scale: shMa.pressed ? 0.86 : (shMa.containsMouse ? 0.96 : 1)
                                        Behavior on width { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutCubic } }
                                        Behavior on radius { NumberAnimation { duration: Atelier.durFast } }
                                        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                                        Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
                                    }
                                    MouseArea { id: shMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.shutter() }
                                }

                                // switch camera
                                Rectangle {
                                    anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                                    width: 54; height: 54; radius: 27
                                    color: swMa.containsMouse ? Qt.rgba(0, 0, 0, 0.6) : Qt.rgba(0, 0, 0, 0.42)
                                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.22)
                                    opacity: win.recording ? 0.4 : 1
                                    Text { anchors.centerIn: parent; text: "󰓡"; font.family: Atelier.font; font.pixelSize: 22; color: "white"
                                        rotation: win.source === "iphone" ? 180 : 0
                                        Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } } }
                                    MouseArea { id: swMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: win.pickSource(win.source === "iphone" ? "laptop" : "iphone") }
                                }
                            }

                            // ── keyboard shortcuts sheet ──
                            Rectangle {
                                anchors.centerIn: parent
                                width: Math.min(parent.width - 60, 520)
                                height: helpCol.implicitHeight + 36
                                radius: 20
                                color: Qt.rgba(0, 0, 0, 0.74)
                                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)
                                visible: opacity > 0
                                opacity: win.showHelp ? 1 : 0
                                scale: win.showHelp ? 1 : 0.95
                                Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
                                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                MouseArea { anchors.fill: parent; onClicked: win.showHelp = false }
                                Column {
                                    id: helpCol
                                    x: 22; y: 18
                                    width: parent.width - 44
                                    spacing: 12
                                    Text { text: "Keyboard shortcuts"; font.family: Atelier.fontUi; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
                                    Grid {
                                        columns: 2
                                        columnSpacing: 24; rowSpacing: 8
                                        Repeater {
                                            model: [
                                                ["Space", "Take photo / record"], ["Tab", "Photo ↔ video"],
                                                ["I", "iPhone ↔ laptop"],         ["A", "Gallery"],
                                                ["+  −", "Zoom (or scroll)"],      ["0", "Reset zoom"],
                                                ["B", "Brightness & quality"],     ["T", "Timer 3s / 10s"],
                                                ["G", "Grid"],                     ["M", "Mirror"],
                                                ["O", "Open folder"],              ["Esc", "Close"]
                                            ]
                                            Row {
                                                width: (helpCol.width - 24) / 2
                                                spacing: 10
                                                Rectangle {
                                                    width: Math.max(28, kText.implicitWidth + 14); height: 22; radius: 6
                                                    color: Qt.rgba(1, 1, 1, 0.1); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.18)
                                                    Text { id: kText; anchors.centerIn: parent; text: modelData[0]
                                                        font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: "white" }
                                                }
                                                Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]
                                                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Qt.rgba(1, 1, 1, 0.8) }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ═══ gallery ═══
                        Item {
                            id: galleryView
                            anchors.fill: parent
                            visible: camRoot.gallery

                            // the photo / video
                            Loader {
                                id: viewer
                                anchors.fill: parent
                                anchors.topMargin: 64; anchors.bottomMargin: 96
                                active: camRoot.gallery && !!win.shot
                                sourceComponent: win.shot && win.shot.type === "video" ? videoView : photoView
                            }
                            Component {
                                id: photoView
                                Image {
                                    source: win.shot ? "file://" + win.shot.path + "?t=" + camRoot.shotStamp : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    sourceSize.width: 1920; sourceSize.height: 1920
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
                                    MouseArea { anchors.fill: parent; onDoubleClicked: Quickshell.execDetached(["xdg-open", win.shot.path]) }
                                }
                            }
                            Component {
                                id: videoView
                                Item {
                                    function toggle() { vid.playbackState === MediaPlayer.PlayingState ? vid.pause() : vid.play(); }
                                    Video {
                                        id: vid
                                        anchors.fill: parent
                                        source: win.shot ? "file://" + win.shot.path : ""
                                        fillMode: VideoOutput.PreserveAspectFit
                                    }
                                    Image {      // poster until it plays
                                        anchors.fill: parent
                                        visible: vid.playbackState === MediaPlayer.StoppedState && win.shot && win.shot.thumb !== ""
                                        source: visible ? "file://" + win.shot.thumb : ""
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 64; height: 64; radius: 32
                                        color: Qt.rgba(0, 0, 0, 0.5); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.25)
                                        visible: vid.playbackState !== MediaPlayer.PlayingState
                                        Text { anchors.centerIn: parent; anchors.horizontalCenterOffset: 2; text: "\u{F040A}"
                                            font.family: Atelier.font; font.pixelSize: 30; color: "white" }
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.toggle() }
                                    // progress
                                    Rectangle {
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                        anchors.margins: 18
                                        height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.18)
                                        visible: vid.duration > 0 && vid.playbackState !== MediaPlayer.StoppedState
                                        Rectangle { height: parent.height; radius: 2; color: "white"
                                            width: parent.width * (vid.duration > 0 ? vid.position / vid.duration : 0) }
                                    }
                                }
                            }

                            // prev / next
                            Repeater {
                                model: [-1, 1]
                                Rectangle {
                                    anchors.verticalCenter: viewer.verticalCenter
                                    x: modelData < 0 ? 14 : galleryView.width - width - 14
                                    width: 40; height: 40; radius: 20
                                    visible: win.shots.length > 1
                                    color: navMa.containsMouse ? Qt.rgba(0, 0, 0, 0.6) : Qt.rgba(0, 0, 0, 0.38)
                                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.16)
                                    Text { anchors.centerIn: parent; text: modelData < 0 ? "\u{F0141}" : "\u{F0142}"
                                        font.family: Atelier.font; font.pixelSize: 22; color: "white" }
                                    MouseArea { id: navMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: win.step(modelData) }
                                }
                            }

                            // top bar: back · counter + date · actions
                            Item {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                anchors.margins: 14
                                height: 36

                                Rectangle {
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    width: backRow.implicitWidth + 26; height: 36; radius: Atelier.radiusLg
                                    color: backMa.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)
                                    Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                                    Row {
                                        id: backRow
                                        anchors.centerIn: parent
                                        spacing: 7
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{F004D}"; font.family: Atelier.font; font.pixelSize: Atelier.fsXl; color: "white" }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Camera"
                                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; color: "white" }
                                    }
                                    MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.closeGallery() }
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 1
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: win.shots.length ? (win.shotIndex + 1) + " of " + win.shots.length : "No photos yet"
                                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold; color: "white"
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        visible: text !== ""
                                        // Photo_2026-11-22_14-05-09.jpg → "22 Nov 2026 · 2:05 PM"
                                        text: {
                                            if (!win.shot) return "";
                                            const m = win.shot.path.match(/(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})/);
                                            if (!m) return win.shot.path.split("/").pop();
                                            const d = new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
                                            return Qt.formatDateTime(d, Atelier.clock24 ? "d MMM yyyy · H:mm" : "d MMM yyyy · h:mm AP");
                                        }
                                        font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; color: Qt.rgba(1, 1, 1, 0.6)
                                    }
                                }

                                Row {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    visible: !!win.shot
                                    ToolBtn { glyph: "\u{F0003}"; tip: "AirDrop to iPhone"; visible: AirDrop.available; onClicked: AirDrop.send([win.shot.path]) }
                                    ToolBtn { glyph: "\u{F018F}"; tip: "Copy (C)"; onClicked: win.copyShot() }
                                    ToolBtn { glyph: "\u{F03CC}"; tip: "Open (O)"; onClicked: Quickshell.execDetached(["xdg-open", win.shot.path]) }
                                    ToolBtn { glyph: "󰉋"; tip: "Folder"; onClicked: Quickshell.execDetached(["xdg-open", camRoot.dir]) }
                                    ToolBtn { glyph: "\u{F0A7A}"; tip: "Delete (Del)"; danger: true; onClicked: win.trashShot() }
                                }
                            }

                            // filmstrip
                            ListView {
                                id: strip
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                anchors.leftMargin: 14; anchors.rightMargin: 14; anchors.bottomMargin: 16
                                height: 64
                                orientation: ListView.Horizontal
                                spacing: 8
                                clip: true
                                model: win.shots
                                currentIndex: win.shotIndex
                                highlightMoveDuration: 220
                                preferredHighlightBegin: width / 2 - 32; preferredHighlightEnd: width / 2 + 32
                                highlightRangeMode: ListView.ApplyRange
                                delegate: Item {
                                    width: 64; height: 64
                                    readonly property bool cur: index === win.shotIndex
                                    scale: cur ? 1 : (tMa.containsMouse ? 0.96 : 0.9)
                                    opacity: cur ? 1 : 0.7
                                    Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
                                    ClippingRectangle {
                                        anchors.fill: parent
                                        radius: Atelier.radiusMd
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                        border.width: parent.cur ? 2 : 0; border.color: "white"
                                        Image {
                                            anchors.fill: parent
                                            source: modelData.thumb ? "file://" + modelData.thumb + (modelData.type === "photo" ? "?t=" + camRoot.shotStamp : "") : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            sourceSize.width: 128; sourceSize.height: 128
                                        }
                                        Text { anchors.centerIn: parent; visible: modelData.type === "video"; text: "\u{F040A}"
                                            font.family: Atelier.font; font.pixelSize: 18; color: "white"; style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.4) }
                                    }
                                    MouseArea { id: tMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.shotIndex = index }
                                }
                                WheelHandler {
                                    onWheel: (ev) => win.step(ev.angleDelta.y > 0 || ev.angleDelta.x > 0 ? -1 : 1)
                                }
                            }

                            // status toast (gallery)
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top; anchors.topMargin: 62
                                visible: win.status !== ""
                                width: gsText.implicitWidth + 26; height: 34; radius: Atelier.radiusLg
                                color: Qt.rgba(0, 0, 0, 0.6)
                                border.width: 1; border.color: win.statusBad ? Qt.alpha(Atelier.red, 0.6) : Qt.rgba(1, 1, 1, 0.12)
                                Text { id: gsText; anchors.centerIn: parent; text: win.status; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: "white" }
                            }
                        }
                    }

                    // ── pieces ──
                    component SegBtn: Item {
                        id: sb
                        property string key
                        property string glyph
                        property string label
                        readonly property bool on: win.source === key
                        width: sbRow.implicitWidth + 26; height: 28
                        Row {
                            id: sbRow
                            anchors.centerIn: parent
                            spacing: 7
                            Text { anchors.verticalCenter: parent.verticalCenter; text: sb.glyph; font.family: Atelier.font; font.pixelSize: 14
                                color: sb.on ? "#141414" : "white" }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: sb.label; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd
                                font.weight: Font.DemiBold; color: sb.on ? "#141414" : "white" }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.pickSource(sb.key) }
                    }
                    component ToolBtn: Rectangle {
                        id: tb
                        property string glyph
                        property bool on: false
                        property bool danger: false
                        property string badge: ""
                        property string tip: ""
                        signal clicked()
                        width: badge ? tbRow.implicitWidth + 24 : 36; height: 36; radius: Atelier.radiusLg
                        color: on ? Qt.rgba(1, 1, 1, 0.9)
                             : tbMa.containsMouse ? (danger ? Qt.alpha(Atelier.red, 0.55) : Qt.rgba(0, 0, 0, 0.6))
                             : Qt.rgba(0, 0, 0, 0.42)
                        border.width: on ? 0 : 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                        scale: tbMa.pressed ? 0.9 : 1
                        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                        Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
                        Row {
                            id: tbRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text { anchors.verticalCenter: parent.verticalCenter; text: tb.glyph; font.family: Atelier.font; font.pixelSize: Atelier.fsXl
                                color: tb.on ? "#141414" : "white" }
                            Text { anchors.verticalCenter: parent.verticalCenter; visible: tb.badge !== ""; text: tb.badge
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; color: tb.on ? "#141414" : "white" }
                        }
                        // tooltip under the button
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom; anchors.topMargin: 6
                            visible: tb.tip !== "" && tipDelay.shown
                            width: tipText.implicitWidth + 14; height: 22; radius: 11
                            color: Qt.rgba(0, 0, 0, 0.75)
                            z: 10
                            Text { id: tipText; anchors.centerIn: parent; text: tb.tip; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: "white" }
                        }
                        Timer { id: tipDelay; property bool shown: false; interval: 550; running: tbMa.containsMouse && !shown
                            onTriggered: shown = true }
                        MouseArea { id: tbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onExited: tipDelay.shown = false
                            onClicked: { tipDelay.shown = false; tb.clicked(); } }
                    }
                }
            }
        }
    }
}
