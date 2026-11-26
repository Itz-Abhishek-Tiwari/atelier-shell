import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd
import qs.config
import qs.services
import qs.modules.lock

// Atelier login screen: a Quickshell greeter for greetd that looks exactly like your lock
// screen. It loads the SAME style files (modules/lock → the shell's quickshell/modules/lock):
// Atelier or one of the phone styles, whichever Settings → Lock screen uses, with the
// same options. A small pill in the top-left corner picks the person and the desktop session.
//
//   greetd -> cage -> quickshell -p /etc/greetd/atelier-greeter/shell.qml -> session.sh -> session
//
// Self-contained on purpose: at login this runs as the `greeter` system user, so it cannot read
// your $HOME or the main shell. config/ and services/ here are small stand-ins for the shell's
// Atelier, Settings, Wallpaper… fed from /var/lib/atelier-greeter, which
// quickshell/scripts/greeter-sync.sh fills (Settings → Login screen runs it for you).
//
// Preview without touching your login (demo mode, password "demo", Esc closes):
//     greeter/install.sh --demo
ShellRoot {
    id: root

    readonly property bool demo: !Greetd.available

    // ── people and desktop sessions ─────────────────────────────────────────
    property var users: []        // [{name, real}]
    property var sessions: []     // [{name, exec, desktop}]
    property int userIdx: 0
    property int sessIdx: 0
    readonly property string user: users.length ? users[userIdx].name : ""
    readonly property var session: sessions.length ? sessions[sessIdx] : null
    onUserChanged: { GreeterData.user = user; GreeterData.realName = users.length ? (users[userIdx].real || user) : ""; }

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
                GreeterData.user = root.user;
                GreeterData.realName = root.users.length ? (root.users[root.userIdx].real || root.user) : "";
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
        greeterAuth.reset();
    }
    function nextUser() { if (users.length > 1) pickUser((userIdx + 1) % users.length); }
    function nextSession() { if (sessions.length > 1) sessIdx = (sessIdx + 1) % sessions.length; }

    // ── the lock styles' host ("lockRoot"), with greetd instead of PAM ─────
    // Same contract as quickshell/modules/lock/LockScreen.qml, so the styles can't tell the
    // difference: they type into `buffer`, call submit(), and play their exit when `unlocking`.
    QtObject {
        id: greeterAuth
        readonly property bool active: true
        readonly property bool previewing: false
        property bool authMode: false
        property string buffer: ""
        property bool checking: false
        property string message: ""
        property int failCount: 0
        property bool unlocking: false
        property string weather: ""
        property bool answered: false
        signal failed()
        signal shotTaken(string path)
        signal shotFailed(string error)

        function screenshot(output) { shotFailed("Screenshots aren't available before you sign in"); }
        function reset() { buffer = ""; message = ""; checking = false; answered = false; }

        function submit() {
            if (checking || unlocking || !root.user || buffer.length === 0) return;
            message = "";
            checking = true;
            if (root.demo) { demoTimer.start(); return; }
            if (Greetd.state === GreetdState.Inactive) {
                answered = false;
                Greetd.createSession(root.user);
            } else {
                answered = true;
                Greetd.respond(buffer);
                buffer = "";
            }
        }
        function fail(msg) {
            checking = false;
            answered = false;
            buffer = "";
            failCount++;
            message = msg || "Incorrect password";
            failed();
        }
    }
    Timer {
        id: demoTimer
        interval: 700
        onTriggered: {
            if (greeterAuth.buffer === "demo") { greeterAuth.checking = false; greeterAuth.buffer = ""; greeterAuth.unlocking = true; demoDone.start(); }
            else greeterAuth.fail("Incorrect password (the demo password is “demo”)");
        }
    }
    Timer { id: demoDone; interval: 1600; onTriggered: { greeterAuth.unlocking = false; greeterAuth.authMode = false; } }

    Connections {
        target: Greetd
        function onAuthMessage(msg, error, responseRequired, echoResponse) {
            if (responseRequired) {
                if (!greeterAuth.answered && greeterAuth.buffer.length > 0) {
                    greeterAuth.answered = true;
                    Greetd.respond(greeterAuth.buffer);
                    greeterAuth.buffer = "";
                } else {
                    // a further question (a second factor…): show it and wait for the answer
                    greeterAuth.checking = false;
                    greeterAuth.message = msg.replace(/:\s*$/, "") || "Password";
                }
            } else {
                greeterAuth.message = msg;
            }
        }
        function onAuthFailure(msg) { Greetd.cancelSession(); greeterAuth.fail(msg); }
        function onReadyToLaunch() {
            root.saveLast();
            greeterAuth.checking = false;
            greeterAuth.message = "";
            greeterAuth.failCount = 0;
            greeterAuth.unlocking = true;          // the style plays its unlock animation
            launchTimer.start();
        }
        function onError(e) { greeterAuth.fail(e); }
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

    // ── weather for the styles that show it (wttr.in) ──
    Process {
        id: weatherProc
        running: true
        command: ["sh", "-c", "for i in 1 2 3 4 5; do w=$(curl -s --max-time 4 \"wttr.in/$(printf '%s' \"$1\" | sed 's/ /+/g')?$2&format=%t+%C\" 2>/dev/null); case \"$w\" in *°*) printf '%s' \"$w\"; exit 0;; esac; sleep 3; done",
            "sh", Settings.widgets.weatherLocation || "", Settings.widgets.weatherUnits === "imperial" ? "u" : "m"]
        stdout: StdioCollector {
            onStreamFinished: {
                greeterAuth.weather = text.trim().length < 40 ? text.trim() : "";
                Weather.line = greeterAuth.weather;
            }
        }
    }

    // ── the style in use on your lock screen ─────────────────────────────────
    readonly property var phoneStyles: ["cupertino", "hyper", "harmony", "oxygen", "material", "dot", "terminal", "analog", "aurora", "poster", "flip", "split", "hud"]
    readonly property string style: Settings.lock.theme
    Component { id: atelierUi; LockContent { lockRoot: greeterAuth } }
    Component { id: phoneUi; PhoneLock { lockRoot: greeterAuth } }
    function uiFor(t) { return phoneStyles.indexOf(t) >= 0 ? phoneUi : atelierUi; }

    // ═══ Windows ═════════════════════════════════════════════════════════════
    // Real login: one kiosk window in cage (cage makes it fullscreen; decorations are off
    // via QT_WAYLAND_DISABLE_WINDOWDECORATION in /etc/greetd/config.toml).
    LazyLoader {
        active: !root.demo
        FloatingWindow {
            id: kiosk
            title: "Atelier Login"
            color: "black"
            LoginView { anchors.fill: parent; screen: kiosk.screen }
        }
    }
    // Preview inside Hyprland (no greetd): a fullscreen overlay, Esc closes it.
    LazyLoader {
        active: root.demo
        PanelWindow {
            id: previewWin
            anchors { top: true; bottom: true; left: true; right: true }
            color: "black"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            // ATELIER_GREETER_TEST=1: don't take the keyboard (for screenshots while you work)
            WlrLayershell.keyboardFocus: Quickshell.env("ATELIER_GREETER_TEST") ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell-greeter-preview"
            LoginView { anchors.fill: parent; screen: previewWin.screen }
        }
    }

    component LoginView: Item {
        id: v
        property var screen: null

        Loader {
            id: ui
            anchors.fill: parent
            focus: true
            sourceComponent: root.uiFor(root.style)
            onLoaded: {
                item.screen = v.screen;
                if (item.variant !== undefined) item.variant = Qt.binding(() => root.style);
                item.forceActiveFocus();
            }
        }
        // the style couldn't load (a broken copy): a plain sign-in so nobody is ever locked out
        FallbackLogin { anchors.fill: parent; visible: ui.status === Loader.Error }

        // F1 = next person · F2 = next session · Esc closes the demo
        Shortcut { sequence: "F1"; onActivated: root.nextUser() }
        Shortcut { sequence: "F2"; onActivated: root.nextSession() }
        Shortcut { sequence: "Esc"; enabled: root.demo; onActivated: Qt.quit() }

        // ── who and what: a quiet pill in the top-left corner ────────────────
        Row {
            id: picker
            visible: !greeterAuth.unlocking && (root.users.length > 1 || root.sessions.length > 1 || root.demo)
            x: 28; y: 24
            spacing: 8
            opacity: greeterAuth.unlocking ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 250 } }
            PickChip {
                visible: root.users.length > 0
                icon: "󰀄"
                label: root.users.length ? (root.users[root.userIdx].real || root.user) : ""
                more: root.users.length > 1
                hint: "F1"
                onClicked: root.nextUser()
            }
            PickChip {
                visible: !!root.session
                icon: "󰍹"
                label: root.session ? root.session.name : ""
                more: root.sessions.length > 1
                hint: "F2"
                onClicked: root.nextSession()
            }
            PickChip { visible: root.demo; icon: "󰈈"; label: "Preview · password “demo” · Esc closes"; more: false }
        }
    }

    // a glass pill like the lock styles' own buttons
    component PickChip: Rectangle {
        id: pc
        property string icon
        property string label
        property string hint: ""
        property bool more: false
        signal clicked()
        height: 34
        width: pcRow.implicitWidth + 28
        radius: 17
        color: pcMa.containsMouse && more ? Qt.alpha(Atelier.crust, 0.62) : Qt.alpha(Atelier.crust, 0.45)
        border.width: 1
        border.color: Qt.alpha("white", 0.12)
        Behavior on color { ColorAnimation { duration: 150 } }
        Row {
            id: pcRow
            anchors.centerIn: parent
            spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter; text: pc.icon; font.family: Atelier.font; font.pixelSize: 14; color: "white" }
            Text { anchors.verticalCenter: parent.verticalCenter; text: pc.label; font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: Font.Medium; color: "white" }
            Text { anchors.verticalCenter: parent.verticalCenter; visible: pc.more; text: "󰅀"; font.family: Atelier.font; font.pixelSize: 12; color: Qt.alpha("white", 0.7) }
            Text { anchors.verticalCenter: parent.verticalCenter; visible: pc.more && pc.hint !== ""; text: pc.hint
                   font.family: Atelier.font; font.pixelSize: 10; color: Qt.alpha("white", 0.45) }
        }
        MouseArea { id: pcMa; anchors.fill: parent; enabled: pc.more; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pc.clicked() }
    }

    // last resort if a style file fails to load: wallpaper, a password field, nothing else
    component FallbackLogin: Item {
        Image { anchors.fill: parent; source: "file://" + Wallpaper.current; fillMode: Image.PreserveAspectCrop; asynchronous: true }
        Rectangle { anchors.fill: parent; color: Qt.alpha("black", 0.45) }
        Column {
            anchors.centerIn: parent
            spacing: 14
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Sign in as " + root.user; color: "white"; font.family: Atelier.fontUi; font.pixelSize: 18 }
            Rectangle {
                width: 320; height: 46; radius: 23
                color: Qt.alpha("white", 0.14); border.width: 1; border.color: Qt.alpha("white", 0.3)
                TextInput {
                    id: fb
                    anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18
                    verticalAlignment: Text.AlignVCenter
                    echoMode: TextInput.Password
                    color: "white"; font.pixelSize: 16
                    focus: parent.parent.parent.visible
                    onTextChanged: greeterAuth.buffer = text
                    onAccepted: { greeterAuth.submit(); text = ""; }
                }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: greeterAuth.message; color: "white"; font.family: Atelier.fontUi; font.pixelSize: 13 }
        }
    }
}
