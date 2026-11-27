import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.config

// Settings → Displays. Lists every output Hyprland knows (`hyprctl -j monitors all`); a change
// writes that output's entry in Settings.displays.monitors. Settings.qml saves the monitor
// rules and reloads Hyprland, which applies them through conf/monitors.lua. Every change asks
// "Keep these settings?" and goes back by itself after 15 s, so a bad mode can't strand you.
ColumnLayout {
    id: page
    Layout.fillWidth: true
    spacing: 18

    property var mons: []
    readonly property var saved: Settings.displays.monitors || []
    property string monitorError: ""
    property string monitorSnapshot: ""
    readonly property var arranged: mons.filter(m => !m.disabled && (!m.mirrorOf || m.mirrorOf === "none"))

    Process {
        id: monProc
        command: ["hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const monitors = JSON.parse(text);
                    if (!Array.isArray(monitors)) throw new Error("Expected a monitor list");
                    page.monitorError = "";
                    if (!arr.dragging && text !== page.monitorSnapshot) {
                        page.monitorSnapshot = text;
                        page.mons = monitors;
                        if (!monitors.some(m => m.name === page.selected))
                            page.selected = page.selectedOutput;
                    }
                } catch (e) {
                    page.monitorError = "Could not read displays from Hyprland";
                }
            }
        }
    }
    function refresh() { monProc.running = true; }
    onVisibleChanged: {
        if (visible) refresh();
        else if (pending) revert();
    }
    Component.onCompleted: refresh()
    Connections { target: Quickshell; function onScreensChanged() { refreshTimer.restart(); } }
    Timer { interval: 1500; repeat: true; running: page.visible; onTriggered: page.refresh() }
    Timer { id: refreshTimer; interval: 900; onTriggered: page.refresh() }

    // ── helpers ─────────────────────────────────────────────────────────────
    function entry(name) { return page.saved.find(x => x && x.output === name); }
    function niceName(m) {
        if (/^eDP/.test(m.name)) return "Built-in display";
        const d = ((m.make || "") + " " + (m.model || "")).trim();
        return d || m.description || m.name;
    }
    function parseMode(s) {
        const r = /^(\d+)x(\d+)@([\d.]+)/.exec(s || "");
        return r ? { w: +r[1], h: +r[2], hz: +r[3] } : null;
    }
    function supportsMode(m, mode) {
        const requested = parseMode(mode);
        return requested && (m.availableModes || []).some(s => {
            const offered = parseMode(s);
            return offered && offered.w === requested.w && offered.h === requested.h && offered.hz === requested.hz;
        });
    }
    function scaleFits(mode, scale) {
        if (typeof scale !== "number" || !mode) return true;
        return [mode.w, mode.h].every(n => Math.abs(n / scale - Math.round(n / scale)) < 0.001);
    }
    function resolutions(m) {
        const seen = {}, out = [];
        for (const s of (m.availableModes || [])) {
            const p = parseMode(s);
            if (!p) continue;
            const k = p.w + "x" + p.h;
            if (!seen[k]) { seen[k] = true; out.push({ id: k, label: p.w + " × " + p.h, area: p.w * p.h }); }
        }
        return out.sort((a, b) => b.area - a.area);
    }
    function rates(m, res) {
        const out = [];
        for (const s of (m.availableModes || [])) {
            const p = parseMode(s);
            if (p && p.w + "x" + p.h === res) out.push(p.hz);
        }
        return Array.from(new Set(out)).sort((a, b) => b - a);
    }
    function hzLabel(hz) { return (Math.round(hz * 100) / 100).toString() + " Hz"; }

    // ── change / keep / revert ──────────────────────────────────────────────
    property bool pending: false
    property int countdown: 0
    property var backup: []
    function begin() {
        if (!pending) backup = JSON.parse(JSON.stringify(page.saved));
        pending = true;
        countdown = 15;
        confirmTimer.restart();
        refreshTimer.restart();
    }
    function change(m, patch) {
        const list = page.saved.map(x => Object.assign({}, x));
        let i = list.findIndex(x => x.output === m.name);
        if (i < 0) {
            list.push({ output: m.name, mode: "preferred", position: "auto", scale: m.scale || 1, transform: m.transform || 0 });
            i = list.length - 1;
        }
        const next = Object.assign(list[i], patch);
        if (m.availableModes && m.availableModes.length && parseMode(next.mode) && !supportsMode(m, next.mode)) next.mode = "preferred";
        if (patch.mode && !scaleFits(parseMode(next.mode), next.scale)) next.scale = 1;
        begin();
        Settings.displays.monitors = list;
    }
    function forget(m) {
        begin();
        Settings.displays.monitors = page.saved.filter(x => x.output !== m.name);
    }
    function keep() { pending = false; confirmTimer.stop(); }
    function revert() {
        confirmTimer.stop();
        pending = false;
        Settings.displays.monitors = backup;
        refreshTimer.restart();
    }
    Timer {
        id: confirmTimer
        interval: 1000; repeat: true
        onTriggered: { page.countdown--; if (page.countdown <= 0) page.revert(); }
    }

    Controls.Popup {
        id: confirmation
        parent: Controls.Overlay.overlay
        visible: page.pending && page.visible
        closePolicy: Controls.Popup.NoAutoClose
        focus: true
        width: parent ? Math.min(parent.width - 24, 600) : 600
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? parent.height - height - 16 : 0
        padding: 14
        background: Rectangle {
            radius: Atelier.radiusMd
            color: Atelier.base
            border.color: Atelier.accent
        }
        contentItem: ColumnLayout {
            spacing: 8
            SettingRow {
                label: "Keep these display settings?"
                description: "Reverting in " + page.countdown + " s"
                Row {
                    spacing: 6
                    Chip { text: "Revert"; variant: "secondary"; interactive: true; onClicked: page.revert() }
                    Chip { text: "Keep"; variant: "primary"; interactive: true; onClicked: page.keep() }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 3
                radius: 2
                color: Atelier.outline
                Rectangle {
                    width: parent.width * page.countdown / 15
                    height: parent.height
                    radius: parent.radius
                    color: Atelier.accent
                }
            }
        }
    }

    // ── arrangement: drag displays to place them ────────────────────────────
    // Boxes are the displays in layout pixels (rotation and scale applied), scaled to fit.
    // Dragging snaps the box edge-to-edge against the others (and lines its edges up with
    // theirs), so there are never gaps or overlaps; letting go writes "XxY" as its position
    // through change() → the usual Keep / Revert banner.
    property string selected: ""
    readonly property string selectedOutput: mons.some(m => m.name === selected) ? selected
        : (arranged.find(m => m.focused) || arranged[0] || mons[0] || {}).name || ""
    SettingCard {
        visible: page.arranged.length >= 1
        SettingRow {
            label: "Display arrangement"
            description: page.arranged.length > 1 ? "Drag displays to match their physical placement" : ""
            Chip { icon: "󰍹"; text: "Identify"; variant: "secondary"; interactive: true; onClicked: identify.show() }
        }
        Rectangle {
            id: arr
            Layout.fillWidth: true
            Layout.bottomMargin: 12
            implicitHeight: page.arranged.length > 1 ? 230 : 164
            radius: Atelier.radiusMd
            color: Qt.alpha(Atelier.outline, 0.18)
            clip: true
            readonly property var boxes: page.arranged.map(m => {
                const rot = m.transform % 2 === 1;
                const w = Math.round((rot ? m.height : m.width) / m.scale), h = Math.round((rot ? m.width : m.height) / m.scale);
                return { name: m.name, mon: m, x: m.x, y: m.y, w: w, h: h, focused: m.focused };
            })
            // the frame stays put while dragging (so the box doesn't chase the scale)
            property var frame: computeFrame(boxes)
            onBoxesChanged: if (!dragging) frame = computeFrame(boxes)
            property bool dragging: false
            function computeFrame(bs) {
                const minX = Math.min.apply(null, bs.map(b => b.x).concat([0]));
                const minY = Math.min.apply(null, bs.map(b => b.y).concat([0]));
                const spanW = Math.max.apply(null, bs.map(b => b.x + b.w).concat([1])) - minX;
                const spanH = Math.max.apply(null, bs.map(b => b.y + b.h).concat([1])) - minY;
                // leave room around the layout to drag into
                const padX = page.arranged.length > 1 ? spanW * 0.45 : spanW * 0.1;
                const padY = page.arranged.length > 1 ? spanH * 0.45 : spanH * 0.1;
                const k = Math.min((arr.width - 24) / (spanW + 2 * padX), (arr.height - 24) / (spanH + 2 * padY));
                return { minX: minX, minY: minY, spanW: spanW, spanH: spanH, k: k > 0 ? k : 0.05 };
            }
            onWidthChanged: if (!dragging) frame = computeFrame(boxes)
            onHeightChanged: if (!dragging) frame = computeFrame(boxes)
            function toView(lx, ly) {
                const f = frame;
                return { x: (arr.width - f.spanW * f.k) / 2 + (lx - f.minX) * f.k, y: (arr.height - f.spanH * f.k) / 2 + (ly - f.minY) * f.k };
            }
            function toLayout(vx, vy) {
                const f = frame;
                return { x: f.minX + (vx - (arr.width - f.spanW * f.k) / 2) / f.k, y: f.minY + (vy - (arr.height - f.spanH * f.k) / 2) / f.k };
            }
            // nearest edge-to-edge spot next to any other display, edges aligned when close
            function snap(b, px, py) {
                const others = boxes.filter(o => o.name !== b.name);
                if (!others.length) return { x: b.x, y: b.y };
                const thr = 80;                                  // layout px: "close enough" to line up
                const clampAlign = (v, lo, hi, a1, a2) => {
                    v = Math.max(lo, Math.min(hi, v));
                    if (Math.abs(v - a1) < thr) v = a1; else if (Math.abs(v - a2) < thr) v = a2;
                    return v;
                };
                let best = null;
                for (const o of others) {
                    const cands = [
                        { x: o.x + o.w, y: clampAlign(py, o.y - b.h + 1, o.y + o.h - 1, o.y, o.y + o.h - b.h) },   // right of o
                        { x: o.x - b.w, y: clampAlign(py, o.y - b.h + 1, o.y + o.h - 1, o.y, o.y + o.h - b.h) },   // left
                        { y: o.y + o.h, x: clampAlign(px, o.x - b.w + 1, o.x + o.w - 1, o.x, o.x + o.w - b.w) },   // below
                        { y: o.y - b.h, x: clampAlign(px, o.x - b.w + 1, o.x + o.w - 1, o.x, o.x + o.w - b.w) }    // above
                    ];
                    for (const c of cands) {
                        // no overlap with any other display
                        if (others.some(q => c.x < q.x + q.w && c.x + b.w > q.x && c.y < q.y + q.h && c.y + b.h > q.y)) continue;
                        const d = Math.hypot(c.x - px, c.y - py);
                        if (!best || d < best.d) best = { x: Math.round(c.x), y: Math.round(c.y), d: d };
                    }
                }
                return best ? best : { x: b.x, y: b.y };
            }

            Canvas {
                anchors.fill: parent
                property color dotColor: Atelier.subtext
                onDotColorChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.fillStyle = dotColor;
                    ctx.globalAlpha = 0.22;
                    for (let y = 12; y < height; y += 16)
                        for (let x = 12; x < width; x += 16)
                            ctx.fillRect(x, y, 2, 2);
                }
            }

            Repeater {
                model: arr.boxes
                Rectangle {
                    id: box
                    required property var modelData
                    readonly property var b: modelData
                    readonly property bool sel: page.selectedOutput === b.name
                    readonly property bool movable: page.arranged.length > 1
                    // where it is drawn: its real spot, or the snapped spot while dragging
                    property var live: null
                    readonly property var at: arr.toView(live ? live.x : b.x, live ? live.y : b.y)
                    x: at.x + 2; y: at.y + 2
                    width: Math.max(1, b.w * arr.frame.k - 4)
                    height: Math.max(1, b.h * arr.frame.k - 4)
                    clip: true
                    z: dragMa.pressed ? 10 : (sel ? 2 : 1)
                    radius: Atelier.radiusSm
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.tint(Atelier.containerHigh, Qt.alpha(Atelier.accent, box.sel ? 0.32 : 0.12)) }
                        GradientStop { position: 1; color: Qt.tint(Atelier.container, Qt.alpha(Atelier.accent, box.sel ? 0.16 : 0.04)) }
                    }
                    border.width: sel ? 2 : 1
                    border.color: Qt.alpha(Atelier.accent, sel ? 0.9 : 0.5)
                    Behavior on x { enabled: !dragMa.pressed; NumberAnimation { duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.emphasizedDecel } }
                    Behavior on y { enabled: !dragMa.pressed; NumberAnimation { duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.emphasizedDecel } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: box.b.name
                            font.family: Atelier.font; font.pixelSize: Atelier.fsMd; font.bold: true; color: Atelier.text }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; visible: box.height > 44
                            text: box.live ? box.live.x + ", " + box.live.y
                                : box.b.mon.width + "×" + box.b.mon.height + (box.b.mon.scale !== 1 ? " · " + (Math.round(box.b.mon.scale * 100) / 100) + "×" : "")
                            font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; color: Atelier.subtext }
                    }
                    MouseArea {
                        id: dragMa
                        anchors.fill: parent
                        cursorShape: box.movable ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.PointingHandCursor
                        property point grab: Qt.point(0, 0)
                        onPressed: (m) => { page.selected = box.b.name; grab = Qt.point(m.x, m.y); if (box.movable) arr.dragging = true; }
                        onPositionChanged: (m) => {
                            if (!pressed || !box.movable) return;
                            const p = box.mapToItem(arr, m.x - grab.x, m.y - grab.y);
                            const l = arr.toLayout(p.x - 2, p.y - 2);
                            box.live = arr.snap(box.b, l.x, l.y);
                        }
                        onCanceled: {
                            box.live = null;
                            arr.dragging = false;
                            arr.frame = arr.computeFrame(arr.boxes);
                        }
                        onReleased: {
                            arr.dragging = false;
                            const l = box.live;
                            box.live = null;
                            if (l && (l.x !== box.b.x || l.y !== box.b.y))
                                page.change(box.b.mon, { position: l.x + "x" + l.y });
                            arr.frame = arr.computeFrame(arr.boxes);
                        }
                    }
                }
            }

        }
    }

    Flow {
        Layout.fillWidth: true
        visible: page.mons.length > 1
        spacing: 8
        Repeater {
            model: page.mons
            Chip {
                required property var modelData
                text: modelData.name + (modelData.disabled ? " · Off" : "")
                icon: selected ? "󰄬" : "󰍹"
                variant: "secondary"
                selected: page.selectedOutput === modelData.name
                interactive: true
                implicitHeight: 34
                onClicked: page.selected = modelData.name
            }
        }
    }

    // "Identify": each display's name, big, on that display for 2.5 s
    QtObject {
        id: identify
        property bool on: false
        function show() { on = true; identifyTimer.restart(); }
    }
    Timer { id: identifyTimer; interval: 2500; onTriggered: identify.on = false }
    LazyLoader {
        active: identify.on
        Variants {
            model: Quickshell.screens
            PanelWindow {
                id: idWin
                required property var modelData
                screen: modelData
                // no anchors = centred on that display; Overlay so the open Settings drawer and
                // the bar can't cover it
                implicitWidth: idCol.implicitWidth + 72
                implicitHeight: idCol.implicitHeight + 48
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-identify"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                Rectangle {
                    anchors.fill: parent
                    radius: 28
                    color: Atelier.accentFill
                    Column {
                        id: idCol
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: idWin.modelData.name
                            font.family: Atelier.font; font.pixelSize: 44; font.bold: true
                            color: Atelier.onFill
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: idWin.modelData.width + " × " + idWin.modelData.height
                                // the model, unless it's only a raw panel code ("0xD1ED")
                                + (idWin.modelData.model && !/^0x[0-9a-f]+$/i.test(idWin.modelData.model) ? "  ·  " + idWin.modelData.model : "")
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsXl
                            color: Qt.alpha(Atelier.onFill, 0.8)
                        }
                    }
                }
            }
        }
    }

    Text {
        visible: page.mons.length === 0 || page.monitorError !== ""
        text: page.monitorError || "Looking for displays…"
        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
    }

    // Show controls for the selected connector.
    Repeater {
        model: page.mons
        SettingCard {
            id: card
            required property var modelData
            readonly property var m: modelData
            readonly property var e: page.entry(m.name)
            readonly property var cur: ({ w: m.width || 0, h: m.height || 0, hz: m.refreshRate || 0 })
            readonly property string res: cur.w + "x" + cur.h
            readonly property var others: page.arranged.filter(x => x.name !== m.name)
            readonly property bool canDisable: !page.arranged.includes(m) || page.arranged.length > 1
            visible: page.selectedOutput === m.name

            SettingRow {
                label: page.niceName(card.m)
                description: card.m.name + "  ·  " + (card.m.disabled ? "Off"
                    : card.m.width + " × " + card.m.height + "  ·  " + page.hzLabel(card.m.refreshRate)
                      + (card.m.mirrorOf && card.m.mirrorOf !== "none" ? "  ·  Mirrors " + card.m.mirrorOf : "")
                      + (!card.m.make && !card.m.model && !card.m.physicalWidth ? "\nOnly fallback modes may be available." : ""))
                Chip { visible: !!card.e; icon: "󰦛"; text: "Reset to automatic"; variant: "secondary"; interactive: true
                    onClicked: page.forget(card.m) }
            }
            SettingSwitch {
                visible: page.mons.length > 1
                label: "Use this display"
                description: !card.m.disabled && !card.canDisable ? "Keep one extended display on" : ""
                checked: !card.m.disabled
                onToggled: (v) => {
                    if (!v && !card.m.disabled && !card.canDisable) return;
                    page.change(card.m, { disabled: !v });
                }
            }
            DisplayChoice {
                visible: !card.m.disabled && options.length > 0
                label: "Resolution"
                options: page.resolutions(card.m)
                value: card.res
                onPicked: (id) => {
                    const hz = page.rates(card.m, id)[0] || 60;
                    page.change(card.m, { mode: id + "@" + hz.toFixed(2) + "Hz" });
                }
            }
            DisplayChoice {
                visible: !card.m.disabled && options.length > 1
                label: "Refresh rate"
                options: page.rates(card.m, card.res).map(hz => ({ id: hz.toFixed(2), label: page.hzLabel(hz) }))
                value: card.cur.hz.toFixed(2)
                onPicked: (id) => page.change(card.m, { mode: card.res + "@" + id + "Hz" })
            }
            DisplayChoice {
                visible: !card.m.disabled
                label: "Scale"
                options: [{ id: "1", label: "100%" }, { id: "1.25", label: "125%" }, { id: "1.5", label: "150%" },
                          { id: "2", label: "200%" }, { id: "auto", label: "Auto" }]
                    .filter(option => option.id === "auto" || page.scaleFits(card.cur, Number(option.id)))
                value: card.e && card.e.scale === "auto" ? "auto" : String(Math.round(card.m.scale * 100) / 100)
                onPicked: (id) => page.change(card.m, { scale: id === "auto" ? "auto" : parseFloat(id) })
            }
            DisplayChoice {
                visible: !card.m.disabled
                label: "Rotation"
                options: [{ id: "0", label: "Normal" }, { id: "1", label: "90°" }, { id: "2", label: "180°" }, { id: "3", label: "270°" }]
                value: String(card.m.transform)
                onPicked: (id) => page.change(card.m, { transform: parseInt(id) })
            }
            DisplayChoice {
                visible: page.arranged.includes(card.m) && page.arranged.length > 1
                label: "Position"
                description: "Or drag it in Arrangement above"
                readonly property string pos: card.e ? (card.e.position || "auto") : "auto"
                options: [{ id: "auto", label: "Auto" }, { id: "auto-left", label: "Left" }, { id: "auto-right", label: "Right" },
                          { id: "auto-up", label: "Above" }, { id: "auto-down", label: "Below" }]
                    .concat(/^-?\d+x-?\d+$/.test(pos) ? [{ id: pos, label: "Placed (" + pos.replace("x", ", ") + ")" }] : [])
                value: pos
                onPicked: (id) => page.change(card.m, { position: id })
            }
            DisplayChoice {
                visible: !card.m.disabled && card.others.length > 0
                label: "Mirror"
                description: "Show the same picture as another display"
                options: [{ id: "", label: "Off" }].concat(card.others.map(x => ({ id: x.name, label: x.name })))
                value: card.m.mirrorOf && card.m.mirrorOf !== "none" ? card.m.mirrorOf : ""
                onPicked: (id) => page.change(card.m, { mirror: id })
            }
            DisplayChoice {
                visible: !card.m.disabled && (!card.m.hardwareDetails || card.m.hardwareDetails.vrrCapable)
                label: "Variable refresh rate"
                description: "Adaptive sync (FreeSync / G-Sync), if the display supports it"
                options: [{ id: "0", label: "Off" }, { id: "1", label: "On" }, { id: "2", label: "Fullscreen" }]
                value: card.e && card.e.vrr !== undefined ? String(card.e.vrr) : (card.m.vrr ? "1" : "0")
                onPicked: (id) => page.change(card.m, { vrr: parseInt(id) })
            }
        }
    }
}
