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
//   saver   battery saver: opaque windows, no blur / shadows / animations / dimming, the
//           power-saver profile, desktop widgets and the shell's shadows are not drawn. The
//           biggest wins for battery life; kept across logins.
//   game    maximum performance: no blur / shadows / animations, opaque windows, tearing
//           allowed, performance power profile, Do Not Disturb, screen stays awake, desktop
//           widgets and the shell's shadows are not drawn
//
// The compositor half is hypr/atelier-mode.lua (applied live with `hyprctl eval`).
// With Settings > Behavior > "Game mode automatically", opening a game (Steam, gamescope,
// Lutris, Heroic, ...) switches to Game mode and closing it switches back.
//
//   qs ipc call mode set game|dev|saver|normal     qs ipc call mode cycle|toggleGame|toggleDev|toggleSaver|get
Singleton {
    id: root

    property string mode: "normal"                       // normal | game | dev | saver
    readonly property bool game: mode === "game"
    readonly property bool dev: mode === "dev"
    readonly property bool saver: mode === "saver"
    readonly property string label: mode === "game" ? "Game mode" : mode === "dev" ? "Programming mode" : mode === "saver" ? "Battery saver" : "Normal"
    readonly property var modes: ["normal", "dev", "game", "saver"]
    // what the mode pickers (Settings → Modes, control center) show for each mode.
    // cost: how heavy it is on the GPU, 1 (lightest) to 5, as a hint, not a measurement
    readonly property var info: [
        { id: "normal",   label: "Normal",        short: "Normal", icon: "󰖲", blurb: "Your own look",             cost: 3, tint: Atelier.green },
        { id: "dev",      label: "Programming",   short: "Coding", icon: "󰅩", blurb: "Crisp text, snappy",        cost: 2, tint: Atelier.sapphire },
        { id: "game",     label: "Game",          short: "Game",   icon: "󰊴", blurb: "Maximum performance",       cost: 1, tint: Atelier.peach },
        { id: "saver",    label: "Battery saver", short: "Saver",  icon: "󰌪", blurb: "Longest battery life",      cost: 1, tint: Atelier.yellow }
    ]
    function infoOf(id) { return info.find(i => i.id === id) || info[0]; }
    // the shell side (Settings → Modes): the desktop widget, shell shadows / glass
    readonly property bool hideWidgets: (game && Settings.modes.gameHideWidgets) || (saver && Settings.modes.saverHideWidgets)
    readonly property bool lean: (game && Settings.modes.gameLeanShell) || (saver && Settings.modes.saverLeanShell)
    // a mode's option from Settings → Modes, e.g. opt("dev", "Power")
    function opt(m, key) { return Settings.modes[m + key]; }

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
    // plus your own (Settings → Modes → "Also counts as a game"), compared case-insensitively
    readonly property var extraGames: (Settings.modes.gameApps || "").split(",").map(x => x.trim().toLowerCase()).filter(x => x !== "")
    function isGameClass(cls) { return gameClass.test(cls) || extraGames.indexOf(cls.toLowerCase()) >= 0; }

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
    function toggleSaver() { set(root.mode === "saver" ? "normal" : "saver"); }

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
        root._gtkAnimations(m !== "saver");          // Saver: apps (GTK) stop animating too
        root._applyBoost();

        // shell + system
        if (m === "normal") {
            Notifs.dnd = root._savedDnd;
            Atelier.caffeine = root._savedCaffeine;
            root._setProfile(root._normalProfile());
            root._hasSaved = false;
        } else {
            root._applyShell(m);
        }
        root._persist();
        root.switched(m, auto);
    }

    // the shell / system half of Programming, Game and Saver mode, from Settings → Modes
    function _applyShell(m) {
        Atelier.caffeine = opt(m, "Caffeine") ? true : root._savedCaffeine;
        Notifs.dnd = opt(m, "Dnd") ? true : root._savedDnd;
        const p = opt(m, "Power");
        if (p === "unchanged") root._setProfile(root._savedProfile);
        else root._setProfile(m === "dev" && p === "performance" && UPower.onBattery ? "balanced" : p);
    }
    // change a setting while in that mode: apply it now (the compositor half is re-applied by
    // Settings' own live apply, see atelier_mode in atelier-mode.lua)
    readonly property string _modeKey: mode === "normal" ? "" : mode + ":" + opt(mode, "Caffeine") + opt(mode, "Dnd") + opt(mode, "Power")
    on_ModeKeyChanged: if (mode !== "normal" && _hasSaved) _applyShell(mode)

    // The desktop-wide "animations" switch GTK apps follow (Nautilus, dialogs, …). Saver turns it
    // off and remembers the old value in ~/.config/atelier/gtk-animations, so leaving Saver (or a
    // shell restart in between) puts it back exactly as it was.
    function _gtkAnimations(on) {
        const f = '"$HOME/.config/atelier/gtk-animations"';
        const k = "org.gnome.desktop.interface enable-animations";
        gtkAnim.command = ["sh", "-c", on
            ? 'f=' + f + '; if [ -f "$f" ]; then gsettings set ' + k + ' "$(cat "$f")"; rm -f "$f"; fi'
            : 'f=' + f + '; [ -f "$f" ] || gsettings get ' + k + ' > "$f"; gsettings set ' + k + ' false'];
        gtkAnim.running = true;
    }
    Process { id: gtkAnim }

    // CPU turbo boost (written through /sys/devices/system/cpu/cpufreq/boost, made group-writable
    // by system/power/battery-tweaks.sh; a no-op without it). Game: on, even on battery. Saver:
    // off. Normal / Programming: on with the charger, off on battery (the udev rule does the same
    // at every plug / unplug; the short delay below lets it run first so the mode has the last word).
    function _applyBoost() {
        const on = root.mode === "game" ? true : root.mode === "saver" ? false : !UPower.onBattery;
        boostSet.command = ["sh", "-c", 'f=/sys/devices/system/cpu/cpufreq/boost; [ -w "$f" ] && echo ' + (on ? 1 : 0) + ' > "$f"; true'];
        boostSet.running = true;
    }
    Process { id: boostSet }
    Timer { id: boostLater; interval: 600; onTriggered: root._applyBoost() }

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

    // Startup: make Hyprland match the shell. Programming and Saver mode are kept across logins; Game mode
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
        if (m === "dev" || m === "saver" || (m === "game" && o.session === root.session)) {
            root.mode = m;
            reapply.restart();   // deferred: right at startup the process can't run yet
            if (root.opt(m, "Caffeine")) Atelier.caffeine = true;   // caffeine doesn't survive a restart
            if (root.opt(m, "Dnd")) Notifs.dnd = true;
            console.info("Perf: restored", m, "after shell start");
        } else {
            if (root._hasSaved) {
                Notifs.dnd = root._savedDnd;
                Atelier.caffeine = root._savedCaffeine;
                root._setProfile(root._normalProfile());
                root._hasSaved = false;
            }
            root.mode = "normal";
            reapply.restart();
        }
        root._persist();
        policyAtStart.restart();
    }

    // The profile Normal mode goes back to. A saved "power-saver" is almost always left over from
    // Saver mode (or a stale save) and makes Normal stutter, so Normal never inherits it.
    function _normalProfile() { return root._savedProfile === "power-saver" ? "balanced" : root._savedProfile; }

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
        if (root.mode === "game" || root.mode === "saver") return;   // these keep their own profile
        if (root.mode === "dev") { if (opt("dev", "Power") === "performance") root._setProfile("performance"); return; }   // → balanced on battery
        if (UPower.onBattery) powerCheck.running = true;       // demote a manual/stale "performance"
        else if (root._acProfile) { const p = root._acProfile; root._acProfile = ""; root._setProfile(p); }
    }
    Connections {
        target: UPower
        function onOnBatteryChanged() { root._powerPolicy(); boostLater.restart(); }
    }
    Timer { id: policyAtStart; interval: 1500; onTriggered: { root._powerPolicy(); root._applyBoost(); } }
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
            const isGame = root.isGameClass(cls);
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
