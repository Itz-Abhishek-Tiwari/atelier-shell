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
//   top     Laptop / iPhone switch · REC timer · timer, grid, mirror, folder
//   bottom  last shot · PHOTO / VIDEO · shutter · switch camera
//   Keys: Space/Enter shutter · Tab mode · I iPhone/laptop · T timer · G grid · M mirror · O folder · Esc
// The camera lives in a Loader that's only active while the drawer is visible (webcam light off
// when closed). iPhone: services/PhoneCam.qml → "iPhone Camera (Atelier)" (/dev/video11).
// Photos/videos go to ~/Pictures/Camera; a photo is also copied to the clipboard.
Item {
    id: camRoot
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool isLight: Atelier.isLight
    property bool animActive: false
    signal closedSignal()

    readonly property string dir: (Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")) + "/Camera"
    property string lastShot: ""            // newest photo/video path (kept across openings)
    property bool lastIsVideo: false
    property bool grid: false               // rule-of-thirds overlay (kept across openings)

    property double openedAt: 0
    function fresh() { return Date.now() - openedAt < 350; }
    function toggle() { if (visible && animActive) close(); else open(); }
    function open() {
        openedAt = Date.now();
        visible = true;
        animActive = true;
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
        function onLiveChanged() { camRoot.rebuildTries = 0; if (camRoot.visible) camRoot.rebuild(); }
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
                    readonly property bool recording: recorder.recorderState === MediaRecorder.RecordingState

                    function clean(d) { return d.description.replace(/"/g, "").trim(); }   // modprobe may leave quotes
                    readonly property var phoneDev: devices.videoInputs.find(d => clean(d) === PhoneCam.deviceName + " (Atelier)")
                                                  || devices.videoInputs.find(d => clean(d) === PhoneCam.deviceName)
                    readonly property var laptopDev: devices.videoInputs.find(d => !clean(d).startsWith(PhoneCam.deviceName)) || devices.defaultVideoInput
                    readonly property var activeDev: source === "iphone" ? phoneDev : laptopDev
                    readonly property bool showing: camera.active && (source === "laptop" || PhoneCam.live)

                    function pickSource(s) {
                        if (recording || s === source) return;
                        source = s;
                        mirror = s === "laptop";
                        if (s === "iphone" && !PhoneCam.running) PhoneCam.start("drawer");
                    }
                    function stamp() { return Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss"); }
                    function shutter() {
                        if (countdown > 0) { countdown = 0; countTimer.stop(); return; }   // cancel a countdown
                        if (mode === "video" && recording) { recorder.stop(); return; }
                        if (!showing) return;
                        if (timer > 0) { countdown = timer; countTimer.start(); return; }
                        fire();
                    }
                    function fire() {
                        if (mode === "photo") {
                            flash.restart();
                            imageCapture.captureToFile(camRoot.dir + "/Photo_" + stamp() + ".jpg");
                        } else {
                            recorder.outputLocation = "file://" + camRoot.dir + "/Video_" + stamp() + ".mp4";
                            recorder.record();
                        }
                    }
                    function say(t, bad) { status = t; statusBad = !!bad; statusTimer.restart(); }

                    Process { running: true; command: ["mkdir", "-p", camRoot.dir] }
                    Timer { id: countTimer; interval: 1000; repeat: true
                        onTriggered: { win.countdown--; if (win.countdown <= 0) { stop(); win.fire(); } } }
                    Timer { id: statusTimer; interval: 2600; onTriggered: win.status = "" }
                    // iPhone live but not listed yet / camera didn't start: rebuild (bounded)
                    Timer {
                        interval: 1800; repeat: true
                        running: win.source === "iphone" && PhoneCam.live && (!win.phoneDev || !camera.active)
                        onTriggered: { if (++camRoot.rebuildTries <= 4) camRoot.rebuild(); }
                    }

                    // ── camera ──
                    MediaDevices { id: devices }
                    function bestFormat(dev) {     // largest ≤ 1920 wide at ≥ 24 fps (defaults are often 640×480)
                        if (!dev) return undefined;
                        let best = undefined;
                        for (const f of dev.videoFormats) {
                            const w = f.resolution.width;
                            if (w > 1920 || f.maxFrameRate < 24) continue;
                            if (!best || w > best.resolution.width) best = f;
                        }
                        return best;
                    }
                    CaptureSession {
                        camera: Camera {
                            id: camera
                            cameraDevice: win.activeDev
                            cameraFormat: win.bestFormat(win.activeDev)
                            active: !!win.activeDev && (win.source === "laptop" || PhoneCam.live)
                            onErrorOccurred: (error, errorString) => win.say(errorString || "Camera error", true)
                        }
                        imageCapture: ImageCapture {
                            id: imageCapture
                            onImageSaved: (requestId, path) => {
                                camRoot.lastShot = path; camRoot.lastIsVideo = false;
                                thumbPop.restart();
                                Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/jpeg < "$1"', "sh", path]);
                                win.say("Saved · copied to clipboard");
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
                        if (e.isAutoRepeat || camRoot.fresh()) return;   // the opening shortcut may still be held
                        if (e.key === Qt.Key_Escape) camRoot.close();
                        else if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.shutter();
                        else if (e.key === Qt.Key_Tab && !win.recording) win.mode = win.mode === "photo" ? "video" : "photo";
                        else if (e.key === Qt.Key_I) win.pickSource(win.source === "iphone" ? "laptop" : "iphone");
                        else if (e.key === Qt.Key_T) win.timer = win.timer === 0 ? 3 : (win.timer === 3 ? 10 : 0);
                        else if (e.key === Qt.Key_G) camRoot.grid = !camRoot.grid;
                        else if (e.key === Qt.Key_M) win.mirror = !win.mirror;
                        else if (e.key === Qt.Key_O) Quickshell.execDetached(["xdg-open", camRoot.dir]);
                        else return;
                        e.accepted = true;
                    }

                    // ═══ the picture, filling the drawer ═══
                    ClippingRectangle {
                        id: frame
                        anchors.fill: parent
                        radius: Math.max(14, Atelier.rounding - 6)
                        color: "#0b0b0f"

                        VideoOutput {
                            id: preview
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                            opacity: win.showing ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 260 } }
                            transform: Scale { origin.x: preview.width / 2; xScale: win.mirror ? -1 : 1 }
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
                            height: 170
                            gradient: Gradient {
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.62) }
                            }
                        }

                        // ── no picture yet: laptop starting / iPhone connecting / not found ──
                        Column {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -30
                            spacing: 12
                            visible: !win.showing
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 72; height: 72; radius: 36
                                color: Qt.rgba(1, 1, 1, 0.07)
                                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                                Text { anchors.centerIn: parent; text: win.source === "iphone" ? "󰄜" : "󰌢"
                                    font.family: Atelier.font; font.pixelSize: 30
                                    color: PhoneCam.state === "error" && win.source === "iphone" ? Atelier.peach : Qt.rgba(1, 1, 1, 0.75) }
                                // spinner ring while connecting/starting
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: -5; radius: width / 2
                                    color: "transparent"; border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.12)
                                    visible: !(win.source === "iphone" && (PhoneCam.state === "error" || PhoneCam.state === "off"))
                                    Rectangle {
                                        width: 10; height: 10; radius: 5; color: "white"
                                        x: parent.width / 2 - 5; y: -4
                                    }
                                    RotationAnimation on rotation { running: parent.visible && camRoot.visible; loops: Animation.Infinite; from: 0; to: 360; duration: 1100 }
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(440, implicitWidth); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                                text: win.source === "laptop" ? (devices.videoInputs.length === 0 ? "No camera found" : "Starting the camera…")
                                    : PhoneCam.state === "connecting" ? "Connecting to your iPhone" + (PhoneCam.linkLabel ? " · " + PhoneCam.linkLabel : "") + "…"
                                    : PhoneCam.state === "error" ? PhoneCam.error
                                    : PhoneCam.live ? "Starting the iPhone camera…"
                                    : "Open DroidCam on your iPhone"
                                font.family: Atelier.fontUi; font.pixelSize: 15; font.weight: Font.Medium; color: "white"
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: win.source === "iphone" && !PhoneCam.running
                                width: cbText.implicitWidth + 36; height: 38; radius: 19
                                color: cbMa.containsMouse ? Qt.lighter(Atelier.accentFill, 1.1) : Atelier.accentFill
                                Text { id: cbText; anchors.centerIn: parent; text: PhoneCam.state === "error" ? "Try again" : "Connect iPhone"
                                    font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: Atelier.onFill }
                                MouseArea { id: cbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: PhoneCam.start("drawer") }
                            }
                        }

                        // countdown: big number with a draining ring
                        Item {
                            anchors.centerIn: parent
                            width: 180; height: 180
                            visible: win.countdown > 0
                            Text {
                                anchors.centerIn: parent
                                text: win.countdown
                                font.family: "Inter Display"; font.pixelSize: 120; font.weight: Font.Bold
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
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: 14
                            height: 36

                            // source switch (segmented)
                            Rectangle {
                                id: seg
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                width: segRow.implicitWidth + 8; height: 36; radius: 18
                                color: Qt.rgba(0, 0, 0, 0.42)
                                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                                opacity: win.recording ? 0.45 : 1
                                // sliding highlight
                                Rectangle {
                                    y: 4; height: 28; radius: 14; color: "white"
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

                            // REC pill
                            Rectangle {
                                anchors.centerIn: parent
                                visible: win.recording
                                width: recRow.implicitWidth + 24; height: 32; radius: 16
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
                                ToolBtn { glyph: "󰔛"; on: win.timer > 0; badge: win.timer ? win.timer + "s" : ""
                                    tip: "Timer (T)"; onClicked: win.timer = win.timer === 0 ? 3 : (win.timer === 3 ? 10 : 0) }
                                ToolBtn { glyph: "󰋁"; on: camRoot.grid; tip: "Grid (G)"; onClicked: camRoot.grid = !camRoot.grid }
                                ToolBtn { glyph: "󰯎"; on: win.mirror; tip: "Mirror (M)"; onClicked: win.mirror = !win.mirror }
                                ToolBtn { glyph: "󰉋"; tip: "Open folder (O)"; onClicked: Quickshell.execDetached(["xdg-open", camRoot.dir]) }
                            }
                        }

                        // status toast
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top; anchors.topMargin: 62
                            visible: win.status !== ""
                            width: stRow.implicitWidth + 26; height: 34; radius: 17
                            color: Qt.rgba(0, 0, 0, 0.6)
                            border.width: 1; border.color: win.statusBad ? Qt.alpha(Atelier.red, 0.6) : Qt.rgba(1, 1, 1, 0.12)
                            Row {
                                id: stRow
                                anchors.centerIn: parent
                                spacing: 8
                                Text { anchors.verticalCenter: parent.verticalCenter; text: win.statusBad ? "󰀦" : "󰄬"; font.family: Atelier.font; font.pixelSize: 14
                                    color: win.statusBad ? Atelier.red : Atelier.green }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: win.status; font.family: Atelier.fontUi; font.pixelSize: 13; color: "white" }
                            }
                        }

                        // ═══ bottom bar ═══
                        Item {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                            anchors.leftMargin: 22; anchors.rightMargin: 22; anchors.bottomMargin: 16
                            height: 118

                            // PHOTO · VIDEO
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                spacing: 22
                                opacity: win.recording ? 0 : 1
                                Behavior on opacity { NumberAnimation { duration: 180 } }
                                Repeater {
                                    model: [{ id: "photo", label: "PHOTO" }, { id: "video", label: "VIDEO" }]
                                    Text {
                                        text: modelData.label
                                        font.family: Atelier.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 1.6
                                        color: win.mode === modelData.id ? Atelier.yellow : Qt.rgba(1, 1, 1, 0.75)
                                        MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor
                                            enabled: !win.recording; onClicked: win.mode = modelData.id }
                                    }
                                }
                            }

                            // last shot
                            ClippingRectangle {
                                id: thumb
                                anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                                width: 54; height: 54; radius: 12
                                color: Qt.rgba(1, 1, 1, 0.1)
                                border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.85)
                                visible: camRoot.lastShot !== ""
                                Image {
                                    anchors.fill: parent
                                    visible: !camRoot.lastIsVideo
                                    source: !camRoot.lastIsVideo && camRoot.lastShot ? "file://" + camRoot.lastShot : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 108; sourceSize.height: 108
                                }
                                Text { anchors.centerIn: parent; visible: camRoot.lastIsVideo; text: "󰕧"; font.family: Atelier.font; font.pixelSize: 22; color: "white" }
                                SequentialAnimation on scale {
                                    id: thumbPop; running: false
                                    NumberAnimation { from: 0.6; to: 1.08; duration: 220; easing.type: Easing.OutCubic }
                                    NumberAnimation { to: 1; duration: 140 }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached(["xdg-open", camRoot.lastShot]) }
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
                                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                    Behavior on radius { NumberAnimation { duration: 200 } }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Behavior on scale { NumberAnimation { duration: 110 } }
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
                            Text { anchors.verticalCenter: parent.verticalCenter; text: sb.label; font.family: Atelier.fontUi; font.pixelSize: 12
                                font.weight: Font.DemiBold; color: sb.on ? "#141414" : "white" }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.pickSource(sb.key) }
                    }
                    component ToolBtn: Rectangle {
                        id: tb
                        property string glyph
                        property bool on: false
                        property string badge: ""
                        property string tip: ""
                        signal clicked()
                        width: badge ? tbRow.implicitWidth + 24 : 36; height: 36; radius: 18
                        color: on ? Qt.rgba(1, 1, 1, 0.9) : (tbMa.containsMouse ? Qt.rgba(0, 0, 0, 0.6) : Qt.rgba(0, 0, 0, 0.42))
                        border.width: on ? 0 : 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Row {
                            id: tbRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text { anchors.verticalCenter: parent.verticalCenter; text: tb.glyph; font.family: Atelier.font; font.pixelSize: 15
                                color: tb.on ? "#141414" : "white" }
                            Text { anchors.verticalCenter: parent.verticalCenter; visible: tb.badge !== ""; text: tb.badge
                                font.family: Atelier.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: tb.on ? "#141414" : "white" }
                        }
                        MouseArea { id: tbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked() }
                    }
                }
            }
        }
    }
}
