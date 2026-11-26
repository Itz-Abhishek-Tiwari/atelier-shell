import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.config
import qs.services

// "Dock" bar design (Settings → Bar → Bar design): a bare icon rail. Bigger icons on no background,
// hairline dividers, workspaces as dots (the active one stretches into an accent capsule), small
// numbers as badges. Waybar.qml loads this in place of its pill layout and keeps all data +
// signals; this file only draws. Works on every edge: a column on the left/right, a row on the
// top/bottom.
Item {
    id: root

    required property var bar            // Waybar: data, signals, centerOf(), setHover()

    // the items the hover-open drawers anchor to (Waybar.zones())
    readonly property Item clockItem: clock
    readonly property Item wifiItem: wifi
    readonly property Item btItem: bt

    readonly property bool v: bar.vertical
    readonly property int thick: Atelier.barWidth                 // the bar's cross size
    readonly property int cell: Math.max(24, thick - 12)   // one icon's square
    readonly property int pad: 6                       // gap between the bar ends and the content

    // ── building blocks ──────────────────────────────────────────────────────
    component Divider: Rectangle {
        Layout.alignment: Qt.AlignCenter
        implicitWidth: root.v ? root.cell - 8 : 1
        implicitHeight: root.v ? 1 : root.cell - 8
        color: Atelier.outline
    }

    // an icon button; `badge` is a small number beside (row) or under (column) the icon
    component Cell: Item {
        id: c
        property string icon: ""
        property string badge: ""
        property color tint: Atelier.text
        property bool active: false
        property string hoverName: ""
        signal clicked()
        Layout.alignment: Qt.AlignCenter
        readonly property bool hasBadge: badge !== ""
        implicitWidth: root.v ? root.cell : (hasBadge ? 4 + glyph.implicitWidth + 2 + badgeText.implicitWidth + 6 : root.cell)
        implicitHeight: root.v ? root.cell + (hasBadge ? 10 : 0) : root.cell

        Rectangle {   // active: accent tint; hover: soft wash
            anchors.fill: parent
            radius: !c.hasBadge ? Math.min(width, height) / 2 : Atelier.radiusSm
            color: c.active ? Qt.alpha(Atelier.accent, 0.2)
                 : Atelier.containerHigh
            opacity: c.active || ma.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
        }
        Text {
            id: glyph
            x: root.v ? (parent.width - width) / 2 : (c.hasBadge ? 4 : (parent.width - width) / 2)
            y: root.v ? (c.hasBadge ? 3 : (parent.height - height) / 2) : (parent.height - height) / 2
            text: c.icon
            font.family: Atelier.font
            font.pixelSize: 18
            color: c.tint
            scale: ma.pressed ? 0.85 : ma.containsMouse ? 1.1 : 1
            Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
        }
        Text {
            id: badgeText
            visible: c.hasBadge
            x: root.v ? (parent.width - width) / 2 : glyph.x + glyph.width + 2
            y: root.v ? parent.height - height - 1 : (parent.height - height) / 2
            text: c.badge
            font.family: Atelier.font; font.pixelSize: 9; font.bold: true
            color: Atelier.subtext
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: c.clicked()
            onContainsMouseChanged: if (c.hoverName !== "") bar.setHover(c.hoverName, c, containsMouse)
        }
    }

    // ── layout ───────────────────────────────────────────────────────────────
    GridLayout {
        anchors.fill: parent
        anchors.topMargin: root.v ? root.pad + 2 : 0
        anchors.bottomMargin: root.v ? root.pad + 2 : 0
        anchors.leftMargin: root.v ? 0 : root.pad + 4
        anchors.rightMargin: root.v ? 0 : root.pad + 4
        flow: root.v ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: root.v ? 40 : 1
        columns: root.v ? 1 : 40
        rowSpacing: 5
        columnSpacing: 5

        // logo → app grid
        Cell {
            visible: Settings.bar.showLogo
            icon: "󰣇"
            tint: Atelier.accent
            active: bar.activeOverlay === "apps"
            onClicked: bar.openLauncher()
        }

        Divider { visible: Settings.bar.showWorkspaces }

        // workspaces
        Item {
            id: wsBox
            visible: Settings.bar.showWorkspaces
            Layout.alignment: Qt.AlignCenter
            readonly property int slot: 16
            implicitWidth: root.v ? root.cell : bar.wsCount * slot
            implicitHeight: root.v ? bar.wsCount * slot : root.cell
            Grid {
                anchors.centerIn: parent
                columns: root.v ? 1 : 100
                Repeater {
                    model: bar.wsCount
                    Item {
                        id: w
                        required property int index
                        readonly property int num: index + 1
                        readonly property bool on: bar.activeWs === num
                        readonly property var ws: bar.wsById[num] || null
                        readonly property bool used: !!(ws && ws.toplevels.values.length > 0)
                        readonly property bool urgent: !!(ws && ws.urgent)
                        width: root.v ? root.cell : wsBox.slot
                        height: root.v ? wsBox.slot : root.cell

                        // dots; the active one is an accent capsule along the bar
                        Rectangle {
                            anchors.centerIn: parent
                            width: root.v ? 6 : (w.on ? 16 : 6)
                            height: root.v ? (w.on ? 16 : 6) : 6
                            radius: 3
                            color: w.urgent ? Atelier.red : w.on ? Atelier.accent : Atelier.text
                            opacity: w.on ? 1 : w.used ? 0.7 : 0.25
                            Behavior on width { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.OutCubic } }
                            Behavior on height { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.OutCubic } }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: bar.goToWorkspace(w.num) }
                    }
                }
            }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (e) => bar.scrollWorkspace(e.angleDelta.y > 0)
            }
        }

        Divider { visible: Settings.bar.showApps && !Atelier.dockOn }

        // pinned apps
        Repeater {
            model: Settings.bar.showApps && !Atelier.dockOn ? Settings.bar.pinned : []
            Cell {
                required property var modelData
                icon: modelData.icon
                tint: Atelier[modelData.color] !== undefined ? Atelier[modelData.color] : Atelier.text
                onClicked: Quickshell.execDetached(["sh", "-c", modelData.cmd])
            }
        }

        // the focused window's title fills the middle
        Item {
            Layout.fillWidth: !root.v
            Layout.fillHeight: root.v
            Layout.alignment: Qt.AlignCenter
            implicitWidth: root.v ? root.cell : 10
            implicitHeight: root.v ? 10 : root.cell
            clip: true
            Text {
                visible: Settings.bar.showTitle
                anchors.centerIn: parent
                width: root.v ? parent.height - 16 : parent.width - 16
                rotation: root.v ? 90 : 0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: Hyprland.activeToplevel && Hyprland.activeToplevel.title ? Hyprland.activeToplevel.title : ""
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                color: Atelier.subtext
                opacity: text ? 0.85 : 0
            }
        }

        // git: dot-free, the branch icon tinted by state, the change count as a badge
        Cell {
            visible: Settings.bar.showGit && GitStatus.active
            icon: "󰊢"
            badge: GitStatus.dirty > 0 ? (GitStatus.dirty > 99 ? "99+" : String(GitStatus.dirty)) : ""
            tint: GitStatus.dirty > 0 ? Atelier.peach : Atelier.green
            onClicked: Quickshell.execDetached(["wl-copy", GitStatus.branch])
        }

        // recording: red dot + time, click to stop
        Item {
            visible: Recorder.recording
            Layout.alignment: Qt.AlignCenter
            implicitWidth: root.v ? root.cell : recRow.implicitWidth + 10
            implicitHeight: root.v ? recRow.implicitHeight + 8 : root.cell
            Rectangle { anchors.fill: parent; radius: Atelier.radiusSm; color: Qt.alpha(Atelier.red, 0.18) }
            Grid {
                id: recRow
                anchors.centerIn: parent
                columns: root.v ? 1 : 2
                spacing: 3
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter
                Rectangle { width: 8; height: 8; radius: 4; color: Atelier.red }
                Text { text: Recorder.elapsedText; font.family: Atelier.font; font.pixelSize: 9; font.bold: true; color: Atelier.red }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Recorder.stop() }
        }

        Divider { visible: Settings.bar.showClock }

        // clock → calendar
        Item {
            id: clock
            visible: Settings.bar.showClock
            Layout.alignment: Qt.AlignCenter
            implicitWidth: root.v ? root.cell : clockGrid.implicitWidth + 14
            implicitHeight: root.v ? clockGrid.implicitHeight + 10 : root.cell
            readonly property bool on: bar.activeOverlay === "calendar"
            Rectangle {
                anchors.fill: parent
                radius: Atelier.radiusSm
                color: clock.on ? Qt.alpha(Atelier.accent, 0.2) : Atelier.containerHigh
                opacity: clock.on || clockMa.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
            }
            Grid {
                id: clockGrid
                anchors.centerIn: parent
                columns: root.v ? 1 : 4
                rowSpacing: -3
                columnSpacing: 1
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter
                readonly property color ink: Atelier.text
                Text { text: Atelier.hour12(bar.now); font.family: Atelier.font; font.pixelSize: 14; font.bold: true
                       color: Atelier.accent }
                Text { visible: !root.v; text: ":"; font.family: Atelier.font; font.pixelSize: 14; font.bold: true; color: clockGrid.ink }
                Text { text: Qt.formatTime(bar.now, "mm"); font.family: Atelier.font; font.pixelSize: 14; font.bold: true; color: clockGrid.ink }
                Text {   // AM / PM ("" in 24-hour mode)
                    visible: text !== ""
                    topPadding: root.v ? 3 : 0
                    leftPadding: root.v ? 0 : 3
                    text: Atelier.ampm(bar.now)
                    font.family: Atelier.font; font.pixelSize: 8; font.bold: true
                    color: Atelier.blue
                }
            }
            MouseArea {
                id: clockMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: bar.openCalendar(bar.centerOf(clock))
                onContainsMouseChanged: bar.setHover("calendar", clock, containsMouse)
            }
        }

        Divider { visible: Settings.bar.showStatus }

        // status
        Cell {
            id: wifi
            visible: Settings.bar.showStatus
            hoverName: "wifi"
            active: bar.activeOverlay === "wifi"
            icon: SysState.wifiIcon
            tint: SysState.wifiConnected ? Atelier.sky : Atelier.subtext
            onClicked: bar.openWifi(bar.centerOf(wifi))
        }
        Cell {
            id: bt
            visible: Settings.bar.showStatus
            hoverName: "bluetooth"
            active: bar.activeOverlay === "bluetooth"
            icon: !bar.btOn ? "󰂲" : bar.btConnected ? "󰂱" : "󰂯"
            tint: bar.btConnected ? Atelier.blue : Atelier.subtext
            onClicked: bar.openBluetooth(bar.centerOf(bt))
        }
        Cell {
            visible: Settings.bar.showStatus
            icon: bar.muted ? "󰝟" : bar.volume > 0.6 ? "󰕾" : bar.volume > 0.25 ? "󰖀" : "󰕿"
            tint: bar.muted ? Atelier.red : Atelier.text
            onClicked: if (bar.sink && bar.sink.audio) bar.sink.audio.muted = !bar.sink.audio.muted
            WheelHandler {
                onWheel: (e) => {
                    if (!bar.sink || !bar.sink.audio) return;
                    bar.sink.audio.volume = Math.max(0, Math.min(1, bar.sink.audio.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05)));
                    bar.sink.audio.muted = false;
                }
            }
        }
        Cell {
            visible: Settings.bar.showStatus && bar.hasBattery
            icon: bar.charging ? "󰂄" : bar.batPct > 0.9 ? "󰁹" : bar.batPct > 0.7 ? "󰂁" : bar.batPct > 0.5 ? "󰁿"
                : bar.batPct > 0.3 ? "󰁽" : bar.batPct > 0.15 ? "󰁻" : "󰂃"
            badge: Math.round(bar.batPct * 100) + "%"
            tint: bar.charging ? Atelier.green : bar.batPct <= 0.15 ? Atelier.red : bar.batPct <= 0.3 ? Atelier.peach : Atelier.text
        }
        Cell {
            visible: Settings.bar.showStatus
            active: bar.activeOverlay === "notifications"
            icon: Notifs.dnd ? "󰂛" : (Notifs.count > 0 ? "󰂚" : "󰂜")
            badge: Notifs.count > 0 && !Notifs.dnd ? String(Notifs.count) : ""
            tint: Notifs.count > 0 && !Notifs.dnd ? Atelier.accent : Atelier.text
            onClicked: bar.openNotifications()
        }

        Cell {
            visible: Settings.bar.showPower
            active: bar.activeOverlay === "power"
            icon: "⏻"
            tint: Atelier.red
            onClicked: bar.openPower()
        }
    }
}
