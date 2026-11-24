import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.components
import qs.config
import qs.services

// The lock screen UI (Caelestia-style, atelier look): one glass panel over the blurred
// wallpaper, three columns.
//   left    weather · now playing
//   centre  greeting · clock · date · avatar · password · sleep/restart/power
//   right   system (battery, Wi-Fi, Bluetooth) · notifications (app + title only)
// Narrow/portrait screens show only the centre. The password pill is always live: just type.
// Used by LockScreen.qml for every locked screen and for the preview window. All the PAM
// logic lives in LockScreen.qml (lockRoot): this file only shows state and calls submit().
Item {
    id: c

    required property var lockRoot
    property var screen: null
    property bool isPreview: false

    focus: true
    Component.onCompleted: forceActiveFocus()

    property date now: new Date()
    Timer { interval: 1000; running: c.lockRoot.active; repeat: true; triggeredOnStart: true; onTriggered: c.now = new Date() }

    // ── Data ────────────────────────────────────────────────────────────────
    readonly property string userName: Atelier.userName
    readonly property int hour: now.getHours()
    readonly property string greeting: hour >= 5 && hour < 12 ? "Good morning"
        : hour >= 12 && hour < 17 ? "Good afternoon" : hour >= 17 && hour < 21 ? "Good evening" : "Working late"
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!(battery && battery.isLaptopBattery)
    readonly property real batPct: battery ? battery.percentage : 0
    readonly property bool charging: !!(battery && battery.state === UPowerDeviceState.Charging)
    readonly property var player: {
        const ps = Mpris.players.values;
        return ps.find(p => p.isPlaying) || ps[0] || null;
    }
    readonly property var notifs: Settings.notifications.lockShowCount ? Notifs.list : []
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d.connected)

    property string weather: ""
    Process {
        running: true
        command: [Quickshell.shellDir + "/scripts/weather.sh", Settings.widgets.weatherLocation, Settings.widgets.weatherUnits]
        stdout: StdioCollector { onStreamFinished: c.weather = text.trim() }
    }
    readonly property string temp: (weather.match(/[+-]?\d+°[CF]?/) || [""])[0].replace("+", "")
    readonly property string condition: weather.replace(/[+-]?\d+°[CF]?/, "").trim()

    // MprisPlayer.position does not tick on its own
    Timer {
        interval: 1000; repeat: true
        running: c.lockRoot.active && !!c.player && c.player.isPlaying
        onTriggered: if (c.player) c.player.positionChanged()
    }

    readonly property bool wide: width >= 1100 && height >= 640

    // ── Input: typing always goes to the password ───────────────────────────
    Keys.onPressed: (e) => {
        const r = c.lockRoot;
        if (r.unlocking) return;
        if (e.key === Qt.Key_Print) {           // screenshot of this screen (see LockScreen.screenshot)
            if (r.screenshot) r.screenshot(c.screen ? c.screen.name : "");
            e.accepted = true;
            return;
        }
        if (e.key === Qt.Key_Escape) {
            if (r.buffer.length > 0 || r.message) { r.buffer = ""; r.message = ""; }
            else if (c.isPreview) r.previewing = false;
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
        onClicked: { c.lockRoot.authMode = true; c.forceActiveFocus(); }
    }

    // ── Background: the wallpaper, blurred once (static, so it costs nothing per frame) ──
    Image {
        id: wall
        anchors.fill: parent
        source: Wallpaper.current ? "file://" + Wallpaper.current : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: c.width
        sourceSize.height: c.height
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 48
        blur: 0.75
        saturation: 0.05
        scale: c.lockRoot.unlocking ? 1.06 : 1
        Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveClose } }
    }
    Rectangle { anchors.fill: parent; color: Atelier.crust; opacity: 0.38 }

    // ═══ The panel ═══════════════════════════════════════════════════════════
    Item {
        id: panelWrap
        anchors.centerIn: parent
        width: c.wide ? Math.min(1180, c.width - 140) : Math.min(420, c.width - 48)
        height: c.wide ? Math.min(660, c.height - 150) : Math.min(640, c.height - 80)

        // springs open when the lock appears, shrinks away on unlock
        property real shown: 0
        Component.onCompleted: shown = 1
        Behavior on shown { NumberAnimation { duration: Atelier.durOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen } }
        opacity: c.lockRoot.unlocking ? 0 : Math.min(1, shown * 1.4)
        scale: c.lockRoot.unlocking ? 0.94 : 0.9 + 0.1 * shown
        Behavior on opacity { NumberAnimation { duration: Atelier.durMedium } }
        Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveClose } }

        RectangularShadow {
            anchors.fill: panel
            radius: panel.radius
            blur: 48
            spread: 0
            offset.y: 10
            color: Qt.alpha(Atelier.crust, 0.55)
        }
        Rectangle {
            id: panel
            anchors.fill: parent
            radius: Math.max(28, Atelier.rounding + 12)
            color: Atelier.surface
            border.width: 1
            border.color: Atelier.outline
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 18

            // ── Left: weather · media ───────────────────────────────────────
            ColumnLayout {
                visible: c.wide
                Layout.fillWidth: false
                Layout.preferredWidth: 300
                Layout.minimumWidth: 300
                Layout.maximumWidth: 300
                Layout.fillHeight: true
                spacing: 14

                Card {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    tint: Atelier.sapphire
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 4
                        Chip { icon: c.hour < 6 || c.hour >= 19 ? "󰖔" : "󰖙"; text: "Weather"; tint: Atelier.sapphire }
                        Item { Layout.fillHeight: true }
                        Text {
                            text: c.temp || "—"
                            font.family: Atelier.font; font.pixelSize: 44; font.bold: true
                            color: Atelier.text
                        }
                        Text {
                            Layout.fillWidth: true
                            text: c.condition || (c.weather ? "" : "Fetching weather…")
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg
                            color: Atelier.subtext1
                            elide: Text.ElideRight
                        }
                    }
                }

                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    tint: Atelier.pink
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 12
                        Chip { icon: "󰎆"; text: c.player ? "Now playing" : "Nothing playing"; tint: Atelier.pink }

                        ClippingRectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 60
                            radius: Atelier.radiusMd
                            color: Qt.alpha(Atelier.pink, 0.10)
                            Image {
                                anchors.fill: parent
                                source: c.player ? c.player.trackArtUrl : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 520; sourceSize.height: 520
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !c.player || !c.player.trackArtUrl
                                text: "󰝚"; font.family: Atelier.font; font.pixelSize: 40
                                color: Qt.alpha(Atelier.pink, 0.7)
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text { Layout.fillWidth: true; text: c.player ? (c.player.trackTitle || c.player.identity) : "Play something to see it here"; font.family: Atelier.fontUi; font.pixelSize: 14; font.weight: Font.DemiBold; color: Atelier.text; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; visible: !!c.player; text: c.player ? (c.player.trackArtist || "") : ""; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext; elide: Text.ElideRight }
                        }
                        SlimBar {
                            Layout.fillWidth: true
                            visible: !!c.player && c.player.length > 0
                            value: c.player && c.player.length > 0 ? c.player.position / c.player.length : 0
                            tint: Atelier.pink
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            visible: !!c.player
                            spacing: 10
                            TintButton { size: 36; icon: "󰒮"; tint: Atelier.text; onClicked: c.player.previous() }
                            TintButton { size: 44; icon: c.player && c.player.isPlaying ? "󰏤" : "󰐊"; tint: Atelier.pink; onClicked: c.player.togglePlaying() }
                            TintButton { size: 36; icon: "󰒭"; tint: Atelier.text; onClicked: c.player.next() }
                        }
                    }
                }
            }

            // ── Centre: clock · avatar · password ───────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, 380)
                    spacing: 0

                    Chip {
                        Layout.alignment: Qt.AlignHCenter
                        icon: "󰌾"
                        text: c.greeting + ", " + c.userName
                        tint: Atelier.mauve
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 10
                        spacing: 10
                        Row {
                            readonly property int px: c.wide ? 104 : 84
                            Text { text: Atelier.lockHour(c.now); font.family: Atelier.font; font.pixelSize: parent.px; font.bold: true; color: Atelier.text }
                            Text { text: ":"; font.family: Atelier.font; font.pixelSize: parent.px; font.bold: true; color: Atelier.accent }
                            Text { text: Qt.formatTime(c.now, "mm"); font.family: Atelier.font; font.pixelSize: parent.px; font.bold: true; color: Atelier.text }
                        }
                        Chip {
                            visible: !Atelier.lockClock24
                            Layout.alignment: Qt.AlignVCenter
                            Layout.topMargin: 14
                            text: Atelier.lockAmpm(c.now)
                            mono: true
                            tint: Atelier.blue
                            implicitHeight: 30
                        }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8
                        Text { text: "󰸗"; font.family: Atelier.font; font.pixelSize: 14; color: Atelier.peach }
                        Text { text: Qt.formatDate(c.now, "dddd, d MMMM"); font.family: Atelier.fontUi; font.pixelSize: Atelier.fsXl; color: Atelier.subtext1 }
                    }

                    // avatar (~/.face if present, else the initial) with an accent ring
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 30
                        implicitWidth: 92; implicitHeight: 92
                        radius: 46
                        color: "transparent"
                        border.width: 2
                        border.color: Qt.alpha(Atelier.accent, c.lockRoot.authMode ? 0.85 : 0.45)
                        Behavior on border.color { ColorAnimation { duration: Atelier.durFast } }
                        ClippingRectangle {
                            anchors.fill: parent
                            anchors.margins: 5
                            radius: width / 2
                            color: Qt.alpha(Atelier.accent, 0.18)
                            Image {
                                id: face
                                anchors.fill: parent
                                source: Profile.faceUrl
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 180; sourceSize.height: 180
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: face.status !== Image.Ready
                                text: c.userName.charAt(0)
                                font.family: Atelier.font; font.pixelSize: 36; font.bold: true
                                color: Atelier.accent
                            }
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 10
                        text: c.userName
                        font.family: Atelier.fontUi; font.pixelSize: 17; font.weight: Font.DemiBold
                        color: Atelier.text
                    }

                    // password pill (always live)
                    Item {
                        Layout.fillWidth: true
                        Layout.topMargin: 16
                        implicitHeight: 48
                        transform: Translate { id: shake }

                        Rectangle {
                            anchors.fill: parent
                            radius: 24
                            color: Atelier.container
                            border.width: c.lockRoot.authMode || c.lockRoot.message ? 2 : 1
                            border.color: c.lockRoot.message ? Qt.alpha(Atelier.red, 0.75)
                                : c.lockRoot.authMode ? Qt.alpha(Atelier.accent, 0.7) : Atelier.outline
                            Behavior on border.color { ColorAnimation { duration: Atelier.durFast } }
                        }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 20
                            anchors.verticalCenter: parent.verticalCenter
                            visible: c.lockRoot.buffer.length === 0
                            text: c.lockRoot.checking ? "Checking…" : "Type your password"
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg
                            color: Atelier.subtext
                        }
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 20
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 7
                            Repeater {
                                model: Math.min(c.lockRoot.buffer.length, 20)
                                Rectangle {
                                    width: 9; height: 9; radius: 4.5
                                    color: Atelier.accent
                                    scale: 0
                                    Component.onCompleted: scale = 1
                                    Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen } }
                                }
                            }
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36; height: 36; radius: Atelier.radiusLg
                            visible: c.lockRoot.buffer.length > 0 || c.lockRoot.checking
                            color: Qt.alpha(Atelier.accent, goMa.containsMouse ? 0.32 : 0.2)
                            border.width: 1
                            border.color: Qt.alpha(Atelier.accent, 0.45)
                            Text {
                                anchors.centerIn: parent
                                text: c.lockRoot.checking ? "󰑐" : "󰁔"
                                font.family: Atelier.font; font.pixelSize: 16
                                color: Atelier.accent
                                RotationAnimation on rotation { running: c.lockRoot.checking; loops: Animation.Infinite; from: 0; to: 360; duration: 800 }
                            }
                            MouseArea { id: goMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: c.lockRoot.submit() }
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 10
                        text: c.lockRoot.message || (c.isPreview ? "Preview · Esc to close" : "Enter to unlock")
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                        font.weight: c.lockRoot.message ? Font.DemiBold : Font.Normal
                        color: c.lockRoot.message ? Atelier.red : Atelier.subtext
                    }

                    // sleep · restart · power (power asks once)
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 26
                        spacing: 10
                        property bool confirm: false
                        TintButton { size: 40; icon: "󰄀"; tint: Atelier.sky; onClicked: if (c.lockRoot.screenshot) c.lockRoot.screenshot(c.screen ? c.screen.name : "") }
                        TintButton { size: 40; icon: "󰤄"; tint: Atelier.lavender; onClicked: Quickshell.execDetached(["systemctl", "suspend"]) }
                        TintButton { size: 40; icon: "󰑓"; tint: Atelier.green; visible: parent.confirm; onClicked: Quickshell.execDetached(["systemctl", "reboot"]) }
                        TintButton { size: 40; icon: "⏻"; tint: Atelier.red; visible: parent.confirm; onClicked: Quickshell.execDetached(["systemctl", "poweroff"]) }
                        TintButton { size: 40; icon: parent.confirm ? "󰅖" : "󰐥"; tint: Atelier.red; onClicked: parent.confirm = !parent.confirm }
                    }
                }
            }

            // ── Right: system · notifications ───────────────────────────────
            ColumnLayout {
                visible: c.wide
                Layout.fillWidth: false
                Layout.preferredWidth: 300
                Layout.minimumWidth: 300
                Layout.maximumWidth: 300
                Layout.fillHeight: true
                spacing: 14

                Card {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    tint: Atelier.green
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 10
                        Chip { icon: "󰍹"; text: "System"; tint: Atelier.green }
                        Item { Layout.fillHeight: true }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: c.hasBattery
                            spacing: 10
                            Text { text: c.charging ? "󰂄" : "󰁹"; font.family: Atelier.font; font.pixelSize: Atelier.fsXl; color: c.batPct <= 0.15 && !c.charging ? Atelier.red : Atelier.green }
                            SlimBar {
                                Layout.fillWidth: true
                                value: c.batPct
                                tint: c.batPct <= 0.15 && !c.charging ? Atelier.red : Atelier.green
                            }
                            Text { text: Math.round(c.batPct * 100) + "%"; font.family: Atelier.font; font.pixelSize: Atelier.fsMd; color: Atelier.subtext1 }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Chip { icon: SysState.wifiIcon; text: SysState.wifiConnected ? SysState.ssid : "Offline"; tint: Atelier.sky }
                            Chip {
                                icon: c.btConnected.length > 0 ? "󰂱" : "󰂯"
                                text: c.btConnected.length > 0 ? (c.btConnected[0].name || "Connected") : (c.btAdapter && c.btAdapter.enabled ? "On" : "Off")
                                tint: Atelier.blue
                            }
                        }
                    }
                }

                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    tint: Atelier.lavender
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 10
                        Chip {
                            icon: "󰂚"
                            text: c.notifs.length === 0 ? "No notifications"
                                : c.notifs.length + (c.notifs.length === 1 ? " notification" : " notifications")
                            tint: Atelier.lavender
                        }
                        Repeater {
                            model: c.notifs.slice(0, 4)
                            Rectangle {
                                // no `required` here on purpose: Qt's required-property path reads the
                                // (possibly already deleted) notification object and can segfault
                                Layout.fillWidth: true
                                implicitHeight: 52
                                radius: Atelier.radiusMd
                                color: Atelier.container
                                border.width: 1
                                border.color: Atelier.outline
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10; anchors.rightMargin: 12
                                    spacing: 10
                                    Item {
                                        implicitWidth: 28; implicitHeight: 28
                                        readonly property string src: Notifs.iconFor(modelData)
                                        IconImage { anchors.fill: parent; visible: parent.src !== ""; source: parent.src; asynchronous: true }
                                        Rectangle {
                                            anchors.fill: parent; visible: parent.src === ""; radius: Atelier.radiusSm
                                            color: Qt.alpha(Atelier.lavender, 0.16)
                                            Text { anchors.centerIn: parent; text: "󰂚"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: Atelier.lavender }
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { Layout.fillWidth: true; text: modelData.appName || "Notification"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMicro; color: Atelier.subtext; elide: Text.ElideRight }
                                            Text { text: Notifs.timeAgo(Notifs.receivedAt(modelData)); font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMicro; color: Atelier.subtext; opacity: 0.7 }
                                        }
                                        Text { Layout.fillWidth: true; text: modelData.summary; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; color: Atelier.text; elide: Text.ElideRight }
                                    }
                                }
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Text {
                                anchors.centerIn: parent
                                visible: c.notifs.length === 0
                                text: "󰂜"
                                font.family: Atelier.font; font.pixelSize: 38
                                color: Qt.alpha(Atelier.lavender, 0.35)
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                visible: c.notifs.length > 4
                                text: "+" + (c.notifs.length - 4) + " more"
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; font.weight: Font.DemiBold
                                color: Atelier.subtext
                            }
                        }
                    }
                }
            }
        }
    }

    // wrong password: shake
    Connections {
        target: c.lockRoot
        function onFailed() { shakeAnim.restart(); }
    }
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: shake; property: "x"; to: -18; duration: 60 }
        NumberAnimation { target: shake; property: "x"; to: 16; duration: 70 }
        NumberAnimation { target: shake; property: "x"; to: -10; duration: 70 }
        NumberAnimation { target: shake; property: "x"; to: 6; duration: 60 }
        NumberAnimation { target: shake; property: "x"; to: 0; duration: 60 }
    }

    // ── Pieces ──────────────────────────────────────────────────────────────
    // Card: the control center's card (container + hairline), with a faint tint wash.
    component Card: Rectangle {
        id: card
        property color tint: Atelier.accent
        radius: 20
        color: Atelier.container
        border.width: 1
        border.color: Atelier.outline
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(card.tint, 0.10) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }

    // SlimBar: the shell's slim gradient bar.
    component SlimBar: Rectangle {
        id: slim
        property real value: 0
        property color tint: Atelier.accent
        implicitHeight: 6
        radius: 3
        color: Qt.alpha(tint, 0.16)
        Rectangle {
            width: slim.width * Math.max(0, Math.min(1, slim.value))
            height: parent.height
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.alpha(slim.tint, 0.7) }
                GradientStop { position: 1; color: slim.tint }
            }
            Behavior on width { NumberAnimation { duration: Atelier.durMedium } }
        }
    }

    // Tinted round button (atelier chip style)
    component TintButton: Rectangle {
        id: tb
        property string icon
        property int size: 44
        property color tint: Atelier.accent
        signal clicked()
        width: size
        height: size
        radius: size / 2
        color: Qt.alpha(tint, tbMa.containsMouse ? 0.26 : 0.14)
        border.width: 1
        border.color: Qt.alpha(tint, 0.38)
        scale: tbMa.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Text { anchors.centerIn: parent; text: tb.icon; font.family: Atelier.font; font.pixelSize: tb.size * 0.38; color: tb.tint }
        MouseArea { id: tbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked() }
    }

    LockShotFeedback { lockRoot: c.lockRoot }
}
