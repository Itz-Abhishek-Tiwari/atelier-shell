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
    readonly property bool isLocked: locked

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

    // the shared Weather service fetches ahead of time, so the lock shows it from the first frame
    readonly property string weather: Weather.line

    // built-in looks: a phone style = PhoneLock.qml, "atelier" = LockContent.qml (also the
    // fallback for an unknown id, e.g. the removed "depth")
    readonly property var phoneStyles: ["cupertino", "hyper", "harmony", "oxygen", "material", "dot", "terminal", "analog", "aurora", "poster", "flip", "split", "hud"]
    function isPlugin(t) { return !!Plugins.lockFile(t); }
    function isBuiltin(t) { return !t || t === "atelier" || phoneStyles.indexOf(t) >= 0 || isPlugin(t); }
    // the preview can show another style than the one in use (Settings → a card's Preview)
    property string previewTheme: ""
    readonly property string lockTheme: Settings.lock.theme
    readonly property string shownTheme: previewing && previewTheme ? previewTheme : lockTheme
    Component { id: glassUi; LockContent { lockRoot: root } }
    Component { id: phoneUi; PhoneLock { lockRoot: root } }
    function uiFor(t) { return phoneStyles.indexOf(t) >= 0 || isPlugin(t) ? phoneUi : glassUi; }

    function lock() {
        if (locked) return;
        resetState();
        locked = true;
    }
    function preview() {
        resetState();
        previewing = true;
    }
    // preview a built-in style without switching to it
    function previewStyle(t: string): void {
        if (!isBuiltin(t)) return;
        previewTheme = t;
        preview();
    }
    onPreviewingChanged: if (!previewing) previewTheme = ""
    // preview helpers (only ever affect the preview window, never a real lock)
    function previewAuth() { preview(); authMode = true; }
    function stopPreview() { if (previewing) { previewing = false; resetState(); } }

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
                sourceComponent: root.uiFor(root.lockTheme)
                onLoaded: {
                    item.screen = surface.screen;
                    if (item.variant !== undefined) item.variant = Qt.binding(() => root.lockTheme);
                }
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
            sourceComponent: root.uiFor(root.shownTheme)
            onLoaded: {
                item.isPreview = true;
                if (item.variant !== undefined) item.variant = Qt.binding(() => root.shownTheme);
            }
        }
    }
}
