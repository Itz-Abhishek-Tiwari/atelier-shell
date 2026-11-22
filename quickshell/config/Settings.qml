pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// All user-tweakable shell settings, persisted in ~/.config/atelier/settings.json.
// Edited by the Settings app (SettingsApp.qml) or by hand; the file is watched, so
// changes apply live. Every property has a default, so a missing/partial file is fine.
// Windows/Hyprland values are also written to ~/.config/hypr/atelier-settings.lua (read at
// login by hyprland.lua) and applied to the running compositor with `hyprctl eval`.
Singleton {
    id: root

    readonly property var general: adapter.general
    readonly property var appearance: adapter.appearance
    readonly property var bar: adapter.bar
    readonly property var widgets: adapter.widgets
    readonly property var notifications: adapter.notifications
    readonly property var windows: adapter.windows
    readonly property var behavior: adapter.behavior
    readonly property var lock: adapter.lock
    readonly property var greeter: adapter.greeter
    readonly property var recorder: adapter.recorder
    readonly property var phone: adapter.phone
    readonly property var airdrop: adapter.airdrop
    readonly property var modes: adapter.modes
    readonly property var controlCenter: adapter.controlCenter
    readonly property var emoji: adapter.emoji
    readonly property var nightLight: adapter.nightLight
    readonly property var input: adapter.input
    readonly property var displays: adapter.displays
    readonly property var keybinds: adapter.keybinds
    readonly property var battery: adapter.battery
    readonly property var idle: adapter.idle
    readonly property var updates: adapter.updates
    readonly property var drives: adapter.drives

    readonly property string path: Quickshell.env("HOME") + "/.config/atelier/settings.json"
    property bool ready: false                  // true once the file has been read (or created)

    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoaded: root.ready = true
        onLoadFailed: (err) => { writeAdapter(); root.ready = true; }   // first run: create the file with defaults

        adapter: JsonAdapter {
            id: adapter

            property JsonObject general: JsonObject {
                property string userName: ""            // "" = use the login name
                property bool clock24: false            // 24-hour clock (hides AM/PM chips)
                property real animSpeed: 1.0            // 0.5 = slower … 2 = faster
            }

            property JsonObject appearance: JsonObject {
                property int barWidth: 44               // left bar
                property int frame: 10                  // screen border thickness
                property int rounding: 24               // frame inner corners + drawers
                property real glass: 0.92               // opacity of bar/drawer surfaces
                property string barPosition: "left"     // left | right | top | bottom
                property bool linkRounding: true        // windows follow the shell's roundness (concentric)
                property string wallTransition: "fade"  // none | fade | wipe | slide | grow | zoom | spread | outline | random
                property string wallDirection: "left"   // wipe / slide: left | right | top | bottom
                property int wallDuration: 800          // ms
            }

            property JsonObject bar: JsonObject {
                property int minWorkspaces: 5
                property bool showTitle: true           // vertical window title
                property bool showApps: true            // pinned apps pill
                property bool showLogo: true            // launcher button
                property bool showWorkspaces: true
                property bool showTray: true
                property bool showClock: true
                property bool showStatus: true          // wifi / bluetooth / volume / battery / bell
                property bool showPower: true
                property bool openOnHover: true         // Caelestia-style: hover Wi-Fi/Bluetooth/clock (and the right edge for the OSD)
                property var pinned: [
                    { icon: "󰈹", color: "peach",    cmd: "firefox" },
                    { icon: "󰆍", color: "green",    cmd: "ghostty || kitty" },
                    { icon: "󰓇", color: "green",    cmd: "spotify-launcher || spotify" },
                    { icon: "󰙯", color: "lavender", cmd: "vesktop || discord" }
                ]
            }

            property JsonObject widgets: JsonObject {
                property bool enabled: true             // the typographic widget in the middle of the desktop
                property real scale: 1.0                // 0.8 small · 1 medium · 1.25 large
                property string vAlign: "bottom"        // top | middle | bottom
                property string hAlign: "left"          // left | center | right
                property int gutter: 64                 // px from the frame's inner edge
                property string clockFont: "display"    // display (Inter Display) | mono | serif
                property string clockWeight: "light"    // thin | light | regular | bold
                property int clockSize: 132             // px at Medium size
                property string clockColor: "text"      // text | accent
                property bool showAmPm: true            // 12-hour clock only
                property bool leadingZero: false        // 09:15 instead of 9:15
                property string textColor: "auto"       // auto (follows the wallpaper) | light | dark
                property string shadow: "soft"          // off | soft | strong
                property real opacity: 1.0              // 0.3 – 1
                property string dateFormat: "long"      // long | short | numeric | iso
                property bool dateCaps: true            // date in spaced capitals
                property string greetingText: ""        // "" = automatic ("Good evening, name")
                property bool showGreeting: true
                property bool showDate: true
                property bool showWeather: true
                property bool showMedia: true           // only while a player exists
                property bool showTasks: true           // only when the tasks file has tasks
                property bool showSystem: false
                property string weatherLocation: ""     // "" = auto (by IP)
                property string weatherUnits: "metric"  // metric | imperial
                property string tasksFile: "~/day_plan.md"
            }

            property JsonObject phone: JsonObject {     // iPhone as a webcam (services/PhoneCam.qml)
                property string mode: "auto"            // auto (USB → hotspot → Wi-Fi) | usb | hotspot | wifi
                property string wifiAddress: ""         // Wi-Fi mode: the iPhone's IP; empty = <name>.local
            }

            // what Programming and Game mode change (services/Perf.qml + hypr/atelier-mode.lua;
            // Settings → Modes). Normal mode is just your own look (the Windows page).
            property JsonObject modes: JsonObject {
                property bool devOpaque: true            // opaque windows: crisp text, no blur behind them
                property bool devDim: false              // dim unfocused windows
                property string devBlur: "light"         // off | light (1 pass) | normal (your setting)
                property bool devShadows: true
                property bool devAnimations: true
                property real devAnimSpeed: 0.6          // window animation duration × this (smaller = faster)
                property string devPower: "performance"  // performance | balanced | power-saver | unchanged
                property bool devCaffeine: true          // keep the screen awake
                property bool devDnd: false
                property bool gameOpaque: true
                property string gameBlur: "off"
                property bool gameShadows: false
                property bool gameAnimations: false
                property bool gameTearing: true          // allow tearing for fullscreen games
                property string gamePower: "performance"
                property bool gameCaffeine: true
                property bool gameDnd: true
                property bool gameHideWidgets: true      // don't draw the desktop widget
                property bool gameLeanShell: true        // no shell shadows, opaque shell surfaces
                property string gameApps: ""             // extra window classes that count as games, comma-separated
            }

            property JsonObject controlCenter: JsonObject {   // modules/drawers/ControlCenter.qml
                property string layout: "list"          // list | tiles | icons | cards
                property string header: "full"          // full (big clock) | compact (one line)
                property var shortcuts: ["screenshot", "wallpaper", "theme", "keyboard", "keybinds"]
                property int notifLimit: 4              // notifications shown before "Show N more"
            }

            property JsonObject airdrop: JsonObject {   // AirDrop through owly (services/AirDrop.qml)
                property bool enabled: false            // receiving: radio + receiver running
                property string name: ""                // the name iPhones see; empty = host name
                property string folder: "~/Downloads/AirDrop"
                property var trusted: []                // sender names accepted without asking
            }

            property JsonObject emoji: JsonObject {     // emoji picker + GIF finder (modules/drawers/EmojiOverlay.qml)
                property bool typeOnPick: true          // also type the emoji into the window you were in (wtype)
                property int tone: 0                    // skin tone: 0 default, 1 light … 5 dark
                property string gifProvider: "giphy"    // giphy | tenor
                property string gifKey: ""              // API key (free); kept only in ~/.config/atelier/settings.json
            }

            property JsonObject recorder: JsonObject {  // screen recording (services/Recorder.qml)
                property string folder: "~/Videos/Recordings"
                property string audio: "none"           // none | system | mic
                property int fps: 60                    // 30 | 60
            }

            property JsonObject nightLight: JsonObject {  // services/NightLight.qml (hyprsunset)
                property bool on: false
                property int temperature: 4000          // K: 2500 very warm … 6000 barely
                property bool schedule: false          // automatically on between from and to
                property string from: "20:00"
                property string to: "07:00"
            }

            property JsonObject notifications: JsonObject {
                property int popupSeconds: 5
                property int maxPopups: 5
                property string position: "top-right"   // top-right | top-left | top-center | bottom-right | bottom-left
                property int popupWidth: 360
                property bool stack: true               // same app + title → one card with +N
                property bool showBody: true            // off: titles only (screen sharing, privacy)
                property bool showSource: true          // the "WhatsApp · iPhone" line
                property bool lockShowCount: true       // show notifications on the lock screen
            }

            property JsonObject windows: JsonObject {   // Hyprland
                property int gapsIn: 5
                property int gapsOut: 10
                property int rounding: 14
                property real activeOpacity: 0.95
                property real inactiveOpacity: 0.90
                property bool blur: true
                property int blurPasses: 2
                property bool shadow: true
                property bool animations: true

                property string layout: "dwindle"       // dwindle | master | scrolling | monocle
                property bool dwindlePreserveSplit: true
                property bool dwindleSmartSplit: false
                property string masterOrientation: "left"   // left | right | top | bottom | center
                property real masterFactor: 0.55
                property bool masterNewOnTop: false
                property real scrollColumnWidth: 0.5
            }

            // Battery alerts (services/Battery.qml)
            property JsonObject battery: JsonObject {
                property bool alerts: true              // notify when it runs low
                property int low: 20                    // %: a normal notification
                property int critical: 5                // %: a critical one (stays, gets through DND)
                property bool chargerToast: true        // "Charging · 64%" when plugged / unplugged
            }

            // Idle & sleep (services/Idle.qml writes ~/.config/atelier/hypridle.conf). Seconds; 0 = never.
            property JsonObject idle: JsonObject {
                property int dimAfter: 60
                property int lockAfter: 120
                property int screenOffAfter: 300
                property int suspendAfter: 600
                property bool suspendOnAC: false        // off: never sleeps by itself while charging
            }

            // System updates (services/Updates.qml)
            property JsonObject updates: JsonObject {
                property bool check: true               // look every few hours, show them in the control center
                property int hours: 3
            }

            // Plugged-in drives (services/Drives.qml)
            property JsonObject drives: JsonObject {
                property bool notify: true              // a notification with Open / Eject when one is plugged in
            }

            property JsonObject behavior: JsonObject {
                property string terminal: "ghostty"
                property string searchUrl: "https://www.google.com/search?q="
                property real osdSeconds: 1.6
                property bool autoGameMode: true
            }

            property JsonObject input: JsonObject {     // Hyprland input (Settings → Keyboard & mouse)
                property string kbLayout: "us"          // xkb layouts, comma separated: "us,de"
                property string kbVariant: ""           // matching variants: ",nodeadkeys"
                property string layoutSwitch: ""        // "" | grp:alt_shift_toggle | grp:win_space_toggle | grp:ctrl_shift_toggle | grp:caps_toggle
                property string capsLock: "default"     // default | escape | ctrl | swapescape | off
                property string kbOptions: ""           // any other xkb options, comma separated
                property int repeatRate: 25             // keys per second
                property int repeatDelay: 600           // ms before repeating
                property bool numlock: false            // Num Lock on at login
                property real sensitivity: 0            // -1 … 1
                property string accelProfile: "adaptive" // adaptive | flat
                property bool mouseCurve: true          // the macOS-style curve on the 2.4 GHz mouse
                property bool naturalScroll: false      // mice
                property real scrollFactor: 1.0         // mice
                property bool leftHanded: false
                property bool followMouse: true         // focus follows the pointer
                property bool tpNatural: true
                property real tpScroll: 0.45
                property bool tpTap: true
                property bool tpClickfinger: true       // 2 fingers = right, 3 = middle click
                property bool tpDwt: true               // ignore the touchpad while typing
                property bool tpDragLock: false         // lifting a finger mid-drag doesn't drop
            }

            property JsonObject displays: JsonObject {  // Hyprland monitors (Settings → Displays)
                // one entry per output you changed: { output, mode, position, scale, transform, vrr?, disabled?, mirror? }
                // mode "preferred" | "WxH@R"; position "auto" | "XxY"; scale number | "auto"; transform 0–7
                property var monitors: [
                    { output: "HDMI-A-1", mode: "1366x768@59.79Hz", position: "auto", scale: "auto", transform: 3 }
                ]
            }

            property JsonObject keybinds: JsonObject {  // Settings → Shortcuts (hypr/conf/keybinds.lua)
                property var overrides: ({})            // "Section · Name" → "SUPER + Y" ("" = off)
                property var custom: []                 // [{ keys, cmd, label }]
            }

            property JsonObject lock: JsonObject {
                // "atelier" = the shell's own lock screen (LockContent.qml); anything else is a
                // qylock theme id (scripts/qylock.py), run as its own lock process
                property string theme: "atelier"
                // "depth": Samsung-style lock (modules/lock/DepthLock.qml), clock behind the subject
                property string depthLayout: "horizontal"   // horizontal (12:45) | stacked (12 over 45)
                property real depthClockSize: 0.22          // digit height, share of the screen height
                property string depthFont: "display"        // display (Inter Display) | mono | serif
                property string depthWeight: "bold"         // light | regular | bold | black
                property bool depthShadow: true
                property string depthPos: "auto"            // auto (placed around the subject) | custom (dragged in the editor)
                property real depthX: 0.5                   // custom: clock centre, share of the screen width
                property real depthY: 0.1                   // custom: top of the date line, share of the screen height
                property bool depthEffect: true             // clock behind the subject (off = a plain big clock on top)
                property string depthStyle: "solid"         // solid | glass (frosted digits)
                property string depthColor: "auto"          // auto (from the wallpaper) | theme | white | black | theme role | "#rrggbb"
            }

            property JsonObject greeter: JsonObject {
                // the login screen (greeter/shell.qml); mirrored to /var/lib/atelier-greeter by
                // services/Greeter.qml. Clock format and weather place come from general/widgets.
                property string layout: "panel"         // panel (three columns) | minimal (centre only)
                property string greeting: ""            // "" = by time of day
                property bool showWeather: true
                property bool showSystem: true
                property bool showPower: true
                property real blur: 0.75                // wallpaper blur 0…1
                property real dim: 0.38                 // darkening over the wallpaper 0…0.8
                property bool autoSync: true            // follow theme, wallpaper and ~/.face
            }
        }
    }

    // ── helpers ─────────────────────────────────────────────────────────────
    function expand(p: string): string {
        return p && p.startsWith("~") ? Quickshell.env("HOME") + p.slice(1) : p;
    }

    readonly property var layouts: ["dwindle", "master", "scrolling", "monocle"]
    function cycleLayout(): string {
        const i = layouts.indexOf(adapter.windows.layout);
        adapter.windows.layout = layouts[(i + 1) % layouts.length];
        return adapter.windows.layout;
    }

    // Whole-file access for Settings → Profiles: the current settings as JSON text, and replacing them.
    function snapshot(): string { return file.text(); }
    function load(text: string): void {
        file.setText(text);
        file.reload();
    }

    function reset(): void {
        // replace the file with an empty object → every property falls back to its default
        file.setText("{}");
        file.reload();
    }

    // ── Hyprland (windows) ──────────────────────────────────────────────────
    // Window corner radius. Linked: concentric with the shell frame (frame rounding − screen-edge gap).
    readonly property int windowRounding: adapter.appearance.linkRounding
        ? Math.max(0, Math.round(adapter.appearance.rounding - adapter.windows.gapsOut))
        : Math.round(adapter.windows.rounding)

    // JS value → Lua literal (strings, numbers, booleans, arrays, objects)
    function lua(v) {
        if (v === null || v === undefined) return "nil";
        if (typeof v === "string") return '"' + v.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"';
        if (typeof v === "number") return isFinite(v) ? String(Math.round(v * 1000) / 1000) : "0";
        if (typeof v === "boolean") return v ? "true" : "false";
        if (Array.isArray(v)) return "{ " + v.map(x => root.lua(x)).join(", ") + " }";
        const keys = Object.keys(v);
        return keys.length ? "{ " + keys.map(k => "[" + root.lua(k) + "] = " + root.lua(v[k])).join(", ") + " }" : "{}";
    }
    readonly property var capsOptions: ({ escape: "caps:escape", ctrl: "ctrl:nocaps", swapescape: "caps:swapescape", off: "caps:none" })
    readonly property string luaInput: {
        const i = adapter.input;
        const opts = [root.capsOptions[i.capsLock] || "", i.layoutSwitch || ""]
            .concat((i.kbOptions || "").split(",").map(x => x.trim())).filter(x => x).join(",");
        return "    input = " + root.lua({
            kb_layout: i.kbLayout.trim() || "us", kb_variant: i.kbVariant.trim(), kb_options: opts,
            repeat_rate: Math.round(i.repeatRate), repeat_delay: Math.round(i.repeatDelay), numlock_by_default: i.numlock,
            sensitivity: Math.max(-1, Math.min(1, i.sensitivity)), accel_profile: i.accelProfile === "flat" ? "flat" : "adaptive",
            natural_scroll: i.naturalScroll, scroll_factor: i.scrollFactor, left_handed: i.leftHanded,
            follow_mouse: i.followMouse ? 1 : 0,
            touchpad: { natural_scroll: i.tpNatural, scroll_factor: i.tpScroll, tap_to_click: i.tpTap,
                        clickfinger_behavior: i.tpClickfinger, disable_while_typing: i.tpDwt, drag_lock: i.tpDragLock ? 1 : 0 }
        }) + ",\n    mouse_curve = " + i.mouseCurve + ",\n";
    }
    readonly property string luaMonitors: {
        const list = (adapter.displays.monitors || []).filter(m => m && m.output).map(m => {
            const o = { output: String(m.output), mode: m.mode || "preferred", position: m.position || "auto",
                        scale: m.scale === undefined ? "auto" : m.scale, transform: Math.round(m.transform || 0) };
            if (m.vrr !== undefined) o.vrr = Math.round(m.vrr);
            if (m.disabled) o.disabled = true;
            if (m.mirror) o.mirror = String(m.mirror);
            return o;
        });
        return "    monitors = " + root.lua(list) + ",\n";
    }
    readonly property string luaBinds: {
        const k = adapter.keybinds;
        const ov = {};
        for (const id in (k.overrides || {})) if (typeof k.overrides[id] === "string") ov[id] = k.overrides[id];
        const custom = (k.custom || []).filter(c => c && c.keys && c.cmd)
            .map(c => ({ keys: String(c.keys), cmd: String(c.cmd), label: String(c.label || "") }));
        return "    binds = { overrides = " + root.lua(ov) + ", custom = " + root.lua(custom) + " },\n";
    }

    // the compositor half of Programming / Game mode
    readonly property string luaModes: {
        const m = adapter.modes;
        const mode = (p) => "{ opaque = " + m[p + "Opaque"] + ", blur = \"" + m[p + "Blur"] + "\", shadows = " + m[p + "Shadows"]
            + ", animations = " + m[p + "Animations"] + (p === "dev" ? ", dim = " + m.devDim + ", anim_speed = " + Number(m.devAnimSpeed).toFixed(2)
                                                                 : ", tearing = " + m.gameTearing) + " }";
        return "    modes = {\n        dev = " + mode("dev") + ",\n        game = " + mode("game") + ",\n    },\n";
    }
    readonly property string hyprLua: {
        const w = adapter.windows;
        return "-- Generated by the Quickshell Settings app. Edit in the app (or settings.json).\n"
            + "return {\n"
            + "    gaps_in = " + Math.round(w.gapsIn) + ", gaps_out = " + Math.round(w.gapsOut) + ",\n"
            + "    rounding = " + Math.round(root.windowRounding) + ",\n"
            + "    active_opacity = " + w.activeOpacity.toFixed(2) + ", inactive_opacity = " + w.inactiveOpacity.toFixed(2) + ",\n"
            + "    blur = " + w.blur + ", blur_passes = " + Math.round(w.blurPasses) + ",\n"
            + "    shadow = " + w.shadow + ", animations = " + w.animations + ",\n"
            + "    layout = \"" + w.layout + "\",\n"
            + "    dwindle_preserve_split = " + w.dwindlePreserveSplit + ", dwindle_smart_split = " + w.dwindleSmartSplit + ",\n"
            + "    master_orientation = \"" + w.masterOrientation + "\", master_mfact = " + w.masterFactor.toFixed(2)
            + ", master_new_on_top = " + w.masterNewOnTop + ",\n"
            + "    scroll_column_width = " + w.scrollColumnWidth.toFixed(2) + ",\n"
            + "    shell_glass = " + Math.min(1, adapter.appearance.glass).toFixed(2) + ",   -- shell surface opacity: blur threshold in conf/rules.lua\n"
            + "    reserved = { top = " + root._inset("top") + ", right = " + root._inset("right")
            + ", bottom = " + root._inset("bottom") + ", left = " + root._inset("left") + " },   -- shell frame: conf/monitors.lua\n"
            + "    -- Settings → Modes (atelier-mode.lua)\n" + root.luaModes
            + "    -- Settings → Keyboard & mouse (conf/input.lua)\n" + root.luaInput
            + "    -- Settings → Displays (conf/monitors.lua)\n" + root.luaMonitors
            + "    -- Settings → Shortcuts (conf/keybinds.lua)\n" + root.luaBinds
            + "}\n";
    }
    // Screen edges the shell frame covers. Hyprland reserves them per monitor (conf/monitors.lua),
    // which replaced four 1×1 exclusive-zone windows (each cost a render thread + GL context).
    // Same rule as Atelier.inset*; computed here because Atelier depends on Settings.
    function _inset(edge) {
        const a = adapter.appearance;
        const bar = ["left", "right", "top", "bottom"].indexOf(a.barPosition) >= 0 ? a.barPosition : "left";
        return Math.round(edge === bar ? a.barWidth : a.frame);
    }
    property string _applied: ""
    // the parts last applied live, so only what changed is re-applied (a monitor re-apply can modeset)
    property string _appliedInput: ""
    property string _appliedMonitors: ""
    property string _appliedBinds: ""
    property var _monitorOutputs: []

    FileView {
        id: hyprFile
        path: Quickshell.env("HOME") + "/.config/hypr/atelier-settings.lua"
        printErrors: false
    }
    Process { id: hyprEval }

    Timer {
        id: applyTimer
        interval: 250
        onTriggered: {
            if (!root.ready || root.hyprLua === root._applied) return;
            const first = root._applied === "";
            root._applied = root.hyprLua;
            hyprFile.setText(root.hyprLua);
            const mode = 'local m = dofile(os.getenv("HOME") .. "/.config/hypr/atelier-mode.lua"); ';
            let extra = "";
            // input / monitors / binds were applied by the config at login; at shell start only
            // remember them, afterwards re-apply each one only when it changed
            if (root.luaInput !== root._appliedInput) {
                if (!first) extra += "m.apply_input(t); ";
                root._appliedInput = root.luaInput;
            }
            const outs = (adapter.displays.monitors || []).filter(x => x && x.output).map(x => String(x.output));
            if (root.luaMonitors !== root._appliedMonitors) {
                const forget = root._monitorOutputs.filter(o => outs.indexOf(o) < 0);
                if (!first) extra += "m.apply_monitors(t, " + root.lua(forget) + "); ";
                root._appliedMonitors = root.luaMonitors;
            }
            root._monitorOutputs = outs;
            if (root.luaBinds !== root._appliedBinds) {
                if (!first) extra += "if atelier_apply_binds then atelier_apply_binds(t.binds) end; ";
                root._appliedBinds = root.luaBinds;
            }
            hyprEval.command = ["hyprctl", "eval",
                'local t = dofile(os.getenv("HOME") .. "/.config/hypr/atelier-settings.lua"); ' + mode + extra + 'hl.config({ '
                + 'general = { gaps_in = t.gaps_in, gaps_out = t.gaps_out }, '
                + 'decoration = { rounding = t.rounding, active_opacity = t.active_opacity, inactive_opacity = t.inactive_opacity, '
                + 'blur = { enabled = t.blur, passes = t.blur_passes }, shadow = { enabled = t.shadow } }, '
                + 'animations = { enabled = t.animations } }); '
                + 'hl.config({ general = { layout = t.layout }, '
                + 'dwindle = { preserve_split = t.dwindle_preserve_split, smart_split = t.dwindle_smart_split }, '
                + 'master = { orientation = t.master_orientation, mfact = t.master_mfact, new_on_top = t.master_new_on_top }, '
                + 'scrolling = { column_width = t.scroll_column_width } }); '
                + 'if atelier_mode and atelier_mode ~= "normal" then m.apply(atelier_mode) end'];
            hyprEval.running = true;
        }
    }
    onHyprLuaChanged: applyTimer.restart()
    onReadyChanged: applyTimer.restart()
}
