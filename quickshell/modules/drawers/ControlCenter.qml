import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.components
import qs.config
import qs.services

// Control center: drawer out of the right border, sized to its content.
// Quiet, monochrome, typographic (the website's language): tiny uppercase labels, ink-filled
// 5px bars, list rows with pill switches, transparent round controls, numbers in mono,
// one accent only for "on". No coloured tiles.
Item {
    id: root
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window



    property bool animActive: false
    signal closedSignal()
    signal requestOverlay(string name)

    function toggle() { if (visible && animActive) close(); else open(); }
    function open() {
        visible = true;
        animActive = true;
        SysState.refreshWifi();
        SysState.refreshBrightness();
        if (!adguardSet.running) adguardGet.running = true;
        focusTimer.restart();
    }
    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }

    Timer { id: focusTimer; interval: 40; onTriggered: keys.forceActiveFocus() }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!root.animActive) root.visible = false }

    // ── AdGuard DNS (config-scripts/adguard-dns.sh → ~/.local/bin/adguard-dns) ──
    property string adguard: "off"          // on | family | off
    readonly property string adguardCli: Quickshell.env("HOME") + "/.local/bin/adguard-dns"
    Process {
        id: adguardGet
        command: [root.adguardCli, "status"]
        stdout: StdioCollector { onStreamFinished: { const t = text.trim(); if (t) root.adguard = t; } }
    }
    Process {
        id: adguardSet
        stdout: StdioCollector { onStreamFinished: { const t = text.trim(); if (t) root.adguard = t; } }
    }
    function setAdguard(mode) {
        if (adguardSet.running) return;
        root.adguard = mode;                  // optimistic; the script echoes the real state back
        adguardSet.command = [root.adguardCli, mode];
        adguardSet.running = true;
    }

    // ── Live data ────────────────────────────────────────────────────────────
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.sink, root.source].filter(o => o) }

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d.connected)

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!(battery && battery.isLaptopBattery)
    readonly property real batPct: battery ? battery.percentage : 0
    readonly property bool charging: !!(battery && battery.state === UPowerDeviceState.Charging)

    property date now: new Date()
    readonly property string greeting: {
        const h = now.getHours();
        return h >= 5 && h < 12 ? "Good morning" : h < 17 && h >= 12 ? "Good afternoon" : h >= 17 && h < 22 ? "Good evening" : "Good night";
    }
    Timer { interval: 1000; running: root.visible; repeat: true; triggeredOnStart: true; onTriggered: root.now = new Date() }

    // ── Dismiss ──────────────────────────────────────────────────────────────
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.close()
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    EdgeDrawer {
        id: drawer
        edge: "right"
        open: root.animActive
        bodyWidth: 392
        bodyHeight: Math.min(root.height - Atelier.insetTop - Atelier.insetBottom - 2 * Atelier.fillet - 24, content.implicitHeight + 44)
        Behavior on bodyHeight { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }

        // The whole panel scrolls as one piece when it is taller than the screen
        // (before, the bottom was simply cut off).
        Flickable {
            id: scroller
            anchors.fill: parent
            contentWidth: width
            contentHeight: content.implicitHeight + 44
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            SmoothWheel { flickable: scroller }

        ColumnLayout {
            id: content
            x: 22
            y: 22
            width: scroller.width - 44
            spacing: 20

            // ── Header: greeting + buttons · big clock + AM/PM chip · date + battery chip ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.greeting + (Atelier.userName ? ", " + Atelier.userName : "")
                        font.family: Atelier.fontUi
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: Atelier.mauve
                        elide: Text.ElideRight
                    }
                    RoundBtn { icon: "󰒓"; size: 30; glyphSize: 14; onClicked: root.requestOverlay("settings") }
                    RoundBtn { icon: "󰐥"; size: 30; glyphSize: 14; hoverTint: Atelier.red; onClicked: root.requestOverlay("power") }
                }

                RowLayout {
                    spacing: 10
                    Row {
                        Layout.alignment: Qt.AlignVCenter
                        Text {
                            text: Atelier.hour12(root.now)
                            font.family: Atelier.font
                            font.pixelSize: 46
                            font.weight: Font.Bold
                            color: Atelier.text
                        }
                        Text {   // the colon breathes once a second, in the accent colour
                            text: ":"
                            font.family: Atelier.font
                            font.pixelSize: 46
                            font.weight: Font.Bold
                            color: Atelier.accent
                            opacity: root.now.getSeconds() % 2 ? 0.45 : 1
                            Behavior on opacity { NumberAnimation { duration: 400 } }
                        }
                        Text {
                            text: Qt.formatTime(root.now, "mm")
                            font.family: Atelier.font
                            font.pixelSize: 46
                            font.weight: Font.Bold
                            color: Atelier.text
                        }
                    }
                    Chip {
                        visible: !Atelier.clock24
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: 6
                        text: Atelier.ampm(root.now)
                        tint: Atelier.blue
                    }
                    Item { Layout.fillWidth: true }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: "󰃭"
                        font.family: Atelier.font
                        font.pixelSize: 13
                        color: Atelier.peach
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: Qt.formatDate(root.now, "dddd, d MMMM")
                        font.family: Atelier.fontUi
                        font.pixelSize: 13
                        color: Atelier.subtext
                        elide: Text.ElideRight
                    }
                    Chip {
                        visible: root.hasBattery
                        readonly property bool low: root.batPct <= 0.15 && !root.charging
                        icon: root.charging ? "󰂄" : root.batPct > 0.9 ? "󰁹" : root.batPct > 0.7 ? "󰂁"
                            : root.batPct > 0.5 ? "󰁿" : root.batPct > 0.3 ? "󰁽" : root.batPct > 0.15 ? "󰁻" : "󰂃"
                        text: Math.round(root.batPct * 100) + "%"
                        tint: low ? Atelier.red : root.charging ? Atelier.green : root.batPct <= 0.3 ? Atelier.yellow : Atelier.green
                    }
                }
            }

            // ── Sound + light: slim ink bars ────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                SlimSlider {
                    Layout.fillWidth: true
                    readonly property bool muted: root.sink && root.sink.audio ? root.sink.audio.muted : false
                    value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
                    dimmed: muted
                    icon: muted ? "󰝟" : value > 0.6 ? "󰕾" : value > 0.25 ? "󰖀" : "󰕿"
                    onMoved: (v) => { if (root.sink && root.sink.audio) { root.sink.audio.volume = v; root.sink.audio.muted = false; } }
                    onIconClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
                }
                SlimSlider {
                    Layout.fillWidth: true
                    value: SysState.brightness
                    icon: value > 0.6 ? "󰃠" : value > 0.3 ? "󰃟" : "󰃞"
                    onMoved: (v) => SysState.setBrightness(v)
                }
            }

            // ── Switches: one grouped list ──────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: switches.implicitHeight + 8
                radius: 18
                color: Atelier.container
                border.width: 1
                border.color: Atelier.outline

                ColumnLayout {
                    id: switches
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 4
                    spacing: 0

                    ToggleRow {
                        icon: SysState.wifiIcon
                        label: "Wi-Fi"
                        sub: !SysState.wifiEnabled ? "Off" : (SysState.ssid || "Not connected")
                        on: SysState.wifiEnabled
                        hasDetails: true
                        onToggled: SysState.setWifi(!SysState.wifiEnabled)
                        onDetails: root.requestOverlay("wifi")
                    }
                    Hairline {}
                    ToggleRow {
                        icon: root.adapter && root.adapter.enabled ? "󰂯" : "󰂲"
                        label: "Bluetooth"
                        sub: !(root.adapter && root.adapter.enabled) ? "Off"
                            : root.btConnected.length === 1 ? root.btConnected[0].name
                            : root.btConnected.length > 1 ? root.btConnected.length + " devices" : "On"
                        on: !!(root.adapter && root.adapter.enabled)
                        hasDetails: true
                        onToggled: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
                        onDetails: root.requestOverlay("bluetooth")
                    }
                    Hairline {}
                    ToggleRow {
                        icon: root.adguard !== "off" ? "󰕥" : "󰒙"
                        label: "AdGuard DNS"
                        sub: root.adguard === "family" ? "Blocking ads · family filter"
                           : root.adguard === "on" ? "Blocking ads and trackers" : "Off"
                        on: root.adguard !== "off"
                        onToggled: root.setAdguard(root.adguard !== "off" ? "off" : "on")
                    }
                    Hairline {}
                    ToggleRow {
                        icon: Notifs.dnd ? "󰂛" : "󰂚"
                        label: "Do Not Disturb"
                        sub: Notifs.dnd ? "Notifications are silenced" : "Off"
                        on: Notifs.dnd
                        onToggled: Notifs.dnd = !Notifs.dnd
                    }
                    Hairline {}
                    ToggleRow {
                        icon: NightLight.active ? "󰖔" : "󰖙"
                        label: "Night light"
                        sub: NightLight.status
                        on: NightLight.active
                        hasDetails: true
                        onToggled: NightLight.toggle()
                        onDetails: root.requestOverlay("settings:appearance")
                    }
                    Hairline {}
                    ToggleRow {
                        icon: "󰑋"
                        label: "Screen recording"
                        sub: Recorder.recording ? "Recording · " + Recorder.elapsedText + " · click to stop"
                           : !Recorder.available ? "Install wf-recorder" : "Pick an area to record"
                        on: Recorder.recording
                        onToggled: root.requestOverlay("record")
                    }
                    Hairline {}
                    ToggleRow {
                        icon: "󰅶"
                        label: "Keep awake"
                        sub: Atelier.caffeine ? "Screen stays on" : "Off"
                        on: Atelier.caffeine
                        onToggled: Atelier.caffeine = !Atelier.caffeine
                    }
                    Hairline {}
                    ToggleRow {
                        icon: "󰄜"
                        label: "iPhone camera"
                        sub: PhoneCam.summary
                        on: PhoneCam.running
                        onToggled: PhoneCam.toggle()
                    }
                    Hairline {}
                    ToggleRow {
                        readonly property bool muted: !root.source || !root.source.audio || root.source.audio.muted
                        icon: muted ? "󰍭" : "󰍬"
                        label: "Microphone"
                        sub: muted ? "Muted" : "On"
                        on: !muted
                        onToggled: if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted
                    }
                }
            }

            // ── Mode ────────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { text: "Mode"; font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: Font.Medium; color: Atelier.text }
                    Text {
                        text: Perf.game ? "Max performance" : Perf.dev ? "Opaque windows, faster" : "Your usual look"
                        font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext
                    }
                }
                Row {
                    spacing: 4
                    Repeater {
                        model: [{ id: "normal", label: "Normal" }, { id: "dev", label: "Coding" }, { id: "game", label: "Game" }]
                        Rectangle {
                            required property var modelData
                            readonly property bool sel: Perf.mode === modelData.id
                            width: segText.implicitWidth + 24
                            height: 30
                            radius: 12
                            color: sel ? Atelier.accentFill : (segMa.containsMouse ? Atelier.containerHigh : Atelier.container)
                            Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                            Text {
                                id: segText
                                anchors.centerIn: parent
                                text: modelData.label
                                font.family: Atelier.fontUi
                                font.pixelSize: 12
                                font.weight: parent.sel ? Font.DemiBold : Font.Normal
                                color: parent.sel ? Atelier.onAccent : Atelier.text
                            }
                            MouseArea { id: segMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Perf.set(modelData.id) }
                        }
                    }
                }
            }

            // ── Shortcuts: four quiet round buttons ─────────────────────────
            Row {
                id: shortcuts
                Layout.fillWidth: true
                Repeater {
                    model: [
                        { icon: "󰄀", label: "Screenshot", act: "screenshot" },
                        { icon: "󰸉", label: "Wallpaper", act: "wallpaper" },
                        { icon: "󰏘", label: "Theme", act: "theme" },
                        { icon: "󰌌", label: "Keyboard", act: "keyboard" },
                        { icon: "󰧺", label: "Shortcuts", act: "keybinds" }
                    ]
                    ColumnLayout {
                        required property var modelData
                        width: shortcuts.width / 5
                        spacing: 6
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 46
                            implicitHeight: 46
                            radius: 23
                            color: scMa.containsMouse ? Atelier.containerHigh : Atelier.container
                            border.width: 1
                            border.color: Atelier.outline
                            scale: scMa.pressed ? 0.94 : 1
                            Behavior on scale { NumberAnimation { duration: 120 } }
                            Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon
                                font.family: Atelier.font
                                font.pixelSize: 17
                                color: scMa.containsMouse ? Atelier.text : Atelier.subtext
                            }
                            MouseArea { id: scMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.requestOverlay(modelData.act) }
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.label
                            font.family: Atelier.fontUi
                            font.pixelSize: 11
                            color: Atelier.subtext
                        }
                    }
                }
            }

            // ── Notifications ───────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8
                SectionLabel { text: "Notifications" }
                Text { visible: Notifs.count > 0; text: Notifs.count; font.family: root.mono; font.pixelSize: 11; color: Atelier.subtext }
                Item { Layout.fillWidth: true }
                Text {
                    visible: Notifs.count > 0
                    text: "Clear all"
                    font.family: Atelier.fontUi
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: clearMa.containsMouse ? Atelier.text : Atelier.subtext
                    MouseArea { id: clearMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.clearAll() }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: -8
                Layout.bottomMargin: 2
                visible: Notifs.count === 0
                text: Notifs.dnd ? "Do Not Disturb is on." : "You're all caught up."
                font.family: Atelier.fontUi
                font.pixelSize: 12
                color: Atelier.subtext
            }

            ListView {
                id: notifList
                Layout.fillWidth: true
                Layout.topMargin: -6
                visible: Notifs.count > 0
                implicitHeight: contentHeight
                interactive: false
                spacing: 8
                model: Notifs.list
                boundsBehavior: Flickable.StopAtBounds

                delegate: NotificationCard {
                    required property var modelData
                    width: notifList.width
                    notif: modelData
                }

                add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Atelier.durFast } }
                remove: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "x"; to: 120; duration: Atelier.durClose; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveClose }
                        NumberAnimation { property: "opacity"; to: 0; duration: Atelier.durClose }
                    }
                }
                displaced: Transition {
                    NumberAnimation { properties: "y"; duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard }
                }
            }
        }
        }
    }

    // ── Pieces ──────────────────────────────────────────────────────────────
    readonly property string mono: "JetBrainsMono Nerd Font"

    // tiny uppercase section label (the site's .lbl)
    component SectionLabel: Text {
        font.family: Atelier.fontUi
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1.3
        font.capitalization: Font.AllUppercase
        color: Atelier.subtext
    }

    component Hairline: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 50
        Layout.rightMargin: 14
        implicitHeight: 1
        color: Atelier.outline
    }

    // transparent round button; tints on hover
    component RoundBtn: Rectangle {
        id: rb
        property string icon
        property int size: 34
        property int glyphSize: 15
        property color hoverTint: Atelier.text
        signal clicked()
        implicitWidth: size
        implicitHeight: size
        radius: size / 2
        opacity: enabled ? 1 : 0.35
        color: rbMa.containsMouse ? Atelier.containerHigh : "transparent"
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Text {
            anchors.centerIn: parent
            text: rb.icon
            font.family: Atelier.font
            font.pixelSize: rb.glyphSize
            color: rbMa.containsMouse ? rb.hoverTint : Atelier.subtext
        }
        MouseArea { id: rbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (rb.enabled) rb.clicked() }
    }

    // pill switch (the site's .tg)
    component PillSwitch: Rectangle {
        id: sw
        property bool on: false
        signal toggled()
        implicitWidth: 38
        implicitHeight: 22
        radius: 11
        color: on ? Atelier.accentFill : Qt.alpha(Atelier.text, 0.18)
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Rectangle {
            y: 3
            x: sw.on ? sw.width - width - 3 : 3
            width: 16; height: 16; radius: 8
            color: sw.on ? Atelier.onFill : (Atelier.isLight ? Atelier.base : Atelier.text)
            Behavior on x { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }
        }
        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
    }

    // one row of the switches list: glyph · label / sub-label · (chevron) · switch
    component ToggleRow: Item {
        id: tr
        property string icon
        property string label
        property string sub
        property bool on: false
        property bool hasDetails: false
        signal toggled()
        signal details()
        Layout.fillWidth: true
        implicitHeight: 54

        Rectangle {   // hover wash
            anchors.fill: parent
            anchors.margins: 4
            radius: 14
            color: Atelier.containerHigh
            opacity: rowMa.containsMouse ? 0.6 : 0
            Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
        }
        MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tr.toggled()
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 14
            spacing: 14
            Text {
                Layout.preferredWidth: 20
                horizontalAlignment: Text.AlignHCenter
                text: tr.icon
                font.family: Atelier.font
                font.pixelSize: 16
                color: tr.on ? Atelier.text : Atelier.subtext
                Behavior on color { ColorAnimation { duration: Atelier.durFast } }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: tr.label
                    font.family: Atelier.fontUi
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: Atelier.text
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: tr.sub
                    font.family: Atelier.fontUi
                    font.pixelSize: 11
                    color: Atelier.subtext
                    elide: Text.ElideRight
                }
            }
            Rectangle {   // the arrow is its own button: opens the full menu (networks, devices)
                visible: tr.hasDetails
                implicitWidth: 28
                implicitHeight: 28
                radius: 14
                color: detMa.containsMouse ? Atelier.containerHigh : "transparent"
                Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                Text {
                    anchors.centerIn: parent
                    text: "󰅂"
                    font.family: Atelier.font
                    font.pixelSize: 13
                    color: detMa.containsMouse ? Atelier.text : Atelier.subtext
                }
                MouseArea { id: detMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tr.details() }
            }
            PillSwitch { on: tr.on; onToggled: tr.toggled() }
        }
    }

    // slim 5px ink bar: glyph (click = mute) · bar · value
    component SlimSlider: Item {
        id: ss
        property real value: 0
        property string icon
        property bool dimmed: false
        signal moved(real v)
        signal iconClicked()
        implicitHeight: 36
        function set(v) { ss.moved(Math.max(0, Math.min(1, v))); }

        RowLayout {
            anchors.fill: parent
            spacing: 10
            RoundBtn {
                icon: ss.icon
                size: 32
                glyphSize: 15
                hoverTint: ss.dimmed ? Atelier.red : Atelier.text
                onClicked: ss.iconClicked()
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 5
                    radius: 2.5
                    color: Atelier.containerHigh
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, ss.value))
                        height: parent.height
                        radius: 2.5
                        color: ss.dimmed ? Atelier.subtext : Atelier.text
                        opacity: ss.dimmed ? 0.5 : 1
                        Behavior on width { enabled: !dragMa.pressed; NumberAnimation { duration: 140; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }
                    }
                    Rectangle {   // knob: only while hovering / dragging
                        x: Math.max(0, Math.min(parent.width - width, parent.width * ss.value - width / 2))
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13; height: 13; radius: 6.5
                        color: Atelier.text
                        opacity: dragMa.containsMouse || dragMa.pressed ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
                    }
                }
                MouseArea {
                    id: dragMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    onPressed: (m) => ss.set(m.x / width)
                    onPositionChanged: (m) => { if (pressed) ss.set(m.x / width); }
                    onWheel: (w) => ss.set(ss.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))
                }
            }
            Text {
                Layout.preferredWidth: 38
                horizontalAlignment: Text.AlignRight
                text: ss.dimmed ? "off" : Math.round(ss.value * 100) + "%"
                font.family: root.mono
                font.pixelSize: 12
                color: Atelier.subtext
            }
        }
    }
}
