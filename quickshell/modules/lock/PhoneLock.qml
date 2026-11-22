import QtQuick
import QtQuick.Effects
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

    readonly property real u: height / 1000
    readonly property bool auth: !thumb && lockRoot.authMode
    readonly property bool leaving: !thumb && lockRoot.unlocking
    readonly property string display: "Inter Display"

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
    readonly property string hh: Atelier.clock24 ? Qt.formatTime(now, "HH") : Atelier.hour12(now)
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
        blur: p.auth ? 0.9 : 0
        saturation: p.variant === "dot" ? -1 : 0
        scale: p.leaving ? 1.08 : 1
        Behavior on blur { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveClose } }
    }
    // legibility: a soft dark at the top and bottom (all over for Dot), more under the password view
    Rectangle {
        anchors.fill: parent
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
        opacity: (p.variant === "dot" ? 0.5 : 0) + (p.auth ? 0.28 : 0)
        Behavior on opacity { NumberAnimation { duration: 320 } }
    }

    // ═══ Status, top right: Wi-Fi · battery (a laptop's corner) ══════════════
    Row {
        anchors.right: parent.right; anchors.top: parent.top
        anchors.rightMargin: 36 * p.u; anchors.topMargin: 28 * p.u
        spacing: 18 * p.u
        opacity: p.leaving ? 0 : 0.92
        Behavior on opacity { NumberAnimation { duration: 260 } }
        readonly property bool mono: p.variant === "dot" || p.variant === "oxygen"
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: SysState.wifiIcon + (SysState.wifiConnected && p.width > 900 ? "  " + SysState.ssid : "")
            font.family: parent.mono ? Atelier.font : p.display; font.pixelSize: 20 * p.u; font.weight: Font.Normal
            color: "white"
        }
        Text {
            visible: p.hasBattery
            anchors.verticalCenter: parent.verticalCenter
            text: (p.charging ? "󰂄 " : p.batPct <= 15 ? "󰂃 " : "󰁹 ") + p.batPct + "%"
            font.family: parent.mono ? Atelier.font : p.display; font.pixelSize: 20 * p.u; font.weight: Font.Normal
            color: p.batPct <= 15 && !p.charging ? Qt.tint("white", Qt.alpha(Atelier.red, 0.8)) : "white"
        }
    }

    // ═══ The face (clock, date, widgets), per style ═════════════════════════
    Item {
        id: faceWrap
        anchors.fill: parent
        opacity: p.auth || p.leaving ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        transform: Translate {
            y: p.auth || p.leaving ? -70 * p.u : 0
            Behavior on y { NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }
        }
        layer.enabled: !p.thumb
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.6
            shadowOpacity: 0.35
            shadowColor: "black"
            shadowVerticalOffset: 2
        }
        Loader {
            anchors.fill: parent
            sourceComponent: ({ cupertino: cupertinoFace, hyper: hyperFace, harmony: harmonyFace,
                                oxygen: oxygenFace, material: materialFace, dot: dotFace })[p.variant] || cupertinoFace
        }
    }

    // ── Cupertino (iOS) ─────────────────────────────────────────────────────
    Component {
        id: cupertinoFace
        Item {
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0.075 * p.height
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(p.now, "dddd d MMMM")
                    font.family: p.display; font.pixelSize: 30 * p.u; font.weight: Font.DemiBold
                    color: Qt.rgba(1, 1, 1, 0.9)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: p.h1 + ":" + p.mm
                    font.family: p.display; font.pixelSize: 220 * p.u; font.weight: Font.Bold
                    color: "white"
                    lineHeight: 0.95
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12 * p.u
                    Glass { visible: p.temp !== ""; icon: "󰖐"; label: p.temp + (p.condition ? "  " + p.condition : "") }
                    Glass { visible: p.hasBattery; icon: p.charging ? "󰂄" : "󰁹"; label: p.batPct + "%" }
                }
            }
            // under the clock on a narrow screen, a right-hand column on a wide one
            Column {
                x: p.wide ? p.width - p.sideW - 0.045 * p.width : (p.width - width) / 2
                y: p.wide ? 0.16 * p.height : 0.52 * p.height
                width: p.wide ? p.sideW : Math.min(p.width * 0.9, 640 * p.u)
                spacing: 10 * p.u
                NowPlaying { width: parent.width; visible: !!p.player }
                Notes { width: parent.width; max: p.wide ? (p.player ? 4 : 5) : (p.player ? 2 : 3) }
            }
            // corner buttons + the home bar
            RoundBtn { anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 56 * p.u
                icon: "󰄀"; onClicked: if (p.lockRoot.screenshot) p.lockRoot.screenshot(p.screen ? p.screen.name : "") }
            RoundBtn { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 56 * p.u
                icon: "󰤄"; onClicked: Quickshell.execDetached(["systemctl", "suspend"]) }
            Hint { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 68 * p.u }
        }
    }

    // ── Hyper (Xiaomi HyperOS) ──────────────────────────────────────────────
    Component {
        id: hyperFace
        Item {
            Column {
                id: hyperClock
                x: 0.07 * p.width
                y: 0.06 * p.height
                spacing: -70 * p.u
                Text { text: p.hh; font.family: p.display; font.pixelSize: 330 * p.u; font.weight: Font.Thin; color: "white" }
                Text { text: p.mm; font.family: p.display; font.pixelSize: 330 * p.u; font.weight: Font.Thin; color: "white" }
            }
            Column {
                x: hyperClock.x + 14 * p.u
                anchors.top: hyperClock.bottom; anchors.topMargin: 10 * p.u
                spacing: 6 * p.u
                Text { text: Qt.formatDate(p.now, "ddd, d MMMM"); font.family: p.display; font.pixelSize: 34 * p.u; font.weight: Font.Medium; color: "white" }
                Text { visible: p.temp !== ""; text: p.temp + (p.condition ? " · " + p.condition : "")
                    font.family: p.display; font.pixelSize: 24 * p.u; color: Qt.rgba(1, 1, 1, 0.8) }
                Text { visible: p.notifs.length > 0; text: "󰂚  " + p.countText
                    font.family: Atelier.font; font.pixelSize: 20 * p.u; color: Qt.rgba(1, 1, 1, 0.75) }
            }
            Text {
                anchors.left: parent.left; anchors.bottom: parent.bottom
                anchors.leftMargin: 0.07 * p.width + 14 * p.u; anchors.bottomMargin: 56 * p.u
                visible: p.hasBattery
                text: (p.charging ? "󰂄  Charging · " : "󰁹  ") + p.batPct + "%"
                font.family: Atelier.font; font.pixelSize: 20 * p.u; color: Qt.rgba(1, 1, 1, 0.8)
            }
            Hint { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 56 * p.u }
            PlainBtn { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 48 * p.u
                icon: "󰄀"; onClicked: if (p.lockRoot.screenshot) p.lockRoot.screenshot(p.screen ? p.screen.name : "") }
        }
    }

    // ── Harmony (Huawei HarmonyOS) ──────────────────────────────────────────
    Component {
        id: harmonyFace
        Item {
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0.1 * p.height
                spacing: 4 * p.u
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: p.hh + ":" + p.mm
                    font.family: p.display; font.pixelSize: 170 * p.u; font.weight: Font.Light; color: "white"
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(p.now, "d MMMM  dddd") + (p.temp ? "   󰖐 " + p.temp : "")
                    font.family: p.display; font.pixelSize: 28 * p.u; color: Qt.rgba(1, 1, 1, 0.88)
                }
                Item { width: 1; height: 26 * p.u; visible: !p.wide }
                Notes { visible: !p.wide && p.notifs.length > 0; anchors.horizontalCenter: parent.horizontalCenter; width: Math.min(p.width * 0.86, 560 * p.u); max: 2 }
            }
            Notes { visible: p.wide && p.notifs.length > 0; x: p.width - p.sideW - 0.045 * p.width; y: 0.16 * p.height; width: p.sideW; max: 5 }
            Hint { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 44 * p.u; glyph: "󰌾" }
            PlainBtn { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 44 * p.u
                icon: "󰄀"; onClicked: if (p.lockRoot.screenshot) p.lockRoot.screenshot(p.screen ? p.screen.name : "") }
        }
    }

    // ── Oxygen (OnePlus OxygenOS) ───────────────────────────────────────────
    Component {
        id: oxygenFace
        Item {
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0.11 * p.height
                spacing: 6 * p.u
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(p.now, "dddd, MMM d").toUpperCase()
                    font.family: p.display; font.pixelSize: 24 * p.u; font.weight: Font.Medium
                    font.letterSpacing: 7 * p.u
                    color: Qt.rgba(1, 1, 1, 0.88)
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    Text { text: p.hh; font.family: Atelier.font; font.pixelSize: 190 * p.u; font.bold: true; color: Atelier.red }
                    Text { text: ":"; font.family: Atelier.font; font.pixelSize: 190 * p.u; font.bold: true; color: "white" }
                    Text { text: p.mm; font.family: Atelier.font; font.pixelSize: 190 * p.u; font.bold: true; color: "white" }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: [p.temp, p.hasBattery ? (p.charging ? "󰂄 " : "󰁹 ") + p.batPct + "%" : ""].filter(x => x).join("     ")
                    font.family: Atelier.font; font.pixelSize: 22 * p.u; color: Qt.rgba(1, 1, 1, 0.8)
                }
            }
            Notes { dark: true
                x: p.wide ? p.width - p.sideW - 0.045 * p.width : (p.width - width) / 2
                y: p.wide ? 0.16 * p.height : 0.5 * p.height
                width: p.wide ? p.sideW : Math.min(p.width * 0.9, 600 * p.u)
                max: p.wide ? 5 : 3 }
            // a pulsing lock ring (a laptop has no fingerprint pad here): click or type to unlock
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 90 * p.u
                width: 104 * p.u; height: 104 * p.u
                Rectangle {
                    anchors.fill: parent; radius: width / 2
                    color: "transparent"
                    border.width: 2 * p.u; border.color: Qt.alpha(Atelier.red, 0.7)
                    SequentialAnimation on scale {
                        running: !p.thumb; loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 1.12; duration: 1100; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1.12; to: 1; duration: 1100; easing.type: Easing.InOutSine }
                    }
                }
                Text { anchors.centerIn: parent; text: "󰌾"; font.family: Atelier.font; font.pixelSize: 46 * p.u; color: "white" }
                MouseArea { anchors.fill: parent; enabled: !p.thumb; cursorShape: Qt.PointingHandCursor
                    onClicked: { p.lockRoot.authMode = true; p.forceActiveFocus(); } }
            }
            Hint { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 44 * p.u }
        }
    }

    // ── Material (Pixel / Material You) ─────────────────────────────────────
    Component {
        id: materialFace
        Item {
            readonly property color tone1: Qt.tint("white", Qt.alpha(Atelier.accent, 0.6))
            readonly property color tone2: Qt.tint("white", Qt.alpha(Atelier.accent, 0.25))
            // at a glance
            Column {
                x: 0.07 * p.width
                y: 0.08 * p.height
                spacing: 4 * p.u
                Text { text: Qt.formatDate(p.now, "ddd, MMM d") + (p.temp ? "   󰖐 " + p.temp : "")
                    font.family: p.display; font.pixelSize: 36 * p.u; font.weight: Font.Medium; color: "white" }
                Text { visible: p.condition !== "" || p.notifs.length > 0
                    text: [p.condition, p.notifs.length > 0 ? p.countText : ""].filter(x => x).join(" · ")
                    font.family: p.display; font.pixelSize: 22 * p.u; color: Qt.rgba(1, 1, 1, 0.78) }
            }
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0.2 * p.height
                spacing: -90 * p.u
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: p.hh
                    font.family: p.display; font.pixelSize: 300 * p.u; font.weight: Font.Black; color: parent.parent.tone1 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: p.mm
                    font.family: p.display; font.pixelSize: 300 * p.u; font.weight: Font.Black; color: parent.parent.tone2 }
            }
            // notification icons, Pixel-style
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0.76 * p.height
                spacing: 14 * p.u
                Repeater {
                    model: p.notifs.slice(0, 6)
                    Item {
                        width: 34 * p.u; height: 34 * p.u
                        readonly property string src: Notifs.iconFor(modelData)
                        IconImage { anchors.fill: parent; visible: parent.src !== ""; source: parent.src; asynchronous: true }
                        Text { anchors.centerIn: parent; visible: parent.src === ""; text: "󰂚"; font.family: Atelier.font; font.pixelSize: 24 * p.u; color: "white" }
                    }
                }
            }
            SquircleBtn { anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 52 * p.u; tint: parent.tone2
                icon: "󰄀"; onClicked: if (p.lockRoot.screenshot) p.lockRoot.screenshot(p.screen ? p.screen.name : "") }
            SquircleBtn { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 52 * p.u; tint: parent.tone2
                icon: "󰤄"; onClicked: Quickshell.execDetached(["systemctl", "suspend"]) }
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 48 * p.u
                spacing: 10 * p.u
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 60 * p.u; height: 60 * p.u; radius: width / 2
                    color: Qt.rgba(1, 1, 1, 0.16)
                    Text { anchors.centerIn: parent; text: "󰌾"; font.family: Atelier.font; font.pixelSize: 26 * p.u; color: "white" }
                }
                Hint { anchors.horizontalCenter: parent.horizontalCenter }
            }
        }
    }

    // ── Dot (Nothing OS) ────────────────────────────────────────────────────
    Component {
        id: dotFace
        Item {
            readonly property string mono: Atelier.font
            Column {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -70 * p.u
                spacing: 34 * p.u
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(p.now, "ddd d MMM").toUpperCase()
                    font.family: parent.parent.mono; font.pixelSize: 28 * p.u; font.letterSpacing: 10 * p.u
                    color: "white"
                }
                DotClock { anchors.horizontalCenter: parent.horizontalCenter; text: p.hh + ":" + p.mm; dot: 17 * p.u }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: [p.temp, p.hasBattery ? "BAT " + p.batPct + "%" + (p.charging ? " +" : "") : "",
                           p.notifs.length > 0 ? p.notifs.length + " NOTIF" : ""].filter(x => x).join("   ·   ")
                    font.family: parent.parent.mono; font.pixelSize: 20 * p.u; font.letterSpacing: 4 * p.u
                    color: Qt.rgba(1, 1, 1, 0.75)
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 56 * p.u
                text: "[ TYPE TO UNLOCK ]"
                font.family: parent.mono; font.pixelSize: 18 * p.u; font.letterSpacing: 6 * p.u
                color: Qt.rgba(1, 1, 1, 0.55)
            }
        }
    }

    // ═══ Password view: a laptop login (avatar, name, password field) ═══════
    Item {
        id: authView
        anchors.fill: parent
        visible: opacity > 0
        opacity: p.auth && !p.leaving ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
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
                    Behavior on border.color { ColorAnimation { duration: 200 } }
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
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
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
                        Behavior on color { ColorAnimation { duration: 120 } }
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
    // frosted pill widget (Cupertino)
    component Glass: Rectangle {
        id: gl
        property string icon
        property string label
        width: glRow.width + 30 * p.u
        height: 44 * p.u
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.16)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.22)
        Row {
            id: glRow
            anchors.centerIn: parent
            spacing: 8 * p.u
            Text { anchors.verticalCenter: parent.verticalCenter; text: gl.icon; font.family: Atelier.font; font.pixelSize: 20 * p.u; color: "white" }
            Text { anchors.verticalCenter: parent.verticalCenter; text: gl.label; font.family: p.display; font.pixelSize: 20 * p.u; font.weight: Font.Medium; color: "white" }
        }
    }

    // notification stack: app + title only (never the message), "+N more"
    component Notes: Column {
        id: ns
        property int max: 3
        property bool dark: false
        visible: p.notifs.length > 0
        spacing: 8 * p.u
        Repeater {
            model: p.notifs.slice(0, ns.max)
            Rectangle {
                // no `required` on purpose (see LockContent.qml: a deleted notification can segfault)
                width: ns.width
                height: 70 * p.u
                radius: 22 * p.u
                color: ns.dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(1, 1, 1, 0.18)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, ns.dark ? 0.1 : 0.2)
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
            visible: p.notifs.length > ns.max
            anchors.horizontalCenter: parent.horizontalCenter
            text: "+" + (p.notifs.length - ns.max) + " more"
            font.family: p.display; font.pixelSize: 18 * p.u; font.weight: Font.Medium; color: Qt.rgba(1, 1, 1, 0.75)
        }
    }

    // now playing (Cupertino): art · title/artist · play/pause
    component NowPlaying: Rectangle {
        height: 92 * p.u
        radius: 24 * p.u
        color: Qt.rgba(1, 1, 1, 0.18)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.2)
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

    // "Click or type to unlock" (optionally after a glyph)
    component Hint: Text {
        property string glyph: ""
        text: (glyph ? glyph + "  " : "") + "Start typing to unlock"
        font.family: p.display; font.pixelSize: 19 * p.u; font.weight: Font.Medium
        color: Qt.rgba(1, 1, 1, 0.75)
    }

    // frosted round corner button (Cupertino)
    component RoundBtn: Rectangle {
        id: rb
        property string icon
        signal clicked()
        width: 64 * p.u; height: 64 * p.u; radius: width / 2
        color: Qt.rgba(1, 1, 1, rbMa.containsMouse ? 0.3 : 0.18)
        scale: rbMa.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: 110 } }
        Text { anchors.centerIn: parent; text: rb.icon; font.family: Atelier.font; font.pixelSize: 26 * p.u; color: "white" }
        MouseArea { id: rbMa; anchors.fill: parent; enabled: !p.thumb; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
    }
    // a bare glyph button (Hyper, Harmony)
    component PlainBtn: Text {
        id: pb
        property string icon
        signal clicked()
        text: icon
        font.family: Atelier.font; font.pixelSize: 30 * p.u
        color: Qt.rgba(1, 1, 1, pbMa.containsMouse ? 1 : 0.75)
        MouseArea { id: pbMa; anchors.fill: parent; anchors.margins: -12; enabled: !p.thumb; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }
    // tonal rounded-square button (Material)
    component SquircleBtn: Rectangle {
        id: sq
        property string icon
        property color tint: "white"
        signal clicked()
        width: 72 * p.u; height: 72 * p.u; radius: 24 * p.u
        color: Qt.alpha(tint, sqMa.containsMouse ? 0.38 : 0.24)
        Text { anchors.centerIn: parent; text: sq.icon; font.family: Atelier.font; font.pixelSize: 28 * p.u; color: "white" }
        MouseArea { id: sqMa; anchors.fill: parent; enabled: !p.thumb; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sq.clicked() }
    }
    // a 5×7 dot-matrix clock (Dot): lit dots white, the colon in red, unlit dots faint
    component DotClock: Row {
        id: dc
        property string text
        property real dot: 16
        readonly property var glyphs: ({
            "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
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
                        color: lit ? (g.colon ? Atelier.red : "white") : Qt.rgba(1, 1, 1, 0.08)
                    }
                }
            }
        }
    }
}
