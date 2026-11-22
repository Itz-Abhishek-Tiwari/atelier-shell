import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.config

// Settings → Displays. Lists every output Hyprland knows (`hyprctl monitors all -j`); a change
// writes that output's entry in Settings.displays.monitors, which Settings.qml applies live
// (atelier-mode.lua M.apply_monitors) and conf/monitors.lua applies at login. Every change asks
// "Keep these settings?" and goes back by itself after 15 s, so a bad mode can't strand you.
ColumnLayout {
    id: page
    Layout.fillWidth: true
    spacing: 20

    property var mons: []
    readonly property var saved: Settings.displays.monitors || []
    readonly property int enabledCount: mons.filter(m => !m.disabled).length

    Process {
        id: monProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: { try { page.mons = JSON.parse(text); } catch (e) {} }
        }
    }
    function refresh() { monProc.running = true; }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()
    Connections { target: Quickshell; function onScreensChanged() { refreshTimer.restart(); } }
    Timer { id: refreshTimer; interval: 900; onTriggered: page.refresh() }

    // ── helpers ─────────────────────────────────────────────────────────────
    function entry(name) { return page.saved.find(x => x.output === name); }
    function niceName(m) {
        if (/^eDP/.test(m.name)) return "Built-in display";
        const d = ((m.make || "") + " " + (m.model || "")).trim();
        return d || m.description || m.name;
    }
    function modeOf(m) { return m.width + "x" + m.height + "@" + m.refreshRate.toFixed(2) + "Hz"; }
    function parseMode(s) {
        const r = /^(\d+)x(\d+)@([\d.]+)/.exec(s || "");
        return r ? { w: +r[1], h: +r[2], hz: +r[3] } : null;
    }
    // the mode this output is set to: its saved entry, else what it runs at
    function curMode(m) {
        const e = entry(m.name);
        return (e && parseMode(e.mode)) || { w: m.width, h: m.height, hz: m.refreshRate };
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
        return out.sort((a, b) => b - a);
    }
    function hzLabel(hz) { return (Math.round(hz * 100) / 100).toString().replace(/\.?0+$/, "") + " Hz"; }

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
            list.push({ output: m.name, mode: modeOf(m), position: "auto", scale: m.scale, transform: m.transform });
            i = list.length - 1;
        }
        Object.assign(list[i], patch);
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

    // ── the confirmation banner ─────────────────────────────────────────────
    SettingCard {
        visible: page.pending
        SettingRow {
            label: "Keep these display settings?"
            description: "Going back to the previous ones in " + page.countdown + " s"
            RowLayout {
                spacing: 8
                Chip { icon: "󰜺"; text: "Revert"; tint: Atelier.red; interactive: true; implicitHeight: 32; onClicked: page.revert() }
                Chip { icon: "󰄬"; text: "Keep"; tint: Atelier.green; interactive: true; implicitHeight: 32; onClicked: page.keep() }
            }
        }
    }

    // ── arrangement: drag displays to place them ────────────────────────────
    // Boxes are the displays in layout pixels (rotation and scale applied), scaled to fit.
    // Dragging snaps the box edge-to-edge against the others (and lines its edges up with
    // theirs), so there are never gaps or overlaps; letting go writes "XxY" as its position
    // through change() → the usual Keep / Revert banner.
    property string selected: ""
    SettingCard {
        visible: page.enabledCount >= 1
        title: "Arrangement"
        Item {
            id: arr
            Layout.fillWidth: true
            implicitHeight: page.enabledCount > 1 ? 210 : 150
            readonly property var boxes: page.mons.filter(m => !m.disabled).map(m => {
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
                const padX = page.enabledCount > 1 ? spanW * 0.45 : spanW * 0.1;
                const padY = page.enabledCount > 1 ? spanH * 0.45 : spanH * 0.1;
                const k = Math.min((arr.width - 24) / (spanW + 2 * padX), (arr.height - 24) / (spanH + 2 * padY));
                return { minX: minX, minY: minY, spanW: spanW, spanH: spanH, k: k > 0 ? k : 0.05 };
            }
            onWidthChanged: frame = computeFrame(boxes)
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

            // faint grid
            Repeater {
                model: 9
                Rectangle { required property int index; x: arr.width * (index + 1) / 10; width: 1; height: arr.height; color: Atelier.outline; opacity: 0.5 }
            }

            Repeater {
                model: arr.boxes
                Rectangle {
                    id: box
                    required property var modelData
                    readonly property var b: modelData
                    readonly property bool sel: page.selected === b.name
                    readonly property bool movable: page.enabledCount > 1
                    // where it is drawn: its real spot, or the snapped spot while dragging
                    property var live: null
                    readonly property var at: arr.toView(live ? live.x : b.x, live ? live.y : b.y)
                    x: at.x + 2; y: at.y + 2
                    width: b.w * arr.frame.k - 4; height: b.h * arr.frame.k - 4
                    z: dragMa.drag.active ? 10 : (sel ? 2 : 1)
                    radius: 10
                    color: dragMa.pressed ? Qt.alpha(Atelier.accent, 0.30) : Qt.alpha(Atelier.accent, sel ? 0.22 : 0.10)
                    border.width: sel ? 2 : 1
                    border.color: Qt.alpha(Atelier.accent, sel ? 0.9 : 0.5)
                    Behavior on x { enabled: !dragMa.pressed; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on y { enabled: !dragMa.pressed; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: box.b.name
                            font.family: Atelier.font; font.pixelSize: 12; font.bold: true; color: Atelier.text }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; visible: box.height > 44
                            text: box.live ? box.live.x + ", " + box.live.y
                                : box.b.mon.width + "×" + box.b.mon.height + (box.b.mon.scale !== 1 ? " · " + (Math.round(box.b.mon.scale * 100) / 100) + "×" : "")
                            font.family: Atelier.font; font.pixelSize: 10; color: Atelier.subtext }
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

            Text {
                visible: page.enabledCount <= 1
                anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                text: "Connect another display to arrange them by dragging"
                font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext
            }
        }
        SettingRow {
            label: page.enabledCount > 1 ? "Drag a display to move it" : "Your display"
            description: page.enabledCount > 1 ? "It snaps to the edges of the others · click one to select it" : "Identify shows each display's name on it"
            Chip { icon: "󰍹"; text: "Identify"; tint: Atelier.accent; interactive: true; implicitHeight: 30; onClicked: identify.show() }
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
                required property var modelData
                screen: modelData
                anchors { top: true; left: true }
                margins { top: 40; left: 40 }
                implicitWidth: idText.implicitWidth + 56
                implicitHeight: idText.implicitHeight + 36
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                Rectangle {
                    anchors.fill: parent
                    radius: 20
                    color: Atelier.accentFill
                    Text {
                        id: idText
                        anchors.centerIn: parent
                        text: parent.parent.modelData.name
                        font.family: Atelier.font; font.pixelSize: 40; font.bold: true
                        color: Atelier.onFill
                    }
                }
            }
        }
    }

    Text {
        visible: page.mons.length === 0
        text: "Looking for displays…"
        font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.subtext
    }

    // ── one card per output ─────────────────────────────────────────────────
    Repeater {
        model: page.mons
        SettingCard {
            id: card
            required property var modelData
            readonly property var m: modelData
            readonly property var e: page.entry(m.name)
            readonly property var cur: page.curMode(m)
            readonly property string res: cur.w + "x" + cur.h
            readonly property var others: page.mons.filter(x => x.name !== m.name)
            title: page.niceName(m) + "  ·  " + m.name
            highlighted: page.selected === m.name

            SettingRow {
                label: m.disabled ? "Off" : (m.width + " × " + m.height + " at " + page.hzLabel(m.refreshRate))
                description: m.disabled ? "This display is turned off"
                    : ("Scale " + (Math.round(m.scale * 100) / 100) + "×" + (m.transform ? " · rotated" : "")
                       + (m.mirrorOf && m.mirrorOf !== "none" ? " · mirrors " + m.mirrorOf : "")
                       + (card.e ? " · your settings" : " · automatic"))
                Chip { visible: !!card.e; icon: "󰦛"; text: "Automatic"; tint: Atelier.lavender; interactive: true; implicitHeight: 30
                    onClicked: page.forget(card.m) }
            }
            SettingSwitch {
                visible: page.mons.length > 1
                label: "Use this display"
                description: !card.m.disabled && page.enabledCount <= 1 ? "Your only display can't be turned off" : ""
                checked: !card.m.disabled
                onToggled: (v) => {
                    if (!v && page.enabledCount <= 1) { checked = true; return; }
                    page.change(card.m, { disabled: !v });
                }
            }
            Stepper {
                visible: !card.m.disabled
                label: "Resolution"
                options: page.resolutions(card.m)
                value: card.res
                onPicked: (id) => {
                    const hz = page.rates(card.m, id)[0] || 60;
                    page.change(card.m, { mode: id + "@" + hz.toFixed(2) + "Hz" });
                }
            }
            Stepper {
                visible: !card.m.disabled && options.length > 1
                label: "Refresh rate"
                options: page.rates(card.m, card.res).map(hz => ({ id: hz.toFixed(2), label: page.hzLabel(hz) }))
                value: card.cur.hz.toFixed(2)
                onPicked: (id) => page.change(card.m, { mode: card.res + "@" + id + "Hz" })
            }
            SettingChoice {
                visible: !card.m.disabled
                label: "Scale"
                options: [{ id: "1", label: "100%" }, { id: "1.25", label: "125%" }, { id: "1.5", label: "150%" },
                          { id: "2", label: "200%" }, { id: "auto", label: "Auto" }]
                value: card.e ? String(card.e.scale) : String(Math.round(card.m.scale * 100) / 100)
                onPicked: (id) => page.change(card.m, { scale: id === "auto" ? "auto" : parseFloat(id) })
            }
            SettingChoice {
                visible: !card.m.disabled
                label: "Rotation"
                options: [{ id: "0", label: "Normal" }, { id: "1", label: "90°" }, { id: "2", label: "180°" }, { id: "3", label: "270°" }]
                value: String(card.e ? (card.e.transform || 0) : card.m.transform)
                onPicked: (id) => page.change(card.m, { transform: parseInt(id) })
            }
            SettingChoice {
                visible: !card.m.disabled && page.enabledCount > 1
                label: "Position"
                description: "Or drag it in Arrangement above"
                readonly property string pos: card.e ? (card.e.position || "auto") : "auto"
                options: [{ id: "auto", label: "Auto" }, { id: "auto-left", label: "Left" }, { id: "auto-right", label: "Right" },
                          { id: "auto-up", label: "Above" }, { id: "auto-down", label: "Below" }]
                    .concat(/^-?\d+x-?\d+$/.test(pos) ? [{ id: pos, label: "Placed (" + pos.replace("x", ", ") + ")" }] : [])
                value: pos
                onPicked: (id) => page.change(card.m, { position: id })
            }
            SettingChoice {
                visible: !card.m.disabled && card.others.length > 0
                label: "Mirror"
                description: "Show the same picture as another display"
                options: [{ id: "", label: "Off" }].concat(card.others.map(x => ({ id: x.name, label: x.name })))
                value: card.e && card.e.mirror ? card.e.mirror : ""
                onPicked: (id) => page.change(card.m, { mirror: id })
            }
            SettingChoice {
                visible: !card.m.disabled
                label: "Variable refresh rate"
                description: "Adaptive sync (FreeSync / G-Sync), if the display supports it"
                options: [{ id: "0", label: "Off" }, { id: "1", label: "On" }, { id: "2", label: "Fullscreen" }]
                value: card.e && card.e.vrr !== undefined ? String(card.e.vrr) : (card.m.vrr ? "1" : "0")
                onPicked: (id) => page.change(card.m, { vrr: parseInt(id) })
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        wrapMode: Text.Wrap
        text: "Displays you plug in later use their best mode automatically until you change them here. Settings are remembered per connector (eDP-1, HDMI-A-1…)."
        font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext
    }

    // ‹ value › picker for long lists (resolutions, refresh rates)
    component Stepper: SettingRow {
        id: st
        property var options: []
        property string value: ""
        signal picked(string id)
        readonly property int idx: options.findIndex(o => o.id === value)
        RowLayout {
            spacing: 6
            Chip { icon: "󰅁"; tint: Atelier.accent; interactive: st.idx < st.options.length - 1; implicitHeight: 30
                opacity: interactive ? 1 : 0.35
                onClicked: st.picked(st.options[Math.min(st.options.length - 1, st.idx + 1)].id) }
            Text {
                Layout.minimumWidth: 110
                horizontalAlignment: Text.AlignHCenter
                text: st.idx >= 0 ? st.options[st.idx].label : st.value.replace("x", " × ")
                font.family: Atelier.font; font.pixelSize: 12; color: Atelier.text
            }
            Chip { icon: "󰅂"; tint: Atelier.accent; interactive: st.idx > 0; implicitHeight: 30
                opacity: interactive ? 1 : 0.35
                onClicked: st.picked(st.options[Math.max(0, st.idx - 1)].id) }
        }
    }
}
