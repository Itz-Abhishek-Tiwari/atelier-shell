import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config

// Keyboard shortcut helper: a bottom drawer listing every described Hyprland bind, read live
// from `hyprctl binds -j` on each open (so it always matches hypr/conf/keybinds.lua).
// Descriptions are "Section · What it does", optionally " @ keys" to override the key text.
// Binds with the same description are merged ("Print  /  Super + P").
// Keys: type to filter · Esc clears, then closes.   Open: Super+? · Control center → Shortcuts.
Item {
    id: root
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool isLight: Atelier.isLight
    property bool animActive: false
    property var sections: []         // [{ name, items: [{ desc, combos: [[cap, ...], ...] }] }]
    property double openedAt: 0

    signal closedSignal()

    // ── Data ────────────────────────────────────────────────────────────────
    readonly property var order: ["Shell", "Apps", "Windows", "Layout", "Workspaces", "Capture", "Media", "Modes"]
    function tint(name) {
        return name === "Shell" ? Atelier.accent : name === "Apps" ? Atelier.blue
             : name === "Windows" ? Atelier.green : name === "Layout" ? Atelier.teal
             : name === "Workspaces" ? Atelier.sapphire : name === "Capture" ? Atelier.red
             : name === "Media" ? Atelier.pink : name === "Modes" ? Atelier.peach : Atelier.lavender;
    }
    readonly property var keyNames: ({
        "SPACE": "Space", "space": "Space", "Return": "Enter", "BackSpace": "Backspace", "Tab": "Tab",
        "comma": ",", "period": ".", "slash": "/", "grave": "`", "bracketleft": "[", "bracketright": "]",
        "minus": "-", "equal": "=", "semicolon": ";", "apostrophe": "'", "backslash": "\\",
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "Left": "←", "Right": "→", "Up": "↑", "Down": "↓",
        "mouse:272": "Left drag", "mouse:273": "Right drag", "mouse:275": "Mouse back", "mouse:276": "Mouse forward",
        "mouse_up": "Scroll up", "mouse_down": "Scroll down", "Print": "Print",
        "XF86AudioPlay": "Play", "XF86AudioNext": "Next", "XF86AudioPrev": "Prev", "XF86AudioMicMute": "Mic mute"
    })
    function combo(b) {
        const caps = [];
        const m = b.modmask;
        if (m & 64) caps.push("Super");
        if (m & 4) caps.push("Ctrl");
        if (m & 8) caps.push("Alt");
        if (m & 1) caps.push("Shift");
        caps.push(keyNames[b.key] !== undefined ? keyNames[b.key] : (b.key.length === 1 ? b.key.toUpperCase() : b.key));
        return caps;
    }
    function load(json) {
        let binds = [];
        try { binds = JSON.parse(json); } catch (e) { return; }
        const bySection = {};
        const byDesc = {};
        for (const b of binds) {
            const d = (b.description || "").trim();
            if (!d) continue;
            const dot = d.indexOf(" · ");
            const section = dot > 0 ? d.slice(0, dot) : "Other";
            let text = dot > 0 ? d.slice(dot + 3) : d;
            let caps = null;
            const at = text.indexOf(" @ ");
            if (at > 0) { caps = text.slice(at + 3).split(" + "); text = text.slice(0, at); }
            caps = caps || combo(b);
            const id = section + "|" + text;
            if (!byDesc[id]) {
                byDesc[id] = { desc: text, combos: [] };
                (bySection[section] = bySection[section] || []).push(byDesc[id]);
            }
            const s = caps.join("+");
            if (!byDesc[id].combos.some(c => c.join("+") === s)) byDesc[id].combos.push(caps);
        }
        const names = order.filter(n => bySection[n]).concat(Object.keys(bySection).filter(n => order.indexOf(n) < 0));
        sections = names.map(n => ({ name: n, items: bySection[n] }));
    }

    // search: keep matching rows (description or keys); drop empty sections
    readonly property var shown: {
        const q = search.text.toLowerCase().trim();
        if (!q) return sections;
        return sections.map(s => ({
            name: s.name,
            items: s.items.filter(i => i.desc.toLowerCase().includes(q) || s.name.toLowerCase().includes(q)
                || i.combos.some(c => c.join(" ").toLowerCase().includes(q)))
        })).filter(s => s.items.length);
    }
    readonly property int total: sections.reduce((n, s) => n + s.items.length, 0)

    // sections spread over three columns, balanced by row count
    readonly property var columns: {
        const cols = [[], [], []], weight = [0, 0, 0];
        for (const s of shown) {
            const i = weight.indexOf(Math.min.apply(null, weight));
            cols[i].push(s);
            weight[i] += s.items.length + 2;
        }
        return cols;
    }

    Process {
        id: bindsProc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector { onStreamFinished: root.load(text) }
    }

    // ── Open / close ────────────────────────────────────────────────────────
    function toggle() { if (visible && animActive) close(); else open(); }
    function open() {
        visible = true;
        animActive = true;
        search.text = "";
        openedAt = Date.now();
        bindsProc.running = true;
        flick.contentY = 0;
        focusTimer.restart();
    }
    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }

    Timer { id: focusTimer; interval: 40; onTriggered: search.forceActiveFocus() }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!root.animActive) root.visible = false }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    // ── Drawer ──────────────────────────────────────────────────────────────
    EdgeDrawer {
        id: drawer
        edge: "bottom"
        open: root.animActive
        bodyWidth: Math.min(root.width - 160, 1020)
        bodyHeight: Math.min(root.height * 0.72, header.implicitHeight + grid.implicitHeight + 16 * 2 + 14)
        Behavior on bodyHeight { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }

        MouseArea { anchors.fill: parent }   // clicks inside don't close

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            // header
            RowLayout {
                id: header
                Layout.fillWidth: true
                spacing: 8
                Text { text: "󰌌"; font.family: Atelier.font; font.pixelSize: Atelier.iconMd; color: Atelier.accent }
                Text { text: "Keyboard shortcuts"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsXl; font.weight: Font.DemiBold; color: Atelier.text }
                Chip { text: root.total; mono: true; tint: Atelier.accent; implicitHeight: 20; pad: 7 }
                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 240
                    implicitHeight: 32
                    radius: Atelier.radiusMd
                    color: Atelier.container
                    border.width: 1
                    border.color: search.activeFocus ? Qt.alpha(Atelier.accent, 0.5) : Atelier.outline
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 8
                        Text { text: "󰍉"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: Atelier.subtext }
                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            font.family: Atelier.fontUi
                            font.pixelSize: Atelier.fsMd
                            color: Atelier.text
                            clip: true
                            selectByMouse: true
                            onTextChanged: flick.contentY = 0
                            // the opening key (Super+?) is still held for a moment: don't type its
                            // repeats (fresh presses go through, so fast typing keeps its first letter)
                            Keys.onPressed: (e) => {
                                if (e.isAutoRepeat && Date.now() - root.openedAt < 350) e.accepted = true;
                            }
                            Keys.onEscapePressed: { if (text) text = ""; else root.close(); }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !search.text
                                text: "Search shortcuts…"
                                font.family: Atelier.fontUi
                                font.pixelSize: Atelier.fsMd
                                color: Atelier.subtext
                                opacity: 0.6
                            }
                        }
                    }
                }
            }

            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: grid.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                SmoothWheel { flickable: flick }

                RowLayout {
                    id: grid
                    width: flick.width
                    spacing: 28

                    Repeater {
                        model: root.columns
                        ColumnLayout {
                            required property var modelData
                            Layout.preferredWidth: (grid.width - 2 * 28) / 3
                            Layout.alignment: Qt.AlignTop
                            spacing: 18

                            Repeater {
                                model: modelData
                                ColumnLayout {
                                    id: sec
                                    required property var modelData
                                    readonly property color tint: root.tint(modelData.name)
                                    Layout.fillWidth: true
                                    spacing: 7

                                    RowLayout {
                                        spacing: 7
                                        Rectangle { implicitWidth: 6; implicitHeight: 6; radius: 3; color: sec.tint }
                                        Text {
                                            text: sec.modelData.name.toUpperCase()
                                            font.family: Atelier.fontUi
                                            font.pixelSize: Atelier.fsMicro
                                            font.weight: Font.DemiBold
                                            font.letterSpacing: 1.2
                                            color: sec.tint
                                        }
                                    }

                                    Repeater {
                                        model: sec.modelData.items
                                        RowLayout {
                                            id: row
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 10
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignTop
                                                topPadding: 3
                                                text: row.modelData.desc
                                                font.family: Atelier.fontUi
                                                font.pixelSize: Atelier.fsMd
                                                color: Atelier.subtext1
                                                elide: Text.ElideRight
                                            }
                                            Column {
                                                Layout.alignment: Qt.AlignTop
                                                spacing: 4
                                                Repeater {
                                                    model: row.modelData.combos
                                                    Row {
                                                        id: comboRow
                                                        required property var modelData
                                                        anchors.right: parent.right
                                                        spacing: 3
                                                        Repeater {
                                                            model: comboRow.modelData
                                                            Rectangle {
                                                                required property string modelData
                                                                implicitWidth: Math.max(22, cap.implicitWidth + 12)
                                                                implicitHeight: 22
                                                                radius: 6
                                                                color: Atelier.container
                                                                border.width: 1
                                                                border.color: Atelier.outline
                                                                Text {
                                                                    id: cap
                                                                    anchors.centerIn: parent
                                                                    text: parent.modelData
                                                                    font.family: Atelier.fontUi
                                                                    font.pixelSize: Atelier.fsSm
                                                                    font.weight: Font.Medium
                                                                    color: Atelier.text
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.shown.length === 0 && root.sections.length > 0
                Layout.alignment: Qt.AlignHCenter
                text: "No shortcut matches “" + search.text + "”"
                font.family: Atelier.fontUi
                font.pixelSize: Atelier.fsMd
                color: Atelier.subtext
            }
        }
    }
}
