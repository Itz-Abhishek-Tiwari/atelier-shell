import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.config

// On-screen keyboard, built into the shell. Open with Super+/ (or `qs ipc call keyboard toggle`).
// It is a layer surface that NEVER takes keyboard focus, so keys go to whatever window (or the
// launcher/search field) you were typing in. Typing is done by `wtype`, which uses the Wayland
// virtual-keyboard protocol (no root needed): `sudo pacman -S wtype`.
//   · Shift / Ctrl / Alt / Super are one-shot latches (tap, then press a key); Caps is a lock.
//   · "More" page: Esc, F1–F12, navigation keys, and common shortcuts (copy, paste, undo, ...).
PanelWindow {
    id: root

    property bool shown: false
    property bool holdHidden: false          // brief un-map used to re-stack above newly opened overlays
    property string page: "main"             // main | more
    property bool shift: false               // one-shot
    property bool caps: false                // lock
    property bool ctrl: false
    property bool alt: false
    property bool sup: false
    property bool hasWtype: true

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: (shown || drawer.visible) && !holdHidden
    // only the drawn keyboard takes clicks; everything above it stays click-through
    mask: Region { x: drawer.x; y: drawer.y + drawer.height - drawer.depth; width: drawer.width; height: drawer.depth }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None       // never steal focus from the window being typed into
    WlrLayershell.namespace: "quickshell-keyboard"

    function toggle() { shown ? close() : open(); }
    function open() { shown = true; checkProc.running = true; }
    function close() { shown = false; releaseAll(); }
    // overlays opened later are stacked above us; briefly re-map so the keyboard stays on top
    function raise() { if (shown) { holdHidden = true; remap.restart(); } }
    Timer { id: remap; interval: 40; onTriggered: root.holdHidden = false }

    Process {
        id: checkProc
        command: ["sh", "-c", 'command -v wtype >/dev/null 2>&1 || test -x "$HOME/.local/bin/wtype"']
        onExited: (code) => root.hasWtype = code === 0
    }

    // ── Key sending ──────────────────────────────────────────────────────────
    function releaseAll() { shift = false; ctrl = false; alt = false; sup = false; }

    function latched() {
        const m = [];
        if (ctrl) m.push("ctrl");
        if (alt) m.push("alt");
        if (sup) m.push("logo");
        return m;
    }

    // run wtype with these arguments (resolved from PATH or ~/.local/bin)
    function wtype(args) {
        Quickshell.execDetached(["sh", "-c",
            'w=$(command -v wtype || echo "$HOME/.local/bin/wtype"); exec "$w" "$@"', "sh"].concat(args));
    }

    function withMods(mods, sym) {
        const a = [];
        for (const m of mods) a.push("-M", m);
        a.push("-k", sym);
        for (const m of mods.slice().reverse()) a.push("-m", m);
        return a;
    }

    function done() { shift = false; ctrl = false; alt = false; sup = false; }

    // a character key: { base, shifted, sym }
    function pressChar(k) {
        const letter = /^[a-z]$/.test(k.base);
        const up = letter ? (shift !== caps) : shift;
        const mods = latched();
        if (mods.length) wtype(withMods(up ? mods.concat(["shift"]) : mods, k.sym));
        else wtype(["--", up ? k.shifted : k.base]);
        done();
    }

    // a named key (Return, BackSpace, F5, Left, ...)
    function pressSym(sym, extraMods) {
        const mods = latched().concat(shift ? ["shift"] : []).concat(extraMods || []);
        wtype(mods.length ? withMods(mods, sym) : ["-k", sym]);
        done();
    }

    // a shortcut: modifiers + key, e.g. ctrl+c
    function combo(mods, sym) {
        wtype(withMods(mods, sym));
        done();
    }

    // ── Layout data ──────────────────────────────────────────────────────────
    function c(base, shifted, sym, w) { return { kind: "char", base: base, shifted: shifted, sym: sym, w: w || 1 }; }
    function letters(s) { return s.split("").map(ch => c(ch, ch.toUpperCase(), ch)); }
    function k(label, sym, w, rep) { return { kind: "sym", label: label, sym: sym, w: w || 1, repeat: !!rep }; }
    function m(id, label, w) { return { kind: "mod", id: id, label: label, w: w || 1 }; }
    function sc(label, mods, sym, w) { return { kind: "combo", label: label, mods: mods, sym: sym, w: w || 1 }; }
    function fkeys() { const a = []; for (let i = 1; i <= 12; i++) a.push(k("F" + i, "F" + i, 1)); return a; }

    readonly property var mainRows: [
        [c("`", "~", "grave"), c("1", "!", "1"), c("2", "@", "2"), c("3", "#", "3"), c("4", "$", "4"), c("5", "%", "5"),
         c("6", "^", "6"), c("7", "&", "7"), c("8", "*", "8"), c("9", "(", "9"), c("0", ")", "0"),
         c("-", "_", "minus"), c("=", "+", "equal"), k("⌫", "BackSpace", 2, true)],
        [k("Tab", "Tab", 1.5)].concat(letters("qwertyuiop")).concat([c("[", "{", "bracketleft"), c("]", "}", "bracketright"), c("\\", "|", "backslash", 1.5)]),
        [m("caps", "Caps", 1.8)].concat(letters("asdfghjkl")).concat([c(";", ":", "semicolon"), c("'", "\"", "apostrophe"), k("Enter", "Return", 2.2)]),
        [m("shift", "⇧ Shift", 2.3)].concat(letters("zxcvbnm")).concat([c(",", "<", "comma"), c(".", ">", "period"), c("/", "?", "slash"), m("shift", "⇧ Shift", 2.7)]),
        [m("ctrl", "Ctrl", 1.4), m("sup", "Super", 1.3), m("alt", "Alt", 1.3), k("", "space", 6, true),
         { kind: "page", label: "More", to: "more", w: 1.5 },
         k("←", "Left", 1, true), k("↑", "Up", 1, true), k("↓", "Down", 1, true), k("→", "Right", 1, true)]
    ]

    readonly property var moreRows: [
        [k("Esc", "Escape", 1.4)].concat(fkeys()),
        [k("Home", "Home"), k("End", "End"), k("PgUp", "Prior"), k("PgDn", "Next"), k("Ins", "Insert"),
         k("Del", "Delete", 1, true), k("PrtSc", "Print"), k("Menu", "Menu"), k("⌫", "BackSpace", 1.5, true), k("Enter", "Return", 1.5)],
        [sc("Copy", ["ctrl"], "c", 1.2), sc("Paste", ["ctrl"], "v", 1.2), sc("Cut", ["ctrl"], "x", 1.2), sc("Select all", ["ctrl"], "a", 1.4),
         sc("Undo", ["ctrl"], "z", 1.2), sc("Redo", ["ctrl", "shift"], "z", 1.2), sc("Save", ["ctrl"], "s", 1.2), sc("Find", ["ctrl"], "f", 1.2),
         sc("New tab", ["ctrl"], "t", 1.4), sc("Close tab", ["ctrl"], "w", 1.4)],
        [k("Tab", "Tab", 1.4), k("Alt+Tab", "Tab", 1.6), k("←", "Left", 1, true), k("↑", "Up", 1, true), k("↓", "Down", 1, true), k("→", "Right", 1, true),
         k("Space", "space", 3, true)],
        [m("ctrl", "Ctrl", 1.4), m("sup", "Super", 1.3), m("alt", "Alt", 1.3), m("shift", "⇧ Shift", 1.8),
         { kind: "page", label: "ABC", to: "main", w: 2 }]
    ]

    readonly property var rows: page === "main" ? mainRows : moreRows

    function modActive(id) { return id === "shift" ? shift : id === "caps" ? caps : id === "ctrl" ? ctrl : id === "alt" ? alt : sup; }
    function toggleMod(id) {
        if (id === "shift") shift = !shift;
        else if (id === "caps") caps = !caps;
        else if (id === "ctrl") ctrl = !ctrl;
        else if (id === "alt") alt = !alt;
        else sup = !sup;
    }

    function activate(spec) {
        if (spec.kind === "char") pressChar(spec);
        else if (spec.kind === "mod") toggleMod(spec.id);
        else if (spec.kind === "page") page = spec.to;
        else if (spec.kind === "combo") combo(spec.mods, spec.sym);
        else if (spec.label === "Alt+Tab") pressSym(spec.sym, ["alt"]);
        else pressSym(spec.sym);
    }

    // ── Look ─────────────────────────────────────────────────────────────────
    readonly property real keyH: 46
    readonly property real gap: 6
    readonly property real kbWidth: Math.min(1180, width - Atelier.insetLeft - Atelier.insetRight - 48)

    EdgeDrawer {
        id: drawer
        edge: "bottom"
        open: root.shown
        bodyWidth: root.kbWidth
        bodyHeight: 14 + 34 + 10 + 5 * root.keyH + 4 * root.gap + 16

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 12
            anchors.bottomMargin: 14
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "󰌌"; font.family: Atelier.font; font.pixelSize: 16; color: Atelier.accent }
                Text { text: "On-screen keyboard"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold; color: Atelier.text }
                Text {
                    visible: root.hasWtype
                    text: "types into the focused window  ·  Super+/ to close"
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
                }
                Chip {
                    visible: !root.hasWtype
                    icon: "󰀦"
                    text: "Typing needs wtype — run: sudo pacman -S wtype"
                    tint: Atelier.red
                    implicitHeight: 26
                }
                Item { Layout.fillWidth: true }
                Chip { text: root.caps ? "CAPS" : "abc"; mono: true; tint: root.caps ? Atelier.yellow : Atelier.subtext; implicitHeight: 24; pad: 8 }
                Chip { icon: "󰅖"; text: "Close"; tint: Atelier.red; interactive: true; implicitHeight: 26; onClicked: root.close() }
            }

            Column {
                id: keysCol
                Layout.fillWidth: true
                spacing: root.gap

                Repeater {
                    model: root.rows
                    Item {
                        id: rowItem
                        required property var modelData
                        readonly property real sumW: modelData.reduce((a, s) => a + s.w, 0)
                        readonly property real avail: keysCol.width - (modelData.length - 1) * root.gap
                        width: keysCol.width
                        height: root.keyH

                        Row {
                            spacing: root.gap
                            Repeater {
                                model: rowItem.modelData
                                OskKey {
                                    required property var modelData
                                    width: rowItem.avail * modelData.w / rowItem.sumW
                                    height: root.keyH
                                    readonly property bool isChar: modelData.kind === "char"
                                    readonly property bool letter: isChar && /^[a-z]$/.test(modelData.base)
                                    readonly property bool up: letter ? (root.shift !== root.caps) : root.shift
                                    label: isChar ? (up ? modelData.shifted : modelData.base)
                                         : (modelData.label !== undefined ? modelData.label : "")
                                    sub: isChar && !letter && !root.shift ? modelData.shifted : ""
                                    active: modelData.kind === "mod" && root.modActive(modelData.id)
                                    repeat: !!modelData.repeat
                                    tint: modelData.kind === "mod" ? (modelData.id === "caps" ? Atelier.yellow : Atelier.accent)
                                        : modelData.kind === "page" ? Atelier.blue : Atelier.accent
                                    onTapped: root.activate(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
