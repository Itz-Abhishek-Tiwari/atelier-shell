import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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

    // ── arrangement preview ─────────────────────────────────────────────────
    SettingCard {
        visible: page.enabledCount > 1
        title: "Arrangement"
        Item {
            id: arr
            Layout.fillWidth: true
            implicitHeight: 150
            readonly property var boxes: page.mons.filter(m => !m.disabled).map(m => {
                const rot = m.transform % 2 === 1;
                const w = (rot ? m.height : m.width) / m.scale, h = (rot ? m.width : m.height) / m.scale;
                return { name: m.name, x: m.x, y: m.y, w: w, h: h, focused: m.focused };
            })
            readonly property real minX: Math.min.apply(null, boxes.map(b => b.x).concat([0]))
            readonly property real minY: Math.min.apply(null, boxes.map(b => b.y).concat([0]))
            readonly property real spanW: Math.max.apply(null, boxes.map(b => b.x + b.w).concat([1])) - minX
            readonly property real spanH: Math.max.apply(null, boxes.map(b => b.y + b.h).concat([1])) - minY
            readonly property real k: Math.min((width - 24) / spanW, (height - 24) / spanH)
            Repeater {
                model: arr.boxes
                Rectangle {
                    required property var modelData
                    x: (arr.width - arr.spanW * arr.k) / 2 + (modelData.x - arr.minX) * arr.k
                    y: (arr.height - arr.spanH * arr.k) / 2 + (modelData.y - arr.minY) * arr.k
                    width: modelData.w * arr.k - 4; height: modelData.h * arr.k - 4
                    radius: 8
                    color: Qt.alpha(Atelier.accent, modelData.focused ? 0.22 : 0.10)
                    border.width: 1
                    border.color: Qt.alpha(Atelier.accent, 0.5)
                    Text { anchors.centerIn: parent; text: modelData.name; font.family: Atelier.font; font.pixelSize: 11; color: Atelier.text }
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
                description: "Where it sits next to your other displays"
                options: [{ id: "auto", label: "Auto" }, { id: "auto-left", label: "Left" }, { id: "auto-right", label: "Right" },
                          { id: "auto-up", label: "Above" }, { id: "auto-down", label: "Below" }]
                value: card.e ? (card.e.position || "auto") : "auto"
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
