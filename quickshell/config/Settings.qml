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

    // the shell's glass opacity: the focused-window opacity when "Match windows" is on
    readonly property real shellGlass: adapter.appearance.glassMatchWindows ? adapter.windows.activeOpacity : adapter.appearance.glass
    readonly property var general: adapter.general
    readonly property var appearance: adapter.appearance
    readonly property var bar: adapter.bar
    readonly property var dock: adapter.dock
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
    readonly property var lockStyle: adapter.lockStyle

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
                property real glass: 0.92               // opacity of bar/drawer surfaces (when not matching windows)
                property bool glassMatchWindows: true   // the shell uses the focused window opacity, so both show the same blur
                property string glassTone: "deep"       // deep (the theme's darkest colour) | base (its background colour, like most apps)
                property bool shellBlur: true           // blur behind the bar and drawers
                property bool shellShadow: true         // soft shadow under drawers and the frame
                property bool edgeSpectrum: true        // audio spectrum along the bottom edge while music plays
                property string barPosition: "left"     // left | right | top | bottom
                property string layout: "atelier"       // atelier (tiling) | classic (Traditional: floating windows, title bars, dock)
                // each layout remembers its own bar edge and file manager (setLayout)
                property var layoutBar: ({ atelier: "left", classic: "top" })
                property var layoutFiles: ({ atelier: "org.kde.dolphin.desktop", classic: "org.gnome.Nautilus.desktop" })
                property string titlebarButtons: "right" // Traditional: close / maximise / minimise on the left | right
                property bool linkRounding: true        // windows follow the shell's roundness (concentric)
                property string wallTransition: "fade"  // none | fade | wipe | slide | grow | zoom | spread | random
                property string wallDirection: "left"   // wipe / slide: left | right | top | bottom
                property int wallDuration: 800          // ms
            }

            property JsonObject bar: JsonObject {
                property string design: "pills"         // pills (the original) | gauge (ring gauges, cover art, big clock) | dock (bare icon rail with dots)
                property string style: "pills"          // pills (round, filled) | square (rounded-square tiles) | accent (accent-filled) | outline (accent line, no fill) | flat (no backgrounds, wider gaps)
                property int minWorkspaces: 5
                property bool showTitle: true           // vertical window title
                property bool showApps: true            // pinned apps pill
                property bool showLogo: true            // launcher button
                property bool showWorkspaces: true
                property bool showTray: true
                property bool showGit: true             // branch + changes of the focused window's git project
                property bool showClock: true
                property bool showPrivacy: true         // mic / camera / screen-share dots while an app uses them
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

            property JsonObject dock: JsonObject {     // Traditional layout dock (modules/dock/Dock.qml)
                property int iconSize: 40
                property bool magnify: true             // icons grow under the pointer
                property bool showRunning: true         // open apps that aren't kept in the dock appear after a divider
                property string style: "shelf"          // shelf (a tab rising from a thin frame, sized to the icons) | bar (the whole bottom edge)
                property bool showFolders: true         // Downloads and Trash at the right end
                property var pinned: ["firefox", "com.mitchellh.ghostty", "org.gnome.Nautilus", "com.microsoft.VSCode", "spotify-launcher", "vesktop"]
            }

            property JsonObject widgets: JsonObject {
                property bool enabled: true             // the typographic widget in the middle of the desktop
                property real scale: 1.0                // 0.8 small · 1 medium · 1.25 large
                property string vAlign: "bottom"        // top | middle | bottom
                property string hAlign: "left"          // left | center | right
                property int gutter: 64                 // px from the frame's inner edge
                property int offsetX: 0                 // fine tune: nudge from that spot, px, + = right
                property int offsetY: 0                 // + = down
                property string clockFont: "display"    // display (Inter Display) | mono | serif
                property string clockWeight: "light"    // thin | light | regular | bold
                property int clockSize: 132             // px at Medium size
                property string clockColor: "text"      // text | auto (stands out on the wallpaper) | accent | palette role | "#rrggbb"
                property string dateColor: "text"       // same choices
                property string glyphColor: "colourful" // colourful (one hue per line) | same choices as the clock
                property bool glass: false              // the clock's digits are glass (iOS 26 style)
                property real glassBlur: 0.7            // how frosted the glass is, 0.1 … 1
                property real glassTint: 0.2            // how much of the clock colour shows in the glass, 0 … 0.85
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

            // what Programming, Game and Battery saver mode change (services/Perf.qml + hypr/atelier-mode.lua;
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
                property bool saverOpaque: true          // opaque windows: nothing is blended
                property bool saverDim: false
                property string saverBlur: "off"
                property bool saverShadows: false
                property string saverPower: "power-saver"
                property bool saverCaffeine: false
                property bool saverDnd: false
                property bool saverHideWidgets: true     // don't draw (or refresh) the desktop widget
                property bool saverLeanShell: true       // no shell shadows, solid instead of glass
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
                property int historyHours: 0            // forget notifications older than this many hours (0 = keep until dismissed)
            }

            property JsonObject windows: JsonObject {   // Hyprland
                property int gapsIn: 5
                property int gapsOut: 10
                property int rounding: 14
                property real activeOpacity: 0.95
                property real inactiveOpacity: 0.90
                property bool blur: true
                property int blurPasses: 2
                property int blurSize: 9                // blur radius per pass
                property real blurVibrancy: 0.17        // colour saturation of what shows through
                property real blurNoise: 0.012          // grain (hides banding)
                property real blurContrast: 0.95
                property real blurBrightness: 0.90
                property bool blurBehind: false         // blur real windows behind (off = only the wallpaper, much cheaper)
                property bool blurPopups: true          // menus and tooltips
                property bool dimInactive: true
                property real dimStrength: 0.06
                property bool solidApps: true           // video, image viewers, games, creative apps stay opaque
                property bool solidFullscreen: true     // fullscreen windows stay opaque
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
                property int pomoFocus: 25              // Timers → Focus (pomodoro), minutes
                property int pomoShort: 5
                property int pomoLong: 15
                property int pomoEvery: 4               // a long break after this many focus rounds
                property bool screenTime: true          // count screen time per app (System monitor → Screen time)
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
                // touchpad gestures (hypr/conf/input.lua)
                property bool gestureWorkspace: true    // swipe sideways: previous / next workspace
                property int gestureFingers: 3          // 3 | 4 for that swipe; the overview uses the other count
                property bool gestureInvert: false      // swipe the other way round
                property bool gestureCreateNew: true    // swiping past the last workspace makes a new one
                property int gestureDistance: 300       // px of finger travel for one workspace
                property bool gestureOverview: true     // swipe up / down: open / close the overview
                property bool gestureLauncher: true     // pinch in / out: open / close the launcher
                property int pinchFingers: 4            // 3 | 4
            }

            property JsonObject displays: JsonObject {  // Hyprland monitors (Settings → Displays)
                // one entry per output you changed: { output, mode, position, scale, transform, vrr?, disabled?, mirror? }
                // mode "preferred" | "WxH@R"; position "auto" | "XxY"; scale number | "auto"; transform 0–7
                property var monitors: []
            }

            property JsonObject keybinds: JsonObject {  // Settings → Shortcuts (hypr/conf/keybinds.lua)
                property var overrides: ({})            // "Section · Name" → "SUPER + Y" ("" = off)
                property var custom: []                 // [{ keys, cmd, label }]
            }

            property JsonObject lock: JsonObject {
                // atelier (LockContent.qml) | a phone style (PhoneLock.qml):
                // cupertino, hyper, harmony, oxygen, material, dot, terminal, analog, aurora, poster, flip, split, hud
                property string theme: "atelier"
                property string clock: "system"             // system (General → 24-hour clock) | 12 | 24, for every built-in style
            }

            // the phone-inspired lock styles (modules/lock/PhoneLock.qml), each one's own options
            property JsonObject lockStyle: JsonObject {
                property real size: 0.72                    // every style's text and widgets, 0.5 … 1.1
                property string cupertinoWeight: "bold"     // regular | bold | heavy
                property string cupertinoTint: "white"      // white | soft | accent
                property bool cupertinoWidgets: true        // the round gauges under the clock
                property string cupertinoNotifs: "pile"     // pile | list | count
                property string hyperGradient: "accent"     // accent | sunset | ocean | mono
                property string hyperWeight: "regular"      // thin | regular | bold
                property bool hyperCards: true              // weather / battery / notifications cards
                property bool harmonyCalendar: true         // the month on the right
                property bool harmonyAccent: false          // the big day number in the accent colour
                property string harmonyWeekStart: "mon"     // mon | sun
                property string oxygenShelf: "bottom"       // bottom | top
                property string oxygenAccent: "red"         // red | theme
                property bool oxygenSeconds: false
                property string materialLayout: "grid"      // grid (2×2) | line
                property bool materialShrink: true          // smaller tiles while there are notifications
                property string dotColor: "white"           // white | red | theme
                property bool dotSeconds: true              // the 60-dot seconds bar
                property string dotBackground: "mono"       // mono (black & white wallpaper) | black
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

    // Settings → Atelier / Traditional. Each layout keeps its own bar edge (Atelier: left,
    // Traditional: top) and file manager (Dolphin / Nautilus): leaving a layout remembers its
    // edge, entering one restores both. Either layout's values can be edited while the other is
    // in use; only the active one's are applied right away.
    readonly property var layoutDefaults: ({ bar: { atelier: "left", classic: "top" },
                                             files: { atelier: "org.kde.dolphin.desktop", classic: "org.gnome.Nautilus.desktop" } })
    function layoutBarOf(l: string): string {
        const m = adapter.appearance.layoutBar || {};
        return l === adapter.appearance.layout ? adapter.appearance.barPosition : (m[l] || layoutDefaults.bar[l]);
    }
    function layoutFilesOf(l: string): string { return (adapter.appearance.layoutFiles || {})[l] || layoutDefaults.files[l]; }
    function _applyFiles(id: string): void {
        // a layout switch is not a new default for fresh installs: leave the repo's seed alone
        Quickshell.execDetached(["env", "ATELIER_NO_SEED=1", "python3", Quickshell.shellDir + "/scripts/default-apps.py", "set", "files", id]);
    }
    function setLayoutBar(l: string, edge: string): void {
        const a = adapter.appearance;
        a.layoutBar = Object.assign({}, layoutDefaults.bar, a.layoutBar || {}, { [l]: edge });
        if (l === a.layout) a.barPosition = edge;
    }
    function setLayoutFiles(l: string, id: string): void {
        const a = adapter.appearance;
        a.layoutFiles = Object.assign({}, layoutDefaults.files, a.layoutFiles || {}, { [l]: id });
        if (l === a.layout) _applyFiles(id);
    }
    function setLayout(id: string): void {
        const a = adapter.appearance;
        if (id === a.layout || (id !== "atelier" && id !== "classic")) return;
        setLayoutBar(a.layout, a.barPosition);    // remember the edge of the layout you leave
        const edge = layoutBarOf(id);
        a.layout = id;
        a.barPosition = edge;
        _applyFiles(layoutFilesOf(id));
    }
    // Default apps → Files: that becomes the current layout's file manager
    function rememberFiles(appId: string): void {
        const a = adapter.appearance;
        a.layoutFiles = Object.assign({}, layoutDefaults.files, a.layoutFiles || {}, { [a.layout === "classic" ? "classic" : "atelier"]: appId });
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
        }) + ",\n    mouse_curve = " + i.mouseCurve + ",\n" + root.luaGestures;
    }
    // registration (on/off, finger counts) needs a config reload; the rest applies live
    readonly property string luaGestureReg: {
        const i = adapter.input;
        const f = (n, d) => (n === 3 || n === 4) ? n : d;
        return "workspace = " + i.gestureWorkspace + ", workspace_fingers = " + f(i.gestureFingers, 3)
            + ", overview = " + i.gestureOverview + ", launcher = " + i.gestureLauncher + ", pinch_fingers = " + f(i.pinchFingers, 4);
    }
    readonly property string luaGestures: {
        const i = adapter.input;
        return "    gestures = { " + root.luaGestureReg + ", invert = " + i.gestureInvert + ", create_new = " + i.gestureCreateNew
            + ", distance = " + Math.round(Math.max(100, Math.min(1000, i.gestureDistance))) + " },\n";
    }
    readonly property string luaMonitorList: {
        const list = (adapter.displays.monitors || []).filter(m => m && m.output).map(m => {
            const o = { output: String(m.output), mode: m.mode || "preferred", position: m.position || "auto",
                        scale: m.scale === undefined ? "auto" : m.scale, transform: Math.round(m.transform || 0) };
            if (m.vrr !== undefined) o.vrr = Math.round(m.vrr);
            if (m.disabled) o.disabled = true;
            if (m.mirror) o.mirror = String(m.mirror);
            return o;
        });
        return root.lua(list);
    }
    readonly property string luaBinds: {
        const k = adapter.keybinds;
        const ov = {};
        for (const id in (k.overrides || {})) if (typeof k.overrides[id] === "string") ov[id] = k.overrides[id];
        const custom = (k.custom || []).filter(c => c && c.keys && c.cmd)
            .map(c => ({ keys: String(c.keys), cmd: String(c.cmd), label: String(c.label || "") }));
        return "    binds = { overrides = " + root.lua(ov) + ", custom = " + root.lua(custom) + " },\n";
    }

    // the compositor half of Programming / Game / Battery saver mode
    readonly property string luaModes: {
        const m = adapter.modes;
        const mode = (p) => "{ opaque = " + m[p + "Opaque"] + ", blur = \"" + m[p + "Blur"] + "\", shadows = " + m[p + "Shadows"]
            + ", animations = " + (p === "saver" ? "false" : m[p + "Animations"]) + (p === "dev" ? ", dim = " + m.devDim + ", anim_speed = " + Number(m.devAnimSpeed).toFixed(2)
                                                                 : p === "saver" ? ", dim = " + m.saverDim
                                                                 : ", tearing = " + m.gameTearing) + " }";
        return "    modes = {\n        dev = " + mode("dev") + ",\n        game = " + mode("game") + ",\n        saver = " + mode("saver") + ",\n    },\n";
    }
    readonly property string hyprLua: {
        const w = adapter.windows;
        return "-- Generated by the Quickshell Settings app. Edit in the app (or settings.json).\n"
            + "return {\n"
            + "    gaps_in = " + Math.round(w.gapsIn) + ", gaps_out = " + Math.round(w.gapsOut) + ",\n"
            + "    rounding = " + Math.round(root.windowRounding) + ",\n"
            + "    active_opacity = " + w.activeOpacity.toFixed(2) + ", inactive_opacity = " + w.inactiveOpacity.toFixed(2) + ",\n"
            + "    blur = " + w.blur + ", blur_passes = " + Math.round(w.blurPasses) + ",\n"
            + "    blur_size = " + Math.round(w.blurSize) + ", blur_vibrancy = " + w.blurVibrancy.toFixed(2)
            + ", blur_noise = " + w.blurNoise.toFixed(3) + ", blur_contrast = " + w.blurContrast.toFixed(2)
            + ", blur_brightness = " + w.blurBrightness.toFixed(2) + ",\n"
            + "    blur_xray = " + !w.blurBehind + ", blur_popups = " + w.blurPopups
            + ", dim_inactive = " + w.dimInactive + ", dim_strength = " + w.dimStrength.toFixed(2) + ",\n"
            + "    solid_apps = " + w.solidApps + ", solid_fullscreen = " + w.solidFullscreen
            + ", shell_blur = " + adapter.appearance.shellBlur + ",\n"
            + "    shadow = " + w.shadow + ", animations = " + w.animations + ",\n"
            + "    layout = \"" + w.layout + "\",\n"
            + "    dwindle_preserve_split = " + w.dwindlePreserveSplit + ", dwindle_smart_split = " + w.dwindleSmartSplit + ",\n"
            + "    master_orientation = \"" + w.masterOrientation + "\", master_mfact = " + w.masterFactor.toFixed(2)
            + ", master_new_on_top = " + w.masterNewOnTop + ",\n"
            + "    scroll_column_width = " + w.scrollColumnWidth.toFixed(2) + ",\n"
            + "    shell_layout = \"" + (adapter.appearance.layout === "classic" ? "classic" : "atelier") + "\", titlebar_buttons = \""
            + (adapter.appearance.titlebarButtons === "left" ? "left" : "right") + "\",   -- conf/traditional.lua\n"
            + "    shell_glass = " + Math.min(1, root.shellGlass).toFixed(2) + ",   -- shell surface opacity: blur threshold in conf/rules.lua\n"
            + "    reserved = { top = " + root._inset("top") + ", right = " + root._inset("right")
            + ", bottom = " + root._inset("bottom") + ", left = " + root._inset("left") + " },   -- shell frame: conf/monitors.lua\n"
            + "    -- Settings → Modes (atelier-mode.lua)\n" + root.luaModes
            + "    -- Settings → Keyboard & mouse (conf/input.lua)\n" + root.luaInput
            + "    -- Settings → Displays (conf/monitors.lua)\n    monitors = " + root.luaMonitorList + ",\n"
            + "    -- Settings → Shortcuts (conf/keybinds.lua)\n" + root.luaBinds
            + "}\n";
    }
    // Screen edges the shell frame covers. Hyprland reserves them per monitor (conf/monitors.lua),
    // which replaced four 1×1 exclusive-zone windows (each cost a render thread + GL context).
    // Same rule as Atelier.inset*; computed here because Atelier depends on Settings.
    function _inset(edge) {
        const a = adapter.appearance;
        const bar = ["left", "right", "top", "bottom"].indexOf(a.barPosition) >= 0 ? a.barPosition : "left";
        // Traditional: the bottom edge is the dock bar (same rule as Atelier.insetBottom)
        if (edge === "bottom" && a.layout === "classic" && bar !== "bottom") return Math.round(adapter.dock.iconSize + 14);
        // Traditional with the bar on top: the slim flat bar (same rule as Atelier.barWidth)
        const barW = a.layout === "classic" && bar === "top" ? 32 : a.barWidth;
        return Math.round(edge === bar ? barW : a.frame);
    }
    property string _applied: ""
    // the parts last applied live, so only what changed is re-applied (a monitor re-apply can modeset)
    property string _appliedInput: ""
    property string _appliedMonitors: ""
    property string _appliedReserved: ""
    property string _appliedBinds: ""
    property string _appliedGestures: ""
    property bool _reloadAfterSave: false

    FileView {
        id: hyprFile
        path: Quickshell.env("HOME") + "/.config/hypr/atelier-settings.lua"
        printErrors: false
        onSaved: {
            if (!root._reloadAfterSave) return;
            root._reloadAfterSave = false;
            hyprEval.command = ["hyprctl", "reload"];
            hyprEval.running = true;
        }
        onSaveFailed: (error) => {
            root._reloadAfterSave = false;
            root._applied = "";
            console.warn("Could not save Hyprland settings:", error);
        }
    }
    Process { id: hyprEval }

    Timer {
        id: applyTimer
        interval: 250
        onTriggered: {
            if (!root.ready || root.hyprLua === root._applied) return;
            if (hyprEval.running || root._reloadAfterSave) { applyTimer.restart(); return; }
            const first = root._applied === "";
            root._applied = root.hyprLua;
            const mode = 'local m = dofile(os.getenv("HOME") .. "/.config/hypr/atelier-mode.lua"); ';
            let extra = "";
            // input / monitors / binds were applied by the config at login; at shell start only
            // remember them, afterwards re-apply each one only when it changed
            if (root.luaInput !== root._appliedInput) {
                if (!first) extra += "m.apply_input(t); ";
                root._appliedInput = root.luaInput;
            }
            // Re-read monitor rules from disk so changes also take effect on disabled outputs.
            const resKey = ["top", "right", "bottom", "left"].map(e => root._inset(e)).join(",");
            const monitorReload = !first && (root.luaMonitorList !== root._appliedMonitors || resKey !== root._appliedReserved);
            root._appliedReserved = resKey;
            root._appliedMonitors = root.luaMonitorList;
            if (root.luaBinds !== root._appliedBinds) {
                if (!first) extra += "if atelier_apply_binds then atelier_apply_binds(t.binds) end; ";
                root._appliedBinds = root.luaBinds;
            }
            // a gesture switched on/off or to other fingers: only a config reload re-registers them
            // (it re-reads the file written above, so it also covers everything below)
            const gestReload = !first && root.luaGestureReg !== root._appliedGestures;
            root._appliedGestures = root.luaGestureReg;
            root._reloadAfterSave = monitorReload || gestReload;
            hyprFile.setText(root.hyprLua);
            if (monitorReload || gestReload) return;
            hyprEval.command = ["hyprctl", "eval",
                'local t = dofile(os.getenv("HOME") .. "/.config/hypr/atelier-settings.lua"); ' + mode + extra + 'hl.config({ '
                + 'general = { gaps_in = t.gaps_in, gaps_out = t.gaps_out }, '
                + 'decoration = { rounding = t.rounding, active_opacity = t.active_opacity, inactive_opacity = t.inactive_opacity, '
                + 'dim_inactive = t.dim_inactive, dim_strength = t.dim_strength, '
                + 'blur = { enabled = t.blur, passes = t.blur_passes, size = t.blur_size, vibrancy = t.blur_vibrancy, '
                + 'noise = t.blur_noise, contrast = t.blur_contrast, brightness = t.blur_brightness, '
                + 'xray = t.blur_xray, popups = t.blur_popups }, shadow = { enabled = t.shadow } }, '
                + 'animations = { enabled = t.animations } }); '
                + 'hl.config({ general = { layout = t.layout }, '
                + 'dwindle = { preserve_split = t.dwindle_preserve_split, smart_split = t.dwindle_smart_split }, '
                + 'master = { orientation = t.master_orientation, mfact = t.master_mfact, new_on_top = t.master_new_on_top }, '
                + 'scrolling = { column_width = t.scroll_column_width } }); '
                + 'if atelier_apply_solid then atelier_apply_solid(t) end; '
                + 'if atelier_apply_shell_blur then atelier_apply_shell_blur(t) end; '
                + 'if atelier_apply_traditional then atelier_apply_traditional(t) end; '
                + 'if atelier_mode and atelier_mode ~= "normal" then m.apply(atelier_mode) end'];
            hyprEval.running = true;
        }
    }
    onHyprLuaChanged: applyTimer.restart()
    onReadyChanged: applyTimer.restart()

    // The lock screens this shell ships (Settings → Lock screen, Settings → Login screen)
    readonly property var lockStyles: [
        { id: "atelier",   name: "Atelier",   note: "Glass panel, this shell's own" },
        { id: "cupertino", name: "Cupertino", note: "iOS-style" },
        { id: "hyper",     name: "Hyper",     note: "Xiaomi HyperOS-style" },
        { id: "harmony",   name: "Harmony",   note: "Huawei HarmonyOS-style" },
        { id: "oxygen",    name: "Oxygen",    note: "OnePlus OxygenOS-style" },
        { id: "material",  name: "Material",  note: "Pixel, Material You-style" },
        { id: "dot",       name: "Dot",       note: "Nothing OS-style" },
        { id: "terminal",  name: "Terminal",  note: "Full-screen terminal, pixel clock" },
        { id: "analog",    name: "Analog",    note: "Designer wall clock, paper white" },
        { id: "aurora",    name: "Aurora",    note: "Night sky, mountains, aurora" },
        { id: "poster",    name: "Poster",    note: "Huge flat-colour numerals" },
        { id: "flip",      name: "Flip",      note: "Flip-card clock that really flips" },
        { id: "split",     name: "Split",     note: "Slanted panel, clear wallpaper" },
        { id: "hud",       name: "HUD",       note: "Thin-lined dashboard grid" }
    ]
}
