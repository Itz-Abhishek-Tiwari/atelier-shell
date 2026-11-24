import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config

// Settings → Shortcuts. Built-in shortcuts come from hypr/conf/keybinds.lua, which writes its
// registry to ~/.cache/atelier/keybinds.json. New keys / "off" go to Settings.keybinds.overrides,
// your own shortcuts to Settings.keybinds.custom; Settings.qml rebinds live (atelier_apply_binds).
ColumnLayout {
    id: page
    Layout.fillWidth: true
    spacing: 20

    property var binds: []                       // [{ id, keys, default }]
    FileView {
        path: Quickshell.env("HOME") + "/.cache/atelier/keybinds.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { page.binds = JSON.parse(text()); } catch (e) {} }
    }

    readonly property var overrides: Settings.keybinds.overrides || ({})
    readonly property var custom: Settings.keybinds.custom || []

    property string query: ""
    readonly property var sections: {
        const q = query.trim().toLowerCase();
        const by = {}, order = [];
        for (const b of binds) {
            const dot = b.id.indexOf(" · ");
            const sec = dot > 0 ? b.id.slice(0, dot) : "Other";
            const name = (dot > 0 ? b.id.slice(dot + 3) : b.id).replace(/ #(\d+)$/, " ($1)");
            if (q && !(name + " " + sec + " " + b.keys).toLowerCase().includes(q)) continue;
            if (!by[sec]) { by[sec] = []; order.push(sec); }
            by[sec].push(Object.assign({ name: name }, b));
        }
        return order.map(s => ({ name: s, items: by[s] }));
    }

    // ── key names ───────────────────────────────────────────────────────────
    readonly property var named: ({
        [Qt.Key_Space]: "SPACE", [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Return", [Qt.Key_Tab]: "Tab",
        [Qt.Key_Backspace]: "BackSpace", [Qt.Key_Delete]: "Delete", [Qt.Key_Insert]: "Insert",
        [Qt.Key_Home]: "Home", [Qt.Key_End]: "End", [Qt.Key_PageUp]: "Prior", [Qt.Key_PageDown]: "Next",
        [Qt.Key_Left]: "left", [Qt.Key_Right]: "right", [Qt.Key_Up]: "up", [Qt.Key_Down]: "down",
        [Qt.Key_Comma]: "comma", [Qt.Key_Less]: "comma", [Qt.Key_Period]: "period", [Qt.Key_Greater]: "period",
        [Qt.Key_Slash]: "slash", [Qt.Key_Question]: "slash", [Qt.Key_Backslash]: "backslash", [Qt.Key_Bar]: "backslash",
        [Qt.Key_Minus]: "minus", [Qt.Key_Underscore]: "minus", [Qt.Key_Equal]: "equal", [Qt.Key_Plus]: "equal",
        [Qt.Key_BracketLeft]: "bracketleft", [Qt.Key_BraceLeft]: "bracketleft",
        [Qt.Key_BracketRight]: "bracketright", [Qt.Key_BraceRight]: "bracketright",
        [Qt.Key_Semicolon]: "semicolon", [Qt.Key_Colon]: "semicolon", [Qt.Key_Apostrophe]: "apostrophe",
        [Qt.Key_QuoteDbl]: "apostrophe", [Qt.Key_QuoteLeft]: "grave", [Qt.Key_AsciiTilde]: "grave",
        [Qt.Key_Print]: "Print", [Qt.Key_Escape]: "Escape",
        [Qt.Key_Exclam]: "1", [Qt.Key_At]: "2", [Qt.Key_NumberSign]: "3", [Qt.Key_Dollar]: "4", [Qt.Key_Percent]: "5",
        [Qt.Key_AsciiCircum]: "6", [Qt.Key_Ampersand]: "7", [Qt.Key_Asterisk]: "8", [Qt.Key_ParenLeft]: "9", [Qt.Key_ParenRight]: "0"
    })
    readonly property var modKeys: [Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Control, Qt.Key_Alt,
                                    Qt.Key_Shift, Qt.Key_AltGr, Qt.Key_Hyper_L, Qt.Key_Hyper_R]
    function comboFrom(e) {
        let key = "";
        if (e.key >= Qt.Key_A && e.key <= Qt.Key_Z) key = String.fromCharCode(e.key);
        else if (e.key >= Qt.Key_0 && e.key <= Qt.Key_9) key = String.fromCharCode(e.key);
        else if (e.key >= Qt.Key_F1 && e.key <= Qt.Key_F24) key = "F" + (e.key - Qt.Key_F1 + 1);
        else key = page.named[e.key] || "";
        if (!key) return "";
        const mods = [];
        if (e.modifiers & Qt.MetaModifier) mods.push("SUPER");
        if (e.modifiers & Qt.ControlModifier) mods.push("Ctrl");
        if (e.modifiers & Qt.AltModifier) mods.push("Alt");
        if (e.modifiers & Qt.ShiftModifier) mods.push("Shift");
        return mods.concat([key]).join(" + ");
    }
    // "SUPER + Shift + d" and "shift+super+D" are the same combo
    function norm(s) {
        const parts = (s || "").split("+").map(x => x.trim().toUpperCase()).filter(x => x);
        const alias = { CONTROL: "CTRL", WIN: "SUPER", MOD4: "SUPER", META: "SUPER" };
        const mods = parts.slice(0, -1).map(p => alias[p] || p).sort();
        return mods.concat(parts.slice(-1)).join("+");
    }
    readonly property var pretty: ({ SUPER: "Super", SPACE: "Space", CTRL: "Ctrl", CONTROL: "Ctrl", ALT: "Alt", SHIFT: "Shift",
        LEFT: "←", RIGHT: "→", UP: "↑", DOWN: "↓", COMMA: ",", PERIOD: ".", SLASH: "/", BACKSLASH: "\\", MINUS: "-",
        EQUAL: "=", BRACKETLEFT: "[", BRACKETRIGHT: "]", SEMICOLON: ";", APOSTROPHE: "'", GRAVE: "`",
        RETURN: "Enter", BACKSPACE: "⌫", PRIOR: "PgUp", NEXT: "PgDn", ESCAPE: "Esc" })
    function caps(s) {
        return (s || "").split("+").map(x => x.trim()).filter(x => x)
            .map(x => page.pretty[x.toUpperCase()] || (x.length === 1 ? x.toUpperCase() : x));
    }
    // who else uses this combo (built-in or custom), "" if nobody
    function owner(combo, selfId) {
        const n = norm(combo);
        for (const b of binds) if (b.id !== selfId && b.keys && norm(b.keys) === n) return b.id.replace(" · ", " → ");
        for (let i = 0; i < custom.length; i++)
            if ("custom:" + i !== selfId && norm(custom[i].keys) === n) return "Your shortcut “" + (custom[i].label || custom[i].cmd) + "”";
        return "";
    }

    // ── editing ─────────────────────────────────────────────────────────────
    property string capturing: ""                // bind id, or "custom:<index>"
    property string message: ""
    function setOverride(id, keys) {
        const o = Object.assign({}, page.overrides);
        const b = binds.find(x => x.id === id);
        if (b && keys === b.default) delete o[id]; else o[id] = keys;
        Settings.keybinds.overrides = o;
    }
    function resetOne(id) {
        const o = Object.assign({}, page.overrides);
        delete o[id];
        Settings.keybinds.overrides = o;
    }
    function setCustom(i, key, val) {
        const a = page.custom.map(x => Object.assign({}, x));
        a[i][key] = val;
        Settings.keybinds.custom = a;
    }
    function startCapture(id) { message = ""; capturing = id; catcher.forceActiveFocus(); }
    function finishCapture(combo) {
        const id = capturing;
        capturing = "";
        const who = owner(combo, id);
        if (who) { message = caps(combo).join(" + ") + " is already " + who; return; }
        message = "";
        if (id.startsWith("custom:")) setCustom(parseInt(id.slice(7)), "keys", combo);
        else setOverride(id, combo);
    }

    // takes the keyboard while capturing a combo
    Item {
        id: catcher
        width: 0; height: 0
        onActiveFocusChanged: if (!activeFocus) page.capturing = ""
        Keys.onPressed: (e) => {
            e.accepted = true;
            if (!page.capturing || e.isAutoRepeat || page.modKeys.indexOf(e.key) >= 0) return;
            if (e.key === Qt.Key_Escape && !(e.modifiers & ~Qt.KeypadModifier)) { page.capturing = ""; return; }
            const c = page.comboFrom(e);
            if (c) page.finishCapture(c);
        }
    }

    // ── header ──────────────────────────────────────────────────────────────
    SettingCard {
        SettingRow {
            label: "Find a shortcut"
            description: Object.keys(page.overrides).length ? Object.keys(page.overrides).length + " changed from the defaults" : "All built-in shortcuts are at their defaults"
            RowLayout {
                spacing: 8
                Rectangle {
                    implicitWidth: 200; implicitHeight: 34; radius: Atelier.radiusLg
                    color: Atelier.containerHigh
                    border.width: 1
                    border.color: q.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                    TextInput {
                        id: q
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                        verticalAlignment: Text.AlignVCenter
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.text
                        clip: true
                        onTextChanged: page.query = text
                        Text { anchors.verticalCenter: parent.verticalCenter; visible: !q.text; text: "Name or keys"
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext; opacity: 0.6 }
                    }
                }
                Chip { visible: Object.keys(page.overrides).length > 0; icon: "󰦛"; text: "Reset all"; tint: Atelier.red
                    interactive: true; implicitHeight: 32; onClicked: Settings.keybinds.overrides = ({}) }
            }
        }
        SettingRow {
            visible: page.message !== ""
            label: page.message
            description: "Change or turn off that one first"
            Chip { icon: "󰅖"; tint: Atelier.subtext; interactive: true; implicitHeight: 28; onClicked: page.message = "" }
        }
    }

    // ── your own ────────────────────────────────────────────────────────────
    SettingCard {
        title: "Your shortcuts"
        Text {
            visible: page.custom.length === 0
            Layout.topMargin: 12; Layout.bottomMargin: 4
            text: "Run any command from a key combination"
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
        }
        Repeater {
            model: page.custom
            Item {
                id: cr
                required property var modelData
                required property int index
                readonly property string cid: "custom:" + index
                Layout.fillWidth: true
                implicitHeight: 54
                Rectangle { visible: cr.index > 0; width: parent.width; height: 1; color: Atelier.outline }
                RowLayout {
                    anchors.fill: parent
                    spacing: 10
                    InlineField { Layout.preferredWidth: 150; text: cr.modelData.label || ""; placeholder: "Name"
                        onCommitted: (t) => page.setCustom(cr.index, "label", t) }
                    InlineField { Layout.fillWidth: true; text: cr.modelData.cmd || ""; placeholder: "Command, e.g. obsidian"; mono: true
                        onCommitted: (t) => page.setCustom(cr.index, "cmd", t) }
                    KeyButton { combo: cr.modelData.keys || ""; active: page.capturing === cr.cid; onClicked: page.startCapture(cr.cid) }
                    Chip { icon: "󰆴"; tint: Atelier.red; interactive: true; implicitHeight: 30
                        onClicked: Settings.keybinds.custom = page.custom.filter((x, k) => k !== cr.index) }
                }
            }
        }
        Chip { Layout.topMargin: 8; Layout.bottomMargin: 12; icon: "󰐕"; text: "Add shortcut"; tint: Atelier.accent; interactive: true; implicitHeight: 32
            onClicked: Settings.keybinds.custom = page.custom.concat([{ keys: "", cmd: "", label: "" }]) }
    }

    // ── built-in, by section ────────────────────────────────────────────────
    Repeater {
        model: page.sections
        SettingCard {
            id: sec
            required property var modelData
            title: modelData.name
            Repeater {
                model: sec.modelData.items
                SettingRow {
                    id: br
                    required property var modelData
                    readonly property bool changed: page.overrides[modelData.id] !== undefined
                    readonly property bool off: modelData.keys === ""
                    readonly property bool mouse: /mouse/i.test(modelData.default)
                    label: modelData.name
                    description: changed ? (off ? "Turned off · " : "Changed · ") + "default " + page.caps(modelData.default).join(" + ") : ""
                    RowLayout {
                        spacing: 8
                        KeyButton {
                            combo: br.modelData.keys
                            active: page.capturing === br.modelData.id
                            enabled: !br.mouse
                            onClicked: page.startCapture(br.modelData.id)
                        }
                        Chip { visible: br.changed; icon: "󰦛"; tint: Atelier.lavender; interactive: true; implicitHeight: 30
                            onClicked: page.resetOne(br.modelData.id) }
                        Chip { visible: !br.off; icon: "󰐥"; tint: Atelier.subtext; interactive: true; implicitHeight: 30
                            onClicked: page.setOverride(br.modelData.id, "") }
                    }
                }
            }
        }
    }

    Text {
        visible: page.binds.length === 0
        text: "Shortcuts appear here once Hyprland has loaded conf/keybinds.lua"
        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        wrapMode: Text.Wrap
        text: "Click the keys to record new ones, Esc cancels. Combos Hyprland already uses never reach this window, so turn the other shortcut off first. Groups like Super + 1 … 0 stay as they are in hypr/conf/keybinds.lua."
        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
    }

    // keycaps of a combo; click to record a new one
    component KeyButton: Rectangle {
        id: kb
        property string combo: ""
        property bool active: false
        signal clicked()
        implicitWidth: Math.max(96, capsRow.implicitWidth + 16)
        implicitHeight: 32
        radius: Atelier.radiusSm
        color: active ? Qt.alpha(Atelier.accent, 0.16) : (kbMa.containsMouse && enabled ? Atelier.containerHigh : "transparent")
        border.width: 1
        border.color: active ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Row {
            id: capsRow
            anchors.centerIn: parent
            spacing: 4
            Text { visible: kb.active; text: "Press keys…"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.accent }
            Text { visible: !kb.active && kb.combo === ""; text: "Off"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext }
            Repeater {
                model: kb.active ? [] : page.caps(kb.combo)
                Rectangle {
                    required property var modelData
                    implicitWidth: Math.max(22, t.implicitWidth + 12); implicitHeight: 22; radius: 6
                    color: Atelier.containerHigh
                    border.width: 1; border.color: Atelier.outline
                    Text { id: t; anchors.centerIn: parent; text: modelData; font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; color: Atelier.text }
                }
            }
        }
        MouseArea { id: kbMa; anchors.fill: parent; hoverEnabled: true; enabled: kb.enabled
            cursorShape: Qt.PointingHandCursor; onClicked: kb.clicked() }
    }

    // compact text field for the custom rows
    component InlineField: Rectangle {
        id: f
        property string text: ""
        property string placeholder: ""
        property bool mono: false
        signal committed(string text)
        implicitHeight: 32
        radius: Atelier.radiusMd
        color: Atelier.containerHigh
        border.width: 1
        border.color: fin.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
        TextInput {
            id: fin
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
            verticalAlignment: Text.AlignVCenter
            font.family: f.mono ? Atelier.font : Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.text
            clip: true; selectByMouse: true
            text: f.text
            onEditingFinished: if (text !== f.text) f.committed(text)
            Connections { target: f; function onTextChanged() { if (!fin.activeFocus) fin.text = f.text; } }
            Text { anchors.verticalCenter: parent.verticalCenter; visible: !fin.text && !fin.activeFocus; text: f.placeholder
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext; opacity: 0.6 }
        }
    }
}
