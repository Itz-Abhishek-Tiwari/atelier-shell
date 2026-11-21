import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Greetd
import Quickshell.Services.UPower

// Atelier login screen: a Quickshell greeter for greetd, drawn like the lock screen
// (modules/lock/LockContent.qml): one glass panel over the blurred wallpaper.
//   left    weather · sessions
//   centre  greeting · clock · date · avatar · password · sleep/restart/power
//   right   system (host, battery, network) · users
//
//   greetd -> cage -> quickshell -p /etc/greetd/atelier-greeter/shell.qml
//
// Self-contained on purpose: at login this runs as the `greeter` system user, so it cannot
// read your $HOME or the main shell's singletons. Everything it shows comes from
// /var/lib/atelier-greeter (owned by you, written by Settings → Login screen):
//   settings.json   options        colors.json   your theme        wallpaper.jpg
//   faces/<user>    avatars        fonts/        SpaceMono (the shell's clock font)
//
// Preview without touching your login (demo mode, password "demo", Esc to close):
//     quickshell -p ~/Downloads/quickshell-atelier/greeter/shell.qml
ShellRoot {
    id: root

    readonly property string dataDir: Quickshell.env("ATELIER_GREETER_DATA") || "/var/lib/atelier-greeter"
    readonly property bool demo: !Greetd.available

    // ── options (settings.json; written by the Settings app) ────────────────
    property var cfg: ({
        layout: "panel",          // panel (three columns) | minimal (centre only)
        greeting: "",             // "" = by time of day
        clock24: false,
        showWeather: true,
        weatherLocation: "",
        weatherUnits: "metric",
        showSystem: true,
        showPower: true,
        blur: 0.75,
        dim: 0.38
    })
    FileView {
        path: root.dataDir + "/settings.json"
        printErrors: false
        onLoaded: {
            try {
                const o = JSON.parse(text());
                const merged = Object.assign({}, root.cfg);
                for (const k in o) if (k in merged) merged[k] = o[k];
                root.cfg = merged;
            } catch (e) { console.log("greeter: bad settings.json, using defaults"); }
        }
    }

    // ── palette (colors.json = a copy of ~/.config/atelier/theme.json) ──────
    property var c: ({
        base: "#1e1e2e", crust: "#11111b", text: "#cdd6f4", subtext1: "#bac2de", subtext0: "#a6adc8",
        red: "#f38ba8", peach: "#fab387", green: "#a6e3a1", sky: "#89dceb", sapphire: "#74c7ec",
        blue: "#89b4fa", lavender: "#b4befe", mauve: "#cba6f7", pink: "#f5c2e7", accent: "#cba6f7"
    })
    property bool isLight: false
    FileView {
        path: root.dataDir + "/colors.json"
        printErrors: false
        onLoaded: {
            try {
                const t = JSON.parse(text());
                root.c = Object.assign({}, root.c, t.colors);
                root.isLight = t.variant === "light";
            } catch (e) { console.log("greeter: bad colors.json, using defaults"); }
        }
    }
    readonly property color surface: Qt.alpha(isLight ? c.base : c.crust, 0.92)
    readonly property color container: Qt.alpha(c.text, 0.06)
    readonly property color containerHigh: Qt.alpha(c.text, 0.11)
    readonly property color outline: Qt.alpha(c.text, 0.08)

    // fonts: Inter is system-wide; the shell's SpaceMono lives in your $HOME, so a copy is used
    FontLoader { id: monoR; source: "file://" + root.dataDir + "/fonts/mono-regular.ttf" }
    FontLoader { id: monoB; source: "file://" + root.dataDir + "/fonts/mono-bold.ttf" }
    readonly property string font: monoR.status === FontLoader.Ready ? monoR.name : "JetBrainsMono Nerd Font"
    readonly property string fontUi: "Inter"

    // motion (Atelier.curveOpen / curveClose)
    readonly property var curveOpen: [0.38, 1.21, 0.22, 1, 1, 1]
    readonly property var curveClose: [0.3, 0, 0.8, 0.15, 1, 1]

    // ── clock ───────────────────────────────────────────────────────────────
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }
    readonly property int hour: now.getHours()
    function hour12(d) { const h = cfg.clock24 ? d.getHours() : (d.getHours() % 12 || 12); return (h < 10 ? "0" : "") + h; }
    function ampm(d) { return cfg.clock24 ? "" : (d.getHours() < 12 ? "AM" : "PM"); }
    readonly property string greeting: cfg.greeting ? cfg.greeting
        : hour >= 5 && hour < 12 ? "Good morning" : hour >= 12 && hour < 17 ? "Good afternoon"
        : hour >= 17 && hour < 21 ? "Good evening" : "Working late"

    // ── users, sessions, last choice ────────────────────────────────────────
    property var users: []        // [{name, real}]
    property var sessions: []     // [{name, exec, desktop}]
    property int userIdx: 0
    property int sessIdx: 0
    readonly property string user: users.length ? users[userIdx].name : ""
    readonly property string realName: users.length ? (users[userIdx].real || user) : ""
    readonly property var session: sessions.length ? sessions[sessIdx] : null

    Process {
        running: true
        command: ["sh", "-c", "getent passwd | awk -F: '$3>=1000 && $3<60000 && $7 !~ /nologin|false/ {print $1\"|\"$5}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.users = text.trim().split("\n").filter(l => l).map(l => {
                    const p = l.split("|");
                    return { name: p[0], real: (p[1] || "").split(",")[0] || p[0] };
                });
                root.restoreLast();
            }
        }
    }
    Process {
        running: true
        command: ["sh", "-c", "for f in /usr/share/wayland-sessions/*.desktop; do n=$(grep -m1 '^Name=' \"$f\" | cut -d= -f2-); e=$(grep -m1 '^Exec=' \"$f\" | cut -d= -f2-); d=$(grep -m1 '^DesktopNames=' \"$f\" | cut -d= -f2- | cut -d';' -f1); [ -n \"$e\" ] && echo \"$n|$e|$d\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.sessions = text.trim().split("\n").filter(l => l).map(l => {
                    const p = l.split("|");
                    return { name: p[0], exec: p[1], desktop: p[2] || "Hyprland" };
                });
                root.restoreLast();
            }
        }
    }
    FileView { id: lastFile; path: "/var/cache/atelier-greeter/last"; printErrors: false }
    function restoreLast() {
        let t = "";
        try { t = lastFile.text(); } catch (e) {}
        const p = t.trim().split("|");
        if (p.length < 2) return;
        const ui = users.findIndex(u => u.name === p[0]);
        const si = sessions.findIndex(s => s.name === p[1]);
        if (ui >= 0) userIdx = ui;
        if (si >= 0) sessIdx = si;
    }
    Process { id: saver }
    function saveLast() {
        saver.command = ["sh", "-c", "printf '%s|%s' \"$1\" \"$2\" > /var/cache/atelier-greeter/last 2>/dev/null; true", "sh", user, session ? session.name : ""];
        saver.running = true;
    }

    function pickUser(i) {
        if (i === userIdx || i < 0 || i >= users.length) return;
        if (!demo && Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
        userIdx = i;
        buffer = ""; message = ""; checking = false; answered = false; prompt = "Type your password"; echo = false;
    }
    function nextUser() { if (users.length > 1) pickUser((userIdx + 1) % users.length); }
    function nextSession() { if (sessions.length > 1) sessIdx = (sessIdx + 1) % sessions.length; }

    // ── auth (greetd) ───────────────────────────────────────────────────────
    property string buffer: ""
    property bool checking: false
    property bool answered: false
    property string prompt: "Type your password"
    property bool echo: false            // the current prompt shows what you type (e.g. a code)
    property string message: ""
    property bool messageIsError: true
    property bool launching: false
    signal failed()

    function submit() {
        if (checking || launching || !user || buffer.length === 0) return;
        message = "";
        checking = true;
        if (demo) { demoTimer.start(); return; }
        if (Greetd.state === GreetdState.Inactive) {
            answered = false;
            Greetd.createSession(user);
        } else {
            answered = true;
            Greetd.respond(buffer);
            buffer = "";
        }
    }
    function fail(msg) {
        checking = false;
        answered = false;
        echo = false;
        prompt = "Type your password";
        buffer = "";
        messageIsError = true;
        message = msg || "Incorrect password";
        failed();
    }
    Timer {
        id: demoTimer
        interval: 700
        onTriggered: {
            if (root.buffer === "demo") { root.checking = false; root.buffer = ""; root.messageIsError = false; root.message = "Demo: signed in (nothing launched)"; }
            else root.fail("Incorrect password (the demo password is “demo”)");
        }
    }

    Connections {
        target: Greetd
        function onAuthMessage(msg, error, responseRequired, echoResponse) {
            if (responseRequired) {
                root.echo = echoResponse;
                if (!root.answered && root.buffer.length > 0) {
                    root.answered = true;
                    Greetd.respond(root.buffer);
                    root.buffer = "";
                } else {
                    // a further question (second factor etc.): wait for the user
                    root.checking = false;
                    root.prompt = msg.replace(/:\s*$/, "") || "Password";
                }
            } else {
                root.messageIsError = error;
                root.message = msg;
            }
        }
        function onAuthFailure(msg) { Greetd.cancelSession(); root.fail(msg); }
        function onReadyToLaunch() {
            root.saveLast();
            root.checking = false;
            root.messageIsError = false;
            root.message = "";
            root.launching = true;       // plays the same exit animation as unlocking
            launchTimer.start();
        }
        function onError(e) { root.fail(e); }
    }
    Timer {
        id: launchTimer
        interval: 420
        onTriggered: {
            const s = root.session;
            const exec = s ? s.exec.split(" ").filter(x => x) : ["start-hyprland"];
            const desk = s ? s.desktop : "Hyprland";
            // session.sh clears the login VT and sends the session's console output to a log
            // file, so no text flashes on screen between the greeter and the desktop
            Greetd.launch([Quickshell.shellPath("session.sh")].concat(exec),
                ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=" + desk, "XDG_CURRENT_DESKTOP=" + desk], true);
        }
    }

    // ── system info (right column) ──────────────────────────────────────────
    property string hostName: ""
    FileView {
        path: "/etc/hostname"
        printErrors: false
        onLoaded: root.hostName = text().trim()
    }
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!(battery && battery.isLaptopBattery)
    readonly property real batPct: battery ? battery.percentage : 0
    readonly property bool charging: !!(battery && battery.state === UPowerDeviceState.Charging)

    property string netType: ""       // wifi | ethernet | ""
    property string netName: ""
    Process {
        id: netProc
        running: true
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE,CONNECTION device 2>/dev/null | awk -F: '$2==\"connected\" && ($1==\"wifi\"||$1==\"ethernet\") {print $1\"|\"$3; exit}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split("|");
                root.netType = p[0] || "";
                root.netName = p[1] || "";
            }
        }
    }
    Timer { interval: 8000; running: true; repeat: true; onTriggered: netProc.running = true }

    // ── weather (wttr.in, like scripts/weather.sh) ──────────────────────────
    property string weather: ""
    Process {
        id: weatherProc
        running: root.cfg.showWeather
        command: ["sh", "-c", "for i in 1 2 3 4 5; do w=$(curl -s --max-time 4 \"wttr.in/$(printf '%s' \"$1\" | sed 's/ /+/g')?$2&format=%t+%C\" 2>/dev/null); case \"$w\" in *°*) printf '%s' \"$w\"; exit 0;; esac; sleep 3; done",
            "sh", root.cfg.weatherLocation || "", root.cfg.weatherUnits === "imperial" ? "u" : "m"]
        stdout: StdioCollector { onStreamFinished: root.weather = text.trim().length < 40 ? text.trim() : "" }
    }
    readonly property string temp: (weather.match(/[+-]?\d+°[CF]?/) || [""])[0].replace("+", "")
    readonly property string condition: weather.replace(/[+-]?\d+°[CF]?/, "").trim()

    Process { id: power }
    function runPower(cmd) { power.command = ["systemctl", cmd]; power.running = true; }

    // ═══ Windows ═════════════════════════════════════════════════════════════
    // Real login: one kiosk window in cage (cage makes it fullscreen; decorations are off
    // via QT_WAYLAND_DISABLE_WINDOWDECORATION in /etc/greetd/config.toml).
    LazyLoader {
        active: !root.demo
        FloatingWindow {
            title: "Atelier Login"
            color: "black"
            GreeterView { anchors.fill: parent }
        }
    }
    // Preview inside Hyprland (no greetd): a fullscreen overlay, Esc closes it.
    LazyLoader {
        active: root.demo
        PanelWindow {
            anchors { top: true; bottom: true; left: true; right: true }
            color: "black"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell-greeter-preview"
            GreeterView { anchors.fill: parent }
        }
    }

    // ═══ The UI ══════════════════════════════════════════════════════════════
    component GreeterView: Item {
        id: v
        focus: true
        Component.onCompleted: forceActiveFocus()

        readonly property bool wide: root.cfg.layout !== "minimal" && width >= 1100 && height >= 640

        // typing always goes to the password, like the lock screen
        Keys.onPressed: (e) => {
            if (root.launching) return;
            if (e.key === Qt.Key_Escape) {
                if (root.buffer.length > 0 || root.message) { root.buffer = ""; root.message = ""; }
                else if (root.demo) Qt.quit();
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                root.submit();
            } else if (e.key === Qt.Key_Backspace) {
                root.buffer = (e.modifiers & Qt.ControlModifier) ? "" : root.buffer.slice(0, -1);
            } else if (e.key === Qt.Key_Tab) {
                root.nextUser();
            } else if (e.key === Qt.Key_F2) {
                root.nextSession();
            } else if (e.text && e.text.length === 1 && e.text.charCodeAt(0) >= 32 && !root.checking) {
                root.buffer += e.text;
                root.message = "";
            }
            e.accepted = true;
        }
        MouseArea { anchors.fill: parent; onClicked: v.forceActiveFocus() }

        // ── background: the wallpaper, blurred once ─────────────────────────
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: root.c.base }
                GradientStop { position: 1; color: root.c.crust }
            }
        }
        Image {
            id: wall
            anchors.fill: parent
            source: "file://" + root.dataDir + "/wallpaper.jpg"
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize.width: Math.max(1, v.width)
            sourceSize.height: Math.max(1, v.height)
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: wall
            visible: wall.status === Image.Ready
            autoPaddingEnabled: false
            blurEnabled: root.cfg.blur > 0
            blurMax: 48
            blur: root.cfg.blur
            saturation: 0.05
            scale: root.launching ? 1.06 : 1
            Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveClose } }
        }
        Rectangle { anchors.fill: parent; color: root.c.crust; opacity: root.cfg.dim }

        // ═══ The panel ═══════════════════════════════════════════════════════
        Item {
            id: panelWrap
            anchors.centerIn: parent
            width: v.wide ? Math.min(1180, v.width - 140) : Math.min(420, v.width - 48)
            height: v.wide ? Math.min(660, v.height - 150) : Math.min(640, v.height - 80)

            property real shown: 0
            Component.onCompleted: shown = 1
            Behavior on shown { NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveOpen } }
            opacity: root.launching ? 0 : Math.min(1, shown * 1.4)
            scale: root.launching ? 0.94 : 0.9 + 0.1 * shown
            Behavior on opacity { NumberAnimation { duration: 260 } }
            Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveClose } }

            RectangularShadow {
                anchors.fill: panel
                radius: panel.radius
                blur: 48
                offset.y: 10
                color: Qt.alpha(root.c.crust, 0.55)
            }
            Rectangle {
                id: panel
                anchors.fill: parent
                radius: 36
                color: root.surface
                border.width: 1
                border.color: root.outline
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 18

                // ── Left: weather · sessions ────────────────────────────────
                ColumnLayout {
                    visible: v.wide
                    Layout.preferredWidth: 300
                    Layout.minimumWidth: 300
                    Layout.maximumWidth: 300
                    Layout.fillHeight: true
                    spacing: 14

                    Card {
                        visible: root.cfg.showWeather
                        Layout.fillWidth: true
                        Layout.preferredHeight: 150
                        tint: root.c.sapphire
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 4
                            Chip { icon: root.hour < 6 || root.hour >= 19 ? "󰖔" : "󰖙"; text: "Weather"; tint: root.c.sapphire }
                            Item { Layout.fillHeight: true }
                            Text { text: root.temp || "—"; font.family: root.font; font.pixelSize: 44; font.bold: true; color: root.c.text }
                            Text {
                                Layout.fillWidth: true
                                text: root.condition || (weatherProc.running ? "Fetching weather…" : "Offline")
                                font.family: root.fontUi; font.pixelSize: 13
                                color: root.c.subtext1
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        tint: root.c.blue
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 8
                            Chip { icon: "󰍹"; text: "Session"; tint: root.c.blue }
                            Item { implicitHeight: 2 }
                            Repeater {
                                model: root.sessions
                                ListRow {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    icon: "󰍹"
                                    title: modelData.name
                                    sub: modelData.exec.split(" ")[0].split("/").pop()
                                    tint: root.c.blue
                                    selected: index === root.sessIdx
                                    onClicked: root.sessIdx = index
                                }
                            }
                            Item { Layout.fillHeight: true }
                            Text {
                                Layout.fillWidth: true
                                text: "F2 switches session · Tab switches user"
                                font.family: root.fontUi; font.pixelSize: 11
                                color: root.c.subtext0
                                horizontalAlignment: Text.AlignHCenter
                                opacity: 0.8
                            }
                        }
                    }
                }

                // ── Centre: greeting · clock · avatar · password ────────────
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
                            text: root.greeting
                            tint: root.c.mauve
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 10
                            spacing: 10
                            Row {
                                readonly property int px: v.wide ? 104 : 84
                                Text { text: root.hour12(root.now); font.family: root.font; font.pixelSize: parent.px; font.bold: true; color: root.c.text }
                                Text { text: ":"; font.family: root.font; font.pixelSize: parent.px; font.bold: true; color: root.c.accent }
                                Text { text: Qt.formatTime(root.now, "mm"); font.family: root.font; font.pixelSize: parent.px; font.bold: true; color: root.c.text }
                            }
                            Chip {
                                visible: !root.cfg.clock24
                                Layout.alignment: Qt.AlignVCenter
                                Layout.topMargin: 14
                                text: root.ampm(root.now)
                                mono: true
                                tint: root.c.blue
                                implicitHeight: 30
                            }
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 8
                            Text { text: "󰸗"; font.family: root.font; font.pixelSize: 14; color: root.c.peach }
                            Text { text: Qt.formatDate(root.now, "dddd, d MMMM"); font.family: root.fontUi; font.pixelSize: 15; color: root.c.subtext1 }
                        }

                        // avatar with an accent ring (click: next user)
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 30
                            implicitWidth: 92; implicitHeight: 92
                            radius: 46
                            color: "transparent"
                            border.width: 2
                            border.color: Qt.alpha(root.c.accent, root.buffer.length > 0 || avMa.containsMouse ? 0.85 : 0.45)
                            Behavior on border.color { ColorAnimation { duration: 180 } }
                            Avatar { anchors.fill: parent; anchors.margins: 5; userName: root.user; letterSize: 36 }
                            MouseArea {
                                id: avMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: root.users.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: { root.nextUser(); v.forceActiveFocus(); }
                            }
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 10
                            text: root.realName
                            font.family: root.fontUi; font.pixelSize: 17; font.weight: Font.DemiBold
                            color: root.c.text
                        }

                        // password pill (always live: just type)
                        Item {
                            Layout.fillWidth: true
                            Layout.topMargin: 16
                            implicitHeight: 48
                            transform: Translate { id: shake }

                            Rectangle {
                                anchors.fill: parent
                                radius: 24
                                color: root.container
                                border.width: root.buffer.length > 0 || root.message ? 2 : 1
                                border.color: root.message && root.messageIsError ? Qt.alpha(root.c.red, 0.75)
                                    : root.buffer.length > 0 ? Qt.alpha(root.c.accent, 0.7) : root.outline
                                Behavior on border.color { ColorAnimation { duration: 200 } }
                            }
                            Text {
                                anchors.left: parent.left; anchors.leftMargin: 20
                                anchors.right: parent.right; anchors.rightMargin: 50
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.buffer.length === 0 || root.echo
                                text: root.echo && root.buffer.length > 0 ? root.buffer
                                    : root.checking ? "Signing in…" : root.prompt
                                elide: Text.ElideRight
                                font.family: root.fontUi; font.pixelSize: 13
                                color: root.echo && root.buffer.length > 0 ? root.c.text : root.c.subtext0
                            }
                            Row {
                                visible: !root.echo
                                anchors.left: parent.left; anchors.leftMargin: 20
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 7
                                Repeater {
                                    model: Math.min(root.buffer.length, 20)
                                    Rectangle {
                                        width: 9; height: 9; radius: 4.5
                                        color: root.c.accent
                                        scale: 0
                                        Component.onCompleted: scale = 1
                                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveOpen } }
                                    }
                                }
                            }
                            Rectangle {
                                anchors.right: parent.right; anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: 36; height: 36; radius: 18
                                visible: root.buffer.length > 0 || root.checking
                                color: Qt.alpha(root.c.accent, goMa.containsMouse ? 0.32 : 0.2)
                                border.width: 1
                                border.color: Qt.alpha(root.c.accent, 0.45)
                                Text {
                                    anchors.centerIn: parent
                                    text: root.checking ? "󰑐" : "󰁔"
                                    font.family: root.font; font.pixelSize: 16
                                    color: root.c.accent
                                    RotationAnimation on rotation { running: root.checking; loops: Animation.Infinite; from: 0; to: 360; duration: 800 }
                                }
                                MouseArea { id: goMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.submit() }
                            }
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 10
                            Layout.maximumWidth: 380
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: root.message || (root.demo ? "Preview · password “demo” · Esc to close" : "Enter to sign in")
                            font.family: root.fontUi; font.pixelSize: 11
                            font.weight: root.message ? Font.DemiBold : Font.Normal
                            color: root.message ? (root.messageIsError ? root.c.red : root.c.green) : root.c.subtext0
                        }

                        // sleep · restart · power (power asks once)
                        Row {
                            visible: root.cfg.showPower
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 26
                            spacing: 10
                            property bool confirm: false
                            TintButton { size: 40; icon: "󰤄"; tint: root.c.lavender; onClicked: root.runPower("suspend") }
                            TintButton { size: 40; icon: "󰑓"; tint: root.c.green; visible: parent.confirm; onClicked: root.runPower("reboot") }
                            TintButton { size: 40; icon: "⏻"; tint: root.c.red; visible: parent.confirm; onClicked: root.runPower("poweroff") }
                            TintButton { size: 40; icon: parent.confirm ? "󰅖" : "󰐥"; tint: root.c.red; onClicked: parent.confirm = !parent.confirm }
                        }
                    }
                }

                // ── Right: system · users ───────────────────────────────────
                ColumnLayout {
                    visible: v.wide
                    Layout.preferredWidth: 300
                    Layout.minimumWidth: 300
                    Layout.maximumWidth: 300
                    Layout.fillHeight: true
                    spacing: 14

                    Card {
                        visible: root.cfg.showSystem
                        Layout.fillWidth: true
                        Layout.preferredHeight: 150
                        tint: root.c.green
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 10
                            Chip { icon: "󰌢"; text: root.hostName || "System"; tint: root.c.green }
                            Item { Layout.fillHeight: true }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: root.hasBattery
                                spacing: 10
                                Text { text: root.charging ? "󰂄" : "󰁹"; font.family: root.font; font.pixelSize: 15; color: root.batPct <= 0.15 && !root.charging ? root.c.red : root.c.green }
                                SlimBar {
                                    Layout.fillWidth: true
                                    value: root.batPct
                                    tint: root.batPct <= 0.15 && !root.charging ? root.c.red : root.c.green
                                }
                                Text { text: Math.round(root.batPct * 100) + "%"; font.family: root.font; font.pixelSize: 12; color: root.c.subtext1 }
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Chip {
                                    icon: root.netType === "wifi" ? "󰖩" : root.netType === "ethernet" ? "󰈀" : "󰖪"
                                    text: root.netType ? (root.netName || "Connected") : "Offline"
                                    tint: root.c.sky
                                }
                            }
                        }
                    }

                    Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        tint: root.c.lavender
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 8
                            Chip { icon: "󰀎"; text: root.users.length === 1 ? "1 user" : root.users.length + " users"; tint: root.c.lavender }
                            Item { implicitHeight: 2 }
                            Repeater {
                                model: root.users
                                ListRow {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    avatarUser: modelData.name
                                    title: modelData.real || modelData.name
                                    sub: modelData.name
                                    tint: root.c.lavender
                                    selected: index === root.userIdx
                                    onClicked: { root.pickUser(index); v.forceActiveFocus(); }
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }
        }

        // narrow / minimal layout: the session as a pill under the panel
        Chip {
            visible: !v.wide && root.sessions.length > 0
            anchors { left: parent.left; bottom: parent.bottom; margins: 28 }
            icon: "󰍹"
            text: (root.session ? root.session.name : "") + (root.sessions.length > 1 ? "  ·  F2" : "")
            tint: root.c.blue
            interactive: root.sessions.length > 1
            implicitHeight: 32
            onClicked: { root.nextSession(); v.forceActiveFocus(); }
        }

        // wrong password: shake
        Connections {
            target: root
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
    }

    // ── Pieces (copies of the shell's components, on the greeter's palette) ─
    component Card: Rectangle {
        id: card
        property color tint: root.c.accent
        radius: 20
        color: root.container
        border.width: 1
        border.color: root.outline
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(card.tint, 0.10) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }

    component Chip: Rectangle {
        id: chip
        property string icon: ""
        property string text: ""
        property color tint: root.c.accent
        property bool interactive: false
        property bool mono: false
        signal clicked()
        implicitHeight: 26
        implicitWidth: chipRow.implicitWidth + 20
        radius: height / 2
        color: Qt.alpha(tint, chipMa.containsMouse ? 0.24 : 0.14)
        border.width: 1
        border.color: Qt.alpha(tint, 0.35)
        Behavior on color { ColorAnimation { duration: 180 } }
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5
            Text { visible: chip.icon !== ""; text: chip.icon; font.family: root.font; font.pixelSize: 12; color: chip.tint }
            Text { visible: chip.text !== ""; text: chip.text; font.family: chip.mono ? root.font : root.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold; color: chip.tint }
        }
        MouseArea {
            id: chipMa
            anchors.fill: parent
            enabled: chip.interactive
            hoverEnabled: chip.interactive
            cursorShape: chip.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: chip.clicked()
        }
    }

    component SlimBar: Rectangle {
        id: slim
        property real value: 0
        property color tint: root.c.accent
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
        }
    }

    component TintButton: Rectangle {
        id: tb
        property string icon
        property int size: 44
        property color tint: root.c.accent
        signal clicked()
        width: size
        height: size
        radius: size / 2
        color: Qt.alpha(tint, tbMa.containsMouse ? 0.26 : 0.14)
        border.width: 1
        border.color: Qt.alpha(tint, 0.38)
        scale: tbMa.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 120 } }
        Behavior on color { ColorAnimation { duration: 180 } }
        Text { anchors.centerIn: parent; text: tb.icon; font.family: root.font; font.pixelSize: tb.size * 0.38; color: tb.tint }
        MouseArea { id: tbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked() }
    }

    // Avatar: faces/<user> (synced from ~/.face), else AccountsService's icon, else the initial
    component Avatar: ClippingRectangle {
        id: av
        property string userName: ""
        property int letterSize: 16
        radius: width / 2
        color: Qt.alpha(root.c.accent, 0.18)
        property int attempt: 0
        onUserNameChanged: attempt = 0
        readonly property var sources: [root.dataDir + "/faces/" + userName, "/var/lib/AccountsService/icons/" + userName]
        Image {
            id: faceImg
            anchors.fill: parent
            source: av.userName && av.attempt < av.sources.length ? "file://" + av.sources[av.attempt] : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize.width: 180; sourceSize.height: 180
            onStatusChanged: if (status === Image.Error) av.attempt++
        }
        Text {
            anchors.centerIn: parent
            visible: faceImg.status !== Image.Ready
            text: av.userName ? av.userName.charAt(0).toUpperCase() : "?"
            font.family: root.font; font.pixelSize: av.letterSize; font.bold: true
            color: root.c.accent
        }
    }

    // A selectable row in the session / user cards
    component ListRow: Rectangle {
        id: lr
        property string icon: ""
        property string avatarUser: ""
        property string title: ""
        property string sub: ""
        property color tint: root.c.accent
        property bool selected: false
        signal clicked()
        implicitHeight: 52
        radius: 14
        color: selected ? Qt.alpha(tint, 0.16) : lrMa.containsMouse ? root.containerHigh : root.container
        border.width: 1
        border.color: selected ? Qt.alpha(tint, 0.45) : root.outline
        Behavior on color { ColorAnimation { duration: 180 } }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10; anchors.rightMargin: 12
            spacing: 10
            Item {
                implicitWidth: 30; implicitHeight: 30
                Avatar { anchors.fill: parent; visible: lr.avatarUser !== ""; userName: lr.avatarUser; letterSize: 13 }
                Rectangle {
                    anchors.fill: parent; visible: lr.avatarUser === ""; radius: 9
                    color: Qt.alpha(lr.tint, 0.16)
                    Text { anchors.centerIn: parent; text: lr.icon; font.family: root.font; font.pixelSize: 14; color: lr.tint }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text { Layout.fillWidth: true; text: lr.title; font.family: root.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.c.text; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; visible: lr.sub !== ""; text: lr.sub; font.family: root.fontUi; font.pixelSize: 10; color: root.c.subtext0; elide: Text.ElideRight }
            }
            Text { visible: lr.selected; text: "󰄬"; font.family: root.font; font.pixelSize: 14; color: lr.tint }
        }
        MouseArea { id: lrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lr.clicked() }
    }
}
