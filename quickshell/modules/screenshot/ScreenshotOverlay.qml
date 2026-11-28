import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import qs.components
import qs.config
import qs.services

// Screenshot tool, built into the shell (no separate app).
//   1. freeze: grim captures the monitor, the frozen frame is shown full-screen
//   2. pick:   Region (drag) · Window (hover + click) · Screen (click / Enter)
//   3. result: saved to ~/Pictures/Screenshots, copied to the clipboard, and a preview
//              card slides out of the right edge (Edit in Swappy · Open · Folder · Delete)
// With Record on (R key, toolbar, or `record(...)`), the picked area is screen-recorded instead
// (services/Recorder.qml). IPC: `qs ipc call screenshot region|window|screen|full`,
// `qs ipc call record toggle|region|window|screen|stop` (see shell.qml)
Scope {
    id: root

    property string mode: "region"          // region | window | screen
    property bool editAfter: false
    property bool picking: false
    property bool busy: false
    property string frozenUrl: ""
    property var windows: []
    property string lastPath: ""
    // what the preview card shows: the last screenshot, or a recording that just finished
    property string previewPath: ""
    property bool previewVideo: false
    property int previewSeconds: 0
    property string previewSize: ""
    property string previewThumb: ""
    readonly property string thumbFile: Quickshell.cachePath("recording-thumb.jpg")

    // after a recording (shell.qml, Recorder.finished): a frame for the thumbnail + the size, then the card
    function showRecording(path, seconds) {
        previewPath = path;
        previewVideo = true;
        previewSeconds = seconds;
        previewSize = "";
        previewThumb = "";
        thumbProc.command = ["sh", "-c",
            'ffmpeg -y -loglevel error -ss "$3" -i "$1" -frames:v 1 -vf scale=640:-2 "$2" </dev/null >/dev/null 2>&1; stat -c %s "$1"',
            "sh", path, thumbFile, seconds >= 2 ? "1" : "0"];
        thumbProc.running = true;
    }
    Process {
        id: thumbProc
        stdout: StdioCollector {
            onStreamFinished: {
                const b = Number(text.trim());
                root.previewSize = b > 0 ? Fmt.bytes(b) : "";
                // the same cache path every time: a query string makes the Image reload it
                root.previewThumb = "file://" + root.thumbFile + "?" + Date.now();
                preview.show();
            }
        }
    }
    property bool instant: false             // full screen, no UI
    property bool recordMode: false          // pick an area to record instead of a screenshot

    signal toastRequested(string msg, string icon, color clr)
    signal frozen()                          // the picker is up with the frozen frame

    readonly property string script: Quickshell.shellDir + "/scripts/screenshot.py"
    readonly property string frozenFile: Quickshell.cachePath("screenshot-freeze.png")

    // the monitor with focus
    // Picked when a capture starts, not bound live: re-targeting a mapped window on a focus
    // change crashes Quickshell (setScreen on a visible window).
    property var targetScreen: pickScreen()
    function pickScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        return Quickshell.screens.find(s => s.name === name) || Quickshell.screens[0];
    }

    // ── API ─────────────────────────────────────────────────────────────────
    function open(m, delay) {
        if (busy || picking) return;
        targetScreen = pickScreen();
        recordMode = false;
        _open(m, delay);
    }
    // pick an area to record; "screen" starts at once on the focused monitor
    function record(m, delay) {
        if (busy || picking || Recorder.recording) return;
        if (m === "screen") { recordStart.geometry = ""; recordStart.interval = Math.max(delay || 0, 1); recordStart.restart(); return; }
        recordMode = true;
        _open(m, delay);
    }
    function _open(m, delay) {
        mode = m || "region";
        instant = false;
        startTimer.interval = delay || 0;
        startTimer.restart();
    }
    function full(delay) {            // whole screen immediately, no picker
        if (busy || picking) return;
        instant = true;
        startTimer.interval = delay || 0;
        startTimer.restart();
    }
    function cancel() {
        picking = false;
        busy = false;
    }
    function commit(x, y, w, h) {
        if (w < 2 || h < 2) return;
        const f = picker.scaleFactor;
        picking = false;
        if (recordMode) {
            // whole monitor → by output name; otherwise global layout coords, even sizes (H.264)
            const whole = x <= 0 && y <= 0 && w >= picker.width && h >= picker.height;
            const s = root.targetScreen;
            recordStart.geometry = whole ? "" : Math.round(s.x + x) + "," + Math.round(s.y + y) + " "
                + (2 * Math.floor(w / 2)) + "x" + (2 * Math.floor(h / 2));
            recordStart.interval = 250;          // let the picker unmap first
            recordStart.restart();
            return;
        }
        cropProc.command = ["python3", script, "crop", frozenFile,
                            Math.round(x * f), Math.round(y * f), Math.round(w * f), Math.round(h * f)];
        cropProc.running = true;
    }

    Timer {
        id: recordStart
        property string geometry: ""
        onTriggered: Recorder.start(root.targetScreen.name, geometry)
    }

    Timer {
        id: startTimer
        onTriggered: {
            if (preview.shown) {               // don't freeze the previous preview card into the shot
                preview.shown = false;
                interval = Atelier.durClose + 80;
                restart();
                return;
            }
            root.busy = true;
            Quickshell.execDetached(["mkdir", "-p", Quickshell.cacheDir]);
            captureProc.command = ["python3", root.script, "capture", root.targetScreen.name, root.frozenFile];
            captureProc.running = true;
        }
    }

    Process {
        id: captureProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.frozenUrl = "file://" + root.frozenFile + "?" + Date.now();   // bust the image cache
                if (root.instant) {
                    root.busy = false;
                    cropProc.command = ["python3", root.script, "crop", root.frozenFile, 0, 0, 100000, 100000];
                    cropProc.running = true;
                } else {
                    windowsProc.command = ["python3", root.script, "windows", root.targetScreen.name];
                    windowsProc.running = true;
                    picker.reset();
                    root.picking = true;
                    root.busy = false;
                    root.frozen();
                }
            }
        }
        onExited: (code) => { if (code !== 0) { root.busy = false; root.toastRequested("Screenshot failed", "󰀦", Atelier.red); } }
    }

    Process {
        id: windowsProc
        stdout: StdioCollector { onStreamFinished: { try { root.windows = JSON.parse(text); } catch (e) { root.windows = []; } } }
    }

    Process {
        id: cropProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text.trim());
                    root.lastPath = r.path;
                    root.previewPath = r.path;
                    root.previewVideo = false;
                    if (root.editAfter) Quickshell.execDetached(["swappy", "-f", r.path, "-o", r.path]);
                    else preview.show();
                } catch (e) {
                    root.toastRequested("Screenshot failed", "󰀦", Atelier.red);
                }
            }
        }
    }

    // ═══ Picker ═════════════════════════════════════════════════════════════
    PanelWindow {
        id: picker
        screen: root.targetScreen
        visible: root.picking
        anchors { top: true; bottom: true; left: true; right: true }
        color: "black"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: root.picking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-screenshot"

        // frozen pixels per logical pixel (HiDPI-safe)
        readonly property real scaleFactor: frozen.implicitWidth > 0 ? frozen.implicitWidth / width : 1

        // current selection (logical px)
        property real sx: 0
        property real sy: 0
        property real sw: 0
        property real sh: 0
        property bool dragging: false
        property real ox: 0
        property real oy: 0
        property real mx: -100
        property real my: -100
        property var hovered: null

        readonly property bool hasSel: sw > 1 && sh > 1

        function reset() {
            sx = 0; sy = 0; sw = 0; sh = 0;
            dragging = false; hovered = null;
            if (root.mode === "screen") selectScreen();
        }
        function selectScreen() { sx = 0; sy = 0; sw = width; sh = height; }
        function windowAt(x, y) {
            for (const w of root.windows)
                if (x >= w.x && x < w.x + w.w && y >= w.y && y < w.y + w.h) return w;
            return null;
        }
        function selectWindow(w) {
            hovered = w;
            if (w) { sx = w.x; sy = w.y; sw = w.w; sh = w.h; } else { sw = 0; sh = 0; }
        }

        Connections {
            target: root
            function onModeChanged() {
                if (!root.picking) return;
                if (root.mode === "screen") picker.selectScreen();
                else if (root.mode === "window") picker.selectWindow(picker.windowAt(picker.mx, picker.my));
                else { picker.sw = 0; picker.sh = 0; }
            }
        }

        Image {
            id: frozen
            anchors.fill: parent
            source: root.frozenUrl
            cache: false
            smooth: false
            fillMode: Image.Stretch
        }

        // dim everything outside the selection
        Item {
            anchors.fill: parent
            readonly property color dim: Qt.rgba(0, 0, 0, 0.45)
            Rectangle { color: parent.dim; x: 0; y: 0; width: parent.width; height: picker.hasSel ? picker.sy : parent.height }
            Rectangle { color: parent.dim; visible: picker.hasSel; x: 0; y: picker.sy + picker.sh; width: parent.width; height: parent.height - y }
            Rectangle { color: parent.dim; visible: picker.hasSel; x: 0; y: picker.sy; width: picker.sx; height: picker.sh }
            Rectangle { color: parent.dim; visible: picker.hasSel; x: picker.sx + picker.sw; y: picker.sy; width: parent.width - x; height: picker.sh }
        }

        // crosshair (region mode, before dragging)
        Rectangle { visible: root.mode === "region" && !picker.dragging; x: 0; y: picker.my; width: parent.width; height: 1; color: Qt.alpha(Atelier.text, 0.35) }
        Rectangle { visible: root.mode === "region" && !picker.dragging; x: picker.mx; y: 0; width: 1; height: parent.height; color: Qt.alpha(Atelier.text, 0.35) }

        // selection outline + size label
        Rectangle {
            id: selRect
            visible: picker.hasSel
            x: picker.sx - 2
            y: picker.sy - 2
            width: picker.sw + 4
            height: picker.sh + 4
            radius: root.mode === "window" ? 16 : 4
            color: "transparent"
            border.width: 2
            border.color: Atelier.accent
            Behavior on x { enabled: root.mode === "window"; NumberAnimation { duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }
            Behavior on y { enabled: root.mode === "window"; NumberAnimation { duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }
            Behavior on width { enabled: root.mode === "window"; NumberAnimation { duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }
            Behavior on height { enabled: root.mode === "window"; NumberAnimation { duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }
        }

        Rectangle {
            visible: picker.hasSel && root.mode !== "screen"
            readonly property bool below: picker.sy < 40
            x: Math.min(picker.width - width - 8, Math.max(8, picker.sx))
            y: below ? picker.sy + picker.sh + 8 : picker.sy - height - 8
            implicitWidth: sizeLabel.implicitWidth + 18
            implicitHeight: 24
            radius: Atelier.radiusMd
            color: Atelier.surface
            Text {
                id: sizeLabel
                anchors.centerIn: parent
                text: Math.round(picker.sw * picker.scaleFactor) + " × " + Math.round(picker.sh * picker.scaleFactor)
                      + (root.mode === "window" && picker.hovered ? "   " + (picker.hovered.class || "") : "")
                font.family: Atelier.font
                font.pixelSize: Atelier.fsSm
                font.bold: true
                color: Atelier.text
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: root.mode === "region" ? Qt.CrossCursor : Qt.PointingHandCursor

            onPositionChanged: (m) => {
                picker.mx = m.x; picker.my = m.y;
                if (root.mode === "region" && picker.dragging) {
                    picker.sx = Math.min(picker.ox, m.x); picker.sy = Math.min(picker.oy, m.y);
                    picker.sw = Math.abs(m.x - picker.ox); picker.sh = Math.abs(m.y - picker.oy);
                } else if (root.mode === "window") {
                    const w = picker.windowAt(m.x, m.y);
                    if (w !== picker.hovered) picker.selectWindow(w);
                }
            }
            onPressed: (m) => {
                if (m.button === Qt.RightButton) { root.cancel(); return; }
                if (root.mode === "region") {
                    picker.dragging = true;
                    picker.ox = m.x; picker.oy = m.y;
                    picker.sx = m.x; picker.sy = m.y; picker.sw = 0; picker.sh = 0;
                }
            }
            onReleased: (m) => {
                if (m.button !== Qt.LeftButton) return;
                if (root.mode === "region") {
                    picker.dragging = false;
                    if (picker.sw > 4 && picker.sh > 4) root.commit(picker.sx, picker.sy, picker.sw, picker.sh);
                    else {   // a plain click grabs the window under the cursor
                        const w = picker.windowAt(m.x, m.y);
                        if (w) root.commit(w.x, w.y, w.w, w.h);
                    }
                } else if (picker.hasSel) {
                    root.commit(picker.sx, picker.sy, picker.sw, picker.sh);
                }
            }
        }

        Item {
            id: keys
            focus: root.picking
            Keys.onEscapePressed: root.cancel()
            Keys.onReturnPressed: if (picker.hasSel) root.commit(picker.sx, picker.sy, picker.sw, picker.sh)
            Keys.onEnterPressed: if (picker.hasSel) root.commit(picker.sx, picker.sy, picker.sw, picker.sh)
            Keys.onTabPressed: root.mode = root.mode === "region" ? "window" : root.mode === "window" ? "screen" : "region"
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_1) root.mode = "region";
                else if (e.key === Qt.Key_2) root.mode = "window";
                else if (e.key === Qt.Key_3) root.mode = "screen";
                else if (e.key === Qt.Key_E && !root.recordMode) root.editAfter = !root.editAfter;
                else if (e.key === Qt.Key_R) root.recordMode = !root.recordMode;
            }
        }
        onVisibleChanged: if (visible) keys.forceActiveFocus()

        // ── Toolbar drawer ───────────────────────────────────────────────────
        EdgeDrawer {
            id: toolbar
            edge: "bottom"
            open: root.picking && !picker.dragging
            bodyWidth: toolRow.implicitWidth + 28
            bodyHeight: 64

            RowLayout {
                id: toolRow
                anchors.centerIn: parent
                spacing: 8

                Repeater {
                    model: [
                        { id: "region", icon: "󰩭", label: "Region", key: "1" },
                        { id: "window", icon: "󰖯", label: "Window", key: "2" },
                        { id: "screen", icon: "󰍹", label: "Screen", key: "3" }
                    ]
                    Rectangle {
                        required property var modelData
                        readonly property bool on: root.mode === modelData.id
                        implicitWidth: modeRow.implicitWidth + 24
                        implicitHeight: 38
                        radius: Math.min(height / 2, Atelier.radiusSm)
                        color: on ? Atelier.accentFill : Atelier.container
                        Behavior on color { CAnim {} }
                        StateLayer { mouseArea: modeMa }
                        RowLayout {
                            id: modeRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: modelData.icon; font.family: Atelier.font; font.pixelSize: Atelier.fsXl; color: parent.parent.on ? Atelier.onFill : Atelier.text }
                            Text { text: modelData.label; font.family: Atelier.font; font.pixelSize: Atelier.fsSm; font.bold: true; color: parent.parent.on ? Atelier.onFill : Atelier.text }
                        }
                        MouseArea { id: modeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.mode = modelData.id }
                    }
                }

                Rectangle { implicitWidth: 1; implicitHeight: 24; color: Atelier.outline }

                // record instead of a screenshot
                Rectangle {
                    implicitWidth: recRow.implicitWidth + 22
                    implicitHeight: 38
                    radius: Math.min(height / 2, Atelier.radiusSm)
                    color: root.recordMode ? Qt.alpha(Atelier.red, 0.22) : Atelier.container
                    StateLayer { mouseArea: recMa }
                    border.width: root.recordMode ? 1 : 0
                    border.color: Qt.alpha(Atelier.red, 0.6)
                    Behavior on color { CAnim {} }
                    RowLayout {
                        id: recRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "󰑋"; font.family: Atelier.font; font.pixelSize: Atelier.iconSm; color: root.recordMode ? Atelier.red : Atelier.text }
                        Text { text: "Record"; font.family: Atelier.font; font.pixelSize: Atelier.fsSm; font.bold: true; color: root.recordMode ? Atelier.red : Atelier.text }
                    }
                    MouseArea { id: recMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.recordMode = !root.recordMode }
                }

                // edit afterwards (Swappy)
                Rectangle {
                    visible: !root.recordMode
                    implicitWidth: editRow.implicitWidth + 22
                    implicitHeight: 38
                    radius: Math.min(height / 2, Atelier.radiusSm)
                    color: root.editAfter ? Qt.alpha(Atelier.yellow, 0.25) : Atelier.container
                    StateLayer { mouseArea: editMa }
                    border.width: root.editAfter ? 1 : 0
                    border.color: Qt.alpha(Atelier.yellow, 0.6)
                    RowLayout {
                        id: editRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "󰏫"; font.family: Atelier.font; font.pixelSize: Atelier.iconSm; color: root.editAfter ? Atelier.yellow : Atelier.text }
                        Text { text: "Edit"; font.family: Atelier.font; font.pixelSize: Atelier.fsSm; font.bold: true; color: root.editAfter ? Atelier.yellow : Atelier.text }
                    }
                    MouseArea { id: editMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.editAfter = !root.editAfter }
                }

                // capture (window/screen) and cancel
                Rectangle {
                    visible: root.mode !== "region"
                    implicitWidth: 38
                    implicitHeight: 38
                    radius: Math.min(height / 2, Atelier.radiusSm)
                    color: capMa.containsMouse ? Qt.alpha(Atelier.green, 0.3) : Qt.alpha(Atelier.green, 0.18)
                    opacity: picker.hasSel ? 1 : 0.4
                    Text { anchors.centerIn: parent; text: "󰄀"; font.family: Atelier.font; font.pixelSize: Atelier.iconMd; color: Atelier.green }
                    MouseArea { id: capMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (picker.hasSel) root.commit(picker.sx, picker.sy, picker.sw, picker.sh) }
                }
                Rectangle {
                    implicitWidth: 38
                    implicitHeight: 38
                    radius: Math.min(height / 2, Atelier.radiusSm)
                    color: xMa.containsMouse ? Qt.alpha(Atelier.red, 0.25) : Atelier.container
                    Text { anchors.centerIn: parent; text: "󰅖"; font.family: Atelier.font; font.pixelSize: Atelier.fsXl; color: xMa.containsMouse ? Atelier.red : Atelier.text }
                    MouseArea { id: xMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.cancel() }
                }
            }
        }

        // hint
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Atelier.insetTop + 16
            visible: root.picking && !picker.dragging && !picker.hasSel
            implicitWidth: hint.implicitWidth + 28
            implicitHeight: 32
            radius: Atelier.radiusMd
            color: Atelier.surface
            Text {
                id: hint
                anchors.centerIn: parent
                text: (root.recordMode ? "Recording  ·  " : "")
                    + (root.mode === "region" ? "Drag to select  ·  click a window to " + (root.recordMode ? "record" : "grab") + " it  ·  Esc to cancel"
                    : root.mode === "window" ? "Hover a window and click  ·  Esc to cancel"
                    : "Click or press Enter to " + (root.recordMode ? "record" : "capture") + " the screen")
                font.family: Atelier.font
                font.pixelSize: Atelier.fsSm
                color: Atelier.text
            }
        }
    }

    // ═══ Preview card (after capture) ═══════════════════════════════════════
    PanelWindow {
        id: preview
        screen: root.targetScreen
        anchors { top: true; bottom: true; right: true }
        implicitWidth: 340 + Atelier.maxInset
        color: "transparent"
        visible: card.visible || shown
        mask: Region { item: card }

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-screenshot-preview"

        property bool shown: false
        function show() { shown = true; hideTimer.restart(); }
        Timer { id: hideTimer; interval: 6000; onTriggered: if (!cardHover.hovered) preview.shown = false; else restart() }

        EdgeDrawer {
            id: card
            edge: "right"
            open: preview.shown
            bodyWidth: 320
            bodyHeight: 252
            anchorPos: preview.height - Atelier.insetBottom - Atelier.rounding - 40 - total / 2

            HoverHandler { id: cardHover }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                ClippingRectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    radius: Atelier.radiusMd
                    color: Atelier.container
                    Image {
                        id: thumb
                        anchors.fill: parent
                        source: root.previewVideo ? root.previewThumb : (root.previewPath ? "file://" + root.previewPath : "")
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                        sourceSize.width: 600
                    }
                    // a recording: play mark over the frame (or alone, if no frame could be read)
                    Rectangle {
                        visible: root.previewVideo
                        anchors.centerIn: parent
                        width: 44; height: 44; radius: 22
                        color: Qt.rgba(0, 0, 0, 0.45)
                        Text { anchors.centerIn: parent; anchors.horizontalCenterOffset: 2; text: "󰐊"; font.family: Atelier.font; font.pixelSize: 22; color: "white" }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { Quickshell.execDetached(["xdg-open", root.previewPath]); preview.shown = false; } }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text { text: "󰄬"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: Atelier.green }
                    Text {
                        Layout.fillWidth: true
                        text: root.previewVideo
                              ? "Saved · " + Math.floor(root.previewSeconds / 60) + ":" + String(root.previewSeconds % 60).padStart(2, "0")
                                + (root.previewSize ? " · " + root.previewSize : "")
                              : "Copied & saved"
                        elide: Text.ElideRight
                        font.family: Atelier.font
                        font.pixelSize: Atelier.fsMd
                        font.bold: true
                        color: Atelier.text
                    }
                    PreviewBtn { icon: "󰏫"; tint: Atelier.yellow; visible: !root.previewVideo   // swappy edits images only
                        onClicked: { Quickshell.execDetached(["swappy", "-f", root.previewPath, "-o", root.previewPath]); preview.shown = false; } }
                    PreviewBtn { icon: "󰉖"; tint: Atelier.blue; onClicked: { Quickshell.execDetached(["xdg-open", root.previewPath.substring(0, root.previewPath.lastIndexOf("/"))]); preview.shown = false; } }
                    // AirDrop to a nearby iPhone: the AirDrop card takes over (pick the device, progress)
                    PreviewBtn { icon: "\u{F0003}"; tint: Atelier.sky; visible: AirDrop.available
                        onClicked: { AirDrop.send([root.previewPath]); preview.shown = false; } }
                    PreviewBtn { icon: "󰆴"; tint: Atelier.red; onClicked: {
                            Quickshell.execDetached(["rm", "-f", root.previewPath]);
                            if (!root.previewVideo) Quickshell.execDetached(["wl-copy", "--clear"]);   // screenshots were also copied
                            preview.shown = false;
                            root.toastRequested(root.previewVideo ? "Recording deleted" : "Screenshot deleted", "󰆴", Atelier.red);
                        } }
                }
            }
        }
    }

    component PreviewBtn: Rectangle {
        id: pb
        property string icon
        property color tint: Atelier.accent
        signal clicked()
        implicitWidth: 32
        implicitHeight: 32
        radius: Atelier.radiusMd
        color: pbMa.containsMouse ? Qt.alpha(tint, 0.25) : Atelier.container
        Text { anchors.centerIn: parent; text: pb.icon; font.family: Atelier.font; font.pixelSize: Atelier.iconSm; color: pbMa.containsMouse ? pb.tint : Atelier.text }
        MouseArea { id: pbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }
}
