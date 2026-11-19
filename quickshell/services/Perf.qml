pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs.config

// Performance modes. The UI keeps the same look; the work behind it changes.
//
//   normal  your own look and settings
//   dev     programming: opaque windows (crisp text, no blur behind them), 1-pass blur, faster
//           window animations, no dimming, performance power profile (balanced on battery),
//           screen stays awake
//   game    maximum performance: no blur / shadows / animations, opaque windows, tearing
//           allowed, performance power profile, Do Not Disturb, screen stays awake, desktop
//           widgets and the shell's shadows are not drawn
//
// The compositor half is hypr/atelier-mode.lua (applied live with `hyprctl eval`).
// With Settings > Behavior > "Game mode automatically", opening a game (Steam, gamescope,
// Lutris, Heroic, ...) switches to Game mode and closing it switches back.
//
//   qs ipc call mode set game|dev|normal     qs ipc call mode cycle|toggleGame|toggleDev|get
Singleton {
    id: root

    property string mode: "normal"                       // normal | game | dev
    readonly property bool game: mode === "game"
    readonly property bool dev: mode === "dev"
    readonly property string label: mode === "game" ? "Game mode" : mode === "dev" ? "Programming mode" : "Normal"
    readonly property var modes: ["normal", "dev", "game"]

    signal switched(string mode, bool automatic)

    // ── what we restore when going back to normal ───────────────────────────
    property bool _hasSaved: false
    property bool _savedDnd: false
    property bool _savedCaffeine: false
    property string _savedProfile: "balanced"
    property string _pending: ""
    property bool _pendingAuto: false

    // automatic game detection
    property bool autoActive: false
    property string beforeAuto: "normal"
    readonly property var gameClass: /^(steam_app_.+|gamescope|lutris|heroic.*|bottles|prismlauncher|minecraft.*|cs2|dota2|portal2|factorio|terraria|stardew.*|hollow_knight.*)$/i

    function set(m, automatic) {
        if (root.modes.indexOf(m) < 0) return;
        if (!automatic) root.autoActive = false;
        if (m === root.mode) return;
        root._pending = m;
        root._pendingAuto = !!automatic;
        if (root.mode === "normal" && !root._hasSaved) {
            // leaving normal: remember the power profile first (async), then continue
            profileGet.running = true;
        } else {
            root._enter();
        }
    }
    function cycle() { set(root.modes[(root.modes.indexOf(root.mode) + 1) % root.modes.length]); }
    function toggleGame() { set(root.mode === "game" ? "normal" : "game"); }
    function toggleDev() { set(root.mode === "dev" ? "normal" : "dev"); }

    function _enter() {
        const m = root._pending;
        const auto = root._pendingAuto;
        if (root.mode === "normal" && !root._hasSaved) {
            root._savedDnd = Notifs.dnd;
            root._savedCaffeine = Atelier.caffeine;
            root._hasSaved = true;
        }
        console.info("Perf: mode ->", m, auto ? "(automatic: game window focused)" : "(manual)");
        root.mode = m;

        root._applyHypr(m);

        // shell + system
        if (m === "normal") {
            Notifs.dnd = root._savedDnd;
            Atelier.caffeine = root._savedCaffeine;
            root._setProfile(root._savedProfile);
            root._hasSaved = false;
        } else {
            Atelier.caffeine = true;
            Notifs.dnd = (m === "game") ? true : root._savedDnd;
            root._setProfile(m === "dev" && UPower.onBattery ? "balanced" : "performance");
        }
        root._persist();
        root.switched(m, auto);
    }

    function _applyHypr(m) {
        hypr.command = ["hyprctl", "eval", 'dofile(os.getenv("HOME") .. "/.config/hypr/atelier-mode.lua")("' + m + '")'];
        hypr.running = true;
    }

    // What survives a shell restart: the mode, the session it belongs to, and what to restore.
    readonly property string session: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    function _persist() {
        store.setText(JSON.stringify({
            mode: root.mode,
            session: root.session,
            saved: root._hasSaved ? { dnd: root._savedDnd, caffeine: root._savedCaffeine, profile: root._savedProfile } : null
        }));
    }

    // Startup: make Hyprland match the shell. Programming mode is kept across logins; Game mode
    // only within the same Hyprland session (a shell restart mid-game stays in Game mode, a new
    // login goes back to Normal and undoes Game mode's side effects).
    function _restore(raw) {
        let o = null;
        try { o = JSON.parse(raw); } catch (e) { o = { mode: raw === "dev" ? "dev" : "normal", saved: null }; }
        if (o && o.saved) {
            root._savedDnd = !!o.saved.dnd;
            root._savedCaffeine = !!o.saved.caffeine;
            root._savedProfile = o.saved.profile || "balanced";
            root._hasSaved = true;
        }
        const m = o ? o.mode : "normal";
        if (m === "dev" || (m === "game" && o.session === root.session)) {
            root.mode = m;
            reapply.restart();   // deferred: right at startup the process can't run yet
            Atelier.caffeine = true;               // caffeine doesn't survive a restart; the mode wants it
            if (m === "game") Notifs.dnd = true;
            console.info("Perf: restored", m, "after shell start");
        } else {
            if (root._hasSaved) {
                Notifs.dnd = root._savedDnd;
                Atelier.caffeine = root._savedCaffeine;
                root._setProfile(root._savedProfile);
                root._hasSaved = false;
            }
            root.mode = "normal";
            reapply.restart();
        }
        root._persist();
        policyAtStart.restart();
    }

    function _setProfile(p) {
        // Battery policy: outside Game mode, "performance" only runs on AC. On battery it becomes
        // "balanced" and comes back when the charger is plugged in (measured: performance on
        // battery held high clocks at idle, Tctl ~66 °C).
        if (p === "performance" && root.mode !== "game" && UPower.onBattery) {
            root._acProfile = p;
            p = "balanced";
        }
        profileSet.command = ["powerprofilesctl", "set", p];
        profileSet.running = true;
    }

    // ── power profile follows the charger ───────────────────────────────────
    property string _acProfile: ""    // what to restore when AC returns
    function _powerPolicy() {
        if (root.mode === "game") return;                       // Game mode keeps performance
        if (root.mode === "dev") { root._setProfile("performance"); return; }   // → balanced on battery
        if (UPower.onBattery) powerCheck.running = true;       // demote a manual/stale "performance"
        else if (root._acProfile) { const p = root._acProfile; root._acProfile = ""; root._setProfile(p); }
    }
    Connections {
        target: UPower
        function onOnBatteryChanged() { root._powerPolicy(); }
    }
    Timer { id: policyAtStart; interval: 1500; onTriggered: root._powerPolicy() }
    Process {
        id: powerCheck
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() === "performance") root._setProfile("performance")
        }
    }

    Process { id: hypr }
    Timer { id: reapply; interval: 300; onTriggered: root._applyHypr(root.mode) }
    Process { id: profileSet }
    Process {
        id: profileGet
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p) root._savedProfile = p;
                root._enter();
            }
        }
    }

    // the saved mode (see _persist / _restore)
    FileView {
        id: store
        path: Quickshell.env("HOME") + "/.config/atelier/mode"
        printErrors: false
        onLoaded: root._restore(text().trim())
        onLoadFailed: root._restore("")
    }

    // ── automatic game detection ────────────────────────────────────────────
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                if (root.mode !== "normal") {
                    console.info("Perf: Hyprland config reloaded, re-applying", root.mode);
                    reapply.restart();
                }
                return;
            }
            if (event.name !== "activewindow") return;
            if (!Settings.behavior.autoGameMode) return;
            const cls = (event.data || "").split(",")[0];
            const isGame = root.gameClass.test(cls);
            if (isGame && root.mode !== "game") {
                console.info("Perf: game window detected:", cls);
                root.beforeAuto = root.mode;
                root.autoActive = true;
                root.set("game", true);
            } else if (!isGame && root.autoActive && cls !== "") {
                root.autoActive = false;
                root.set(root.beforeAuto, true);
            }
        }
    }
}
