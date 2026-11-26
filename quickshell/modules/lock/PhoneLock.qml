import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.config
import qs.services

// Phone-inspired lock screens (Settings → Lock screen → Atelier styles):
//   cupertino  iOS: date over a huge clock, glass widgets, notification stack, corner buttons
//   hyper      Xiaomi HyperOS: a giant thin stacked clock on the left
//   harmony    Huawei HarmonyOS: centred light clock and date, quiet and airy
//   oxygen     OnePlus OxygenOS: red hour, letter-spaced date, a pulsing lock ring
//   material   Pixel / Material You: chunky two-tone stacked clock, "at a glance" line
//   dot        Nothing OS: dot-matrix clock on a monochrome screen, one red accent
//   poster     the time as a huge flat-colour poster (full screen, PosterFace.qml)
//   flip       flip-card clock on a dark backdrop (FlipFace.qml)
//   split      a slanted info panel beside your clear wallpaper (SplitFace.qml)
//   hud        a thin-lined dashboard grid (HudFace.qml)
//   terminal   a full-screen terminal with a block-letter clock (TerminalFace.qml)
//   analog     a designer's wall clock (AnalogFace.qml)
//   aurora     a night sky with drifting aurora ribbons (AuroraFace.qml)
// Echoes of their layout and type, not copies: no logos or brand fonts, your wallpaper.
// Made for a laptop: a keyboard login (avatar, name, password field, Caps Lock warning)
// instead of a phone passcode pad, Wi-Fi and battery top right, and on a wide screen the
// notifications sit in a column on the right instead of under the clock.
//
// Same contract as LockContent.qml: PAM lives in LockScreen.qml (lockRoot); this file only
// shows state, fills lockRoot.buffer and calls submit(). Every size scales with the height
// (u), so Settings can show a live miniature (thumb: true with a stub lockRoot, no input).
Item {
    id: p

    required property var lockRoot
    property string variant: "cupertino"
    property var screen: null
    property bool isPreview: false
    property bool thumb: false

    // one unit = a thousandth of the height, times the Size setting (Settings → the style's options)
    readonly property real u: height / 1000 * Math.max(0.5, Math.min(1.1, Settings.lockStyle.size || 0.72))
    readonly property bool auth: !thumb && lockRoot.authMode
    readonly property bool leaving: !thumb && lockRoot.unlocking
    readonly property string display: "Inter Display"
    readonly property real ts: u * 1.3          // multiply the shell's type tokens (Atelier.fsMd …) by this
    // styles that draw the whole screen themselves (own backdrop, no shared dark overlay or status icons)
    // phone styles whose password screen is PhoneAuth.qml (Cupertino keeps the shared one below)
    readonly property bool ownAuth: ["hyper", "harmony", "oxygen", "material", "dot"].indexOf(variant) >= 0
    readonly property var pluginEntry: (Plugins.lockStyles.find(x => x.id === variant) || {}).entry || null
    readonly property string pluginFile: Plugins.lockFile(variant)      // a user plugin's Face.qml (docs/plugins.md)
    readonly property bool owns: pluginFile !== "" || ["poster", "flip", "split", "hud", "terminal", "analog", "aurora"].indexOf(variant) >= 0

    focus: !thumb
    Component.onCompleted: if (!thumb) forceActiveFocus()

    property date now: new Date()
    Timer {
        interval: p.thumb ? 30000 : 1000
        repeat: true
        triggeredOnStart: true
        running: p.thumb ? p.visible : p.lockRoot.active
        onTriggered: p.now = new Date()
    }

    // ── Data ────────────────────────────────────────────────────────────────
    readonly property string hh: Atelier.lockHour(now)                 // 12 or 24 h (Settings → Lock screen → Clock)
    readonly property string ampm: Atelier.lockAmpm(now)               // "" in 24-hour mode
    readonly property string h1: hh.replace(/^0(?=\d)/, "")          // no leading zero
    readonly property string mm: Qt.formatTime(now, "mm")
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!(battery && battery.isLaptopBattery)
    readonly property int batPct: battery ? Math.round(battery.percentage * 100) : 0
    readonly property bool charging: !!(battery && battery.state === UPowerDeviceState.Charging)
    readonly property var notifs: Settings.notifications.lockShowCount ? Notifs.list : []
    readonly property var player: { const ps = Mpris.players.values; return ps.find(x => x.isPlaying) || null; }
    readonly property string weather: lockRoot.weather || ""
    readonly property string temp: (weather.match(/[+-]?\d+°[CF]?/) || [""])[0].replace("+", "")
    readonly property string condition: weather.replace(/[+-]?\d+°[CF]?/, "").trim()
    readonly property bool wide: width / Math.max(1, height) > 1.3
    // the right-hand column (notifications, now playing) on a wide screen
    readonly property real sideW: Math.min(0.28 * width, 540 * u)
    readonly property string countText: notifs.length + (notifs.length === 1 ? " notification" : " notifications")

    // ── Input: typing always goes to the password (as in LockContent.qml) ──
    Keys.onPressed: (e) => {
        const r = p.lockRoot;
        if (p.thumb || r.unlocking) return;
        if (e.key === Qt.Key_Print) {
            if (r.screenshot) r.screenshot(p.screen ? p.screen.name : "");
            e.accepted = true;
            return;
        }
        if (e.key === Qt.Key_Escape) {
            if (r.buffer.length > 0 || r.message) { r.buffer = ""; r.message = ""; }
            else if (p.isPreview && !r.authMode) r.previewing = false;
            r.authMode = false;
        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            r.authMode = true;
            r.submit();
        } else if (e.key === Qt.Key_Backspace) {
            r.authMode = true;
            r.buffer = (e.modifiers & Qt.ControlModifier) ? "" : r.buffer.slice(0, -1);
        } else if (e.text && e.text.length === 1 && e.text.charCodeAt(0) >= 32 && !r.checking) {
            r.authMode = true;
            r.buffer += e.text;
            r.message = "";
        }
        e.accepted = true;
    }
    MouseArea {
        anchors.fill: parent
        enabled: !p.thumb
        onClicked: { p.lockRoot.authMode = true; p.forceActiveFocus(); }
    }
    // Caps Lock from the keyboard LEDs (Qt key events don't carry it), only while typing
    property bool capsOn: false
    Process {
        id: capsProc
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null | sort -r | head -n1"]
        stdout: StdioCollector { onStreamFinished: p.capsOn = parseInt(text.trim()) > 0 }
    }
    Timer { interval: 700; repeat: true; triggeredOnStart: true; running: p.auth && p.lockRoot.active; onTriggered: capsProc.running = true }

    // ── Background: the wallpaper; blurred and dimmed under the password view ──
    Image {
        id: wall
        anchors.fill: parent
        source: Wallpaper.current ? "file://" + Wallpaper.current : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: p.thumb ? 480 : p.width
        sourceSize.height: p.thumb ? 270 : p.height
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        autoPaddingEnabled: false
        blurEnabled: !p.thumb
        blurMax: 64
        blur: p.auth && !p.owns ? 0.9 : 0
        saturation: p.variant === "dot" ? -1 : 0
        scale: p.leaving ? 1.08 : 1
        Behavior on blur { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveClose } }
    }
    // the wallpaper blurred once (static: costs nothing per frame); every Frost card shows its
    // own patch of it, so cards read as frosted glass instead of a thin tint over busy pixels
    MultiEffect {
        id: frostSrc
        anchors.fill: parent
        visible: false
        source: wall
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blur: 1
        brightness: -0.06
        saturation: p.variant === "dot" ? -1 : 0.15
    }
    // legibility: a soft dark at the top and bottom (all over for Dot), more under the password view
    Rectangle {
        anchors.fill: parent
        visible: !p.owns
        gradient: Gradient {
            GradientStop { position: 0;    color: Qt.rgba(0, 0, 0, 0.38) }
            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.06) }
            GradientStop { position: 0.7;  color: Qt.rgba(0, 0, 0, 0.1) }
            GradientStop { position: 1;    color: Qt.rgba(0, 0, 0, 0.5) }
        }
    }
    Rectangle {
        anchors.fill: parent
        color: "black"
        visible: !p.owns
        opacity: Math.min(1, (p.variant === "dot" ? (Settings.lockStyle.dotBackground === "black" ? 1 : 0.5) : 0) + (p.auth ? 0.28 : 0))
        Behavior on opacity { NumberAnimation { duration: 320 } }
    }

    // ═══ Status, top right: Wi-Fi · battery (Oxygen has them in its shelf) ══
    Row {
        visible: p.variant !== "oxygen" && !p.owns
        anchors.right: parent.right; anchors.top: parent.top
        anchors.rightMargin: 40 * p.u; anchors.topMargin: 32 * p.u
        spacing: 22 * p.u
        opacity: p.leaving ? 0 : 0.95
        Behavior on opacity { NumberAnimation { duration: Atelier.durMedium } }
        readonly property string fam: p.variant === "dot" ? Atelier.font : p.display
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: SysState.wifiIcon + (SysState.wifiConnected ? "  " + SysState.ssid : "")
            font.family: parent.fam; font.pixelSize: 22 * p.u; font.weight: Font.Normal
            color: "white"
        }
        Text {
            visible: p.hasBattery
            anchors.verticalCenter: parent.verticalCenter
            text: (p.charging ? "󰂄 " : p.batPct <= 15 ? "󰂃 " : "󰁹 ") + p.batPct + "%"
            font.family: parent.fam; font.pixelSize: 22 * p.u; font.weight: Font.Normal
            color: p.batPct <= 15 && !p.charging ? Qt.tint("white", Qt.alpha(Atelier.red, 0.8)) : "white"
        }
    }

    // ═══ The face (clock, date, widgets), per style ═════════════════════════
    Item {
        id: faceWrap
        anchors.fill: parent
        opacity: (p.owns ? p.leaving : (p.auth || p.leaving)) ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.OutCubic } }
        transform: Translate {
            y: !p.owns && (p.auth || p.leaving) ? -60 * p.u : 0
            Behavior on y { NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }
        }
        layer.enabled: !p.thumb && !p.owns
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.7
            shadowOpacity: 0.3
            shadowColor: "black"
            shadowVerticalOffset: 3
        }
        Loader {
            anchors.fill: parent
            sourceComponent: ({ cupertino: cupertinoFace, hyper: hyperFace, harmony: harmonyFace,
                                oxygen: oxygenFace, material: materialFace, dot: dotFace,
                                poster: posterFace, flip: flipFace, split: splitFace, hud: hudFace,
                                terminal: terminalFace, analog: analogFace, aurora: auroraFace })[p.variant] || cupertinoFace
            visible: p.pluginFile === ""
        }
        // a plugin's face: gets `ph` (this lock) like the built-in full-screen faces; a broken file falls back to nothing
        Loader {
            anchors.fill: parent
            active: p.pluginFile !== ""
            source: p.pluginFile
            onLoaded: { item.ph = p; Plugins.attach(item, p.pluginEntry); }
            onStatusChanged: if (status === Loader.Error && !p.thumb) Plugins.reportError(p.pluginEntry.plugin, p.pluginEntry.id + ": could not load " + p.pluginEntry.file)
        }
    }

    // ── Cupertino (iOS): big clock, round gauges, a notification pile ──────
    Component {
        id: cupertinoFace
        Item {
            readonly property var o: Settings.lockStyle
            readonly property color ink: o.cupertinoTint === "accent" ? Qt.tint("white", Qt.alpha(Atelier.accent, 0.5))
                                       : o.cupertinoTint === "soft" ? Qt.rgba(1, 1, 1, 0.82) : "white"
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0.07 * p.height
                spacing: 0
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(p.now, "dddd, d MMMM")
                    font.family: p.display; font.pixelSize: 32 * p.u; font.weight: Font.DemiBold
                    color: Qt.rgba(1, 1, 1, 0.88)
                }
                // the clock stays centred; AM/PM hangs off its right at the baseline
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: cupClock.width; height: cupClock.height
                    Text {
                        id: cupClock
                        text: p.h1 + ":" + p.mm
                        font.family: p.display; font.pixelSize: 250 * p.u
                        font.weight: o.cupertinoWeight === "regular" ? Font.Medium : o.cupertinoWeight === "heavy" ? Font.Black : Font.Bold
                        font.letterSpacing: -6 * p.u
                        color: parent.parent.parent.ink
                        lineHeight: 0.92
                    }
                    Text {
                        visible: p.ampm !== ""
                        anchors.left: cupClock.right; anchors.leftMargin: 14 * p.u
                        anchors.baseline: cupClock.baseline
                        text: p.ampm
                        font.family: p.display; font.pixelSize: 40 * p.u; font.weight: Font.DemiBold
                        color: Qt.rgba(1, 1, 1, 0.8)
                    }
                }
                // gauges, like the round lock-screen widgets
                Row {
                    visible: o.cupertinoWidgets
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: 8 * p.u
                    spacing: 22 * p.u
                    Gauge {
                        visible: p.hasBattery
                        value: p.batPct / 100
                        tint: p.batPct <= 15 && !p.charging ? Atelier.red : p.charging ? Atelier.green : "white"
                        cap: p.charging ? "󰂄" : "󰁹"; big: String(p.batPct)
                    }
                    Gauge { visible: p.temp !== ""; value: -1; cap: "󰖐"; big: p.temp.replace(/[CF]$/, "") }
                    Gauge { value: -1; cap: Qt.formatDate(p.now, "ddd").toUpperCase(); big: Qt.formatDate(p.now, "d") }
                    Gauge { visible: p.notifs.length > 0; value: -1; cap: "󰂚"; big: String(p.notifs.length) }
                }
            }
            // notifications at the bottom: a pile (newest on top, two edges peeking), a list or a count
            Item {
                id: pile
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 120 * p.u
                width: Math.min(620 * p.u, p.width * 0.8)
                height: childrenRect.height
                visible: p.notifs.length > 0 || !!p.player
                Column {
                    width: parent.width
                    spacing: 10 * p.u
                    NowPlaying { width: parent.width; visible: !!p.player }
                    Item {
                        visible: o.cupertinoNotifs === "pile" && p.notifs.length > 0
                        width: parent.width; height: 74 * p.u + Math.min(2, p.notifs.length - 1) * 10 * p.u
                        Repeater {
                            model: Math.min(2, Math.max(0, p.notifs.length - 1))
                            Rectangle {
                                required property int index
                                z: -1 - index
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: (index + 1) * 10 * p.u
                                width: parent.width - (index + 1) * 36 * p.u
                                height: 74 * p.u; radius: 24 * p.u
                                color: Qt.rgba(1, 1, 1, 0.12 - index * 0.03)
                            }
                        }
                        Notes { width: parent.width; max: 1; showMore: false }
                    }
                    Notes { visible: o.cupertinoNotifs === "list" && p.notifs.length > 0; width: parent.width; max: 3 }
                    Text {
                        visible: p.notifs.length > 0 && (o.cupertinoNotifs === "count" || (o.cupertinoNotifs === "pile" && p.notifs.length > 1))
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: o.cupertinoNotifs === "count" ? "󰂚  " + p.countText : (p.notifs.length - 1) + " more"
                        font.family: p.display; font.pixelSize: 21 * p.u; font.weight: Font.DemiBold; color: Qt.rgba(1, 1, 1, 0.85)
                    }
                }
            }
            RoundBtn { anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 56 * p.u
                icon: "󰄀"; onClicked: if (p.lockRoot.screenshot) p.lockRoot.screenshot(p.screen ? p.screen.name : "") }
            RoundBtn { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 56 * p.u
                icon: "󰤄"; onClicked: Quickshell.execDetached(["systemctl", "suspend"]) }
            Hint { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 56 * p.u }
        }
    }

    // ── Hyper (Xiaomi HyperOS): a huge gradient clock, frosted cards ───────
    Component {
        id: hyperFace
        Item {
            readonly property var o: Settings.lockStyle
            readonly property var grad: ({
                accent: [Qt.tint("white", Qt.alpha(Atelier.accent, 0.25)), Qt.tint("white", Qt.alpha(Atelier.accent, 0.75))],
                sunset: ["#ffe2b8", "#ff8a8a"],
                ocean:  ["#c9f2ff", "#6f9dff"],
                mono:   ["#ffffff", "#cfcfcf"]
            })[o.hyperGradient] || ["#ffffff", "#cfcfcf"]
            readonly property int weight: o.hyperWeight === "thin" ? Font.ExtraLight : o.hyperWeight === "bold" ? Font.Bold : Font.Normal
            Column {
                id: hClock
                x: 0.07 * p.width
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -40 * p.u
                spacing: -80 * p.u
                GradText { text: p.hh; px: 330 * p.u; weight: parent.parent.weight; from: parent.parent.grad[0]; to: parent.parent.grad[1] }
                GradText {
                    id: hMin
                    text: p.mm; px: 330 * p.u; weight: parent.parent.weight; from: parent.parent.grad[0]; to: parent.parent.grad[1]
                    Text {
                        visible: p.ampm !== ""
                        anchors.left: parent.right; anchors.leftMargin: 18 * p.u
                        anchors.top: parent.top; anchors.topMargin: 0.24 * parent.height
                        text: p.ampm
                        font.family: p.display; font.pixelSize: 44 * p.u; font.weight: Font.DemiBold
                        color: "white"
                    }
                }
            }
            Column {
                anchors.left: hClock.left; anchors.leftMargin: 16 * p.u
                anchors.top: hClock.bottom; anchors.topMargin: 6 * p.u
                spacing: 4 * p.u
                Text { text: Qt.formatDate(p.now, "dddd"); font.family: p.display; font.pixelSize: 38 * p.u; font.weight: Font.DemiBold; color: "white" }
                Text { text: Qt.formatDate(p.now, "d MMMM yyyy"); font.family: p.display; font.pixelSize: 26 * p.u; color: Qt.rgba(1, 1, 1, 0.8) }
            }
            // cards on the right
            Column {
                visible: o.hyperCards
                anchors.right: parent.right; anchors.rightMargin: 0.06 * p.width
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(480 * p.u, p.width * 0.32)
                spacing: 16 * p.u
                FrostCard {
                    width: parent.width; height: 150 * p.u
                    visible: p.temp !== ""
                    Text { x: 30 * p.u; anchors.verticalCenter: parent.verticalCenter; text: p.temp
                        font.family: p.display; font.pixelSize: 78 * p.u; font.weight: Font.Light; color: "white" }
                    Column {
                        anchors.right: parent.right; anchors.rightMargin: 30 * p.u; anchors.verticalCenter: parent.verticalCenter
                        spacing: 4 * p.u
                        Text { anchors.right: parent.right; text: "󰖐"; font.family: Atelier.font; font.pixelSize: 40 * p.u; color: "white" }
                        Text { anchors.right: parent.right; text: p.condition || "Weather"; font.family: p.display; font.pixelSize: 22 * p.u; color: Qt.rgba(1, 1, 1, 0.8) }
                    }
                }
                FrostCard {
                    width: parent.width; height: 120 * p.u
                    visible: p.hasBattery
                    Column {
                        x: 30 * p.u; width: parent.width - 60 * p.u
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12 * p.u
                        Item {
                            width: parent.width; height: batT.height
                            Text { id: batT; text: p.batPct + "%"; font.family: p.display; font.pixelSize: 44 * p.u; font.weight: Font.DemiBold; color: "white" }
                            Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: p.charging ? "󰂄  Charging" : "󰁹  On battery"; font.family: p.display; font.pixelSize: 22 * p.u; color: Qt.rgba(1, 1, 1, 0.8) }
                        }
                        Rectangle {
                            width: parent.width; height: 10 * p.u; radius: height / 2
                            color: Qt.rgba(1, 1, 1, 0.2)
                            Rectangle { width: parent.width * p.batPct / 100; height: parent.height; radius: parent.radius
                                gradient: Gradient { orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: hClock.parent.grad[0] }
                                    GradientStop { position: 1; color: hClock.parent.grad[1] } } }
                        }
                    }
                }
                FrostCard {
                    width: parent.width; height: 70 * p.u + Math.min(3, p.notifs.length) * 48 * p.u
                    visible: p.notifs.length > 0
                    Column {
                        x: 30 * p.u; y: 22 * p.u; width: parent.width - 60 * p.u
                        spacing: 10 * p.u
                        Text { text: p.countText; font.family: p.display; font.pixelSize: 24 * p.u; font.weight: Font.DemiBold; color: "white" }
                        Repeater {
                            model: p.notifs.slice(0, 3)
                            Row {
                                spacing: 12 * p.u
                                width: parent.width
                                AppIcon { n: modelData; size: 34 * p.u }
                                Text { width: parent.width - 50 * p.u; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                    text: (modelData.appName || "") + " · " + (modelData.summary || "")
                                    font.family: p.display; font.pixelSize: 20 * p.u; color: Qt.rgba(1, 1, 1, 0.88) }
                            }
                        }
                    }
                }
                NowPlaying { width: parent.width; visible: !!p.player }
            }
            Hint { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 50 * p.u }
        }
    }

    // ── Harmony (Huawei HarmonyOS): a calendar page ────────────────────────
    Component {
        id: harmonyFace
        Item {
            readonly property var o: Settings.lockStyle
            Row {
                id: hDate
                x: 0.07 * p.width
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -60 * p.u
                spacing: 34 * p.u
                Text {
                    id: dayNum
                    text: Qt.formatDate(p.now, "d")
                    font.family: p.display; font.pixelSize: 400 * p.u; font.weight: Font.Light
                    font.letterSpacing: -12 * p.u
                    color: parent.parent.o.harmonyAccent ? Qt.tint("white", Qt.alpha(Atelier.accent, 0.7)) : "white"
                }
                Column {
                    anchors.top: parent.top; anchors.topMargin: 90 * p.u
                    spacing: 8 * p.u
                    Text { text: Qt.formatDate(p.now, "MMMM"); font.family: p.display; font.pixelSize: 56 * p.u; font.weight: Font.DemiBold; color: "white" }
                    Text { text: Qt.formatDate(p.now, "dddd"); font.family: p.display; font.pixelSize: 36 * p.u; color: Qt.rgba(1, 1, 1, 0.85) }
                    Text { text: Qt.formatDate(p.now, "yyyy"); font.family: p.display; font.pixelSize: 28 * p.u; color: Qt.rgba(1, 1, 1, 0.6) }
                    Item { width: 1; height: 20 * p.u }
                    Rectangle { width: 80 * p.u; height: 3 * p.u; color: Qt.rgba(1, 1, 1, 0.7) }
                    Item { width: 1; height: 12 * p.u }
                    Row {
                        spacing: 10 * p.u
                        Text { text: p.h1 + ":" + p.mm; font.family: p.display; font.pixelSize: 72 * p.u; font.weight: Font.Light; color: "white" }
                        Text { visible: p.ampm !== ""; anchors.baseline: parent.children[0].baseline; text: p.ampm
                            font.family: p.display; font.pixelSize: 26 * p.u; font.weight: Font.Medium; color: Qt.rgba(1, 1, 1, 0.8) }
                    }
                    Text { visible: p.temp !== ""; text: "󰖐  " + p.temp + (p.condition ? "  " + p.condition : "")
                        font.family: p.display; font.pixelSize: 24 * p.u; color: Qt.rgba(1, 1, 1, 0.8) }
                }
            }
            Column {
                anchors.right: parent.right; anchors.rightMargin: 0.06 * p.width
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(500 * p.u, p.width * 0.3)
                spacing: 16 * p.u
                MiniMonth { visible: parent.parent.o.harmonyCalendar; width: parent.width; mondayFirst: parent.parent.o.harmonyWeekStart !== "sun" }
                Notes { width: parent.width; max: 2; visible: p.notifs.length > 0 }
            }
            Hint { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 50 * p.u; glyph: "󰌾" }
        }
    }

    // ── Full-screen styles: each one is its own file (PosterFace.qml …) ────
    Component { id: posterFace;   PosterFace   { ph: p } }
    Component { id: flipFace;     FlipFace     { ph: p } }
    Component { id: splitFace;    SplitFace    { ph: p } }
    Component { id: hudFace;      HudFace      { ph: p } }
    Component { id: terminalFace; TerminalFace { ph: p } }
    Component { id: analogFace;   AnalogFace   { ph: p } }
    Component { id: auroraFace;   AuroraFace   { ph: p } }

    // ── Oxygen (OnePlus OxygenOS): a frosted shelf across the screen ───────
    Component {
        id: oxygenFace
        Item {
            readonly property var o: Settings.lockStyle
            readonly property bool atTop: o.oxygenShelf === "top"
            readonly property color hot: o.oxygenAccent === "theme" ? Atelier.accent : "#eb0029"
            // the hint sits just off the shelf, on its open side
            Hint {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.atTop ? shelf.y + shelf.height + 22 * p.u : shelf.y - height - 22 * p.u
            }
            Item {
                id: shelf
                x: 0.04 * p.width
                width: p.width * 0.92
                height: 220 * p.u
                y: parent.atTop ? 44 * p.u : p.height - height - 44 * p.u
                // frosted: the wallpaper, blurred, seen through the shelf
                ClippingRectangle {
                    anchors.fill: parent
                    radius: 52 * p.u
                    color: "transparent"
                    MultiEffect {
                        x: -shelf.x; y: -shelf.y
                        width: p.width; height: p.height
                        source: wall
                        autoPaddingEnabled: false
                        blurEnabled: true; blurMax: 64; blur: 1
                        brightness: -0.12
                    }
                    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.28) }
                }
                Rectangle {
                    anchors.fill: parent; radius: 52 * p.u
                    color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.18)
                }
                // the accent line
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: shelf.parent.atTop ? parent.height - height - 14 * p.u : 14 * p.u
                    width: 90 * p.u; height: 5 * p.u; radius: height / 2
                    color: shelf.parent.hot
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 56 * p.u
                    spacing: 44 * p.u
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: p.hh; font.family: p.display; font.pixelSize: 140 * p.u; font.weight: Font.Bold; color: shelf.parent.hot }
                        Text { text: ":" + p.mm; font.family: p.display; font.pixelSize: 140 * p.u; font.weight: Font.Bold; color: "white" }
                        Text { visible: shelf.parent.o.oxygenSeconds; anchors.baseline: parent.children[0].baseline
                            text: " " + Qt.formatTime(p.now, "ss"); font.family: p.display; font.pixelSize: 48 * p.u; font.weight: Font.Medium; color: Qt.rgba(1, 1, 1, 0.6) }
                        Text { visible: p.ampm !== ""; anchors.baseline: parent.children[0].baseline
                            text: " " + p.ampm; font.family: p.display; font.pixelSize: 36 * p.u; font.weight: Font.DemiBold; color: Qt.rgba(1, 1, 1, 0.75) }
                    }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 2 * p.u; height: 120 * p.u; color: Qt.rgba(1, 1, 1, 0.2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8 * p.u
                        Text { text: Qt.formatDate(p.now, "dddd").toUpperCase(); font.family: p.display; font.pixelSize: 24 * p.u
                            font.weight: Font.DemiBold; font.letterSpacing: 6 * p.u; color: shelf.parent.hot }
                        Text { text: Qt.formatDate(p.now, "d MMMM"); font.family: p.display; font.pixelSize: 44 * p.u; font.weight: Font.Medium; color: "white" }
                        Text { visible: p.temp !== ""; text: "󰖐  " + p.temp + (p.condition ? " · " + p.condition : "")
                            font.family: p.display; font.pixelSize: 22 * p.u; color: Qt.rgba(1, 1, 1, 0.8) }
                    }
                }
                // status chips + the unlock button, on the right
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right; anchors.rightMargin: 48 * p.u
                    spacing: 14 * p.u
                    ShelfChip { icon: SysState.wifiIcon; label: SysState.wifiConnected ? SysState.ssid : "Offline" }
                    ShelfChip { visible: p.hasBattery; icon: p.charging ? "󰂄" : "󰁹"; label: p.batPct + "%" }
                    ShelfChip { visible: p.notifs.length > 0; icon: "󰂚"; label: String(p.notifs.length) }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 96 * p.u; height: 96 * p.u; radius: width / 2
                        color: shelf.parent.hot
                        scale: unlockMa.pressed ? 0.92 : unlockMa.containsMouse ? 1.05 : 1
                        Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
                        Text { anchors.centerIn: parent; text: "󰌾"; font.family: Atelier.font; font.pixelSize: 40 * p.u; color: "white" }
                        MouseArea { id: unlockMa; anchors.fill: parent; enabled: !p.thumb; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { p.lockRoot.authMode = true; p.forceActiveFocus(); } }
                    }
                }
            }
        }
    }

    // ── Material (Pixel / Material You): each digit on its own tonal tile ──
    Component {
        id: materialFace
        Item {
            readonly property var o: Settings.lockStyle
            readonly property bool inLine: o.materialLayout === "line"
            // opaque tonal surfaces (Material You): hours = the theme's accent fill with its light
            // ink, minutes = a deep accent-tinted tone with accent-tinted light digits
            readonly property color base: Qt.rgba(0.07, 0.07, 0.09, 1)
            readonly property color toneA: Atelier.accentFill
            readonly property color toneB: Qt.tint(base, Qt.alpha(Atelier.accent, 0.2))
            readonly property color onA: Atelier.onFill
            readonly property color onTone: Qt.tint("white", Qt.alpha(Atelier.accent, 0.45))
            // the clock (Pixel style): chunky rounded digits, no tiles. Hours in a light accent
            // tone, minutes in white; stacked in "grid", one line in "line". AM/PM small beside.
            readonly property color hourInk: Qt.tint("white", Qt.alpha(Atelier.accent, 0.6))
            Item {
                id: tiles
                readonly property real px: (inLineFace ? 230 : 300) * p.u * (tiles.parent.o.materialShrink && p.notifs.length > 0 ? 0.85 : 1)
                readonly property bool inLineFace: tiles.parent.inLine
                width: clockCol.width
                height: clockCol.height
                x: inLineFace ? (p.width - width) / 2 : 0.1 * p.width
                y: inLineFace ? 0.12 * p.height : 0.1 * p.height
                Grid {
                    id: clockCol
                    columns: tiles.inLineFace ? 3 : 1
                    rowSpacing: -0.3 * tiles.px
                    columnSpacing: 0
                    horizontalItemAlignment: Grid.AlignHCenter
                    Text { text: p.hh; font.family: p.display; font.pixelSize: tiles.px; font.weight: Font.Black
                        font.letterSpacing: -0.04 * tiles.px; font.features: { "tnum": 1 }; color: tiles.parent.hourInk }
                    // a drawn colon: the font's black-weight colon blobs at this size
                    Item {
                        visible: tiles.inLineFace
                        width: 0.2 * tiles.px; height: clockCol.children[0].height
                        Column {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 0.04 * tiles.px
                            spacing: 0.24 * tiles.px
                            Repeater { model: 2
                                Rectangle { width: 0.105 * tiles.px; height: width; radius: width / 2; color: Qt.rgba(1, 1, 1, 0.75) } }
                        }
                    }
                    Text { text: p.mm; font.family: p.display; font.pixelSize: tiles.px; font.weight: Font.Black
                        font.letterSpacing: -0.04 * tiles.px; font.features: { "tnum": 1 }; color: "white" }
                }
            }
            // AM/PM: small, level with the top of the hours (line: the top of the clock)
            Text {
                visible: p.ampm !== ""
                x: tiles.x + tiles.width + 12 * p.u
                y: tiles.y + 0.2 * tiles.px
                text: p.ampm
                font.family: p.display; font.pixelSize: 40 * p.u; font.weight: Font.Bold
                color: parent.hourInk
            }
            // at a glance: date, weather, then notification chips
            Column {
                // line: centred under the clock; grid: left-aligned under the stacked clock
                x: parent.inLine ? (p.width - width) / 2 : tiles.x + 0.03 * tiles.px
                y: tiles.y + tiles.height + (parent.inLine ? 50 : 20) * p.u
                width: Math.min(560 * p.u, p.width * (parent.inLine ? 0.6 : 0.4))
                spacing: 14 * p.u
                Text { anchors.horizontalCenter: parent.parent.inLine ? parent.horizontalCenter : undefined
                    text: Qt.formatDate(p.now, "dddd, MMM d"); font.family: p.display; font.pixelSize: 44 * p.u; font.weight: Font.Medium; color: "white" }
                Row {
                    anchors.horizontalCenter: parent.parent.inLine ? parent.horizontalCenter : undefined
                    spacing: 10 * p.u
                    M3Chip { visible: p.temp !== ""; icon: "󰖐"; label: p.temp + (p.condition ? " · " + p.condition : "") }
                    M3Chip { visible: p.hasBattery; icon: p.charging ? "󰂄" : "󰁹"; label: p.batPct + "%" + (p.charging ? " · Charging" : "") }
                }
                Repeater {
                    model: p.notifs.slice(0, 3)
                    Rectangle {
                        width: parent.width; height: 68 * p.u; radius: 26 * p.u
                        color: tiles.parent.toneB
                        Row {
                            x: 18 * p.u; anchors.verticalCenter: parent.verticalCenter
                            spacing: 14 * p.u
                            AppIcon { n: modelData; size: 34 * p.u }
                            Text { width: 420 * p.u; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                text: (modelData.appName || "") + " · " + (modelData.summary || "")
                                font.family: p.display; font.pixelSize: 21 * p.u; color: tiles.parent.onTone }
                        }
                    }
                }
            }
            // the lock button, Material FAB-style
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 44 * p.u
                spacing: 12 * p.u
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 84 * p.u; height: 84 * p.u; radius: 28 * p.u
                    color: fabMa.containsMouse ? Qt.lighter(tiles.parent.toneA, 1.2) : tiles.parent.toneA
                    Text { anchors.centerIn: parent; text: "󰌾"; font.family: Atelier.font; font.pixelSize: 34 * p.u; color: tiles.parent.onA }
                    MouseArea { id: fabMa; anchors.fill: parent; enabled: !p.thumb; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { p.lockRoot.authMode = true; p.forceActiveFocus(); } }
                }
                Hint { anchors.horizontalCenter: parent.horizontalCenter }
            }
        }
    }

    // ── Dot (Nothing OS): dot-matrix clock, a seconds bar, a dot battery ───
    Component {
        id: dotFace
        Item {
            readonly property var o: Settings.lockStyle
            readonly property string mono: Atelier.font
            readonly property color ink: o.dotColor === "red" ? "#ff1f2d" : o.dotColor === "theme" ? Atelier.accent : "white"
            Column {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -40 * p.u
                spacing: 40 * p.u
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (Qt.formatDate(p.now, "dddd  d MMM") + (p.ampm ? "  " + p.ampm : "")).toUpperCase()
                    font.family: parent.parent.mono; font.pixelSize: 30 * p.u; font.letterSpacing: 12 * p.u
                    color: "white"
                }
                DotClock { anchors.horizontalCenter: parent.horizontalCenter; text: p.hh + ":" + p.mm; dot: 20 * p.u; ink: parent.parent.ink
                    redInk: parent.parent.o.dotColor === "red" }
                // seconds: 60 dots, the elapsed ones lit
                Row {
                    visible: parent.parent.o.dotSeconds
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6 * p.u
                    Repeater {
                        model: 60
                        Rectangle {
                            required property int index
                            width: 7 * p.u; height: 7 * p.u; radius: width / 2
                            color: index <= p.now.getSeconds() ? (index === p.now.getSeconds() ? "#ff1f2d" : "white") : Qt.rgba(1, 1, 1, 0.12)
                        }
                    }
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 40 * p.u
                    Text { visible: p.temp !== ""; anchors.verticalCenter: parent.verticalCenter; text: p.temp.toUpperCase()
                        font.family: parent.parent.parent.mono; font.pixelSize: 24 * p.u; font.letterSpacing: 4 * p.u; color: "white" }
                    // battery as 10 dots
                    Row {
                        visible: p.hasBattery
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12 * p.u
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "BAT"; font.family: parent.parent.parent.parent.mono
                            font.pixelSize: 24 * p.u; font.letterSpacing: 4 * p.u; color: "white" }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5 * p.u
                            Repeater {
                                model: 10
                                Rectangle {
                                    required property int index
                                    width: 12 * p.u; height: 12 * p.u
                                    color: index < Math.round(p.batPct / 10) ? (p.batPct <= 15 ? "#ff1f2d" : "white") : Qt.rgba(1, 1, 1, 0.15)
                                }
                            }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: p.batPct + "%" + (p.charging ? " +" : "")
                            font.family: parent.parent.parent.parent.mono; font.pixelSize: 24 * p.u; color: "white" }
                    }
                    Text { visible: p.notifs.length > 0; anchors.verticalCenter: parent.verticalCenter; text: p.notifs.length + " NOTIF"
                        font.family: parent.parent.parent.mono; font.pixelSize: 24 * p.u; font.letterSpacing: 4 * p.u; color: "white" }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 56 * p.u
                text: "[ TYPE TO UNLOCK ]"
                font.family: parent.mono; font.pixelSize: 20 * p.u; font.letterSpacing: 8 * p.u
                color: Qt.rgba(1, 1, 1, 0.6)
            }
        }
    }

    // ═══ Password view: a laptop login (avatar, name, password field) ═══════
    Item {
        id: authView
        anchors.fill: parent
        visible: opacity > 0
        opacity: p.auth && !p.leaving && !p.owns && !p.ownAuth ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.OutCubic } }
        readonly property bool dotLook: p.variant === "dot"
        // per style: field corners, mono type
        readonly property real fieldRadius: dotLook ? 0 : p.variant === "material" ? 22 * p.u : 32 * p.u
        readonly property string type: dotLook || p.variant === "oxygen" ? Atelier.font : p.display
        function caps(t) { return dotLook ? t.toUpperCase() : t; }

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -40 * p.u
            spacing: 18 * p.u
            scale: p.auth ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            ClippingRectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120 * p.u; height: 120 * p.u
                radius: authView.dotLook ? 0 : width / 2
                color: Qt.rgba(1, 1, 1, 0.18)
                Image { id: face; anchors.fill: parent; source: Profile.faceUrl; fillMode: Image.PreserveAspectCrop; asynchronous: true
                    sourceSize.width: 240; sourceSize.height: 240 }
                Text { anchors.centerIn: parent; visible: face.status !== Image.Ready; text: Atelier.userName.charAt(0).toUpperCase()
                    font.family: authView.type; font.pixelSize: 52 * p.u; color: "white" }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: authView.caps(Atelier.userName)
                font.family: authView.type; font.pixelSize: 34 * p.u
                // the mono font has no Medium: asking for it picks the italic
                font.weight: authView.type === p.display ? Font.DemiBold : Font.Normal
                font.letterSpacing: authView.dotLook ? 6 * p.u : 0
                color: "white"
            }

            // the password field: dots inside, Enter arrow on the right
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 440 * p.u; height: 64 * p.u
                transform: Translate { id: shake }
                Rectangle {
                    anchors.fill: parent
                    radius: authView.fieldRadius
                    color: authView.dotLook ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(1, 1, 1, 0.16)
                    border.width: Math.max(1, 1.5 * p.u)
                    border.color: p.lockRoot.message ? Qt.alpha(Atelier.red, 0.85) : Qt.rgba(1, 1, 1, 0.35)
                    Behavior on border.color { ColorAnimation { duration: Atelier.durFast } }
                }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 26 * p.u
                    anchors.verticalCenter: parent.verticalCenter
                    visible: p.lockRoot.buffer.length === 0
                    text: authView.caps(p.lockRoot.checking ? "Checking…" : "Password")
                    font.family: authView.type; font.pixelSize: 22 * p.u
                    font.letterSpacing: authView.dotLook ? 4 * p.u : 0
                    color: Qt.rgba(1, 1, 1, 0.6)
                }
                Row {
                    anchors.left: parent.left; anchors.leftMargin: 26 * p.u
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10 * p.u
                    Repeater {
                        model: Math.min(p.lockRoot.buffer.length, 20)
                        Rectangle {
                            width: 13 * p.u; height: 13 * p.u
                            radius: authView.dotLook ? 0 : width / 2
                            color: "white"
                            scale: 0
                            Component.onCompleted: scale = 1
                            Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutBack } }
                        }
                    }
                }
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 8 * p.u
                    anchors.verticalCenter: parent.verticalCenter
                    width: 48 * p.u; height: 48 * p.u
                    radius: authView.dotLook ? 0 : p.variant === "material" ? 16 * p.u : width / 2
                    visible: p.lockRoot.buffer.length > 0 || p.lockRoot.checking
                    color: Qt.rgba(1, 1, 1, goMa.containsMouse ? 0.34 : 0.2)
                    Text {
                        anchors.centerIn: parent
                        text: p.lockRoot.checking ? "󰑐" : "󰁔"
                        font.family: Atelier.font; font.pixelSize: 24 * p.u; color: "white"
                        RotationAnimation on rotation { running: p.lockRoot.checking; loops: Animation.Infinite; from: 0; to: 360; duration: 800 }
                    }
                    MouseArea { id: goMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: p.lockRoot.submit() }
                }
            }

            // wrong password / Caps Lock / how to leave
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: authView.caps(p.lockRoot.message ? p.lockRoot.message
                    : p.capsOn ? "Caps Lock is on"
                    : p.isPreview ? "Preview · Esc to go back" : "Enter to unlock · Esc to go back")
                font.family: authView.type; font.pixelSize: 19 * p.u
                font.weight: p.lockRoot.message && authView.type === p.display ? Font.DemiBold : Font.Normal
                font.letterSpacing: authView.dotLook ? 3 * p.u : 0
                color: p.lockRoot.message ? Qt.tint("white", Qt.alpha(Atelier.red, 0.8))
                     : p.capsOn ? Qt.tint("white", Qt.alpha(Atelier.yellow, 0.7)) : Qt.rgba(1, 1, 1, 0.75)
            }
        }

        // sleep · restart · power along the bottom (power asks once)
        Row {
            id: powerRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 56 * p.u
            spacing: 34 * p.u
            property bool confirm: false
            Connections { target: authView; function onVisibleChanged() { powerRow.confirm = false; } }
            Repeater {
                model: powerRow.confirm
                    ? [{ id: "sleep", icon: "󰤄", label: "Sleep" }, { id: "reboot", icon: "󰑓", label: "Restart" }, { id: "poweroff", icon: "⏻", label: "Shut down" }]
                    : [{ id: "sleep", icon: "󰤄", label: "Sleep" }, { id: "ask", icon: "⏻", label: "Power" }]
                Column {
                    id: pw
                    required property var modelData
                    spacing: 6 * p.u
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 58 * p.u; height: 58 * p.u
                        radius: p.variant === "dot" ? 0 : p.variant === "material" ? 20 * p.u : width / 2
                        color: Qt.rgba(1, 1, 1, pwMa.containsMouse ? 0.3 : 0.16)
                        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                        Text { anchors.centerIn: parent; text: pw.modelData.icon; font.family: Atelier.font; font.pixelSize: 24 * p.u; color: "white" }
                        MouseArea {
                            id: pwMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const id = pw.modelData.id;
                                if (id === "ask") powerRow.confirm = true;
                                else if (id === "sleep") Quickshell.execDetached(["systemctl", "suspend"]);
                                else Quickshell.execDetached(["systemctl", id]);
                            }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: authView.caps(pw.modelData.label)
                        font.family: authView.type
                        font.pixelSize: 16 * p.u
                        font.letterSpacing: authView.dotLook ? 3 * p.u : 0
                        color: Qt.rgba(1, 1, 1, 0.75)
                    }
                }
            }
        }
    }

    // the styles with their own password screen
    PhoneAuth {
        anchors.fill: parent
        ph: p
        visible: opacity > 0
        opacity: p.auth && !p.leaving && p.ownAuth ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.OutCubic } }
    }

    // wrong password: shake the dots
    Connections {
        target: p.thumb ? null : p.lockRoot
        ignoreUnknownSignals: true
        function onFailed() { shakeAnim.restart(); }
    }
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: shake; property: "x"; to: -20 * p.u; duration: 60 }
        NumberAnimation { target: shake; property: "x"; to: 18 * p.u; duration: 70 }
        NumberAnimation { target: shake; property: "x"; to: -10 * p.u; duration: 70 }
        NumberAnimation { target: shake; property: "x"; to: 6 * p.u; duration: 60 }
        NumberAnimation { target: shake; property: "x"; to: 0; duration: 60 }
    }

    Loader {
        anchors.fill: parent
        active: !p.thumb
        sourceComponent: Component { LockShotFeedback { lockRoot: p.lockRoot } }
    }

    // ═══ Pieces ═════════════════════════════════════════════════════════════
    // notification stack: app + title only (never the message), "+N more"
    component Notes: Column {
        id: ns
        property int max: 3
        property bool dark: false
        property bool showMore: true
        spacing: 8 * p.u
        Repeater {
            model: p.notifs.slice(0, ns.max)
            Frost {
                // no `required` on purpose (see LockContent.qml: a deleted notification can segfault)
                width: ns.width
                height: 70 * p.u
                radius: 22 * p.u
                wash: ns.dark ? 0.45 : 0.3
                Item {
                    id: nIcon
                    x: 16 * p.u; anchors.verticalCenter: parent.verticalCenter
                    width: 38 * p.u; height: 38 * p.u
                    readonly property string src: Notifs.iconFor(modelData)
                    IconImage { anchors.fill: parent; visible: parent.src !== ""; source: parent.src; asynchronous: true }
                    Text { anchors.centerIn: parent; visible: parent.src === ""; text: "󰂚"; font.family: Atelier.font; font.pixelSize: 24 * p.u; color: "white" }
                }
                Column {
                    anchors.left: nIcon.right; anchors.leftMargin: 14 * p.u
                    anchors.right: parent.right; anchors.rightMargin: 18 * p.u
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2 * p.u
                    Item {
                        width: parent.width; height: appT.height
                        Text { id: appT; width: parent.width - timeT.width - 8; text: modelData.appName || "Notification"; elide: Text.ElideRight
                            font.family: p.display; font.pixelSize: 17 * p.u; color: Qt.rgba(1, 1, 1, 0.75) }
                        Text { id: timeT; anchors.right: parent.right; text: Notifs.timeAgo(Notifs.receivedAt(modelData))
                            font.family: p.display; font.pixelSize: 17 * p.u; color: Qt.rgba(1, 1, 1, 0.6) }
                    }
                    Text { width: parent.width; text: modelData.summary || ""; elide: Text.ElideRight
                        font.family: p.display; font.pixelSize: 21 * p.u; font.weight: Font.DemiBold; color: "white" }
                }
            }
        }
        Text {
            visible: ns.showMore && p.notifs.length > ns.max
            anchors.horizontalCenter: parent.horizontalCenter
            text: "+" + (p.notifs.length - ns.max) + " more"
            font.family: p.display; font.pixelSize: 18 * p.u; font.weight: Font.Medium; color: Qt.rgba(1, 1, 1, 0.75)
        }
    }

    // now playing (Cupertino): art · title/artist · play/pause
    component NowPlaying: Frost {
        height: 92 * p.u
        radius: 24 * p.u
        ClippingRectangle {
            id: art
            x: 14 * p.u; anchors.verticalCenter: parent.verticalCenter
            width: 64 * p.u; height: 64 * p.u; radius: 14 * p.u
            color: Qt.rgba(1, 1, 1, 0.15)
            Image { anchors.fill: parent; source: p.player ? p.player.trackArtUrl : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true
                sourceSize.width: 160; sourceSize.height: 160 }
        }
        Column {
            anchors.left: art.right; anchors.leftMargin: 16 * p.u
            anchors.right: ppBtn.left; anchors.rightMargin: 12 * p.u
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * p.u
            Text { width: parent.width; text: p.player ? (p.player.trackTitle || p.player.identity) : ""; elide: Text.ElideRight
                font.family: p.display; font.pixelSize: 21 * p.u; font.weight: Font.DemiBold; color: "white" }
            Text { width: parent.width; text: p.player ? (p.player.trackArtist || "") : ""; elide: Text.ElideRight
                font.family: p.display; font.pixelSize: 18 * p.u; color: Qt.rgba(1, 1, 1, 0.75) }
        }
        Text {
            id: ppBtn
            anchors.right: parent.right; anchors.rightMargin: 26 * p.u; anchors.verticalCenter: parent.verticalCenter
            text: p.player && p.player.isPlaying ? "󰏤" : "󰐊"
            font.family: Atelier.font; font.pixelSize: 34 * p.u; color: "white"
            MouseArea { anchors.fill: parent; anchors.margins: -10; enabled: !p.thumb; cursorShape: Qt.PointingHandCursor
                onClicked: if (p.player) p.player.togglePlaying() }
        }
    }

    // "Start typing to unlock": a small frosted pill, readable on any wallpaper
    component Hint: Frost {
        id: hint
        property string glyph: "󰌾"
        width: hintRow.width + 40 * p.u
        height: 44 * p.u
        radius: height / 2
        wash: 0.24
        Row {
            id: hintRow
            anchors.centerIn: parent
            spacing: 10 * p.u
            Text { visible: hint.glyph !== ""; anchors.verticalCenter: parent.verticalCenter; text: hint.glyph
                font.family: Atelier.font; font.pixelSize: 18 * p.u; color: Qt.rgba(1, 1, 1, 0.9) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Start typing to unlock"
                font.family: p.display; font.pixelSize: 19 * p.u; font.weight: Font.Medium; color: Qt.rgba(1, 1, 1, 0.92) }
        }
    }

    // frosted round corner button (Cupertino)
    component RoundBtn: Rectangle {
        id: rb
        property string icon
        signal clicked()
        width: 64 * p.u; height: 64 * p.u; radius: width / 2
        color: Qt.rgba(1, 1, 1, rbMa.containsMouse ? 0.3 : 0.18)
        scale: rbMa.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
        Text { anchors.centerIn: parent; text: rb.icon; font.family: Atelier.font; font.pixelSize: 26 * p.u; color: "white" }
        MouseArea { id: rbMa; anchors.fill: parent; enabled: !p.thumb; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
    }
    // a round lock-screen gauge (Cupertino): a ring when value >= 0, a small label over a big one
    component Gauge: Item {
        id: gg
        property real value: -1
        property color tint: "white"
        property string cap
        property string big
        width: 104 * p.u; height: 104 * p.u
        Frost { anchors.fill: parent; radius: width / 2 }
        Shape {
            anchors.fill: parent
            visible: gg.value >= 0
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(1, 1, 1, 0.22); strokeWidth: 6 * p.u; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: gg.width / 2; centerY: gg.height / 2; radiusX: gg.width / 2 - 9 * p.u; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: gg.tint; strokeWidth: 6 * p.u; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: gg.width / 2; centerY: gg.height / 2; radiusX: gg.width / 2 - 9 * p.u; radiusY: radiusX; startAngle: -90; sweepAngle: 360 * Math.max(0.01, gg.value) }
            }
        }
        Column {
            anchors.centerIn: parent
            spacing: -2 * p.u
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: gg.cap
                font.family: /^[A-Z]+$/.test(gg.cap) ? p.display : Atelier.font; font.pixelSize: 18 * p.u; font.weight: Font.DemiBold
                color: Qt.rgba(1, 1, 1, 0.85) }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: gg.big
                font.family: p.display; font.pixelSize: 34 * p.u; font.weight: Font.DemiBold; color: "white" }
        }
    }

    // text filled with a vertical gradient (Hyper's clock)
    component GradText: Item {
        id: gt
        property string text
        property real px: 100
        property int weight: Font.Normal
        property color from: "white"
        property color to: "white"
        width: gtText.implicitWidth
        height: gtText.implicitHeight
        Text {
            id: gtText
            text: gt.text
            font.family: p.display; font.pixelSize: gt.px; font.weight: gt.weight
            font.letterSpacing: -gt.px * 0.03
            color: "white"
            visible: false
            layer.enabled: true
        }
        Rectangle {
            id: gtFill
            anchors.fill: parent
            visible: false
            layer.enabled: true
            gradient: Gradient {
                GradientStop { position: 0.15; color: gt.from }
                GradientStop { position: 0.9; color: gt.to }
            }
        }
        MultiEffect {
            anchors.fill: parent
            source: gtFill
            maskEnabled: true
            maskSource: gtText
            maskThresholdMin: 0.4
            maskSpreadAtMin: 0.6
        }
    }

    // frosted glass: the blurred wallpaper behind this card (frostSrc) + a dark wash + a hairline.
    // Readable over any wallpaper; the position is re-read while visible (layouts settle late).
    component Frost: Item {
        id: fr
        property real radius: 28 * p.u
        property real wash: 0.3
        property point at: Qt.point(0, 0)
        function sync() {
            const q = fr.mapToItem(p, 0, 0);
            if (Math.abs(q.x - at.x) > 0.5 || Math.abs(q.y - at.y) > 0.5) at = Qt.point(q.x, q.y);
        }
        Component.onCompleted: Qt.callLater(sync)
        onWidthChanged: Qt.callLater(sync)
        onHeightChanged: Qt.callLater(sync)
        onVisibleChanged: if (visible) Qt.callLater(sync)
        Timer { interval: 500; repeat: true; running: fr.visible && !p.auth && (p.thumb ? false : p.lockRoot.active); onTriggered: fr.sync() }
        ClippingRectangle {
            anchors.fill: parent
            radius: fr.radius
            color: "transparent"
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: frostSrc
                sourceRect: Qt.rect(fr.at.x, fr.at.y, fr.width, fr.height)
            }
            Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, fr.wash) }
        }
        Rectangle {
            anchors.fill: parent
            radius: fr.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)
        }
    }

    // a frosted card (Hyper)
    component FrostCard: Frost { radius: 36 * p.u }

    // an app's icon, a bell when it has none
    component AppIcon: Item {
        id: ai
        property var n
        property real size: 32
        width: size; height: size
        readonly property string src: n ? Notifs.iconFor(n) : ""
        IconImage { anchors.fill: parent; visible: ai.src !== ""; source: ai.src; asynchronous: true }
        Text { anchors.centerIn: parent; visible: ai.src === ""; text: "󰂚"; font.family: Atelier.font; font.pixelSize: ai.size * 0.7; color: "white" }
    }

    // this month, today ringed (Harmony)
    component MiniMonth: Frost {
        id: mm
        property bool mondayFirst: true
        readonly property int y0: p.now.getFullYear()
        readonly property int m0: p.now.getMonth()
        readonly property int days: new Date(y0, m0 + 1, 0).getDate()
        readonly property int lead: { const d = new Date(y0, m0, 1).getDay(); return mondayFirst ? (d + 6) % 7 : d; }
        readonly property real cell: (width - 48 * p.u) / 7
        height: mmCol.height + 48 * p.u
        radius: 36 * p.u
        Column {
            id: mmCol
            x: 24 * p.u; y: 24 * p.u
            spacing: 10 * p.u
            Text { text: Qt.formatDate(p.now, "MMMM yyyy"); font.family: p.display; font.pixelSize: 26 * p.u; font.weight: Font.DemiBold; color: "white"; leftPadding: 8 * p.u }
            Grid {
                columns: 7
                Repeater {
                    model: mm.mondayFirst ? ["M", "T", "W", "T", "F", "S", "S"] : ["S", "M", "T", "W", "T", "F", "S"]
                    Text { required property string modelData; width: mm.cell; height: mm.cell * 0.7; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        text: modelData; font.family: p.display; font.pixelSize: 18 * p.u; font.weight: Font.DemiBold; color: Qt.rgba(1, 1, 1, 0.55) }
                }
                Repeater {
                    model: Math.ceil((mm.lead + mm.days) / 7) * 7
                    Item {
                        required property int index
                        readonly property int day: index - mm.lead + 1
                        readonly property bool today: day === p.now.getDate()
                        width: mm.cell; height: mm.cell * 0.86
                        Rectangle { anchors.centerIn: parent; width: Math.min(parent.width, parent.height) * 0.9; height: width; radius: width / 2
                            visible: parent.today; color: Atelier.accent }
                        Text { anchors.centerIn: parent; visible: parent.day >= 1 && parent.day <= mm.days; text: parent.day
                            font.family: p.display; font.pixelSize: 20 * p.u; font.weight: parent.today ? Font.Bold : Font.Normal
                            color: parent.today ? Atelier.onFill : "white" }
                    }
                }
            }
        }
    }

    // a status pill in Oxygen's shelf
    component ShelfChip: Rectangle {
        id: sc
        property string icon
        property string label
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: scRow.width + 36 * p.u
        height: 56 * p.u
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.12)
        Row {
            id: scRow
            anchors.centerIn: parent
            spacing: 10 * p.u
            Text { anchors.verticalCenter: parent.verticalCenter; text: sc.icon; font.family: Atelier.font; font.pixelSize: 22 * p.u; color: "white" }
            Text { anchors.verticalCenter: parent.verticalCenter; text: sc.label; font.family: p.display; font.pixelSize: 21 * p.u; font.weight: Font.Medium; color: "white"
                elide: Text.ElideRight; width: Math.min(implicitWidth, 220 * p.u) }
        }
    }

    // a Material 3 assist chip
    component M3Chip: Rectangle {
        id: mc
        property string icon
        property string label
        width: mcRow.width + 40 * p.u
        height: 52 * p.u
        radius: height / 2
        color: Qt.tint(Qt.rgba(0.09, 0.09, 0.11, 1), Qt.alpha(Atelier.accent, 0.24))
        Row {
            id: mcRow
            anchors.centerIn: parent
            spacing: 10 * p.u
            Text { anchors.verticalCenter: parent.verticalCenter; text: mc.icon; font.family: Atelier.font; font.pixelSize: 22 * p.u
                color: Qt.tint("white", Qt.alpha(Atelier.accent, 0.4)) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: mc.label; font.family: p.display; font.pixelSize: 22 * p.u; font.weight: Font.Medium
                color: Qt.tint("white", Qt.alpha(Atelier.accent, 0.22)) }
        }
    }

    // a 5×7 dot-matrix clock (Dot): lit dots white, the colon in red, unlit dots faint
    component DotClock: Row {
        id: dc
        property string text
        property real dot: 16
        property color ink: "white"
        property bool redInk: false             // red digits: the colon goes white instead
        readonly property var glyphs: ({
            "0": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
            "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
            "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
            "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
            "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
            "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
            "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
            "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
            "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
            "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
            ":": ["0", "0", "1", "0", "1", "0", "0"]
        })
        spacing: dot * 1.4
        Repeater {
            model: dc.text.split("")
            Grid {
                id: g
                required property string modelData
                readonly property var bits: dc.glyphs[modelData] || dc.glyphs["0"]
                readonly property bool colon: modelData === ":"
                columns: bits[0].length
                spacing: dc.dot * 0.35
                Repeater {
                    model: g.bits.length * g.columns
                    Rectangle {
                        required property int index
                        readonly property bool lit: g.bits[Math.floor(index / g.columns)].charAt(index % g.columns) === "1"
                        width: dc.dot; height: dc.dot; radius: width / 2
                        color: lit ? (g.colon ? (dc.redInk ? "white" : "#ff1f2d") : dc.ink) : Qt.rgba(1, 1, 1, 0.05)
                    }
                }
            }
        }
    }
}
