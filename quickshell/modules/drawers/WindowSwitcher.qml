import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// Alt-Tab window switcher: a bottom drawer with a live preview of every open window, most
// recently used first. Hold Alt and tap Tab (Shift+Tab goes back); letting go of Alt focuses the
// highlighted window. Esc cancels, Enter or a click picks. Hyprland binds Alt+Tab / Alt+Shift+Tab
// to `switcher next|prev` and the Alt release to `switcher commit`.
// IPC `switcher next|prev|commit|cancel`.
Item {
    id: root
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool isLight: Atelier.isLight
    property bool animActive: false
    property var wins: []                // [{ addr, cls, title, ws }], most recent first
    property int sel: 0
    property double openedAt: 0
    property double lastStep: 0
    property bool loaded: false
    property int pendingSteps: 0         // Tab taps that arrived before the list did
    property bool commitWhenLoaded: false

    signal closedSignal()

    readonly property var current: loaded && wins.length ? wins[Math.min(sel, wins.length - 1)] : null

    function dispatchLua(lua, legacy) { Hyprland.dispatch(Hyprland.usingLua ? lua : legacy); }
    function entryFor(cls) { return cls ? DesktopEntries.heuristicLookup(cls) : null; }
    function nameFor(w) { const e = entryFor(w.cls); return (e && e.name) || w.cls || w.title; }
    function iconFor(w) { const e = entryFor(w.cls); return Quickshell.iconPath(e && e.icon ? e.icon : (w.cls || "").toLowerCase(), "application-x-executable"); }
    function toplevelFor(addr) {
        const a = String(addr).replace(/^0x/, "");
        return Hyprland.toplevels.values.find(t => String(t.address).replace(/^0x/, "") === a) || null;
    }

    // next/prev from the keybind (or Tab inside the drawer: de-duplicated)
    function step(dir) {
        const now = Date.now();
        if (now - lastStep < 60) return;
        lastStep = now;
        if (!visible || !animActive) {
            open();
            pendingSteps = dir;
            return;
        }
        if (!loaded) { pendingSteps += dir; return; }
        if (wins.length) sel = (sel + dir + wins.length) % wins.length;
    }
    function open() {
        wins = [];
        loaded = false;
        sel = 0;
        pendingSteps = 0;
        commitWhenLoaded = false;
        openedAt = Date.now();
        visible = true;
        animActive = true;
        Hyprland.refreshToplevels();
        clients.running = false;
        clients.running = true;
        focusTimer.restart();
    }
    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }
    function commit() {
        if (!visible || !animActive) return;
        // a quick Alt+Tab: Alt came up before the window list did, so switch as soon as it arrives
        if (!loaded) { commitWhenLoaded = true; return; }
        // Close FIRST: while the drawer holds exclusive keyboard focus Hyprland won't hand focus to a
        // window (the request is dropped). The focus goes out once the host has let go.
        pendingFocus = (wins.length && sel >= 0 && sel < wins.length) ? wins[sel].addr : "";
        close();
        if (pendingFocus) focusLater.restart();
    }
    property string pendingFocus: ""
    Timer {
        id: focusLater
        interval: 60
        onTriggered: {
            const a = root.pendingFocus;
            root.pendingFocus = "";
            if (a) root.dispatchLua(`hl.dsp.focus({ window = "address:${a}" })`, `focuswindow address:${a}`);
        }
    }
    function cancel() {
        if (visible && animActive) close();
    }

    Process {
        id: clients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try { list = JSON.parse(text); } catch (e) {}
                list = list.filter(c => c.mapped && !c.hidden && c.workspace && c.workspace.id > 0 && (c.class || c.title))
                           .sort((a, b) => a.focusHistoryID - b.focusHistoryID);
                root.wins = list.map(c => ({ addr: c.address, cls: c.class || c.initialClass || "", title: c.title || c.class,
                                             ws: c.workspace.name, w: c.size[0], h: c.size[1] }));
                root.loaded = true;
                // the window you're in is entry 0, so the first Tab lands on entry 1
                const n = root.wins.length;
                root.sel = n === 0 ? 0 : ((root.pendingSteps % n) + n) % n;
                root.pendingSteps = 0;
                if (n === 0) autoClose.restart();
                if (root.commitWhenLoaded) { root.commitWhenLoaded = false; root.commit(); }
            }
        }
    }
    Timer { id: autoClose; interval: 900; onTriggered: root.cancel() }
    Timer { id: focusTimer; interval: 30; onTriggered: keys.forceActiveFocus() }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!root.animActive) root.visible = false }

    MouseArea { anchors.fill: parent; onClicked: root.cancel() }

    readonly property int tileW: 216
    readonly property int tileH: 168
    readonly property int gap: 10
    readonly property int perRow: Math.max(1, Math.min(Math.max(wins.length, 1), Math.floor((Math.min(root.width - 200, 1180) - 36 + gap) / (tileW + gap))))
    readonly property int rows: Math.max(1, Math.ceil(Math.max(1, wins.length) / perRow))

    EdgeDrawer {
        id: drawer
        edge: "bottom"
        open: root.animActive
        bodyWidth: Math.max(440, root.perRow * (root.tileW + root.gap) - root.gap + 36)
        bodyHeight: Math.min(root.height * 0.7, root.rows * (root.tileH + root.gap) - root.gap + 36 + 50 + 14 + 14 + 18)
        Behavior on bodyWidth { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }
        Behavior on bodyHeight { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }

        MouseArea { anchors.fill: parent }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Escape) root.cancel();
                else if (e.key === Qt.Key_Tab) root.step(e.modifiers & Qt.ShiftModifier ? -1 : 1);
                else if (e.key === Qt.Key_Backtab || e.key === Qt.Key_Left) root.step(-1);
                else if (e.key === Qt.Key_Right) root.step(1);
                else if (e.key === Qt.Key_Up) root.step(-root.perRow);
                else if (e.key === Qt.Key_Down) root.step(root.perRow);
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.commit();
                else return;
                e.accepted = true;
            }
            // letting go of Alt picks the window
            Keys.onReleased: (e) => {
                if (e.key === Qt.Key_Alt || e.key === Qt.Key_Meta) { root.commit(); e.accepted = true; }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            // ── header: the highlighted window ────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    implicitWidth: 36; implicitHeight: 36; radius: Atelier.radiusMd
                    color: Qt.alpha(Atelier.accent, 0.14)
                    border.width: 1
                    border.color: Qt.alpha(Atelier.accent, 0.35)
                    IconImage {
                        anchors.centerIn: parent
                        visible: !!root.current
                        implicitSize: 22
                        source: root.current ? root.iconFor(root.current) : ""
                    }
                    Text { anchors.centerIn: parent; visible: !root.current; text: "󰖲"; font.family: Atelier.font; font.pixelSize: 17; color: Atelier.accent }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0
                    Text { Layout.fillWidth: true; elide: Text.ElideRight
                           text: root.current ? root.current.title : (root.loaded ? "No open windows" : "Windows")
                           font.family: Atelier.fontUi; font.pixelSize: Atelier.fsXl; font.weight: Font.DemiBold; color: Atelier.text }
                    Text { Layout.fillWidth: true; elide: Text.ElideRight
                           text: root.current ? root.nameFor(root.current) + "  ·  workspace " + root.current.ws : ""
                           font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                }
                Chip { visible: root.wins.length > 0; text: (root.sel + 1) + " / " + root.wins.length; mono: true; tint: Atelier.accent; implicitHeight: 22; pad: 9 }
            }

            // ── the windows ──────────────────────────────────────────────────
            Grid {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                columns: root.perRow
                spacing: root.gap
                Repeater {
                    model: root.wins
                    Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool on: root.sel === index
                        readonly property var toplevel: root.animActive ? root.toplevelFor(modelData.addr) : null
                        width: root.tileW; height: root.tileH
                        radius: Atelier.radiusLg
                        color: on ? Atelier.containerHigh : (tm.containsMouse ? Atelier.containerHigh : Atelier.container)
                        border.width: on ? 2 : 1
                        border.color: on ? Atelier.accent : Atelier.outline
                        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                        Behavior on border.color { ColorAnimation { duration: Atelier.durFast } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 7
                            // the preview, letterboxed into the tile
                            ClippingRectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 11
                                color: Atelier.base
                                ScreencopyView {
                                    id: shot
                                    readonly property real ratio: tile.modelData.w > 0 ? tile.modelData.w / tile.modelData.h : 1.6
                                    anchors.centerIn: parent
                                    width: Math.min(parent.width, parent.height * ratio)
                                    height: width / ratio
                                    captureSource: tile.toplevel && tile.toplevel.wayland ? tile.toplevel.wayland : null
                                    live: false
                                }
                                IconImage {
                                    anchors.centerIn: parent
                                    visible: !shot.hasContent
                                    implicitSize: 44
                                    source: root.iconFor(tile.modelData)
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 2
                                Layout.rightMargin: 2
                                spacing: 7
                                IconImage { implicitSize: 16; source: root.iconFor(tile.modelData) }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: root.nameFor(tile.modelData)
                                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: tile.on ? Font.DemiBold : Font.Medium
                                    color: tile.on ? Atelier.text : Atelier.subtext1
                                }
                            }
                        }
                        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.sel = tile.index; root.commit(); } }
                    }
                }
            }

            HintLine { Layout.fillWidth: true; text: "Tab / Shift+Tab or arrows move  ·  let go of Alt, Enter or click to switch  ·  Esc cancels" }
        }
    }
}
