import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.config
import qs.services

// Lock screen (one glass panel, Caelestia-style; the UI is LockContent.qml).
//   lock():    real Wayland session lock (WlSessionLock) on every screen
//   preview(): the same UI in a normal window (no lock), for trying out the design
// Passwords are checked by PAM using /etc/pam.d/hyprlock (= your normal login rules).
// There is deliberately no IPC "unlock".
// Safety net: Hyprland has misc.allow_session_lock_restore = true, so if the shell ever
// dies while locked you can switch to a TTY and run `hyprlock` to take over and unlock.
Scope {
    id: root

    property bool locked: false
    property bool previewing: false
    readonly property bool active: locked || previewing
    // locked by us OR by a qylock theme process (Settings → Lock screen)
    readonly property bool isLocked: locked || themeLock.running

    // shared state for all surfaces (multi-monitor)
    property bool authMode: false          // passcode view shown
    property string buffer: ""
    property bool checking: false
    property string message: ""
    property int failCount: 0
    property bool unlocking: false         // playing the unlock animation

    signal failed()

    // ── Screenshots on the lock screen ──────────────────────────────────────
    // Hyprland's Print binds don't run while locked (keys go to the lock surface), so the lock
    // UIs call this on Print / their camera button. grim captures what's on screen, which while
    // locked is only the lock itself. Saved like the normal tool (~/Pictures/Screenshots, with
    // "_lock") and copied to the clipboard.
    signal shotTaken(string path)
    signal shotFailed(string error)
    function screenshot(output: string): void {
        if (shotProc.running) return;
        shotProc.command = ["sh", "-c",
            'd="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"; mkdir -p "$d" || exit 1; '
            + 'f="$d/Screenshot_$(date +%Y-%m-%d_%H-%M-%S)_lock.png"; '
            + 'if [ -n "$1" ]; then grim -o "$1" "$f"; else grim "$f"; fi || exit 2; '
            + 'wl-copy --type image/png < "$f"; echo "$f"', "sh", output || ""];
        shotProc.running = true;
    }
    Process {
        id: shotProc
        stdout: StdioCollector { id: shotOut }
        stderr: StdioCollector { id: shotErr }
        onExited: (code) => {
            const f = shotOut.text.trim();
            if (code === 0 && f) root.shotTaken(f);
            else root.shotFailed(code === 2 ? "Screenshot failed: " + (shotErr.text.trim().split("\n").pop() || "grim error") : "Screenshot failed");
        }
    }

    // weather fetched ahead of time (and every 20 min), so the lock shows it from the first
    // frame instead of the date line jumping when it arrives
    property string weather: ""
    Process {
        id: weatherProc
        running: true
        command: [Quickshell.shellDir + "/scripts/weather.sh", Settings.widgets.weatherLocation, Settings.widgets.weatherUnits]
        stdout: StdioCollector { onStreamFinished: { const t = text.trim(); if (t) root.weather = t; } }
    }
    Timer { interval: 20 * 60 * 1000; repeat: true; running: true; onTriggered: weatherProc.running = true }

    // built-in looks: "depth" = DepthLock.qml (Samsung-style), anything else = LockContent.qml
    readonly property bool depthStyle: Settings.lock.theme === "depth"
    // touching DepthWall here keeps it alive, so it cuts out each new wallpaper ahead of time
    readonly property bool depthReady: depthStyle && DepthWall.ok
    Component { id: glassUi; LockContent { lockRoot: root } }
    Component { id: depthUi; DepthLock { lockRoot: root } }

    function lock() {
        if (locked || themeLock.running) return;
        const theme = Settings.lock.theme;
        if (theme && theme !== "atelier" && theme !== "depth") {
            // a qylock theme: its own lock process (scripts/qylock.py). If it fails or crashes
            // (non-zero exit), our own lock takes over at once: Hyprland allows a new locker to
            // replace a dead one (misc.allow_session_lock_restore), so the session is never left
            // in the red "locked but nothing drawn" state.
            themeLock.command = [Quickshell.shellDir + "/scripts/qylock.py", "lock", theme];
            themeLock.running = true;
            return;
        }
        resetState();
        locked = true;
    }
    Process {
        id: themeLock
        onExited: (code) => {
            if (code !== 0) {
                console.warn("LockScreen: qylock theme exited with", code, "- falling back to the Atelier lock");
                root.resetState();
                root.locked = true;
            }
        }
    }
    function preview() {
        resetState();
        previewing = true;
    }
    // preview helpers (only ever affect the preview window, never a real lock)
    function previewAuth() { preview(); authMode = true; }
    function stopPreview() { if (previewing) { previewing = false; editing = false; resetState(); } }
    // the Depth lock's editor: the live preview with a customise sheet (never a real lock)
    property bool editing: false
    function edit() { resetState(); editing = true; previewing = true; }

    function resetState() {
        authMode = false;
        buffer = "";
        message = "";
        checking = false;
        unlocking = false;
        if (pam.active) pam.abort();
    }

    function submit() {
        if (checking || buffer.length === 0) return;
        checking = true;
        message = "";
        if (!pam.active) pam.start();
    }

    function finishUnlock() {
        unlocking = true;
        unlockTimer.start();
    }
    Timer {
        id: unlockTimer
        interval: 420
        onTriggered: {
            root.locked = false;
            root.previewing = false;
            root.resetState();
        }
    }

    PamContext {
        id: pam
        config: "hyprlock"
        configDirectory: "/etc/pam.d"

        onPamMessage: {
            if (responseRequired) respond(root.buffer);
            else if (messageIsError) root.message = message;
        }
        onCompleted: (result) => {
            root.checking = false;
            if (result === PamResult.Success) {
                root.failCount = 0;
                root.buffer = "";
                root.finishUnlock();
            } else {
                root.failCount++;
                root.buffer = "";
                root.message = result === PamResult.MaxTries ? "Too many attempts — wait a moment" : "Incorrect password";
                root.failed();
            }
        }
        onError: (err) => {
            root.checking = false;
            root.buffer = "";
            root.message = "Authentication error";
            root.failed();
        }
    }

    // ── Real session lock ───────────────────────────────────────────────────
    WlSessionLock {
        id: sessionLock
        locked: root.locked

        WlSessionLockSurface {
            id: surface
            color: "black"
            Loader {
                anchors.fill: parent
                focus: true
                sourceComponent: root.depthStyle ? depthUi : glassUi
                onLoaded: item.screen = surface.screen
            }
        }
    }

    // ── Preview (not a lock; Esc or unlocking closes it) ────────────────────
    PanelWindow {
        visible: root.previewing
        anchors { top: true; bottom: true; left: true; right: true }
        color: "black"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: root.previewing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-lock-preview"
        Loader {
            anchors.fill: parent
            focus: true
            active: root.previewing
            sourceComponent: root.depthStyle || root.editing ? depthUi : glassUi
            onLoaded: {
                item.isPreview = true;
                if (root.editing) item.editing = Qt.binding(() => root.editing);
            }
        }
    }
}
