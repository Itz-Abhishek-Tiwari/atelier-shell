import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.config
import qs.services

// "Gauge" bar design (Settings → Bar → Bar design): live readouts instead of boxes. Waybar.qml
// loads this in place of its pill layout and keeps all data + signals; this file only draws.
// Works on every edge (a column on the left/right, a row on the top/bottom).
//
//   logo tile · workspaces (app icons, a thin accent marker on the active one) · pinned apps ·
//   now playing (cover art inside a progress ring) · clock (big stacked type + date) ·
//   volume and battery as ring gauges · wifi · bluetooth · bell · power
Item {
    id: root

    required property var bar            // Waybar: data, signals, centerOf(), setHover()
    signal openMedia()

    // the items the hover-open drawers anchor to (Waybar.zones())
    readonly property Item clockItem: clock
    readonly property Item wifiItem: wifi
    readonly property Item btItem: bt

    readonly property bool v: bar.vertical
    readonly property int cell: Math.max(26, Atelier.barWidth - 14)   // one square slot
    readonly property int ring: Math.min(cell, 30)                    // gauge diameter

    // now playing (the first playing player, else the first one)
    readonly property var player: {
        const ps = Mpris.players.values;
        return ps.find(p => p.isPlaying) || ps[0] || null;
    }
    readonly property bool playing: !!(player && player.isPlaying)
    // MprisPlayer.position isn't reactive: poke it while something plays
    Timer { interval: 2000; repeat: true; running: root.playing; onTriggered: root.player.positionChanged() }

    // ── building blocks ──────────────────────────────────────────────────────
    // a ring that fills clockwise from the top; repaints only when its value or colour changes
    component Ring: Canvas {
        id: rg
        property real value: 0
        property color tint: Atelier.accent
        property real stroke: 2.5
        implicitWidth: root.ring
        implicitHeight: root.ring
        onValueChanged: requestPaint()
        onTintChanged: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.reset();
            const r = (Math.min(width, height) - stroke) / 2, cx = width / 2, cy = height / 2;
            c.lineWidth = stroke; c.lineCap = "round";
            c.strokeStyle = Qt.alpha(Atelier.text, 0.12);
            c.beginPath(); c.arc(cx, cy, r, 0, Math.PI * 2); c.stroke();
            const v = Math.max(0, Math.min(1, value));
            if (v > 0.005) {
                c.strokeStyle = tint;
                c.beginPath(); c.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * v); c.stroke();
            }
        }
    }

    // a plain icon button with a hover wash; `dot` = a small accent dot in its corner
    component Glyph: Item {
        id: g
        property string icon: ""
        property color tint: Atelier.text
        property int size: 15
        property bool active: false
        property bool dot: false
        property string hoverName: ""
        signal clicked()
        Layout.alignment: Qt.AlignCenter
        implicitWidth: root.cell
        implicitHeight: root.cell
        Rectangle {
            anchors.fill: parent
            radius: Atelier.radiusSm
            color: g.active ? Qt.alpha(Atelier.accent, 0.2) : Atelier.containerHigh
            opacity: g.active || gma.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
        }
        Text {
            anchors.centerIn: parent
            text: g.icon
            font.family: Atelier.font; font.pixelSize: g.size
            color: g.tint
            scale: gma.pressed ? 0.85 : 1
            Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
        }
        Rectangle {
            visible: g.dot
            x: parent.width - 9; y: 4
            width: 6; height: 6; radius: 3
            color: Atelier.red
        }
        MouseArea {
            id: gma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: g.clicked()
            onContainsMouseChanged: if (g.hoverName !== "") bar.setHover(g.hoverName, g, containsMouse)
        }
    }

    // ── layout ───────────────────────────────────────────────────────────────
    GridLayout {
        anchors.fill: parent
        anchors.topMargin: root.v ? 10 : 0
        anchors.bottomMargin: root.v ? 10 : 0
        anchors.leftMargin: root.v ? 0 : 10
        anchors.rightMargin: root.v ? 0 : 10
        flow: root.v ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: root.v ? 40 : 1
        columns: root.v ? 1 : 40
        rowSpacing: 4
        columnSpacing: 4

        // logo: a filled accent tile → app grid
        Item {
            visible: Settings.bar.showLogo
            Layout.alignment: Qt.AlignCenter
            implicitWidth: root.cell
            implicitHeight: root.cell
            Rectangle {
                anchors.fill: parent
                radius: Atelier.radiusMd
                color: Atelier.accentFill
                scale: logoMa.pressed ? 0.9 : logoMa.containsMouse ? 1.06 : 1
                Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
                Text { anchors.centerIn: parent; text: "󰣇"; font.family: Atelier.font; font.pixelSize: 15; color: Atelier.onFill }
            }
            MouseArea { id: logoMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bar.openLauncher() }
        }

        Item { implicitWidth: 6; implicitHeight: 6 }

        // workspaces: the app on each, a thin accent marker on the inner edge of the active one
        Item {
            id: wsBox
            visible: Settings.bar.showWorkspaces
            Layout.alignment: Qt.AlignCenter
            readonly property int slot: root.cell
            implicitWidth: root.v ? root.cell : bar.wsCount * slot
            implicitHeight: root.v ? bar.wsCount * slot : root.cell

            // the marker slides between workspaces
            Rectangle {
                readonly property real along: (bar.activeWs - 1) * wsBox.slot + (wsBox.slot - 16) / 2
                x: root.v ? (Atelier.barEdge === "right" ? parent.width - width : 0) : along
                y: root.v ? along : (Atelier.barEdge === "bottom" ? parent.height - height : 0)
                width: root.v ? 3 : 16
                height: root.v ? 16 : 3
                radius: 1.5
                color: Atelier.accent
                Behavior on x { enabled: !root.v; NumberAnimation { duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen } }
                Behavior on y { enabled: root.v; NumberAnimation { duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen } }
            }

            Grid {
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
                        readonly property string icon: used ? bar.iconForWorkspace(ws) : ""
                        width: wsBox.slot
                        height: wsBox.slot
                        Rectangle {
                            anchors.fill: parent; anchors.margins: 2
                            radius: Atelier.radiusSm
                            color: Atelier.containerHigh
                            opacity: wma.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
                        }
                        IconImage {
                            visible: w.icon !== ""
                            anchors.centerIn: parent
                            implicitSize: w.on ? 18 : 15
                            source: w.icon
                            asynchronous: true
                            opacity: w.on ? 1 : 0.55
                            Behavior on implicitSize { NumberAnimation { duration: Atelier.durFast } }
                        }
                        Text {
                            visible: w.icon === "" && (w.on || w.used)
                            anchors.centerIn: parent
                            text: w.num
                            font.family: Atelier.font; font.pixelSize: 12; font.bold: w.on
                            color: w.on ? Atelier.accent : Atelier.subtext
                        }
                        Rectangle {
                            visible: !w.used && !w.on
                            anchors.centerIn: parent
                            width: 4; height: 4; radius: 2
                            color: Atelier.overlay1
                        }
                        Rectangle {   // urgent
                            visible: !!(w.ws && w.ws.urgent)
                            x: parent.width - 8; y: 3; width: 5; height: 5; radius: 2.5
                            color: Atelier.red
                        }
                        MouseArea { id: wma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bar.goToWorkspace(w.num) }
                    }
                }
            }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (e) => bar.scrollWorkspace(e.angleDelta.y > 0)
            }
        }

        Item { implicitWidth: 6; implicitHeight: 6; visible: Settings.bar.showApps && !Atelier.dockOn }

        // pinned apps
        Repeater {
            model: Settings.bar.showApps && !Atelier.dockOn ? Settings.bar.pinned : []
            Glyph {
                required property var modelData
                icon: modelData.icon
                tint: Atelier[modelData.color] !== undefined ? Atelier[modelData.color] : Atelier.text
                onClicked: Quickshell.execDetached(["sh", "-c", modelData.cmd])
            }
        }

        // the middle: the window title
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
                width: root.v ? parent.height - 20 : parent.width - 20
                rotation: root.v ? 90 : 0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: Hyprland.activeToplevel && Hyprland.activeToplevel.title ? Hyprland.activeToplevel.title : ""
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                color: Atelier.subtext
                opacity: text ? 0.8 : 0
            }
        }

        // now playing: cover art in a progress ring; click opens the music drawer, wheel skips
        Item {
            id: media
            visible: root.player !== null
            Layout.alignment: Qt.AlignCenter
            implicitWidth: root.ring + 2
            implicitHeight: root.ring + 2
            readonly property real progress: root.player && root.player.length > 0 ? root.player.position / root.player.length : 0
            Ring { anchors.centerIn: parent; value: media.progress; tint: Atelier.green }
            ClippingRectangle {
                anchors.centerIn: parent
                width: root.ring - 8; height: width; radius: width / 2
                color: Atelier.containerHigh
                Image {
                    anchors.fill: parent
                    source: root.player ? (root.player.trackArtUrl || "") : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 64; sourceSize.height: 64
                    asynchronous: true
                    opacity: root.playing ? 1 : 0.45
                }
                Text {
                    anchors.centerIn: parent
                    visible: !root.player || !root.player.trackArtUrl
                    text: "󰎆"; font.family: Atelier.font; font.pixelSize: 12; color: Atelier.green
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onClicked: (m) => { if (m.button === Qt.MiddleButton) root.player.togglePlaying(); else root.openMedia(); }
                onWheel: (e) => { if (e.angleDelta.y > 0) root.player.previous(); else root.player.next(); }
            }
        }

        // git: branch icon tinted by state + the change count
        Item {
            visible: Settings.bar.showGit && GitStatus.active
            Layout.alignment: Qt.AlignCenter
            implicitWidth: root.v ? root.cell : gitCol.implicitWidth + 8
            implicitHeight: root.v ? gitCol.implicitHeight + 6 : root.cell
            Grid {
                id: gitCol
                anchors.centerIn: parent
                columns: root.v ? 1 : 2
                spacing: root.v ? 0 : 3
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter
                Text { text: "󰊢"; font.family: Atelier.font; font.pixelSize: 14
                       color: GitStatus.dirty > 0 ? Atelier.peach : Atelier.green }
                Text { visible: GitStatus.dirty > 0; text: GitStatus.dirty > 99 ? "99+" : GitStatus.dirty
                       font.family: Atelier.font; font.pixelSize: 9; font.bold: true; color: Atelier.subtext }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["wl-copy", GitStatus.branch]) }
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

        Item { implicitWidth: 6; implicitHeight: 6 }

        // clock: big stacked type, the date under it (a row on top/bottom bars)
        Item {
            id: clock
            visible: Settings.bar.showClock
            Layout.alignment: Qt.AlignCenter
            implicitWidth: root.v ? root.cell + 4 : clockGrid.implicitWidth + 14
            implicitHeight: root.v ? clockGrid.implicitHeight + 10 : root.cell
            readonly property bool on: bar.activeOverlay === "calendar"
            Rectangle {
                anchors.fill: parent
                radius: Atelier.radiusMd
                color: clock.on ? Qt.alpha(Atelier.accent, 0.2) : Atelier.containerHigh
                opacity: clock.on || clockMa.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
            }
            Grid {
                id: clockGrid
                anchors.centerIn: parent
                columns: root.v ? 1 : 6
                rowSpacing: -4
                columnSpacing: 0
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter
                Text { text: Atelier.hour12(bar.now); font.family: Atelier.fontDisplay; font.pixelSize: root.v ? 20 : 15; font.weight: Font.Bold; color: Atelier.text }
                Text { visible: !root.v; text: ":"; font.family: Atelier.fontDisplay; font.pixelSize: 15; font.weight: Font.Bold; color: Atelier.accent }
                Text { text: Qt.formatTime(bar.now, "mm"); font.family: Atelier.fontDisplay; font.pixelSize: root.v ? 20 : 15; font.weight: Font.Medium
                       color: root.v ? Atelier.accent : Atelier.text }
                Text { visible: text !== ""; text: Atelier.ampm(bar.now)
                       topPadding: root.v ? 4 : 0; leftPadding: root.v ? 0 : 4
                       font.family: Atelier.font; font.pixelSize: 8; font.bold: true; color: Atelier.subtext }
                Rectangle { visible: root.v; width: 12; height: 1; color: Atelier.outline }
                Text {
                    topPadding: root.v ? 5 : 0; leftPadding: root.v ? 0 : 10
                    text: root.v ? Qt.formatDate(bar.now, "ddd").toUpperCase() + "\n" + Qt.formatDate(bar.now, "d")
                                 : Qt.formatDate(bar.now, "ddd d").toUpperCase()
                    horizontalAlignment: Text.AlignHCenter
                    lineHeight: 0.95
                    font.family: Atelier.font; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.5
                    color: Atelier.subtext
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

        Item { implicitWidth: 6; implicitHeight: 6 }

        // volume gauge: click mutes, wheel changes
        Item {
            visible: Settings.bar.showStatus
            Layout.alignment: Qt.AlignCenter
            implicitWidth: root.ring + 2
            implicitHeight: root.ring + 2
            Ring { anchors.centerIn: parent; value: bar.muted ? 0 : bar.volume; tint: bar.muted ? Atelier.red : Atelier.blue }
            Text {
                anchors.centerIn: parent
                text: bar.muted ? "󰝟" : bar.volume > 0.6 ? "󰕾" : bar.volume > 0.25 ? "󰖀" : "󰕿"
                font.family: Atelier.font; font.pixelSize: 12
                color: bar.muted ? Atelier.red : Atelier.text
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (bar.sink && bar.sink.audio) bar.sink.audio.muted = !bar.sink.audio.muted
                onWheel: (e) => {
                    if (!bar.sink || !bar.sink.audio) return;
                    bar.sink.audio.volume = Math.max(0, Math.min(1, bar.sink.audio.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05)));
                    bar.sink.audio.muted = false;
                }
            }
        }

        // battery gauge: the percentage inside, green while charging, orange / red when low
        Item {
            visible: Settings.bar.showStatus && bar.hasBattery
            Layout.alignment: Qt.AlignCenter
            implicitWidth: root.ring + 2
            implicitHeight: root.ring + 2
            readonly property color tint: bar.charging ? Atelier.green : bar.batPct <= 0.15 ? Atelier.red
                                        : bar.batPct <= 0.3 ? Atelier.peach : Atelier.text
            Ring { anchors.centerIn: parent; value: bar.batPct; tint: parent.tint }
            Text {
                anchors.centerIn: parent
                text: bar.charging ? "󱐋" : Math.round(bar.batPct * 100)
                font.family: Atelier.font; font.pixelSize: bar.charging ? 12 : 10; font.bold: true
                color: parent.tint
            }
        }

        Item { implicitWidth: 4; implicitHeight: 4 }

        Glyph {
            id: wifi
            visible: Settings.bar.showStatus
            hoverName: "wifi"
            active: bar.activeOverlay === "wifi"
            icon: SysState.wifiIcon
            tint: SysState.wifiConnected ? Atelier.text : Atelier.subtext
            onClicked: bar.openWifi(bar.centerOf(wifi))
        }
        Glyph {
            id: bt
            visible: Settings.bar.showStatus
            hoverName: "bluetooth"
            active: bar.activeOverlay === "bluetooth"
            icon: !bar.btOn ? "󰂲" : bar.btConnected ? "󰂱" : "󰂯"
            tint: bar.btConnected ? Atelier.blue : Atelier.subtext
            onClicked: bar.openBluetooth(bar.centerOf(bt))
        }
        Glyph {
            visible: Settings.bar.showStatus
            active: bar.activeOverlay === "notifications"
            icon: Notifs.dnd ? "󰂛" : "󰂚"
            tint: Notifs.dnd ? Atelier.subtext : Atelier.text
            dot: Notifs.count > 0 && !Notifs.dnd
            onClicked: bar.openNotifications()
        }
        Glyph {
            visible: Settings.bar.showPower
            active: bar.activeOverlay === "power"
            icon: "⏻"
            tint: Atelier.red
            onClicked: bar.openPower()
        }
    }
}
