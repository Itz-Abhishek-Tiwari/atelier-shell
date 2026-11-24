import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import Quickshell.Bluetooth
import qs.config
import qs.services

// The bar, Caelestia layout in the atelier palette. Lives inside Frame.qml's bar strip
// (the frame draws the surface). It sits on any screen edge (Settings → Bar → Position):
// a vertical stack on the left/right, a horizontal row on the top/bottom.
// Groups are rounded "pills":
//   logo · workspaces · pinned apps · active window · tray · clock · status · power
Item {
    id: bar
    anchors.fill: parent

    // the value is the position of the clicked item ALONG the bar (y for left/right, x for top/bottom)
    signal openWifi(real centerY)
    signal openBluetooth(real centerY)
    signal openPower()
    signal openLauncher()
    signal openCalendar(real centerY)
    signal openWallpaper()
    signal openControlCenter()

    // ── Open on hover (Settings → Bar → Behaviour) ──────────────────────────
    // hoverTarget: which hover-capable item the pointer is on ("wifi" | "bluetooth" | "calendar" | "").
    // After a short dwell the shell opens that drawer (hoverOpen). shell.qml keeps a hover-opened
    // drawer open while the pointer is on it or on its icon (hoverTarget), Caelestia-style.
    property string hoverTarget: ""
    property real hoverCenter: 0
    signal hoverOpen(string name, real centerY)
    function setHover(name, item, inside) {
        if (inside) {
            bar.hoverTarget = name;
            bar.hoverCenter = bar.centerOf(item);
            if (Settings.bar.openOnHover) hoverDwell.restart();
        } else if (bar.hoverTarget === name) {
            bar.hoverTarget = "";
            hoverDwell.stop();
        }
    }
    // spans ALONG the bar of the hover icons, for the drawer window (DrawerHost.barZones)
    function zones() {
        const out = [];
        for (const [name, item] of [["calendar", clockPill], ["wifi", wifiIcon], ["bluetooth", btIcon]]) {
            if (!item || !item.visible) continue;
            const p = item.mapToItem(null, 0, 0);
            const a = bar.vertical ? p.y : p.x, len = bar.vertical ? item.height : item.width;
            out.push({ name: name, a: a, b: a + len, c: bar.centerOf(item) });
        }
        return out;
    }
    Timer {
        id: hoverDwell
        interval: 140            // brushing past an icon doesn't open it
        onTriggered: if (bar.hoverTarget !== "") bar.hoverOpen(bar.hoverTarget, bar.hoverCenter)
    }

    property string activeOverlay: ""

    readonly property bool vertical: Atelier.barVertical
    readonly property int crossAlign: vertical ? Qt.AlignHCenter : Qt.AlignVCenter
    readonly property int pillWidth: Math.max(26, Atelier.barWidth - 10)
    function centerOf(item) {
        const p = item.mapToItem(bar, item.width / 2, item.height / 2);
        return vertical ? p.y : p.x;
    }

    // ── Data ─────────────────────────────────────────────────────────────────
    readonly property int activeWs: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    readonly property var wsById: {
        const m = {};
        for (const w of Hyprland.workspaces.values) if (w.id > 0) m[w.id] = w;
        return m;
    }

    // Icon of a workspace's first window (via its desktop entry), "" if unknown
    function iconForWorkspace(ws) {
        const t = ws.toplevels.values[0];
        const cls = t && t.lastIpcObject ? (t.lastIpcObject.class || t.lastIpcObject.initialClass || "") : "";
        if (!cls) return "";
        const e = DesktopEntries.heuristicLookup(cls);
        const name = e && e.icon ? e.icon : cls.toLowerCase();
        return name.startsWith("/") ? "file://" + name : Quickshell.iconPath(name, true);
    }
    readonly property int wsCount: {
        let m = Math.max(1, Math.min(10, Settings.bar.minWorkspaces));
        for (const w of Hyprland.workspaces.values) if (w.id > m && w.id <= 10) m = w.id;
        return Math.max(m, activeWs);
    }

    // window class info (for workspace icons) is only fetched on request: refresh on window events
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name;
            if (n === "openwindow" || n === "closewindow" || n === "movewindow" || n === "movewindowv2") Hyprland.refreshToplevels();
        }
    }

    function goToWorkspace(id) {
        Hyprland.dispatch(Hyprland.usingLua ? `hl.dsp.focus({ workspace = ${id} })` : `workspace ${id}`);
    }
    function scrollWorkspace(up) {
        const r = up ? "-1" : "+1";
        Hyprland.dispatch(Hyprland.usingLua ? `hl.dsp.focus({ workspace = "r${r}" })` : `workspace r${r}`);
    }

    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: bar.sink ? [bar.sink] : [] }
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!(battery && battery.isLaptopBattery)
    readonly property real batPct: battery ? battery.percentage : 0
    readonly property bool charging: !!(battery && battery.state === UPowerDeviceState.Charging)

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: !!(adapter && adapter.enabled)
    readonly property bool btConnected: Bluetooth.devices.values.some(d => d.connected)

    property date now: new Date()
    // wake once per minute, on the minute (the bar shows hh:mm only)
    Timer {
        running: true
        interval: (60 - bar.now.getSeconds()) * 1000 + 50
        onTriggered: { bar.now = new Date(); restart(); }
    }

    // ── Layout: a column on the left/right, a row on the top/bottom ──────────
    GridLayout {
        anchors.fill: parent
        anchors.topMargin: bar.vertical ? 10 : 0
        anchors.bottomMargin: bar.vertical ? 10 : 0
        anchors.leftMargin: bar.vertical ? 0 : 10
        anchors.rightMargin: bar.vertical ? 0 : 10
        flow: bar.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: bar.vertical ? 16 : 1
        columns: bar.vertical ? 1 : 16
        rowSpacing: 8
        columnSpacing: 8

        // Logo → app grid
        BarIcon {
            Layout.alignment: bar.crossAlign
            visible: Settings.bar.showLogo
            icon: "󰣇"
            size: 22
            iconColor: Atelier.accent
            active: bar.activeOverlay === "apps"
            rotation: bar.activeOverlay === "apps" ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen } }
            onClicked: bar.openLauncher()
        }

        // Flat bar (Traditional, bar on top): small workspace dots instead of the tile pill.
        // Occupied = ink dot, empty = faint dot, the active one a short accent bar.
        Row {
            visible: Atelier.flatBar && Settings.bar.showWorkspaces
            Layout.alignment: bar.crossAlign
            spacing: 2
            Repeater {
                model: bar.wsCount
                Item {
                    id: flatWs
                    required property int index
                    readonly property int wsId: index + 1
                    readonly property bool isActive: bar.activeWs === wsId
                    readonly property var ws: bar.wsById[wsId] || null
                    readonly property bool isOccupied: !!(ws && ws.toplevels.values.length > 0)
                    width: isActive ? 26 : 14
                    height: 22
                    Behavior on width { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.OutCubic } }
                    Rectangle {
                        anchors.centerIn: parent
                        width: flatWs.isActive ? 18 : 6
                        height: 6
                        radius: 3
                        color: flatWs.isActive ? Atelier.accent : Atelier.text
                        opacity: flatWs.isActive ? 1 : flatWs.isOccupied ? 0.75 : 0.28
                        Behavior on width { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.OutCubic } }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: bar.goToWorkspace(flatWs.wsId) }
                }
            }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (e) => bar.scrollWorkspace(e.angleDelta.y > 0)
            }
        }

        // Workspaces: sliding accent tile; occupied workspaces show their main app's icon
        Rectangle {
            id: wsPill
            Layout.alignment: bar.crossAlign
            visible: Settings.bar.showWorkspaces && !Atelier.flatBar
            readonly property int slot: 30
            implicitWidth: bar.vertical ? bar.pillWidth : bar.wsCount * slot + 8
            implicitHeight: bar.vertical ? bar.wsCount * slot + 8 : bar.pillWidth
            radius: bar.pillWidth / 2
            color: Atelier.container

            Rectangle {
                id: wsActive
                readonly property real along: 4 + (bar.activeWs - 1) * wsPill.slot + (wsPill.slot - 28) / 2
                x: bar.vertical ? (parent.width - width) / 2 : along
                y: bar.vertical ? along : (parent.height - height) / 2
                width: 28
                height: 28
                radius: Atelier.radiusSm
                color: Atelier.accentFill
                Behavior on x { enabled: !bar.vertical; NumberAnimation { duration: 340; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen } }
                Behavior on y { enabled: bar.vertical; NumberAnimation { duration: 340; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen } }
            }

            Grid {
                id: wsGrid
                x: bar.vertical ? 0 : 4
                y: bar.vertical ? 4 : 0
                width: bar.vertical ? parent.width : implicitWidth
                height: bar.vertical ? implicitHeight : parent.height
                columns: bar.vertical ? 1 : 100

                Repeater {
                    model: bar.wsCount
                    Item {
                        id: wsCell
                        required property int index
                        readonly property int wsId: index + 1
                        readonly property bool isActive: bar.activeWs === wsId
                        readonly property var ws: bar.wsById[wsId] || null
                        readonly property bool isOccupied: !!(ws && ws.toplevels.values.length > 0)
                        readonly property string icon: isOccupied ? bar.iconForWorkspace(ws) : ""
                        width: bar.vertical ? wsGrid.width : wsPill.slot
                        height: bar.vertical ? wsPill.slot : wsGrid.height

                        Rectangle {   // hover
                            anchors.centerIn: parent
                            width: 28
                            height: 28
                            radius: Atelier.radiusSm
                            color: Atelier.containerHigh
                            opacity: wsMa.containsMouse && !wsCell.isActive ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
                        }

                        IconImage {
                            anchors.centerIn: parent
                            visible: wsCell.icon !== ""
                            implicitSize: 16
                            source: wsCell.icon
                            asynchronous: true
                            opacity: wsCell.isActive ? 1 : 0.85
                        }

                        Text {   // number: active-but-empty, or occupied without a known icon
                            anchors.centerIn: parent
                            visible: wsCell.icon === "" && (wsCell.isActive || wsCell.isOccupied)
                            text: wsCell.wsId
                            font.family: Atelier.font
                            font.pixelSize: Atelier.fsSm
                            font.bold: true
                            color: wsCell.isActive ? Atelier.onFill : Atelier.text
                        }

                        Rectangle {   // empty workspace
                            anchors.centerIn: parent
                            visible: !wsCell.isOccupied && !wsCell.isActive
                            width: 5
                            height: 5
                            radius: 2.5
                            color: Atelier.subtext
                            opacity: 0.5
                        }

                        Rectangle {   // urgent
                            visible: !!(wsCell.ws && wsCell.ws.urgent)
                            x: parent.width - 9
                            y: 4
                            width: 6
                            height: 6
                            radius: 3
                            color: Atelier.red
                        }

                        MouseArea {
                            id: wsMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bar.goToWorkspace(wsCell.wsId)
                        }
                    }
                }
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (e) => bar.scrollWorkspace(e.angleDelta.y > 0)
            }
        }

        // Pinned apps
        Pill {
            Layout.alignment: bar.crossAlign
            visible: Settings.bar.showApps && Settings.bar.pinned.length > 0 && !Atelier.dockOn   // the dock has them
            pad: 4
            gap: 2
            Repeater {
                model: Settings.bar.pinned
                BarIcon {
                    required property var modelData
                    icon: modelData.icon
                    iconColor: Atelier[modelData.color] !== undefined ? Atelier[modelData.color] : Atelier.text
                    size: 16
                    onClicked: Quickshell.execDetached(["sh", "-c", modelData.cmd])
                }
            }
        }

        // Active window title (vertical text on a side bar, plain text on a top/bottom bar)
        Item {
            id: titleSlot
            Layout.fillWidth: !bar.vertical
            Layout.fillHeight: bar.vertical
            Layout.alignment: bar.crossAlign
            implicitWidth: bar.vertical ? bar.pillWidth : 10
            implicitHeight: bar.vertical ? 10 : bar.pillWidth
            opacity: Settings.bar.showTitle || Atelier.flatBar ? 1 : 0   // the flat bar always names the app
            clip: true

            readonly property string title: Hyprland.activeToplevel && Hyprland.activeToplevel.title ? Hyprland.activeToplevel.title : ""
            // flat bar: the focused app's icon and name (its desktop entry), then the window title
            readonly property string appId: ToplevelManager.activeToplevel ? (ToplevelManager.activeToplevel.appId || "") : ""
            readonly property var app: appId ? DesktopEntries.heuristicLookup(appId) : null
            readonly property string appName: app && app.name ? app.name
                : appId ? appId.split(".").pop().replace(/^./, c => c.toUpperCase()) : "Desktop"

            Row {
                visible: Atelier.flatBar
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: titleSlot.width - 8
                spacing: 8
                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!(titleSlot.app && titleSlot.app.icon)
                    implicitSize: 16
                    source: titleSlot.app && titleSlot.app.icon ? Quickshell.iconPath(titleSlot.app.icon, true) : ""
                    asynchronous: true
                }
                Text {
                    id: flatApp
                    anchors.verticalCenter: parent.verticalCenter
                    text: titleSlot.appName
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold
                    color: Atelier.text
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - x)
                    visible: Settings.bar.showTitle && titleSlot.title !== "" && titleSlot.title !== titleSlot.appName
                    text: titleSlot.title
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd
                    color: Atelier.subtext
                    elide: Text.ElideRight
                }
            }

            Text {
                visible: bar.vertical
                anchors.centerIn: parent
                width: titleSlot.height - 16
                rotation: 90
                horizontalAlignment: Text.AlignHCenter
                text: titleSlot.title
                font.family: Atelier.font
                font.pixelSize: Atelier.fsSm
                color: Atelier.subtext
                elide: Text.ElideRight
                opacity: text ? 0.9 : 0
                Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
            }
            Text {
                visible: !bar.vertical && !Atelier.flatBar
                anchors.centerIn: parent
                width: titleSlot.width - 16
                horizontalAlignment: Text.AlignHCenter
                text: titleSlot.title
                font.family: Atelier.font
                font.pixelSize: Atelier.fsSm
                color: Atelier.subtext
                elide: Text.ElideRight
                opacity: text ? 0.9 : 0
                Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
            }
        }

        // System tray
        Pill {
            Layout.alignment: bar.crossAlign
            visible: Settings.bar.showTray && trayRepeater.count > 0
            pad: 5
            gap: 4
            Repeater {
                id: trayRepeater
                // the live ObjectModel, not `.values`: a JS-array snapshot keeps raw pointers, and when an
                // app quits its item is destroyed before the Repeater rebuilds -> segfault in Qt
                model: SystemTray.items
                Item {
                    id: trayItem
                    required property SystemTrayItem modelData
                    width: 24
                    height: 24
                    Rectangle {
                        anchors.fill: parent
                        radius: Atelier.radiusMd
                        color: trayMa.containsMouse ? Atelier.containerHigh : "transparent"
                    }
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 16
                        source: trayItem.modelData.icon
                    }
                    MouseArea {
                        id: trayMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (m) => {
                            const it = trayItem.modelData;
                            if (m.button === Qt.LeftButton && !it.onlyMenu) it.activate();
                            else if (m.button === Qt.MiddleButton) it.secondaryActivate();
                            else if (it.hasMenu) {
                                // open the menu toward the screen's inside
                                const dx = bar.vertical ? (Atelier.barEdge === "left" ? trayItem.width + 8 : -8) : 0;
                                const dy = bar.vertical ? 0 : (Atelier.barEdge === "top" ? trayItem.height + 8 : -8);
                                const p = trayItem.mapToItem(null, dx, dy);
                                it.display(QsWindow.window, p.x, p.y);
                            }
                        }
                    }
                }
            }
        }

        // Recording → red dot + timer; click to stop
        Pill {
            id: recPill
            Layout.alignment: bar.crossAlign
            visible: Recorder.recording
            pad: 7
            gap: bar.vertical ? 3 : 6
            clickable: true
            color: Qt.alpha(Atelier.red, 0.18)
            onClicked: Recorder.stop()
            Rectangle {
                implicitWidth: 9; implicitHeight: 9; radius: 4.5
                color: Atelier.red
                // gentle pulse, only while recording (the pill is hidden otherwise)
                SequentialAnimation on opacity {
                    running: recPill.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                }
            }
            Text {
                text: Recorder.elapsedText
                font.family: Atelier.font
                font.pixelSize: bar.vertical ? 9 : 12
                font.bold: true
                color: Atelier.red
            }
        }

        // Clock → calendar
        Pill {
            id: clockPill
            hoverName: "calendar"
            Layout.alignment: bar.crossAlign
            visible: Settings.bar.showClock
            pad: 7
            gap: 0
            highlighted: bar.activeOverlay === "calendar"
            clickable: true
            onClicked: bar.openCalendar(bar.centerOf(clockPill))

            // side bar: hh / mm / AM stacked
            Column {
                visible: bar.vertical
                spacing: -3
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Atelier.hour12(bar.now)
                    font.family: Atelier.font
                    font.pixelSize: 14
                    font.bold: true
                    color: Atelier.accent
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(bar.now, "mm")
                    font.family: Atelier.font
                    font.pixelSize: 14
                    font.bold: true
                    color: Atelier.text
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: text !== ""
                    topPadding: 3
                    text: Atelier.ampm(bar.now)
                    font.family: Atelier.font
                    font.pixelSize: 8
                    font.bold: true
                    color: Atelier.blue
                }
            }
            // flat bar: "Tue 24 Nov   4:12 PM" as plain text
            Text {
                visible: Atelier.flatBar
                text: Qt.formatDate(bar.now, "ddd d MMM") + "    "
                    + (Atelier.clock24 ? Qt.formatTime(bar.now, "HH:mm") : Qt.formatTime(bar.now, "h:mm AP"))
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.Medium
                font.features: { "tnum": 1 }
                color: Atelier.text
            }
            // top/bottom bar: hh:mm AM in one line
            Row {
                visible: !bar.vertical && !Atelier.flatBar
                spacing: 5
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Atelier.hour12(bar.now)
                    font.family: Atelier.font
                    font.pixelSize: 14
                    font.bold: true
                    color: Atelier.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ":"
                    font.family: Atelier.font
                    font.pixelSize: 14
                    font.bold: true
                    color: Atelier.accent
                    leftPadding: -3
                    rightPadding: -3
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatTime(bar.now, "mm")
                    font.family: Atelier.font
                    font.pixelSize: 14
                    font.bold: true
                    color: Atelier.text
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    text: Atelier.ampm(bar.now)
                    font.family: Atelier.font
                    font.pixelSize: 9
                    font.bold: true
                    color: Atelier.blue
                }
            }
        }

        // Status → each icon opens its drawer, the bell opens the control center
        Pill {
            id: statusPill
            Layout.alignment: bar.crossAlign
            visible: Settings.bar.showStatus
            pad: 5
            gap: 2
            highlighted: bar.activeOverlay === "controlcenter"

            BarIcon {
                id: wifiIcon
                hoverName: "wifi"
                icon: SysState.wifiIcon
                iconColor: SysState.wifiConnected ? Atelier.sky : Atelier.subtext
                size: 15
                active: bar.activeOverlay === "wifi"
                onClicked: bar.openWifi(bar.centerOf(wifiIcon))
            }
            BarIcon {
                id: btIcon
                hoverName: "bluetooth"
                icon: !bar.btOn ? "󰂲" : bar.btConnected ? "󰂱" : "󰂯"
                iconColor: bar.btConnected ? Atelier.blue : Atelier.subtext
                size: 15
                active: bar.activeOverlay === "bluetooth"
                onClicked: bar.openBluetooth(bar.centerOf(btIcon))
            }
            BarIcon {
                icon: bar.muted ? "󰝟" : bar.volume > 0.6 ? "󰕾" : bar.volume > 0.25 ? "󰖀" : "󰕿"
                iconColor: bar.muted ? Atelier.red : Atelier.text
                size: 15
                onClicked: if (bar.sink && bar.sink.audio) bar.sink.audio.muted = !bar.sink.audio.muted
                WheelHandler {
                    onWheel: (e) => {
                        if (!bar.sink || !bar.sink.audio) return;
                        bar.sink.audio.volume = Math.max(0, Math.min(1, bar.sink.audio.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05)));
                        bar.sink.audio.muted = false;
                    }
                }
            }
            // battery: icon + percentage (stacked on a side bar, side by side on a top/bottom bar)
            Item {
                visible: bar.hasBattery
                width: bar.vertical ? 28 : batGrid.implicitWidth + 4
                height: bar.vertical ? batGrid.implicitHeight + 4 : 28
                Grid {
                    id: batGrid
                    anchors.centerIn: parent
                    columns: bar.vertical ? 1 : 2
                    spacing: bar.vertical ? -2 : 3
                    horizontalItemAlignment: Grid.AlignHCenter
                    verticalItemAlignment: Grid.AlignVCenter
                    Text {
                        text: bar.charging ? "󰂄"
                            : bar.batPct > 0.9 ? "󰁹" : bar.batPct > 0.7 ? "󰂁" : bar.batPct > 0.5 ? "󰁿"
                            : bar.batPct > 0.3 ? "󰁽" : bar.batPct > 0.15 ? "󰁻" : "󰂃"
                        font.family: Atelier.font
                        font.pixelSize: Atelier.fsXl
                        color: bar.charging ? Atelier.green : bar.batPct <= 0.15 ? Atelier.red : Atelier.text
                    }
                    Text {
                        text: Math.round(bar.batPct * 100)
                        font.family: Atelier.font
                        font.pixelSize: 9
                        font.bold: true
                        color: Atelier.subtext
                    }
                }
            }
            BarIcon {
                icon: Notifs.dnd ? "󰂛" : (Notifs.count > 0 ? "󰂚" : "󰂜")
                iconColor: Notifs.count > 0 && !Notifs.dnd ? Atelier.accent : Atelier.text
                size: 15
                active: bar.activeOverlay === "controlcenter"
                onClicked: bar.openControlCenter()

                Rectangle {
                    visible: Notifs.count > 0 && !Notifs.dnd
                    x: parent.width - width - 3
                    y: 3
                    width: 7
                    height: 7
                    radius: 3.5
                    color: Atelier.red
                }
            }
        }

        // Power → session
        BarIcon {
            Layout.alignment: bar.crossAlign
            visible: Settings.bar.showPower
            icon: "⏻"
            size: 16
            iconColor: Atelier.red
            active: bar.activeOverlay === "power"
            onClicked: bar.openPower()
        }
    }

    // ── Building blocks ──────────────────────────────────────────────────────
    // A rounded group of items; its content flows along the bar's direction.
    component Pill: Rectangle {
        id: pill
        property bool highlighted: false
        property bool clickable: false
        property string hoverName: ""       // opens its drawer on hover (see setHover)
        property int pad: 5
        property int gap: 2
        default property alias content: grid.data
        signal clicked()

        implicitWidth: bar.vertical ? bar.pillWidth : grid.implicitWidth + 2 * pad + 6
        implicitHeight: bar.vertical ? grid.implicitHeight + 2 * pad : bar.pillWidth
        radius: bar.pillWidth / 2
        color: highlighted ? Qt.alpha(Atelier.accent, 0.18) : Atelier.flatBar ? "transparent" : Atelier.container
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }

        MouseArea {
            anchors.fill: parent
            enabled: pill.clickable
            hoverEnabled: pill.hoverName !== ""
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
            onContainsMouseChanged: if (pill.hoverName !== "") bar.setHover(pill.hoverName, pill, containsMouse)
        }
        Grid {
            id: grid
            anchors.centerIn: parent
            columns: bar.vertical ? 1 : 100
            spacing: pill.gap
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter
        }
    }

    component BarIcon: Item {
        id: bi
        property string icon
        property color iconColor: Atelier.text
        property int size: 16
        property bool active: false
        property string hoverName: ""       // opens its drawer on hover (see setHover)
        signal clicked()

        implicitWidth: 28
        implicitHeight: 28

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: bi.active ? Qt.alpha(Atelier.accent, 0.25) : (biMa.containsMouse ? Atelier.containerHigh : "transparent")
            Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        }
        Text {
            anchors.centerIn: parent
            text: bi.icon
            font.family: Atelier.font
            font.pixelSize: bi.size
            color: bi.iconColor
            scale: biMa.pressed ? 0.85 : (biMa.containsMouse ? 1.15 : 1)
            Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen } }
        }
        MouseArea {
            id: biMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: bi.clicked()
            onContainsMouseChanged: if (bi.hoverName !== "") bar.setHover(bi.hoverName, bi, containsMouse)
        }
    }
}
