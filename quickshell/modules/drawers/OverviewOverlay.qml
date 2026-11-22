import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// Desktop overview (Super+Tab, IPC `overview toggle`): workspaces 1–10 as miniature desktops
// with real window thumbnails, on a glass panel.
//   click a workspace → go there        click a window → focus it
//   drag a window onto another workspace → move it there (stays where you are)
//   1–9/0 jump · ←/→ select · Enter go · Esc close
// Thumbnails are captured once per opening (ScreencopyView, live: false) and released on close,
// so the overview costs nothing while hidden.
Item {
    id: ov
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool animActive: false
    signal closedSignal()

    readonly property var mon: Hyprland.focusedMonitor
    readonly property real monW: mon ? mon.width / (mon.scale || 1) : 1920
    readonly property real monH: mon ? mon.height / (mon.scale || 1) : 1080
    property int selected: 1

    readonly property int cols: 5
    readonly property int gap: 14
    readonly property real cardW: Math.min(270, (width - 180 - (cols - 1) * gap) / cols)
    readonly property real cardH: cardW * monH / monW

    function dispatchLua(lua, legacy) { Hyprland.dispatch(Hyprland.usingLua ? lua : legacy); }

    // Super+Tab opens the overview while Tab is still held: ignore keys for a moment after
    // opening (and all auto-repeats), or that Tab would act on the overview straight away.
    property real openedAt: 0
    function fresh(e) { return e.isAutoRepeat || Date.now() - openedAt < 350; }

    function open() {
        openedAt = Date.now();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
        selected = Hyprland.focusedWorkspace ? Math.min(10, Math.max(1, Hyprland.focusedWorkspace.id)) : 1;
        visible = true;
        animActive = true;
        focusTimer.restart();
    }
    function close() {
        animActive = false;
        dragGhost.active = false;
        closeTimer.restart();
        closedSignal();
    }
    function goTo(id) {
        dispatchLua(`hl.dsp.focus({ workspace = ${id} })`, `workspace ${id}`);
        close();
    }
    function focusWindow(addr) {
        dispatchLua(`hl.dsp.focus({ window = "address:${addr}" })`, `focuswindow address:${addr}`);
        close();
    }
    function moveWindow(addr, id) {
        dispatchLua(`hl.dsp.window.move({ workspace = ${id}, silent = true, window = "address:${addr}" })`,
                    `movetoworkspacesilent ${id},address:${addr}`);
        refreshLater.restart();
    }
    Timer { id: refreshLater; interval: 120; onTriggered: { Hyprland.refreshWorkspaces(); Hyprland.refreshToplevels(); } }

    Timer { id: focusTimer; interval: 40; onTriggered: keys.forceActiveFocus() }
    Timer {
        id: closeTimer
        interval: Atelier.durClose + 40
        onTriggered: if (!ov.animActive) ov.visible = false
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: (e) => { if (!e.isAutoRepeat) ov.close(); }
        Keys.onLeftPressed: ov.selected = ov.selected <= 1 ? 10 : ov.selected - 1
        Keys.onRightPressed: ov.selected = ov.selected >= 10 ? 1 : ov.selected + 1
        Keys.onUpPressed: ov.selected = ov.selected > ov.cols ? ov.selected - ov.cols : ov.selected + ov.cols
        Keys.onDownPressed: ov.selected = ov.selected > ov.cols ? ov.selected - ov.cols : ov.selected + ov.cols
        Keys.onReturnPressed: ov.goTo(ov.selected)
        Keys.onEnterPressed: ov.goTo(ov.selected)
        // Tab / Shift+Tab step through the desktops (Super+Tab again closes: Hyprland's binding)
        Keys.onTabPressed: (e) => { if (!ov.fresh(e)) ov.selected = ov.selected >= 10 ? 1 : ov.selected + 1; }
        Keys.onBacktabPressed: (e) => { if (!ov.fresh(e)) ov.selected = ov.selected <= 1 ? 10 : ov.selected - 1; }
        Keys.onPressed: (e) => {
            if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) { ov.goTo(e.key - Qt.Key_0); e.accepted = true; }
            else if (e.key === Qt.Key_0) { ov.goTo(10); e.accepted = true; }
        }

        // dim + blur the desktop behind (Mission Control). Alpha above the host's 0.5 blur
        // threshold, so Hyprland blurs it; only while the overview is open.
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Atelier.crust, 0.62)
            opacity: ov.animActive ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: ov.animActive ? Atelier.durOpen : Atelier.durClose } }
            MouseArea { anchors.fill: parent; onClicked: ov.close() }
        }

        // ── Panel ───────────────────────────────────────────────────────────
        Item {
            id: panelWrap
            anchors.centerIn: parent
            width: grid.width + 44
            height: grid.height + header.height + 58
            opacity: ov.animActive ? 1 : 0
            scale: ov.animActive ? 1 : 0.92
            Behavior on opacity { NumberAnimation { duration: ov.animActive ? 220 : Atelier.durClose } }
            Behavior on scale {
                NumberAnimation {
                    duration: ov.animActive ? Atelier.durOpen : Atelier.durClose
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: ov.animActive ? Atelier.curveOpen : Atelier.curveClose
                }
            }

            RectangularShadow {
                anchors.fill: panel
                radius: panel.radius
                blur: 40
                offset.y: 8
                color: Qt.alpha(Atelier.crust, 0.5)
                visible: !Perf.lean
            }
            Rectangle {
                id: panel
                anchors.fill: parent
                radius: Math.max(26, Atelier.rounding + 12)
                color: Atelier.surface
                border.width: 1
                border.color: Atelier.outline
                MouseArea { anchors.fill: parent }        // clicks on the panel itself don't close it
            }

            RowLayout {
                id: header
                anchors.top: parent.top
                anchors.topMargin: 18
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.right: parent.right
                anchors.rightMargin: 22
                spacing: 8
                Chip { icon: "󱂬"; text: "Overview"; tint: Atelier.accent }
                Chip {
                    icon: "󰕰"
                    text: Settings.windows.layout.charAt(0).toUpperCase() + Settings.windows.layout.slice(1)
                    tint: Atelier.blue
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "Click to switch  ·  drag windows between desktops  ·  Esc"
                    font.family: Atelier.fontUi
                    font.pixelSize: 11
                    color: Atelier.subtext
                }
            }

            Grid {
                id: grid
                anchors.top: header.bottom
                anchors.topMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
                columns: ov.cols
                spacing: ov.gap

                Repeater {
                    id: cards
                    model: 10
                    delegate: WorkspaceCard { wsId: index + 1 }
                }
            }
        }

        // the window being dragged (drawn above everything, follows the pointer)
        Rectangle {
            id: dragGhost
            property bool active: false
            property string addr: ""
            property int fromWs: 0
            property int overWs: 0          // workspace card under the pointer while dragging
            property string iconSrc: ""
            visible: active
            width: 120; height: 76
            radius: 12
            color: Qt.alpha(Atelier.accent, 0.22)
            border.width: 2
            border.color: Atelier.accent
            z: 100
            IconImage { anchors.centerIn: parent; implicitSize: 36; source: dragGhost.iconSrc; visible: dragGhost.iconSrc !== "" }
        }
    }

    function cardAt(px, py) {
        for (let i = 0; i < cards.count; i++) {
            const card = cards.itemAt(i);
            const p = card.mapFromItem(ov, px, py);
            if (p.x >= 0 && p.y >= 0 && p.x <= card.width && p.y <= card.height) return card;
        }
        return null;
    }

    // ── A workspace miniature ───────────────────────────────────────────────
    component WorkspaceCard: Item {
        id: card
        property int wsId: 0
        readonly property var ws: Hyprland.workspaces.values.find(w => w.id === card.wsId) || null
        readonly property bool current: !!Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === wsId
        readonly property var wins: ws ? ws.toplevels.values : []
        readonly property bool dropTarget: dragGhost.active && dragGhost.fromWs !== wsId && dragGhost.overWs === wsId
        width: ov.cardW
        height: ov.cardH

        HoverHandler { id: hover }

        ClippingRectangle {
            anchors.fill: parent
            radius: 14
            color: Atelier.container

            // the desktop: wallpaper, a touch dimmed
            Image {
                anchors.fill: parent
                source: ov.visible && Wallpaper.current ? "file://" + Wallpaper.current : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: ov.cardW * 2
                sourceSize.height: ov.cardH * 2
                // empty desktops recede so the ones with windows stand out
                opacity: card.wins.length > 0 ? 0.9 : (hover.hovered ? 0.55 : 0.3)
                Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
            }

            // windows, where they really are
            Repeater {
                // the live ObjectModel, not `card.wins` (= toplevels.values, a frozen JS copy): when a
                // window closes its object dies before the copy updates, and building a row from the
                // dead object segfaults Qt (6 crashes on 2026-11-21, all in this code path)
                model: card.ws ? card.ws.toplevels : null
                delegate: Item {
                    id: win
                    required property var modelData
                    readonly property var ipc: modelData.lastIpcObject || {}
                    readonly property var m: card.ws && card.ws.monitor ? card.ws.monitor : ov.mon
                    readonly property real s: card.width / ov.monW
                    // Hyprland wants the full "0x…" address ("address:0x55…"); HyprlandToplevel.address has no prefix
                    readonly property string addr: ipc.address ? String(ipc.address)
                        : (modelData.address ? "0x" + String(modelData.address).replace(/^0x/, "") : "")
                    readonly property string iconSrc: Quickshell.iconPath(ipc.class || ipc.initialClass || "", "application-x-executable")
                    visible: !!ipc.at && !!ipc.size
                    x: ipc.at ? (ipc.at[0] - (m ? m.x : 0)) * s : 0
                    y: ipc.at ? (ipc.at[1] - (m ? m.y : 0)) * s : 0
                    width: ipc.size ? Math.max(12, ipc.size[0] * s) : 0
                    height: ipc.size ? Math.max(12, ipc.size[1] * s) : 0

                    ClippingRectangle {
                        anchors.fill: parent
                        radius: 6
                        color: Atelier.base
                        border.width: winMa.containsMouse ? 2 : 1
                        border.color: winMa.containsMouse ? Atelier.accent : Atelier.outline

                        ScreencopyView {
                            id: shot
                            anchors.fill: parent
                            // captured once each time the overview opens; released when it closes
                            captureSource: ov.animActive && win.modelData.wayland ? win.modelData.wayland : null
                            live: false
                        }
                        IconImage {
                            anchors.centerIn: parent
                            visible: !shot.hasContent
                            implicitSize: Math.min(parent.width, parent.height) * 0.45
                            source: win.iconSrc
                        }
                    }
                    MouseArea {
                        id: winMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        property point pressAt
                        property bool dragging: false
                        onPressed: (m) => { pressAt = Qt.point(m.x, m.y); dragging = false; }
                        onPositionChanged: (m) => {
                            if (!pressed) return;
                            const p = mapToItem(ov, m.x, m.y);
                            if (!dragging && Math.hypot(m.x - pressAt.x, m.y - pressAt.y) > 6) {
                                dragging = true;
                                dragGhost.addr = win.addr;
                                dragGhost.fromWs = card.wsId;
                                dragGhost.iconSrc = win.iconSrc;
                                dragGhost.active = true;
                            }
                            if (dragging) {
                                dragGhost.x = p.x - dragGhost.width / 2; dragGhost.y = p.y - dragGhost.height / 2;
                                const t = ov.cardAt(p.x, p.y);
                                dragGhost.overWs = t ? t.wsId : 0;
                            }
                        }
                        onReleased: (m) => {
                            if (dragging) {
                                const p = mapToItem(ov, m.x, m.y);
                                const target = ov.cardAt(p.x, p.y);
                                dragGhost.active = false;
                                dragging = false;
                                if (target && target.wsId !== card.wsId) ov.moveWindow(win.addr, target.wsId);
                            } else {
                                ov.focusWindow(win.addr);
                            }
                        }
                    }
                }
            }

            // empty desktop
            Column {
                anchors.centerIn: parent
                visible: card.wins.length === 0
                spacing: 2
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰐕"; font.family: Atelier.font; font.pixelSize: 20; color: Qt.alpha(Atelier.text, hover.hovered ? 0.8 : 0.45) }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Empty"; font.family: Atelier.fontUi; font.pixelSize: 10; color: Qt.alpha(Atelier.text, hover.hovered ? 0.8 : 0.45) }
            }
        }

        // frame: accent for the current desktop, the selection, or a drop target
        Rectangle {
            anchors.fill: parent
            radius: 14
            color: card.dropTarget ? Qt.alpha(Atelier.accent, 0.16) : "transparent"
            border.width: card.current || card.dropTarget || ov.selected === card.wsId ? 2 : 1
            border.color: card.dropTarget ? Atelier.accent
                : card.current ? Atelier.accent
                : ov.selected === card.wsId ? Qt.alpha(Atelier.accent, 0.5)
                : hover.hovered ? Qt.alpha(Atelier.text, 0.25) : Atelier.outline
            Behavior on border.color { ColorAnimation { duration: Atelier.durFast } }
        }

        // number chip
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 7
            width: 24; height: 20; radius: 10
            color: card.current ? Atelier.accentFill : Qt.alpha(Atelier.crust, 0.6)
            Text {
                anchors.centerIn: parent
                text: card.wsId === 10 ? "0" : card.wsId
                font.family: Atelier.font
                font.pixelSize: 11
                font.bold: true
                color: card.current ? Atelier.onAccent : Atelier.text
            }
        }

        // click the desktop (not a window) → go there
        MouseArea {
            anchors.fill: parent
            z: -1
            cursorShape: Qt.PointingHandCursor
            onClicked: ov.goTo(card.wsId)
        }
    }
}
