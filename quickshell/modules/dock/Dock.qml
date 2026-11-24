import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// The dock of the Traditional layout (Settings → Bar → Layout). The frame turns its bottom edge
// into a bar (Atelier.insetBottom = dockHeight), one surface with the rest of the frame; this
// window only puts the app icons in it: app grid · kept apps · (divider) other open apps.
//   click: open the app, or bring its window forward (again: its next window); a minimised
//          window (title bar −) comes back to the workspace you're on
//   middle-click: new window · right-click: New window · Keep in dock / Remove · Quit
// Icons magnify under the pointer (Settings → Dock). Windows come from the Wayland toplevel list
// (live, no polling). Hyprland keeps room for it (Settings._inset) unless it auto-hides.
// It lives in the frame's window (Frame.qml), so the bar and its icons are one surface.
Item {
    id: root
    // the frame's full-screen window holds this (Frame.qml); the frame's input mask uses these
    readonly property Item hitZone: hitZoneItem
    readonly property Item menuZone: menuZoneItem
    // the frame's shelf (Frame.qml Ring) spans the resting dock, so magnified icons rise above it
    readonly property real shelfLeft: Atelier.dockOn ? win.restLeft - 8 : 0
    readonly property real shelfRight: Atelier.dockOn ? win.restLeft + win.restWidth + 8 : 0
    signal openApps()

    readonly property int size: Math.max(24, Math.min(64, Settings.dock.iconSize))
    readonly property int pad: 10            // room at either end of the icon row
    readonly property int gap: 8
    readonly property real magnifyBy: Settings.dock.magnify ? 0.32 : 0

    // ── apps ─────────────────────────────────────────────────────────────────
    readonly property var entries: {
        const m = {};
        for (const e of DesktopEntries.applications.values) m[e.id] = e;
        return m;
    }
    function entryFor(appId) {
        if (!appId) return null;
        return entries[appId] || entries[appId.toLowerCase()] || DesktopEntries.heuristicLookup(appId);
    }
    // kept apps (in order), then open apps that aren't kept: { key, entry, pinned, wins }
    readonly property var items: {
        const byKey = {}, order = [];
        for (const id of (Settings.dock.pinned || [])) {
            const e = entries[id];
            if (!e || byKey[id]) continue;
            byKey[id] = { key: id, entry: e, pinned: true, wins: [] };
            order.push(byKey[id]);
        }
        for (const t of ToplevelManager.toplevels.values) {
            if (!t || !t.appId) continue;
            const e = entryFor(t.appId);
            const k = e ? e.id : t.appId;
            if (!byKey[k]) {
                if (!Settings.dock.showRunning) continue;
                byKey[k] = { key: k, entry: e, pinned: false, wins: [] };
                order.push(byKey[k]);
            }
            byKey[k].wins.push(t);
        }
        return order;
    }
    // Downloads and Trash at the right end, after their own divider (macOS-style)
    readonly property var extras: Settings.dock.showFolders ? ["downloads", "trash"] : []
    property bool trashFull: false
    Process {
        id: trashCheck
        command: ["sh", "-c", 'ls -A "${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files" 2>/dev/null | head -c1']
        stdout: StdioCollector { onStreamFinished: root.trashFull = text.length > 0 }
    }
    // checked when the dock is shown or the pointer reaches it (no polling)
    Component.onCompleted: if (extras.length) trashCheck.running = true
    function openFolder(which) {
        if (which === "trash") Quickshell.execDetached(["gio", "open", "trash:///"]);
        else Quickshell.execDetached(["sh", "-c", 'xdg-open "$(xdg-user-dir DOWNLOAD 2>/dev/null || echo "$HOME/Downloads")"']);
    }
    function emptyTrash() {
        Quickshell.execDetached(["gio", "trash", "--empty"]);
        root.trashFull = false;
    }
    readonly property int pinnedCount: items.filter(i => i.pinned).length
    readonly property bool hasDivider: pinnedCount > 0 && items.length > pinnedCount

    function nameOf(item) { return item.entry && item.entry.name ? item.entry.name : item.key; }
    function iconOf(item) {
        const n = item.entry && item.entry.icon ? item.entry.icon : item.key.toLowerCase();
        return n.startsWith("/") ? "file://" + n : Quickshell.iconPath(n, "application-x-executable");
    }
    function launch(item) {
        if (item.entry) item.entry.execute();
        else Quickshell.execDetached(["sh", "-c", item.key]);
    }
    // not open → launch (true); open → bring it forward; already in front → its next window
    function activate(item) {
        if (item.wins.length === 0) { launch(item); return true; }
        const i = item.wins.findIndex(w => w.activated);
        const w = item.wins[(i + 1) % item.wins.length];
        // a minimised window: Hyprland brings it back and focuses it (activating it here would
        // jump to the hidden workspace before it has moved)
        if (!unminimize(w)) w.activate();
        return false;
    }
    // the title bar's − parks a window on the hidden workspace "minimized"
    // (hypr/conf/traditional.lua); atelier_unminimize grows it back out of the dock
    function unminimize(t) {
        const h = Hyprland.toplevels.values.find(x => x.wayland === t);
        if (!h) return false;
        const ws = h.workspace ? h.workspace.name : (h.lastIpcObject && h.lastIpcObject.workspace ? h.lastIpcObject.workspace.name : "");
        if (ws !== "minimized") return false;
        const addr = "0x" + String(h.address).replace(/^0x/, "");
        Quickshell.execDetached(["hyprctl", "eval", `atelier_unminimize("${addr}")`]);
        return true;
    }
    function setPinned(key, on) {
        const list = (Settings.dock.pinned || []).filter(k => k !== key);
        if (on) list.push(key);
        Settings.dock.pinned = list;
    }

    Item {
        id: win
        anchors.fill: parent
        visible: Atelier.dockOn

        readonly property real barTop: height - Atelier.dockHeight   // the bar's top edge
        // width with nothing magnified: app grid, divider(s), apps
        readonly property real restWidth: (root.items.length + 1) * root.size + root.items.length * root.gap
                                          + (root.hasDivider ? root.gap + 1 : 0) + root.gap + 1 + root.pad * 2
                                          + root.extras.length * (root.size + root.gap) + (root.extras.length ? root.gap + 1 : 0)

        // Where the pointer counts. Its size comes from the RESTING dock plus room for magnified
        // icons, so it never moves while you hover: following the dock's live width made the
        // pointer fall off the edge as icons grew, which shrank them again (the hover glitch).
        Item {
            id: hitZoneItem
            readonly property real w: Atelier.dockOn ? win.restWidth + root.size * root.magnifyBy * 4 : 0
            x: win.centerX - w / 2
            width: w
            y: win.barTop - root.size * root.magnifyBy - 8
            height: win.height - y
        }
        Item {
            id: menuZoneItem
            x: menu.x; y: menu.y
            width: menu.visible ? menu.width : 0
            height: menu.visible ? menu.height : 0
        }

        // ── magnification ────────────────────────────────────────────────────
        // computed from the RESTING layout, so growing icons don't move the point under the
        // pointer; the pointer is read from an item that never moves (the window)
        Item {
            anchors.fill: parent
            HoverHandler {   // input only reaches it inside the mask
                id: hover
                onHoveredChanged: if (hovered && root.extras.length) trashCheck.running = true
            }
        }
        // Smoothed: the bulge eases in when the pointer arrives, follows it with a short glide and
        // eases out when it leaves (it used to pop on/off and jump with every pointer event)
        readonly property bool magnifying: hover.hovered && !menu.visible && root.magnifyBy > 0
        property real amount: magnifying ? 1 : 0
        Behavior on amount { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.OutCubic } }
        property real px: 0
        Behavior on px { enabled: win.amount > 0.01; SmoothedAnimation { duration: 90; velocity: -1 } }
        Connections {
            target: hover
            function onPointChanged() { if (hover.hovered) win.px = hover.point.position.x; }
            function onHoveredChanged() { if (hover.hovered) win.px = hover.point.position.x; }
        }
        readonly property real pointerX: amount > 0.001 ? px : -10000
        // the middle of the frame opening
        readonly property real centerX: (Atelier.insetLeft + width - Atelier.insetRight) / 2
        readonly property real restLeft: centerX - restWidth / 2
        function restCenter(slot) {   // slot 0 = app grid, 1.. = apps
            let x = restLeft + root.pad + root.size / 2;
            if (slot > 0) x += root.size + root.gap * 2 + 1 + (slot - 1) * (root.size + root.gap)
                               + (root.hasDivider && slot > root.pinnedCount ? root.gap + 1 : 0)
                               + (slot > root.items.length ? root.gap + 1 : 0);   // Downloads · Trash
            return x;
        }
        function scaleAt(slot) {
            if (root.magnifyBy <= 0 || pointerX < -1000) return 1;
            // a smooth bell (cosine) over about two and a half icons, so neighbours rise gently
            const d = Math.abs(pointerX - restCenter(slot)) / (root.size * 2.4);
            return 1 + root.magnifyBy * amount * (d >= 1 ? 0 : (1 + Math.cos(Math.PI * d)) / 2);
        }
        // How the dock grows, macOS-style: the spot under the pointer stays put and the dock
        // widens around it. (Growing from the dock's centre slid the icons sideways under the
        // pointer, so between two icons the one under it kept changing.)
        readonly property int slotCount: root.items.length + 1 + root.extras.length
        readonly property var growth: {
            const g = [];
            for (let i = 0; i < slotCount; i++) g.push(root.size * (scaleAt(i) - 1));
            return g;
        }
        readonly property real growthTotal: growth.reduce((a, b) => a + b, 0)
        readonly property real growthLeft: {   // the part of the growth that lies left of the pointer
            let d = 0;
            for (let i = 0; i < slotCount; i++) {
                const l = restCenter(i) - root.size / 2, r = l + root.size;
                if (pointerX >= r) d += growth[i];
                else if (pointerX > l) d += growth[i] * (pointerX - l) / root.size;
            }
            return d;
        }
        function liveCenter(slot) {
            let before = 0;
            for (let j = 0; j < slot; j++) before += growth[j];
            return restCenter(slot) - growthLeft + before + growth[slot] / 2;
        }
        function liveEdge(slot, right) { return liveCenter(slot) + (right ? 1 : -1) * root.size * scaleAt(slot) / 2; }

        // ── the icons, inside the frame's bottom bar ─────────────────────────
        Item {
            id: icons
            width: win.width
            height: root.size
            y: win.barTop + (Atelier.dockHeight - root.size) / 2 - 2   // a little up: the dots sit under them

            Slot {
                slot: 0
                x: win.liveCenter(0) - width / 2
                glyph: "󰀻"
                label: "Apps"
                onPressed: (button) => { if (button === Qt.LeftButton) root.openApps(); }
            }
            Divider { x: (win.liveEdge(0, true) + win.liveEdge(1, false)) / 2 }
            Divider {
                visible: root.hasDivider
                x: root.hasDivider ? (win.liveEdge(root.pinnedCount, true) + win.liveEdge(root.pinnedCount + 1, false)) / 2 : 0
            }
            Divider {
                visible: root.extras.length > 0
                x: visible ? (win.liveEdge(root.items.length, true) + win.liveEdge(root.items.length + 1, false)) / 2 : 0
            }
            Repeater {
                model: root.extras
                Slot {
                    id: extraSlot
                    required property string modelData
                    required property int index
                    readonly property bool trash: modelData === "trash"
                    slot: root.items.length + 1 + index
                    x: win.liveCenter(slot) - width / 2
                    label: trash ? (root.trashFull ? "Trash" : "Trash (empty)") : "Downloads"
                    iconSource: Quickshell.iconPath(trash ? (root.trashFull ? "user-trash-full" : "user-trash") : "folder-download", "folder")
                    onPressed: (button) => {
                        if (button === Qt.RightButton && trash) menu.openTrash(extraSlot);
                        else if (button === Qt.LeftButton) { root.openFolder(modelData); extraSlot.bounce(); }
                    }
                }
            }
            Repeater {
                model: root.items
                Slot {
                    id: appSlot
                    required property var modelData
                    required property int index
                    slot: index + 1
                    x: win.liveCenter(slot) - width / 2
                    app: modelData
                    label: root.nameOf(modelData)
                    iconSource: root.iconOf(modelData)
                    open: modelData.wins.length
                    focused: modelData.wins.some(w => w.activated)
                    onPressed: (button) => {
                        if (button === Qt.LeftButton) { if (root.activate(appSlot.modelData)) appSlot.bounce(); }
                        else if (button === Qt.MiddleButton) { root.launch(appSlot.modelData); appSlot.bounce(); }
                        else menu.openFor(appSlot.modelData, appSlot);
                    }
                }
            }
        }

        // ── the name of the app under the pointer ───────────────────────────
        property Item hoveredSlot: null
        Rectangle {
            readonly property point at: win.hoveredSlot ? win.hoveredSlot.mapToItem(win, win.hoveredSlot.width / 2, 0) : Qt.point(0, 0)
            visible: win.hoveredSlot !== null && !menu.visible
            x: at.x - width / 2
            y: at.y - (win.hoveredSlot ? win.hoveredSlot.artItem.height - root.size : 0) - height - 10
            width: tip.implicitWidth + 20
            height: tip.implicitHeight + 10
            radius: height / 2
            color: Atelier.surface
            border.width: 1
            border.color: Atelier.outline
            Text { id: tip; anchors.centerIn: parent; text: win.hoveredSlot ? win.hoveredSlot.label : ""
                   font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.Medium; color: Atelier.text }
        }

        // ── right-click menu ─────────────────────────────────────────────────
        Rectangle {
            id: menu
            property var app: null
            property real anchorX: 0
            visible: app !== null
            width: 196
            height: menuCol.implicitHeight + 12
            radius: Math.max(12, Atelier.rounding - 6)
            x: Math.max(8, Math.min(win.width - width - 8, anchorX - width / 2))
            y: win.barTop - height - 10
            color: Atelier.surface
            border.width: 1
            border.color: Atelier.outline
            property bool trash: false      // the Trash's menu instead of an app's
            function openFor(app, slotItem) {
                menu.trash = false;
                menu.app = app;
                menu.anchorX = slotItem.mapToItem(win, slotItem.width / 2, 0).x;
            }
            function openTrash(slotItem) {
                menu.trash = true;
                menu.app = { key: "trash", entry: null, pinned: false, wins: [] };
                menu.anchorX = slotItem.mapToItem(win, slotItem.width / 2, 0).x;
            }
            // closes once the pointer has been away a moment (it never takes the keyboard)
            onVisibleChanged: if (visible) menuTimer.restart()
            HoverHandler { onHoveredChanged: if (hovered) menuTimer.stop(); else menuTimer.restart() }
            Timer { id: menuTimer; interval: 1500; onTriggered: menu.app = null }

            Column {
                id: menuCol
                anchors.fill: parent
                anchors.margins: 6
                spacing: 1
                Text {
                    width: parent.width
                    leftPadding: 8; topPadding: 4; bottomPadding: 6
                    text: menu.trash ? "Trash" : menu.app ? root.nameOf(menu.app) : ""
                    elide: Text.ElideRight
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; color: Atelier.text
                }
                // the app's windows: click one to bring it forward (macOS "Show All Windows")
                Repeater {
                    model: menu.app && menu.app.wins.length > 1 ? menu.app.wins : []
                    MenuRow {
                        required property var modelData
                        icon: modelData.activated ? "󰄬" : "󱂬"
                        text: modelData.title || root.nameOf(menu.app)
                        onClicked: { if (!root.unminimize(modelData)) modelData.activate(); menu.app = null; }
                    }
                }
                Rectangle { visible: !!(menu.app && menu.app.wins.length > 1); width: parent.width; height: 1; color: Atelier.outline }
                MenuRow { visible: menu.trash; icon: "󰉋"; text: "Open"
                          onClicked: { root.openFolder("trash"); menu.app = null; } }
                MenuRow { visible: menu.trash && root.trashFull; icon: "󰩹"; tint: Atelier.red; text: "Empty Trash"
                          onClicked: { root.emptyTrash(); menu.app = null; } }
                MenuRow { visible: !!(menu.app && menu.app.entry); icon: "󰐕"; text: "New window"
                          onClicked: { root.launch(menu.app); menu.app = null; } }
                MenuRow { visible: !!(menu.app && menu.app.entry); icon: menu.app && menu.app.pinned ? "󰐄" : "󰐃"
                          text: menu.app && menu.app.pinned ? "Remove from dock" : "Keep in dock"
                          onClicked: { root.setPinned(menu.app.key, !menu.app.pinned); menu.app = null; } }
                MenuRow { visible: !!(menu.app && menu.app.wins.length); icon: "󰅖"; tint: Atelier.red
                          text: menu.app && menu.app.wins.length > 1 ? "Quit (" + menu.app.wins.length + " windows)" : "Quit"
                          onClicked: { for (const w of menu.app.wins) w.close(); menu.app = null; } }
            }
        }
    }

    // ── pieces ───────────────────────────────────────────────────────────────
    component Slot: Item {
        id: sl
        property int slot: 0
        property var app: null
        property string label: ""
        property string glyph: ""
        property string iconSource: ""
        property int open: 0
        property bool focused: false
        property alias artItem: art
        signal pressed(int button)

        readonly property real s: win.scaleAt(slot)
        width: root.size * s
        height: root.size
        property real lift: 0
        function bounce() { bounceAnim.restart(); }
        SequentialAnimation {
            id: bounceAnim
            NumberAnimation { target: sl; property: "lift"; to: -14; duration: Atelier.durFast; easing.type: Easing.OutQuad }
            NumberAnimation { target: sl; property: "lift"; to: 0; duration: 420; easing.type: Easing.OutBounce }
        }

        Item {   // grows upwards from the bottom of the slot
            id: art
            width: root.size * sl.s
            height: width
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -sl.lift
            scale: ma.pressed ? 0.9 : 1
            Behavior on scale { NumberAnimation { duration: Atelier.durFast } }

            IconImage {
                visible: sl.glyph === ""
                anchors.fill: parent
                source: sl.iconSource
                asynchronous: true
                mipmap: true
            }
            Rectangle {   // the app grid: a glyph tile in the accent, like the shell's tiles
                visible: sl.glyph !== ""
                anchors.fill: parent
                anchors.margins: parent.width * 0.06
                radius: width * 0.28
                color: Qt.alpha(Atelier.accent, 0.14)
                border.width: 1
                border.color: Qt.alpha(Atelier.accent, 0.35)
                Text { anchors.centerIn: parent; text: sl.glyph; font.family: Atelier.font
                       font.pixelSize: parent.width * 0.48; color: Atelier.accent }
            }
        }

        Row {   // open windows: up to three dots; the focused app's in the accent
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: 3
            spacing: 3
            Repeater {
                model: Math.min(3, sl.open)
                Rectangle { width: 4; height: 4; radius: 2; color: sl.focused ? Atelier.accent : Atelier.subtext }
            }
        }

        MouseArea {
            id: ma
            x: 0; y: parent.height - art.height
            width: parent.width; height: art.height
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: {
                if (containsMouse) win.hoveredSlot = sl;
                else if (win.hoveredSlot === sl) win.hoveredSlot = null;
            }
            onClicked: (e) => { if (e.button !== Qt.RightButton) menu.app = null; sl.pressed(e.button); }
        }
    }

    component Divider: Rectangle {
        width: 1
        height: root.size * 0.7
        y: root.size * 0.15
        color: Atelier.outline
    }

    component MenuRow: Rectangle {
        id: mr
        property string icon: ""
        property string text: ""
        property color tint: Atelier.text
        signal clicked()
        width: parent ? parent.width : 0
        height: 30
        radius: 9
        color: mrMa.containsMouse ? Atelier.containerHigh : "transparent"
        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 8
            spacing: 10
            Text { text: mr.icon; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: mr.tint; anchors.verticalCenter: parent.verticalCenter }
            Text { text: mr.text; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: mr.tint; anchors.verticalCenter: parent.verticalCenter
                   width: Math.min(implicitWidth, mr.width - 44); elide: Text.ElideRight }
        }
        MouseArea { id: mrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mr.clicked() }
    }
}
