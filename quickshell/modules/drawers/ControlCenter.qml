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
// 5px bars, transparent round controls, numbers in mono, one accent only for "on".
//
// The switches are ONE list (`toggles`, below) drawn in the layout the user picks
// (Settings.controlCenter.layout, or the layout button in the header):
//   list   grouped rows with pill switches (default)     icons  round buttons, labels on hover
//   tiles  wide Wi-Fi/Bluetooth tiles + a 4-across grid  cards  a connections card + a chip column
// Header (full / compact), shortcuts (which ones) and the notification count are settings too.
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
        Notifs.hideAllPopups();               // they're all in the list here
        SysState.refreshWifi();
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

    // ── AdGuard DNS (config/scripts/adguard-dns.sh → ~/.local/bin/adguard-dns) ──
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

    // ── The switches, once: every layout draws these ──────────────────────
    // id · group · icon · label · short (one word) · sub (status) · on · warn (on but broken) · details
    readonly property bool micMuted: !root.source || !root.source.audio || root.source.audio.muted
    readonly property var toggles: [
        { id: "wifi", group: "Connections", icon: SysState.wifiIcon, label: "Wi-Fi", short: "Wi-Fi",
          sub: !SysState.wifiEnabled ? "Off" : (SysState.ssid || "Not connected"), on: SysState.wifiEnabled, warn: false, details: "wifi" },
        { id: "bluetooth", group: "Connections", icon: root.adapter && root.adapter.enabled ? "󰂯" : "󰂲", label: "Bluetooth", short: "Bluetooth",
          sub: !(root.adapter && root.adapter.enabled) ? "Off" : root.btConnected.length === 1 ? root.btConnected[0].name
             : root.btConnected.length > 1 ? root.btConnected.length + " devices" : "On",
          on: !!(root.adapter && root.adapter.enabled), warn: false, details: "bluetooth" },
        { id: "adguard", group: "Connections", icon: root.adguard !== "off" ? "󰕥" : "󰒙", label: "AdGuard DNS", short: "AdGuard",
          sub: root.adguard === "family" ? "Blocking ads · family filter" : root.adguard === "on" ? "Blocking ads and trackers" : "Off",
          on: root.adguard !== "off", warn: false, details: "" },
        { id: "dnd", group: "Focus & display", icon: Notifs.dnd ? "󰂛" : "󰂚", label: "Do Not Disturb", short: "Focus",
          sub: Notifs.dnd ? "Notifications are silenced" : "Off", on: Notifs.dnd, warn: false, details: "" },
        { id: "night", group: "Focus & display", icon: NightLight.active ? "󰖔" : "󰖙", label: "Night light", short: "Night",
          sub: NightLight.status, on: NightLight.active, warn: false, details: "settings:displays" },
        { id: "awake", group: "Focus & display", icon: "󰅶", label: "Keep awake", short: "Awake",
          sub: Atelier.caffeine ? "The screen stays on" : "Off", on: Atelier.caffeine, warn: false, details: "" },
        { id: "record", group: "Focus & display", icon: "󰑋", label: "Screen recording", short: Recorder.recording ? Recorder.elapsedText : "Record",
          sub: Recorder.recording ? "Recording · " + Recorder.elapsedText + " · click to stop" : !Recorder.available ? "Install wf-recorder" : "Pick an area",
          on: Recorder.recording, warn: false, details: "", red: true },
        { id: "airdrop", group: "Phone", icon: "\u{F0003}", label: "AirDrop", short: "AirDrop",
          sub: AirDrop.summary, on: AirDrop.enabled, warn: AirDrop.enabled && AirDrop.radioState === "error", details: "" },
        { id: "phonecam", group: "Phone", icon: "󰄜", label: "iPhone camera", short: "Camera",
          sub: PhoneCam.summary, on: PhoneCam.running, warn: PhoneCam.state === "error", details: "camera" },
        { id: "mic", group: "Phone", icon: root.micMuted ? "󰍭" : "󰍬", label: "Microphone", short: "Mic",
          sub: root.micMuted ? "Muted" : "On", on: !root.micMuted, warn: false, details: "sound" }
    ]
    readonly property var groups: ["Connections", "Focus & display", "Phone"]
    // static ids per group, so the list's rows aren't rebuilt each time a status changes
    readonly property var groupIds: ({ "Connections": ["wifi", "bluetooth", "adguard"],
        "Focus & display": ["dnd", "night", "awake", "record"], "Phone": ["airdrop", "phonecam", "mic"] })
    readonly property var _none: ({ icon: "", label: "", short: "", sub: "", on: false, warn: false, details: "" })
    function t(id) { return toggles.find(x => x.id === id) || _none; }
    function act(id) {
        switch (id) {
        case "wifi": SysState.setWifi(!SysState.wifiEnabled); break;
        case "bluetooth": if (root.adapter) root.adapter.enabled = !root.adapter.enabled; break;
        case "adguard": root.setAdguard(root.adguard !== "off" ? "off" : "on"); break;
        case "dnd": Notifs.dnd = !Notifs.dnd; break;
        case "night": NightLight.toggle(); break;
        case "awake": Atelier.caffeine = !Atelier.caffeine; break;
        case "record": root.requestOverlay("record"); break;
        case "airdrop": AirDrop.toggle(); break;
        case "phonecam": PhoneCam.toggle(); break;
        case "mic": if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted; break;
        }
    }
    function details(id) {
        const d = t(id) ? t(id).details : "";
        if (d === "sound") root.requestOverlay("settings:sound");
        else if (d) root.requestOverlay(d);
    }
    readonly property string layoutName: ["list", "tiles", "icons", "cards"].indexOf(Settings.controlCenter.layout) >= 0
        ? Settings.controlCenter.layout : "list"
    function cycleLayout() {
        const all = ["list", "tiles", "icons", "cards"];
        Settings.controlCenter.layout = all[(all.indexOf(layoutName) + 1) % all.length];
    }
    property string hint: ""                 // the hovered switch's status (icons / tiles)
    // "On" for tiles, icon buttons and chips: a soft tonal wash of the accent (or red for
    // recording) with the glyph in that colour, not a solid saturated fill (too loud)
    function tone(red, hovered) { return Qt.alpha(red ? Atelier.red : Atelier.accent, (Atelier.isLight ? 0.15 : 0.22) + (hovered ? 0.06 : 0)); }
    function toneInk(red) { return red ? Atelier.red : Atelier.accent; }
    function toneEdge(red) { return Qt.alpha(red ? Atelier.red : Atelier.accent, 0.35); }

    // every shortcut the user can pick (Settings → Appearance → Control center)
    readonly property var allShortcuts: [
        { id: "screenshot", icon: "󰄀", label: "Screenshot" }, { id: "record",    icon: "󰑋", label: "Record" },
        { id: "wallpaper",  icon: "󰸉", label: "Wallpaper" },  { id: "theme",     icon: "󰏘", label: "Theme" },
        { id: "emoji",      icon: "󰞅", label: "Emoji" },      { id: "clipboard", icon: "󰅌", label: "Clipboard" },
        { id: "camera",     icon: "󰄀", label: "Camera" },     { id: "keyboard",  icon: "󰌌", label: "Keyboard" },
        { id: "keybinds",   icon: "󰧺", label: "Shortcuts" },  { id: "settings",  icon: "󰒓", label: "Settings" }
    ]
    readonly property var shortcuts: (Settings.controlCenter.shortcuts || []).map(id => allShortcuts.find(x => x.id === id)).filter(x => x).slice(0, 5).concat(Plugins.controlTiles)
    onVisibleChanged: IPhone.watch(visible)

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
        bodyHeight: Math.min(root.height - Atelier.insetTop - Atelier.insetBottom - 2 * Atelier.fillet - 24, 22 + head.implicitHeight + 8 + content.implicitHeight + 34)
        Behavior on bodyHeight { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }

        // The header (greeting, clock, date, buttons) stays put; everything below it scrolls
        // when the panel is taller than the screen (the clock used to scroll away with it).
        ColumnLayout {
            id: head
            x: 22
            y: 22
            width: parent.width - 44
            spacing: 0

            // ── Header ──────────────────────────────────────────────────────
            // full: greeting + buttons · big clock beside date and a slim battery bar
            // compact: one line, time · date · battery · buttons
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                readonly property bool compact: Settings.controlCenter.header === "compact"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        visible: !parent.parent.compact
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.greeting + (Atelier.userName ? ", " + Atelier.userName : "")
                        font.family: Atelier.fontUi
                        font.pixelSize: Atelier.fsLg
                        font.weight: Font.Medium
                        color: Atelier.mauve
                        elide: Text.ElideRight
                    }
                    // compact: everything on this one line
                    Row {
                        visible: parent.parent.compact
                        Layout.fillWidth: true
                        spacing: 8
                        Text { anchors.baseline: dateC.baseline; text: Atelier.hour12(root.now) + ":" + Qt.formatTime(root.now, "mm")
                            font.family: Atelier.font; font.pixelSize: 22; font.weight: Font.Bold; color: Atelier.text }
                        Text { anchors.baseline: dateC.baseline; visible: !Atelier.clock24; text: Atelier.ampm(root.now)
                            font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: Atelier.blue }
                        Text { id: dateC; anchors.verticalCenter: parent.verticalCenter; text: Qt.formatDate(root.now, "ddd d MMM")
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext }
                        Text { anchors.baseline: dateC.baseline; visible: root.hasBattery
                            text: (root.charging ? "󰂄 " : "") + Math.round(root.batPct * 100) + "%"
                            font.family: root.mono; font.pixelSize: Atelier.fsSm
                            color: root.batPct <= 0.15 && !root.charging ? Atelier.red : Atelier.subtext }
                    }
                    RoundBtn { icon: "󰕰"; size: 30; glyphSize: 14; tip: "Layout: " + root.layoutName; onClicked: root.cycleLayout() }
                    RoundBtn { icon: "󰒓"; size: 30; glyphSize: 14; tip: "Settings"; onClicked: root.requestOverlay("settings") }
                    RoundBtn { icon: "󰐥"; size: 30; glyphSize: 14; tip: "Power"; hoverTint: Atelier.red; onClicked: root.requestOverlay("power") }
                }

                // full: big clock | date + battery
                RowLayout {
                    visible: !parent.compact
                    Layout.fillWidth: true
                    spacing: 14
                    Row {
                        Layout.alignment: Qt.AlignVCenter
                        Text { text: Atelier.hour12(root.now); font.family: Atelier.font; font.pixelSize: 46; font.weight: Font.Bold; color: Atelier.text }
                        Text {   // the colon breathes once a second, in the accent colour
                            text: ":"
                            font.family: Atelier.font; font.pixelSize: 46; font.weight: Font.Bold
                            color: Atelier.accent
                            opacity: root.now.getSeconds() % 2 ? 0.45 : 1
                            Behavior on opacity { NumberAnimation { duration: 400 } }
                        }
                        Text { text: Qt.formatTime(root.now, "mm"); font.family: Atelier.font; font.pixelSize: 46; font.weight: Font.Bold; color: Atelier.text }
                        Text {
                            visible: !Atelier.clock24
                            anchors.top: parent.top; anchors.topMargin: 10
                            leftPadding: 6
                            text: Atelier.ampm(root.now)
                            font.family: Atelier.font; font.pixelSize: Atelier.fsMd; font.weight: Font.Bold
                            color: Atelier.blue
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 3
                        Text { Layout.fillWidth: true; text: Qt.formatDate(root.now, "dddd"); elide: Text.ElideRight
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.Medium; color: Atelier.text }
                        Text { Layout.fillWidth: true; text: Qt.formatDate(root.now, "d MMMM yyyy"); elide: Text.ElideRight
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext }
                        // battery: a slim bar + number
                        RowLayout {
                            id: battRow
                            visible: root.hasBattery
                            Layout.fillWidth: true
                            Layout.topMargin: 3
                            spacing: 6
                            readonly property color hue: root.batPct <= 0.15 && !root.charging ? Atelier.red
                                : root.charging ? Atelier.green : root.batPct <= 0.3 ? Atelier.yellow : Atelier.green
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 5; radius: 2.5
                                color: Atelier.containerHigh
                                Rectangle {
                                    width: parent.width * Math.max(0.04, root.batPct); height: parent.height; radius: 2.5
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: Qt.alpha(battRow.hue, 0.55) }
                                        GradientStop { position: 1; color: battRow.hue }
                                    }
                                }
                            }
                            Text { text: (root.charging ? "󰂄  " : "") + Math.round(root.batPct * 100) + "%"
                                font.family: root.mono; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                        }
                    }
                }
            }
        }
        // a hairline under the header once the list has scrolled under it
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 22; anchors.rightMargin: 22
            y: scroller.y - 1
            height: 1
            color: Atelier.outline
            opacity: scroller.contentY > 2 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
        }

        Flickable {
            id: scroller
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.top: head.bottom
            anchors.topMargin: 8
            contentWidth: width
            contentHeight: content.implicitHeight + 34
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            SmoothWheel { flickable: scroller }

        ColumnLayout {
            id: content
            x: 22
            y: 12
            width: scroller.width - 44
            spacing: 20

            // ── Weather: now, feels like, humidity, wind, and the next two days (click refreshes) ──
            Rectangle {
                id: wxCard
                visible: Weather.ok
                Layout.fillWidth: true
                implicitHeight: wxCol.implicitHeight + 24
                radius: Atelier.radiusMd
                color: wxMa.containsMouse ? Atelier.containerHigh : Atelier.container
                border.width: 1
                border.color: Atelier.outline
                Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                readonly property var w: Weather.w
                MouseArea { id: wxMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Weather.refresh() }
                ColumnLayout {
                    id: wxCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Text { text: Weather.glyph(wxCard.w.code || 0); font.family: Atelier.font; font.pixelSize: 34; color: Atelier.sapphire }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Row {
                                spacing: 2
                                Text { text: wxCard.w.temp || ""; font.family: Atelier.font; font.pixelSize: 26; font.weight: Font.Bold; color: Atelier.text }
                                Text { text: wxCard.w.unit || ""; topPadding: 5; font.family: Atelier.font; font.pixelSize: Atelier.fsMd; color: Atelier.subtext }
                            }
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: (wxCard.w.desc || "") + (wxCard.w.place ? "  ·  " + wxCard.w.place : "")
                                   font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext }
                        }
                        ColumnLayout {
                            spacing: 2
                            Text { Layout.alignment: Qt.AlignRight; text: "Feels " + (wxCard.w.feels || "") + "°"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext1 }
                            Text { Layout.alignment: Qt.AlignRight; text: "󰖎 " + (wxCard.w.humidity || "") + "%"; font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: Atelier.sapphire }
                            Text { Layout.alignment: Qt.AlignRight; text: "󰖝 " + (wxCard.w.wind || "") + " " + (wxCard.w.windUnit || ""); font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: Atelier.teal }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Repeater {
                            model: (wxCard.w.days || []).slice(0, 3)
                            Rectangle {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                implicitHeight: 46
                                radius: Atelier.radiusMd
                                color: Atelier.containerHigh
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: Weather.glyph(modelData.code); font.family: Atelier.font; font.pixelSize: 18; color: Atelier.sapphire }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text { text: index === 0 ? "Today" : Qt.formatDate(new Date(modelData.date + "T12:00:00"), "ddd"); font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMicro; color: Atelier.subtext }
                                        Text { text: modelData.max + "° / " + modelData.min + "°"; font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: Atelier.text }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── iPhone (Tether): name, status, battery; click opens Tether ──────────
            Rectangle {
                visible: IPhone.paired
                Layout.fillWidth: true
                implicitHeight: 54
                radius: Atelier.radiusMd
                color: phMa.containsMouse ? Atelier.containerHigh : Atelier.container
                border.width: 1
                border.color: Atelier.outline
                Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                readonly property real pct: IPhone.battery
                readonly property color hue: pct < 0 ? Atelier.subtext : pct <= 0.2 ? Atelier.red : pct <= 0.4 ? Atelier.yellow : Atelier.green
                MouseArea { id: phMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { IPhone.openApp(); root.close(); } }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 14
                    spacing: 10
                    Rectangle {
                        implicitWidth: 34; implicitHeight: 34; radius: Atelier.radiusLg
                        color: IPhone.connected ? Qt.alpha(Atelier.accent, 0.14) : Atelier.containerHigh
                        Text { anchors.centerIn: parent; text: "󰄜"; font.family: Atelier.font; font.pixelSize: 16
                            color: IPhone.connected ? Atelier.accent : Atelier.subtext }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1
                        Text { Layout.fillWidth: true; text: IPhone.name; elide: Text.ElideRight
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.Medium; color: Atelier.text }
                        Text { Layout.fillWidth: true; text: IPhone.status; elide: Text.ElideRight
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                    }
                    // battery: slim bar + number (only while it's known)
                    ColumnLayout {
                        visible: parent.parent.pct >= 0
                        spacing: 4
                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: Math.round(parent.parent.parent.pct * 100) + "%"
                            font.family: root.mono; font.pixelSize: Atelier.fsMd; font.bold: true
                            color: parent.parent.parent.pct <= 0.2 ? Atelier.red : Atelier.text
                        }
                        Rectangle {
                            implicitWidth: 44; implicitHeight: 5; radius: 2.5
                            color: Atelier.containerHigh
                            Rectangle {
                                width: parent.width * Math.max(0.05, parent.parent.parent.parent.pct); height: parent.height; radius: 2.5
                                color: parent.parent.parent.parent.hue
                            }
                        }
                    }
                }
            }

            // ── Updates: shown while there are any; Update opens them in the terminal ──
            Rectangle {
                visible: Settings.updates.check && Updates.count > 0
                Layout.fillWidth: true
                implicitHeight: 54
                radius: Atelier.radiusMd
                color: upMa.containsMouse ? Atelier.containerHigh : Atelier.container
                border.width: 1
                border.color: Atelier.outline
                Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                MouseArea { id: upMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { Updates.run(); root.close(); } }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10
                    Rectangle {
                        implicitWidth: 34; implicitHeight: 34; radius: Atelier.radiusLg
                        color: Qt.alpha(Atelier.teal, 0.14)
                        Text { anchors.centerIn: parent; text: "󰚰"; font.family: Atelier.font; font.pixelSize: 16; color: Atelier.teal }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1
                        Text { Layout.fillWidth: true; elide: Text.ElideRight
                            text: Updates.count + (Updates.count === 1 ? " update" : " updates") + " available"
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.Medium; color: Atelier.text }
                        Text { Layout.fillWidth: true; elide: Text.ElideRight
                            text: (Updates.aur.length > 0 ? Updates.repo.length + " system · " + Updates.aur.length + " AUR" : "System packages")
                                  + (Updates.checkedAt > 0 ? " · " + Notifs.ago(Updates.checkedAt) : "")
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                    }
                    Rectangle {
                        implicitWidth: upTxt.implicitWidth + 20; implicitHeight: 28; radius: Atelier.radiusMd
                        color: root.tone(false, upMa.containsMouse)
                        border.width: 1; border.color: root.toneEdge(false)
                        Text { id: upTxt; anchors.centerIn: parent; text: "Update"
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; color: Atelier.accent }
                    }
                }
            }

            // ── Plugged-in drives: open in the file manager, eject ──────────────
            Repeater {
                model: Drives.drives
                Rectangle {
                    id: drv
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 54
                    radius: Atelier.radiusMd
                    color: drvMa.containsMouse ? Atelier.containerHigh : Atelier.container
                    border.width: 1
                    border.color: Atelier.outline
                    Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                    MouseArea { id: drvMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { Drives.open(drv.modelData); root.close(); } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10
                        Rectangle {
                            implicitWidth: 34; implicitHeight: 34; radius: Atelier.radiusLg
                            color: Qt.alpha(Atelier.sapphire, 0.14)
                            Text { anchors.centerIn: parent; text: "󱊞"; font.family: Atelier.font; font.pixelSize: 16; color: Atelier.sapphire }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 1
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: drv.modelData.label
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.Medium; color: Atelier.text }
                            Text { Layout.fillWidth: true; elide: Text.ElideRight
                                text: drv.modelData.size + " · " + (drv.modelData.mount ? drv.modelData.mount : "Not opened yet")
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                        }
                        // eject
                        Rectangle {
                            implicitWidth: 30; implicitHeight: 30; radius: Atelier.radiusLg
                            color: ejMa.containsMouse ? Qt.alpha(Atelier.sapphire, 0.18) : "transparent"
                            Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                            Text { anchors.centerIn: parent; text: "󰇪"; font.family: Atelier.font; font.pixelSize: Atelier.fsXl
                                color: ejMa.containsMouse ? Atelier.sapphire : Atelier.subtext }
                            MouseArea { id: ejMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: Drives.eject(drv.modelData) }
                        }
                    }
                }
            }

            // ── Switches, in the chosen layout ────────────────────────────────
            Loader {
                Layout.fillWidth: true
                sourceComponent: root.layoutName === "tiles" ? tilesLayout
                               : root.layoutName === "icons" ? iconsLayout
                               : root.layoutName === "cards" ? cardsLayout : listLayout
            }
            // status of the hovered switch (tiles / icons: their labels are one word)
            Text {
                visible: root.layoutName === "tiles" || root.layoutName === "icons"
                Layout.fillWidth: true
                Layout.topMargin: -12
                Layout.leftMargin: 4
                text: root.hint
                opacity: root.hint !== "" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
                elide: Text.ElideRight
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
            }

            // ── Mode: a segmented control with a sliding highlight ──────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    SectionLabel { text: "Mode" }
                    Text {
                        Layout.fillWidth: true
                        text: "· " + Perf.infoOf(Perf.mode).blurb.toLowerCase()
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
                        elide: Text.ElideRight
                    }
                    Text {
                        text: "Customise"
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; font.weight: Font.Medium
                        color: cuMa.containsMouse ? Atelier.text : Atelier.subtext
                        MouseArea { id: cuMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.requestOverlay("settings:modes") }
                    }
                }
                // one tile per mode: glyph over a short name, the active one tinted in its own colour
                Row {
                    id: seg
                    Layout.fillWidth: true
                    spacing: 6
                    readonly property real cell: (width - spacing * (Perf.info.length - 1)) / Perf.info.length
                    Repeater {
                        model: Perf.info
                        Rectangle {
                            id: tile
                            required property var modelData
                            readonly property bool on: Perf.mode === modelData.id
                            width: seg.cell; height: 60
                            radius: Atelier.radiusMd
                            color: on ? Qt.alpha(modelData.tint, Atelier.isLight ? 0.18 : 0.24) : (tileMa.containsMouse ? Atelier.containerHigh : Atelier.container)
                            border.width: 1
                            border.color: on ? Qt.alpha(modelData.tint, 0.6) : Atelier.outline
                            scale: tileMa.pressed ? 0.95 : 1
                            Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                            Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
                            Column {
                                anchors.centerIn: parent
                                spacing: 3
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.icon
                                    font.family: Atelier.font; font.pixelSize: 20
                                    color: tile.on ? tile.modelData.tint : Atelier.subtext
                                    Behavior on color { ColorAnimation { duration: Atelier.durFast } } }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.short
                                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                                    font.weight: tile.on ? Font.DemiBold : Font.Medium
                                    color: tile.on ? Atelier.text : Atelier.subtext }
                            }
                            MouseArea { id: tileMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: Perf.set(tile.modelData.id) }
                        }
                    }
                }
            }

            // ── Shortcuts: the ones picked in Settings (up to five) ───────────────
            Row {
                id: shortcutRow
                visible: root.shortcuts.length > 0
                Layout.fillWidth: true
                Repeater {
                    model: root.shortcuts
                    Item {
                        required property var modelData
                        width: shortcutRow.width / Math.max(4, root.shortcuts.length)
                        height: 62
                        Rectangle {
                            id: scBtn
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 42; height: 42; radius: Atelier.radiusMd
                            color: scMa.containsMouse ? Atelier.containerHigh : Atelier.container
                            scale: scMa.pressed ? 0.92 : 1
                            Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
                            Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon
                                font.family: Atelier.font
                                font.pixelSize: 17
                                color: scMa.containsMouse ? Atelier.text : Atelier.subtext
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: scBtn.bottom; anchors.topMargin: 5
                            text: modelData.label
                            font.family: Atelier.fontUi
                            font.pixelSize: Atelier.fsMicro
                            color: Atelier.subtext
                        }
                        MouseArea { id: scMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: modelData.cmd ? (Quickshell.execDetached(["sh", "-c", modelData.cmd]), root.close()) : root.requestOverlay(modelData.id) }
                    }
                }
            }

            // ── Notifications: just a summary row; the list is its own drawer (left edge) ──
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8
                SectionLabel { text: "Notifications" }
                Rectangle {
                    visible: Notifs.count > 0
                    implicitWidth: ncText.implicitWidth + 12; implicitHeight: 18; radius: 9
                    color: Qt.alpha(Atelier.accent, 0.14)
                    Text { id: ncText; anchors.centerIn: parent; text: Notifs.count; font.family: root.mono; font.pixelSize: Atelier.fsMicro; color: Atelier.accent }
                }
                Text {
                    Layout.fillWidth: true
                    text: Notifs.dnd ? "Do Not Disturb" : (Notifs.count === 0 ? "All caught up" : "")
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
                    elide: Text.ElideRight
                }
                RoundBtn { icon: Notifs.dnd ? "󰂛" : "󰂚"; size: 26; glyphSize: 13; tip: Notifs.dnd ? "Do Not Disturb is on" : "Do Not Disturb"
                    active: Notifs.dnd; onClicked: Notifs.dnd = !Notifs.dnd }
                Text {
                    text: "Open"
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.Medium
                    color: openNMa.containsMouse ? Atelier.text : Atelier.subtext
                    MouseArea { id: openNMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.requestOverlay("notifications") }
                }
            }
        }
        }
    }

    // ── Pieces ──────────────────────────────────────────────────────────────
    readonly property string mono: Atelier.font

    // tiny uppercase section label (the site's .lbl)
    component SectionLabel: Text {
        font.family: Atelier.fontUi
        font.pixelSize: Atelier.fsMicro
        font.weight: Font.DemiBold
        font.letterSpacing: 1.3
        font.capitalization: Font.AllUppercase
        color: Atelier.subtext
    }

    component RoundBtn: Rectangle {
        id: rb
        property string icon
        property int size: 34
        property int glyphSize: 15
        property color hoverTint: Atelier.text
        property string tip: ""
        property bool active: false          // lit (e.g. Do Not Disturb on)
        signal clicked()
        implicitWidth: size
        implicitHeight: size
        radius: size / 2
        opacity: enabled ? 1 : 0.35
        color: active ? Qt.alpha(Atelier.accent, 0.16) : rbMa.containsMouse ? Atelier.containerHigh : "transparent"
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Text {
            anchors.centerIn: parent
            text: rb.icon
            font.family: Atelier.font
            font.pixelSize: rb.glyphSize
            color: rb.active ? Atelier.accent : rbMa.containsMouse ? rb.hoverTint : Atelier.subtext
        }
        Tip { text: rb.tip; shown: rbMa.containsMouse }
        MouseArea { id: rbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (rb.enabled) rb.clicked() }
    }

    // a small tooltip under its parent, after a short hover
    component Tip: Rectangle {
        id: tip
        property string text
        property bool shown: false
        visible: text !== "" && tipDelay.done
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom; anchors.topMargin: 6
        z: 100
        width: tipText.implicitWidth + 14; height: 22; radius: Atelier.radiusSm
        color: Atelier.containerHigh
        border.width: 1; border.color: Atelier.outline
        Text { id: tipText; anchors.centerIn: parent; text: tip.text; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.text }
        Timer { id: tipDelay; property bool done: false; interval: 550; running: tip.shown && !done; onTriggered: done = true }
        onShownChanged: if (!shown) tipDelay.done = false
    }

    // pill switch (the site's .tg)
    component PillSwitch: Rectangle {
        id: ps
        property bool on: false
        property bool warn: false
        signal toggled()
        implicitWidth: 36
        implicitHeight: 20
        radius: Atelier.radiusSm
        color: on ? (warn ? Atelier.fill(Atelier.peach) : Atelier.accentFill) : Atelier.containerHigh
        border.width: on ? 0 : 1
        border.color: Atelier.outline
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Rectangle {
            width: 14; height: 14; radius: 7
            y: 3
            x: ps.on ? parent.width - width - 3 : 3
            color: ps.on ? Atelier.onFill : Atelier.subtext
            Behavior on x { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ps.toggled() }
    }

    // ═══ Layout: TILES — wide Wi-Fi/Bluetooth tiles + a 4-across grid of the rest ═══
    Component {
        id: tilesLayout
        ColumnLayout {
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                WideTile { tid: "wifi" }
                WideTile { tid: "bluetooth" }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 4
                rowSpacing: 8
                columnSpacing: 8
                Repeater {
                    model: ["adguard", "dnd", "night", "awake", "record", "airdrop", "phonecam", "mic"]
                    QuickTile { required property var modelData; tid: modelData }
                }
            }
        }
    }

    component WideTile: Rectangle {
        id: wt
        property string tid
        readonly property var d: root.t(tid)
        readonly property bool on: d.on
        Layout.fillWidth: true
        Layout.preferredWidth: 1          // equal halves
        implicitHeight: 60
        radius: Atelier.radiusLg
        color: on ? root.tone(false, wtMa.containsMouse) : (wtMa.containsMouse ? Atelier.containerHigh : Atelier.container)
        border.width: 1
        border.color: on ? root.toneEdge(false) : Atelier.outline
        scale: wtMa.pressed ? 0.97 : 1
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Behavior on scale { NumberAnimation { duration: Atelier.durFast } }

        MouseArea { id: wtMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.act(wt.tid) }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 6
            spacing: 10
            Rectangle {
                implicitWidth: 32; implicitHeight: 32; radius: Atelier.radiusLg
                color: wt.on ? root.tone(false, true) : Atelier.containerHigh
                Text { anchors.centerIn: parent; text: wt.d.icon; font.family: Atelier.font; font.pixelSize: Atelier.fsXl
                    color: wt.on ? Atelier.accent : Atelier.text }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0
                Text { Layout.fillWidth: true; text: wt.d.label; elide: Text.ElideRight
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold
                    color: Atelier.text }
                Text { Layout.fillWidth: true; text: wt.d.sub; elide: Text.ElideRight
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                    color: Atelier.subtext }
            }
            Rectangle {
                implicitWidth: 26; implicitHeight: 26; radius: 13
                color: detMa.containsMouse ? Atelier.containerHigh : "transparent"
                Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                Text { anchors.centerIn: parent; text: "󰅂"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg
                    color: wt.on ? Atelier.accent : Atelier.subtext }
                MouseArea { id: detMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.details(wt.tid) }
            }
        }
    }

    // a square toggle: icon + one word, filled when on. Right-click = details. Hover = status line.
    component QuickTile: Rectangle {
        id: qt
        property string tid
        readonly property var d: root.t(tid)
        readonly property bool on: d.on
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 68
        radius: Atelier.radiusMd
        color: on ? root.tone(d.red, qtMa.containsMouse) : (qtMa.containsMouse ? Atelier.containerHigh : Atelier.container)
        border.width: d.warn ? 1.5 : 1
        border.color: d.warn ? Atelier.peach : on ? root.toneEdge(d.red) : Atelier.outline
        scale: qtMa.pressed ? 0.94 : 1
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
        Column {
            anchors.centerIn: parent
            width: parent.width - 8
            spacing: 5
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qt.d.icon; font.family: Atelier.font; font.pixelSize: 18
                color: qt.on ? root.toneInk(qt.d.red) : (qt.d.warn ? Atelier.peach : Atelier.text) }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qt.d.short; elide: Text.ElideRight
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; font.weight: Font.Medium
                color: qt.on ? Atelier.text : Atelier.subtext }
        }
        WarnDot { visible: qt.d.warn }
        MouseArea {
            id: qtMa
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (m) => { if (m.button === Qt.RightButton) root.details(qt.tid); else root.act(qt.tid); }
            onContainsMouseChanged: root.hint = containsMouse ? qt.d.label + " · " + qt.d.sub : (root.hint.startsWith(qt.d.label + " ·") ? "" : root.hint)
        }
    }

    component WarnDot: Rectangle {
        width: 7; height: 7; radius: 4
        color: Atelier.peach
        anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 7
    }

    // ═══ Layout: LIST — grouped rows with pill switches (the quiet default) ═══
    Component {
        id: listLayout
        ColumnLayout {
            spacing: 14
            Repeater {
                model: root.groups
                ColumnLayout {
                    required property var modelData
                    readonly property string grp: modelData
                    Layout.fillWidth: true
                    spacing: 6
                    SectionLabel { Layout.leftMargin: 4; text: parent.grp }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: rows.implicitHeight + 6
                        radius: Atelier.radiusMd
                        color: Atelier.container
                        border.width: 1; border.color: Atelier.outline
                        Column {
                            id: rows
                            x: 0; y: 3
                            width: parent.width
                            Repeater {
                                model: root.groupIds[parent.parent.parent.grp] || []
                                ListRow { required property var modelData; required property int index; tid: modelData; first: index === 0; width: rows.width }
                            }
                        }
                    }
                }
            }
        }
    }

    component ListRow: Item {
        id: lr
        property string tid
        property bool first: false
        readonly property var d: root.t(tid)
        implicitHeight: 42
        // the status only where it says something (a name, a problem), not "On"/"Off"
        readonly property string status: d.warn ? d.sub
            : (tid === "wifi" || tid === "bluetooth") && d.on && d.sub !== "On" ? d.sub
            : tid === "record" && d.on ? d.sub : ""
        Rectangle {   // hairline between rows
            visible: !lr.first
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 44; anchors.rightMargin: 12
            height: 1; color: Atelier.outline
        }
        Rectangle {   // hover wash
            anchors.fill: parent; anchors.margins: 3
            radius: Atelier.radiusMd
            color: Atelier.containerHigh
            opacity: lrMa.containsMouse ? 0.6 : 0
            Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
        }
        MouseArea { id: lrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.act(lr.tid) }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 12
            Text {
                Layout.preferredWidth: 18
                horizontalAlignment: Text.AlignHCenter
                text: lr.d.icon
                font.family: Atelier.font; font.pixelSize: Atelier.fsXl
                color: lr.d.warn ? Atelier.peach : lr.d.on ? (lr.d.red ? Atelier.red : Atelier.text) : Atelier.subtext
                Behavior on color { ColorAnimation { duration: Atelier.durFast } }
            }
            Text {
                text: lr.d.label
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.Medium
                color: Atelier.text
            }
            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                horizontalAlignment: Text.AlignRight
                text: lr.status
                elide: Text.ElideRight
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                color: lr.d.warn ? Atelier.peach : Atelier.subtext
            }
            Text {    // a chevron where there's more (Wi-Fi networks, Bluetooth devices, night light…)
                visible: lr.d.details !== ""
                text: "󰅂"
                font.family: Atelier.font; font.pixelSize: Atelier.fsMd
                color: chMa.containsMouse ? Atelier.text : Atelier.subtext
                MouseArea { id: chMa; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.details(lr.tid) }
            }
            PillSwitch { on: lr.d.on; warn: lr.d.warn; onToggled: root.act(lr.tid) }
        }
    }

    // ═══ Layout: ICONS — slim Wi-Fi/Bluetooth chips + round buttons, labels on hover ═══
    Component {
        id: iconsLayout
        ColumnLayout {
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: ["wifi", "bluetooth"]
                    Rectangle {
                        required property var modelData
                        readonly property var d: root.t(modelData)
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 40
                        radius: 20
                        color: chipMa.containsMouse ? Atelier.containerHigh : Atelier.container
                        border.width: 1; border.color: d.on ? Qt.alpha(Atelier.accent, 0.45) : Atelier.outline
                        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (m) => { if (m.button === Qt.RightButton) root.act(parent.modelData); else root.details(parent.modelData); } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6; anchors.rightMargin: 12
                            spacing: 8
                            Rectangle {     // the round part toggles; the rest opens the menu
                                implicitWidth: 28; implicitHeight: 28; radius: Atelier.radiusMd
                                color: parent.parent.d.on ? root.tone(false, true) : Atelier.containerHigh
                                Text { anchors.centerIn: parent; text: parent.parent.parent.d.icon; font.family: Atelier.font; font.pixelSize: Atelier.fsLg
                                    color: parent.parent.parent.d.on ? Atelier.accent : Atelier.subtext }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.act(parent.parent.parent.modelData) }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: parent.parent.d.on && parent.parent.d.sub !== "On" ? parent.parent.d.sub : parent.parent.d.label
                                elide: Text.ElideRight
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.Medium
                                color: parent.parent.d.on ? Atelier.text : Atelier.subtext
                            }
                        }
                    }
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: (width - 8 * 40) / 7
                Repeater {
                    model: ["adguard", "dnd", "night", "awake", "record", "airdrop", "phonecam", "mic"]
                    Rectangle {
                        required property var modelData
                        readonly property var d: root.t(modelData)
                        width: 40; height: 40; radius: 20
                        color: d.on ? root.tone(d.red, icMa.containsMouse) : (icMa.containsMouse ? Atelier.containerHigh : Atelier.container)
                        border.width: d.warn ? 1.5 : 1
                        border.color: d.warn ? Atelier.peach : d.on ? root.toneEdge(d.red) : Atelier.outline
                        scale: icMa.pressed ? 0.9 : (icMa.containsMouse ? 1.06 : 1)
                        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                        Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutBack } }
                        Text { anchors.centerIn: parent; text: parent.d.icon; font.family: Atelier.font; font.pixelSize: 16
                            color: parent.d.on ? root.toneInk(parent.d.red) : parent.d.warn ? Atelier.peach : Atelier.subtext }
                        MouseArea {
                            id: icMa
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (m) => { if (m.button === Qt.RightButton) root.details(parent.modelData); else root.act(parent.modelData); }
                            onContainsMouseChanged: {
                                const l = parent.d.label + " · " + parent.d.sub;
                                root.hint = containsMouse ? l : (root.hint === l ? "" : root.hint);
                            }
                        }
                    }
                }
            }
        }
    }

    // ═══ Layout: CARDS — a connections card on the left, a column of chips on the right ═══
    Component {
        id: cardsLayout
        RowLayout {
            spacing: 8
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                Layout.fillHeight: true
                implicitHeight: connCol.implicitHeight + 16
                radius: Atelier.radiusLg
                color: Atelier.container
                border.width: 1; border.color: Atelier.outline
                Column {
                    id: connCol
                    x: 8; y: 8
                    width: parent.width - 16
                    spacing: 2
                    Repeater {
                        model: ["wifi", "bluetooth", "adguard", "airdrop"]
                        Rectangle {
                            required property var modelData
                            readonly property var d: root.t(modelData)
                            width: connCol.width
                            height: 52
                            radius: Atelier.radiusMd
                            color: ccMa.containsMouse ? Atelier.containerHigh : "transparent"
                            Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                            MouseArea { id: ccMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: (m) => { if (m.button === Qt.RightButton || parent.d.details === "") root.act(parent.modelData); else root.details(parent.modelData); } }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6; anchors.rightMargin: 6
                                spacing: 10
                                Rectangle {   // the round icon toggles
                                    implicitWidth: 32; implicitHeight: 32; radius: Atelier.radiusLg
                                    color: parent.parent.d.on ? (parent.parent.d.warn ? Qt.alpha(Atelier.peach, 0.25) : root.tone(false, true)) : Atelier.containerHigh
                                    Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                                    Text { anchors.centerIn: parent; text: parent.parent.parent.d.icon; font.family: Atelier.font; font.pixelSize: 14
                                        color: parent.parent.parent.d.on ? (parent.parent.parent.d.warn ? Atelier.peach : Atelier.accent) : Atelier.subtext }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.act(parent.parent.parent.modelData) }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 0
                                    Text { Layout.fillWidth: true; text: parent.parent.parent.d.label; elide: Text.ElideRight
                                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; color: Atelier.text }
                                    Text { Layout.fillWidth: true; text: parent.parent.parent.d.sub; elide: Text.ElideRight
                                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                                        color: parent.parent.parent.d.warn ? Atelier.peach : Atelier.subtext }
                                }
                            }
                        }
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 2
                spacing: 6
                Repeater {
                    model: ["dnd", "night", "awake", "record", "phonecam", "mic"]
                    Rectangle {
                        required property var modelData
                        readonly property var d: root.t(modelData)
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: Atelier.radiusMd
                        color: d.on ? root.tone(d.red, chMa2.containsMouse) : (chMa2.containsMouse ? Atelier.containerHigh : Atelier.container)
                        border.width: d.warn ? 1.5 : 1
                        border.color: d.warn ? Atelier.peach : d.on ? root.toneEdge(d.red) : Atelier.outline
                        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                        scale: chMa2.pressed ? 0.96 : 1
                        Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 12
                            spacing: 8
                            Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.d.icon; font.family: Atelier.font; font.pixelSize: Atelier.fsLg
                                color: parent.parent.d.on ? root.toneInk(parent.parent.d.red) : parent.parent.d.warn ? Atelier.peach : Atelier.subtext }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.d.short; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.Medium
                                color: Atelier.text }
                        }
                        MouseArea { id: chMa2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (m) => { if (m.button === Qt.RightButton) root.details(parent.modelData); else root.act(parent.modelData); } }
                    }
                }
            }
        }
    }
}
