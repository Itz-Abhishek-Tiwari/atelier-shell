//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs.components
import qs.config
import qs.modules.background
import qs.modules.bar
import qs.modules.desktop
import qs.modules.drawers
import qs.modules.keyboard
import qs.modules.lock
import qs.modules.osd
import qs.modules.screenshot
import qs.modules.settings
import qs.services

ShellRoot {
    id: shellRoot

    // Dynamic Theme Mode (light/dark) — sourced from the shared Atelier tokens
    readonly property string currentThemeMode: Atelier.mode
    readonly property bool isLight: Atelier.isLight

    // --- Centralized Mutual Exclusivity Panel Controller ---
    property string activeOverlay: "" // "" | "wifi" | "bluetooth" | "power" | "launcher" | "apps" | "calendar" | "wallpaper" | "clipboard" | "controlcenter" | "theme"

    // Last known centerY of the triggering icon (screen-space Y), used to position overlays
    property real lastCenterY: 0

    // Open on hover (Settings → Bar → Behaviour): the open drawer was opened by hovering its bar
    // icon. It closes when the pointer leaves it and its icon; clicking the icon pins it.
    property bool hoverMode: false
    property string barHover: ""          // bar item under the pointer (Waybar.hoverTarget)
    property var barZones: []             // where the hover icons are along the bar (Waybar.zones())

    function hoverOverlay(name, centerY) {
        if (!Settings.bar.openOnHover || activeOverlay === name) return;
        if (activeOverlay !== "" && !hoverMode) return;   // never replace a drawer you clicked open
        const prev = activeOverlay;
        if (prev === "") closeAllOverlays();
        hoverMode = true;          // BEFORE opening: a moment of full-screen input mask would steal the pointer from the bar
        // Switching between bar drawers: open the new one FIRST, then drop the old one instantly.
        // Never go through closeAllOverlays() here: it clears hoverMode for a moment, the host's
        // bar strip loses the pointer, and the leave timer closes the new drawer (close → reopen).
        openOverlay(name, centerY);
        if (prev !== "" && lazyDrawers[prev]) lazyDrawers[prev].hideNow();
    }
    property string edgeHover: ""         // "media" while the pointer is on the top-edge sensor

    // every lazy drawer by name (the `drawers` IPC target)
    readonly property var lazyDrawers: ({ overview: overviewOverlay, games: gamesOverlay, theme: themeOverlay,
        controlcenter: controlCenter, wifi: wifiOverlay, bluetooth: bluetoothOverlay, power: powerOverlay,
        launcher: launcherOverlay, apps: appsOverlay, camera: cameraOverlay, clipboard: clipboardOverlay,
        media: mediaOverlay, keybinds: keybindsOverlay, sysmon: sysMonOverlay, timers: timerOverlay,
        colors: colorPickerOverlay, switcher: windowSwitcher, calendar: calendarOverlay,
        wallpaper: wallpaperOverlay, emoji: emojiOverlay, settings: settingsApp, privacy: privacyOverlay })

    // Drawers are built on demand (components/LazyDrawer.qml). The bar's hover icons prefetch
    // theirs as soon as the pointer reaches them, so the hover-open itself never waits.
    function prefetch(name) {
        const d = lazyDrawers[name];
        if (d) d.prefetch();
    }

    function toggleOverlay(name, centerY) {
        // the on-screen keyboard is independent: it stays open while other overlays come and go
        if (name === "keyboard") { osk.toggle(); return; }
        // Settings on a given page ("settings:<page>"): switch page if it is already open
        if (name.startsWith("settings:")) {
            if (activeOverlay !== "settings") { closeAllOverlays(); activeOverlay = "settings"; }
            hoverMode = false;
            settingsApp.open(name.slice(9));
            return;
        }
        // screen recording: stop if running, otherwise pick what to record (same picker)
        if (name.startsWith("record")) {
            if (Recorder.recording) { Recorder.stop(); return; }
            const wait = activeOverlay !== "" ? Atelier.durClose + 80 : 0;
            closeAllOverlays();
            screenshotTool.record(name === "record-screen" ? "screen" : name === "record-window" ? "window" : "region", wait);
            return;
        }
        // screenshots: an open drawer stays on screen and ends up in the shot. The picker freezes
        // the screen first; only then are drawers closed, behind the frozen frame (onFrozen below).
        if (name.startsWith("screenshot")) {
            if (name === "screenshot-screen") screenshotTool.full(0);
            else screenshotTool.open(name === "screenshot-window" ? "window" : "region", 0);
            return;
        }
        // emoji ⇄ GIFs are two tabs of one drawer: switch tab instead of closing and reopening
        if ((name === "emoji" || name === "gifs") && (activeOverlay === "emoji" || activeOverlay === "gifs")
                && activeOverlay !== name) {
            activeOverlay = name;
            emojiOverlay.call("setTab", name);
            return;
        }
        // clicking the icon of a hover-opened drawer pins it (instead of closing it)
        if (hoverMode && activeOverlay === name) { hoverMode = false; return; }
        if (activeOverlay === name) {
            closeAllOverlays();
        } else {
            closeAllOverlays();
            openOverlay(name, centerY);
        }
    }

    function openOverlay(name, centerY) {
        shellRoot.lastCenterY = centerY || 0;
        activeOverlay = name;
        if (name === "emoji" || name === "gifs") emojiOverlay.open(name);        // two tabs of one drawer
        else if (name === "wifi" || name === "bluetooth" || name === "calendar" || name === "privacy")  // placed by their bar icon
            lazyDrawers[name].open(shellRoot.lastCenterY);
        else if (lazyDrawers[name]) lazyDrawers[name].open();
        else console.warn("openOverlay: no drawer", name);
        // keep the keyboard stacked above whatever just opened (it types into overlays too)
        if (osk.shown) oskRaise.restart();
    }

    function closeAllOverlays() {
        activeOverlay = "";
        hoverMode = false;
        for (const k in lazyDrawers) lazyDrawers[k].close();   // only built drawers do anything
    }

    // 0. Wallpaper, drawn by the shell (crossfades on change; replaces hyprpaper)
    Variants {
        model: Quickshell.screens
        Background {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    // 1. Caelestia-style frame: the left bar + a thin rounded border around each screen
    Variants {
        model: Quickshell.screens

        Frame {
            required property ShellScreen modelData
            screen: modelData
            onEdgeHovered: if (shellRoot.activeOverlay === "") osd.show(osd.focusKind)
            // music drawer from the top edge: hover opens it (only while a player exists), click pins/toggles
            onTopHovered: if (Mpris.players.values.length > 0) shellRoot.hoverOverlay("media")
            onTopClicked: shellRoot.toggleOverlay("media")
            onOpenApps: shellRoot.toggleOverlay("apps")
            onTopHoverChanged: shellRoot.edgeHover = topHover ? "media" : ""

            Waybar {
                id: waybar
                activeOverlay: shellRoot.activeOverlay
                onOpenWifi: (centerY) => shellRoot.toggleOverlay("wifi", centerY)
                onOpenBluetooth: (centerY) => shellRoot.toggleOverlay("bluetooth", centerY)
                onOpenPower: shellRoot.toggleOverlay("power")
                onOpenLauncher: shellRoot.toggleOverlay("apps")   // bar logo → app grid (Super+Space is search)
                onOpenCalendar: (centerY) => shellRoot.toggleOverlay("calendar", centerY)
                onOpenPrivacy: (centerY) => shellRoot.toggleOverlay("privacy", centerY)
                onOpenWallpaper: shellRoot.toggleOverlay("wallpaper")
                onOpenControlCenter: shellRoot.toggleOverlay("controlcenter")
                onHoverOpen: (name, centerY) => { shellRoot.barZones = zones(); shellRoot.hoverOverlay(name, centerY); }
                onHoverTargetChanged: {
                    shellRoot.barHover = hoverTarget;
                    shellRoot.prefetch(hoverTarget);   // build its drawer in the background before the hover opens it
                }
            }
        }
    }



    // On-screen keyboard (Super+/): types into the focused window via wtype, never takes focus itself
    OnScreenKeyboard { id: osk }
    Timer { id: oskRaise; interval: 150; onTriggered: osk.raise() }

    // Lock screen (iPhone-style; real WlSessionLock + PAM)
    LockScreen { id: lockScreen }
    // screen time stops counting while locked (also brings the tracker up at start)
    Binding { target: ScreenTime; property: "locked"; value: lockScreen.locked }

    // Screenshot tool (freeze → pick region/window/screen → save + copy + preview)
    ScreenshotOverlay {
        id: screenshotTool
        onToastRequested: (msg, icon, clr) => toastPopup.showToast(msg, icon, clr)
        // the picker now shows the frozen screen (drawers included): close the live drawers
        // behind it, so they neither take the keyboard from the picker nor stay open afterwards
        onFrozen: if (shellRoot.activeOverlay !== "") shellRoot.closeAllOverlays()
    }



    // Desktop Bento Widgets Suite (Clock, System Health, Media, Quick Apps, Daily Focus)
    DesktopWidgets {
        id: desktopWidgets
        onRequestOverlay: (name) => shellRoot.toggleOverlay(name)
    }

    // 2. Every drawer and pop-up lives in ONE always-mapped window (DrawerHost), Caelestia-style:
    //    opening a drawer only shows an Item. No new window / render thread / GL context.
    //    Order = stacking: drawers, then notifications, OSD, toast on top.
    DrawerHost {
        id: drawerHost
        activeOverlay: shellRoot.activeOverlay
        drawerVisible: {
            for (const k in shellRoot.lazyDrawers) if (shellRoot.lazyDrawers[k].shown) return true;
            return false;
        }
        popupVisible: notificationPopups.visible || osd.visible || toastPopup.visible || airDropPopup.visible
        osdItem: osd.visible ? osd.inputItem : null
        notifItem: notificationPopups.visible ? notificationPopups.inputItem : null
        airdropItem: airDropPopup.visible ? airDropPopup.inputItem : null
        hoverMode: shellRoot.hoverMode
        barHover: shellRoot.barHover
        // the hover drawers (wifi, bluetooth, calendar, media) have a body; the rest give null
        hoverBody: shellRoot.lazyDrawers[shellRoot.activeOverlay] ? shellRoot.lazyDrawers[shellRoot.activeOverlay].bodyItem : null
        barZones: shellRoot.barZones
        edgeHover: shellRoot.edgeHover
        onHoverLeft: shellRoot.closeAllOverlays()
        onHoverSwitch: (name, centerY) => shellRoot.hoverOverlay(name, centerY)
        onHoverPin: shellRoot.hoverMode = false

        // Desktop overview (Super+Tab)
        LazyDrawer {
            id: overviewOverlay
            sourceComponent: Component {
                OverviewOverlay {
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "overview") shellRoot.activeOverlay = "";
                    }
                }
            }
        }

        // Game library, bottom drawer (Super+G)
        LazyDrawer {
            id: gamesOverlay
            sourceComponent: Component {
                GamesOverlay {
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "games") shellRoot.activeOverlay = "";
                    }
                }
            }
        }

        // Theme picker (system-wide themes via `atelier-theme`)
        LazyDrawer {
            id: themeOverlay
            sourceComponent: Component {
                ThemeOverlay {
                    onToastRequested: (msg, icon, clr) => toastPopup.showToast(msg, icon, clr)
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "theme") shellRoot.activeOverlay = "";
                    }
                }
            }
        }
        // Control center: toggles, sliders, notification history (music lives in the top-edge drawer)
        LazyDrawer {
            id: controlCenter
            persistent: true
            sourceComponent: Component {
                ControlCenter {
                    onRequestOverlay: (name) => shellRoot.toggleOverlay(name)
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "controlcenter") shellRoot.activeOverlay = "";
                    }
                }
            }
        }
        // 2. Native Quickshell Overlays (Mutually Exclusive Slide-Out Drawers)
        LazyDrawer {
            id: wifiOverlay
            sourceComponent: Component {
                WifiOverlay {
                    isLight: shellRoot.isLight
                    onToastRequested: (msg, icon, clr) => toastPopup.showToast(msg, icon, clr)
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "wifi") shellRoot.activeOverlay = "";
                    }
                }
            }
        }
        LazyDrawer {
            id: bluetoothOverlay
            sourceComponent: Component {
                BluetoothOverlay {
                    isLight: shellRoot.isLight
                    onToastRequested: (msg, icon, clr) => toastPopup.showToast(msg, icon, clr)
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "bluetooth") shellRoot.activeOverlay = "";
                    }
                }
            }
        }
        LazyDrawer {
            id: privacyOverlay
            sourceComponent: Component {
                PrivacyOverlay {
                    isLight: shellRoot.isLight
                    onClosedSignal: { if (shellRoot.activeOverlay === "privacy") shellRoot.activeOverlay = ""; }
                }
            }
        }
        LazyDrawer {
            id: powerOverlay
            sourceComponent: Component {
                PowerOverlay {
                    isLight: shellRoot.isLight
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "power") shellRoot.activeOverlay = "";
                    }
                }
            }
        }
        LazyDrawer {
            id: launcherOverlay
            persistent: true
            sourceComponent: Component {
                LauncherOverlay {
                    isLight: shellRoot.isLight
                    onRequestOverlay: (name) => shellRoot.toggleOverlay(name)
                    onToastRequested: (msg, icon, clr) => toastPopup.showToast(msg, icon, clr)
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "launcher") shellRoot.activeOverlay = "";
                    }
                }
            }
        }
        // App grid (bar logo, Super+D)
        LazyDrawer {
            id: appsOverlay
            persistent: true
            sourceComponent: Component {
                AppsOverlay {
                    isLight: shellRoot.isLight
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "apps") shellRoot.activeOverlay = "";
                    }
                }
            }
        }
        // Camera (Super+Shift+C): top drawer under the webcam; camera only on while it's open
        LazyDrawer {
            id: cameraOverlay
            sourceComponent: Component {
                CameraOverlay {
                    isLight: shellRoot.isLight
                    onClosedSignal: { if (shellRoot.activeOverlay === "camera") shellRoot.activeOverlay = ""; }
                }
            }
        }
        LazyDrawer {
            id: clipboardOverlay
            sourceComponent: Component {
                ClipboardOverlay {
                    isLight: shellRoot.isLight
                    onItemCopied: (msg) => toastPopup.showToast(msg, "󰅌", Atelier.blue)
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "clipboard") shellRoot.activeOverlay = "";
                    }
                }
            }
        }
        // Music drawer (top edge: hover the middle of the top edge, Super+M)
        LazyDrawer {
            id: mediaOverlay
            persistent: true
            hold: item !== null && item.sleepAt > 0   // its sleep timer keeps running
            sourceComponent: Component {
                MediaOverlay {
                    isLight: shellRoot.isLight
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "media") shellRoot.activeOverlay = "";
                    }
                }
            }
        }
        LazyDrawer {
            id: keybindsOverlay
            sourceComponent: Component {
                KeybindsOverlay {
                    isLight: shellRoot.isLight
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "keybinds") shellRoot.activeOverlay = "";
                    }
                }
            }
        }
        LazyDrawer {
            id: sysMonOverlay
            sourceComponent: Component {
                SysMonOverlay {
                    isLight: shellRoot.isLight
                    onClosedSignal: { if (shellRoot.activeOverlay === "sysmon") shellRoot.activeOverlay = ""; }
                }
            }
        }
        LazyDrawer {
            id: timerOverlay
            sourceComponent: Component {
                TimerOverlay {
                    isLight: shellRoot.isLight
                    onClosedSignal: { if (shellRoot.activeOverlay === "timers") shellRoot.activeOverlay = ""; }
                }
            }
        }
        LazyDrawer {
            id: colorPickerOverlay
            sourceComponent: Component {
                ColorPickerOverlay {
                    isLight: shellRoot.isLight
                    onClosedSignal: { if (shellRoot.activeOverlay === "colors") shellRoot.activeOverlay = ""; }
                }
            }
        }
        LazyDrawer {
            id: windowSwitcher
            persistent: true
            sourceComponent: Component {
                WindowSwitcher {
                    isLight: shellRoot.isLight
                    onClosedSignal: { if (shellRoot.activeOverlay === "switcher") shellRoot.activeOverlay = ""; }
                }
            }
        }
        LazyDrawer {
            id: calendarOverlay
            sourceComponent: Component {
                CalendarOverlay {
                    isLight: shellRoot.isLight
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "calendar") shellRoot.activeOverlay = "";
                    }
                }
            }
        }
        LazyDrawer {
            id: wallpaperOverlay
            sourceComponent: Component {
                WallpaperOverlay {
                    isLight: shellRoot.isLight
                    onWallpaperApplied: (name) => toastPopup.showToast("Wallpaper: " + name, "󰸉", Atelier.accent)
                    onToastRequested: (msg, icon, clr) => toastPopup.showToast(msg, icon, clr)
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "wallpaper") shellRoot.activeOverlay = "";
                    }
                }
            }
        }
        // Emoji picker + GIF finder (bottom edge; Super+; / Super+Shift+;)
        LazyDrawer {
            id: emojiOverlay
            sourceComponent: Component {
                EmojiOverlay {
                    isLight: shellRoot.isLight
                    onToastRequested: (msg, icon, clr) => toastPopup.showToast(msg, icon, clr)
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "emoji" || shellRoot.activeOverlay === "gifs") shellRoot.activeOverlay = "";
                    }
                }
            }
        }
        // Settings (right-edge drawer; edits settings.json live)
        LazyDrawer {
            id: settingsApp
            sourceComponent: Component {
                SettingsApp {
                    isLight: shellRoot.isLight
                    onRequestOverlay: (name) => shellRoot.toggleOverlay(name)
                    onClosedSignal: {
                        if (shellRoot.activeOverlay === "settings") shellRoot.activeOverlay = "";
                    }
                }
            }
        }
        // Notification pop-ups (the shell is the notification daemon — see Notifs.qml)
        NotificationPopups { id: notificationPopups }
        // AirDrop requests / transfers (services/AirDrop.qml, owly)
        AirDropPopup { id: airDropPopup }

        // Volume / brightness OSD (one slider that updates in place)
        Osd {
            id: osd
            suppressed: shellRoot.activeOverlay === "controlcenter"
        }
        ToastPopup {
            id: toastPopup
        }
    }

    // Background services that must run from login (singletons only start when first used):
    // battery alerts, idle & sleep (writes hypridle's config), update checks, plugged-in drives
    readonly property var _services: [Battery, Idle, Updates, Drives, Timers, ColorPicker]
    Connections {
        target: Battery
        function onToast(msg, icon, clr) { toastPopup.showToast(msg, icon, clr); }
    }
    Connections {
        target: Drives
        function onToast(msg, icon, clr) { toastPopup.showToast(msg, icon, clr); }
    }
    Connections {
        target: Timers
        function onToast(msg, icon, clr) { toastPopup.showToast(msg, icon, clr); }
    }
    Connections {
        target: ColorPicker
        function onToast(msg, icon, clr) { toastPopup.showToast(msg, icon, clr); }
    }

    // 3. IPC Handlers for External CLI & Keybindings (Routed Through Controller)
    // IPC handlers call toggleOverlay without centerY — defaults to 0 (overlays fall back to screen center)
    Scope {
        // Lazy drawers (components/LazyDrawer.qml), for the perf-audit skill:
        //   qs ipc call drawers status | warmAll | dropAll
        IpcHandler {
            target: "drawers"
            function status(): string {
                return Object.keys(shellRoot.lazyDrawers).map(k => k + (shellRoot.lazyDrawers[k].item ? (shellRoot.lazyDrawers[k].persistent ? " persistent" : " loaded") : " -")).join("\n");
            }
            function warmAll(): void { for (const k in shellRoot.lazyDrawers) shellRoot.lazyDrawers[k].prefetch(); }
            function dropAll(): void {
                for (const k in shellRoot.lazyDrawers) {
                    const d = shellRoot.lazyDrawers[k];
                    if (!d.shown && !d.hold) d.active = false;
                }
            }
        }
        IpcHandler {
            target: "wifi"
            function toggle() { shellRoot.toggleOverlay("wifi"); }
            function open() { if (shellRoot.activeOverlay !== "wifi") shellRoot.toggleOverlay("wifi"); }
            function close() { if (shellRoot.activeOverlay === "wifi") shellRoot.closeAllOverlays(); }
        }

        IpcHandler {
            target: "privacy"
            function toggle() { shellRoot.toggleOverlay("privacy"); }
            function open() { if (shellRoot.activeOverlay !== "privacy") shellRoot.toggleOverlay("privacy"); }
            function close() { if (shellRoot.activeOverlay === "privacy") shellRoot.closeAllOverlays(); }
        }

        IpcHandler {
            target: "bluetooth"
            function toggle() { shellRoot.toggleOverlay("bluetooth"); }
            function open() { if (shellRoot.activeOverlay !== "bluetooth") shellRoot.toggleOverlay("bluetooth"); }
            function close() { if (shellRoot.activeOverlay === "bluetooth") shellRoot.closeAllOverlays(); }
        }

        IpcHandler {
            target: "power"
            function toggle() { shellRoot.toggleOverlay("power"); }
            function open() { if (shellRoot.activeOverlay !== "power") shellRoot.toggleOverlay("power"); }
            function close() { if (shellRoot.activeOverlay === "power") shellRoot.closeAllOverlays(); }
        }

        IpcHandler {
            target: "launcher"
            function search(query: string): void {
                if (shellRoot.activeOverlay !== "launcher") shellRoot.toggleOverlay("launcher");
                launcherOverlay.call("openWith", query);
            }
            function toggle() { shellRoot.toggleOverlay("launcher"); }
            function open() { if (shellRoot.activeOverlay !== "launcher") shellRoot.toggleOverlay("launcher"); }
            function close() { if (shellRoot.activeOverlay === "launcher") shellRoot.closeAllOverlays(); }
        }

        IpcHandler {
            target: "clipboard"
            function toggle() { shellRoot.toggleOverlay("clipboard"); }
            function open() { if (shellRoot.activeOverlay !== "clipboard") shellRoot.toggleOverlay("clipboard"); }
            function close() { if (shellRoot.activeOverlay === "clipboard") shellRoot.closeAllOverlays(); }
        }

        IpcHandler {
            target: "apps"
            function toggle(): void { shellRoot.toggleOverlay("apps"); }
            function open(): void { if (shellRoot.activeOverlay !== "apps") shellRoot.toggleOverlay("apps"); }
            function close(): void { if (shellRoot.activeOverlay === "apps") shellRoot.closeAllOverlays(); }
        }
        IpcHandler {
            target: "updates"
            function check(): void { Updates.check(); }
            function run(): void { Updates.run(); }
            function count(): int { return Updates.count; }
        }
        IpcHandler {
            target: "sysmon"
            function toggle(): void { shellRoot.toggleOverlay("sysmon"); }
            function open(): void { if (shellRoot.activeOverlay !== "sysmon") shellRoot.toggleOverlay("sysmon"); }
            function close(): void { if (shellRoot.activeOverlay === "sysmon") shellRoot.closeAllOverlays(); }
            function tab(t: string): void {
                if (shellRoot.activeOverlay !== "sysmon") shellRoot.toggleOverlay("sysmon");
                sysMonOverlay.call("setTab", t);
            }
        }
        IpcHandler {
            target: "timers"
            function toggle(): void { shellRoot.toggleOverlay("timers"); }
            function open(): void { if (shellRoot.activeOverlay !== "timers") shellRoot.toggleOverlay("timers"); }
            function close(): void { if (shellRoot.activeOverlay === "timers") shellRoot.closeAllOverlays(); }
            function tab(t: string): void {
                if (shellRoot.activeOverlay !== "timers") shellRoot.toggleOverlay("timers");
                timerOverlay.call("setTab", t);
            }
            // qs ipc call timers start "10m tea"  → returns the new timer's id (-1 = not understood)
            function start(spec: string): int {
                const m = spec.trim().match(/^(\S+)\s*(.*)$/);
                const id = m ? Timers.add(Timers.parse(m[1]), m[2]) : -1;
                if (id > 0) toastPopup.showToast("Timer started · " + m[1], "󱎫", Atelier.peach);
                return id;
            }
            function clear(): void { Timers.clearAll(); }
            function stopwatch(): void { Timers.swToggle(); }
            function pomodoro(): void { Timers.pomoToggle(); }
            function count(): int { return Timers.runningCount; }
        }
        IpcHandler {
            target: "colorpicker"
            function pick(): void { shellRoot.closeAllOverlays(); ColorPicker.pick(); }
            function toggle(): void { shellRoot.toggleOverlay("colors"); }
            function open(): void { if (shellRoot.activeOverlay !== "colors") shellRoot.toggleOverlay("colors"); }
            function close(): void { if (shellRoot.activeOverlay === "colors") shellRoot.closeAllOverlays(); }
            function last(): string { return ColorPicker.last; }
            function clear(): void { ColorPicker.clear(); }
        }
        IpcHandler {
            target: "switcher"
            function _go(d: int): void {
                if (shellRoot.activeOverlay !== "switcher") { shellRoot.closeAllOverlays(); shellRoot.activeOverlay = "switcher"; }
                windowSwitcher.call("step", d);
            }
            function next(): void { _go(1); }
            function prev(): void { _go(-1); }
            function commit(): void { windowSwitcher.call("commit"); }
            function cancel(): void { windowSwitcher.call("cancel"); }
        }
        IpcHandler {
            target: "calendar"
            function toggle() { shellRoot.toggleOverlay("calendar"); }
            function open() { if (shellRoot.activeOverlay !== "calendar") shellRoot.toggleOverlay("calendar"); }
            function close() { if (shellRoot.activeOverlay === "calendar") shellRoot.closeAllOverlays(); }
        }

        IpcHandler {
            target: "emoji"
            function toggle(): void { shellRoot.toggleOverlay("emoji"); }
            function gifs(): void { shellRoot.toggleOverlay("gifs"); }
            function open(): void { if (shellRoot.activeOverlay !== "emoji") shellRoot.toggleOverlay("emoji"); }
            function close(): void { if (shellRoot.activeOverlay === "emoji" || shellRoot.activeOverlay === "gifs") shellRoot.closeAllOverlays(); }
            // `qs ipc call emoji search party` / `qs ipc call emoji searchGifs cat`
            function search(q: string): void { if (shellRoot.activeOverlay !== "emoji") shellRoot.toggleOverlay("emoji"); emojiOverlay.call("openSearch", "emoji", q); }
            function searchGifs(q: string): void { if (shellRoot.activeOverlay !== "gifs") shellRoot.toggleOverlay("gifs"); emojiOverlay.call("openSearch", "gifs", q); }
        }

        IpcHandler {
            target: "keybinds"
            function toggle(): void { shellRoot.toggleOverlay("keybinds"); }
            function open(): void { if (shellRoot.activeOverlay !== "keybinds") shellRoot.toggleOverlay("keybinds"); }
            function close(): void { if (shellRoot.activeOverlay === "keybinds") shellRoot.closeAllOverlays(); }
        }

        IpcHandler {
            target: "controlcenter"
            function toggle(): void { shellRoot.toggleOverlay("controlcenter"); }
            function open(): void { if (shellRoot.activeOverlay !== "controlcenter") shellRoot.toggleOverlay("controlcenter"); }
            function close(): void { if (shellRoot.activeOverlay === "controlcenter") shellRoot.closeAllOverlays(); }
        }

        IpcHandler {
            target: "overview"
            function toggle(): void { shellRoot.toggleOverlay("overview"); }
            function open(): void { if (shellRoot.activeOverlay !== "overview") shellRoot.toggleOverlay("overview"); }
            function close(): void { if (shellRoot.activeOverlay === "overview") shellRoot.closeAllOverlays(); }
        }

        IpcHandler {
            target: "games"
            function toggle(): void { shellRoot.toggleOverlay("games"); }
            function open(): void { if (shellRoot.activeOverlay !== "games") shellRoot.toggleOverlay("games"); }
            function close(): void { if (shellRoot.activeOverlay === "games") shellRoot.closeAllOverlays(); }
            function search(q: string): void {
                if (shellRoot.activeOverlay !== "games") shellRoot.toggleOverlay("games");
                gamesOverlay.set("query", q);
            }
        }

        IpcHandler {
            target: "keyboard"
            function toggle(): void { osk.toggle(); }
            function open(): void { osk.open(); }
            function close(): void { osk.close(); }
        }

        IpcHandler {
            target: "settings"
            function toggle(): void { shellRoot.toggleOverlay("settings"); }
            function open(page: string): void { shellRoot.toggleOverlay("settings:" + page); }     // page: any id in SettingsApp.pages (appearance, bar, widgets, windows, tools, displays, power, …)
            function close(): void { if (shellRoot.activeOverlay === "settings") shellRoot.closeAllOverlays(); }
            function cycleLayout(): string {
                const l = Settings.cycleLayout();
                toastPopup.showToast("Layout: " + l.charAt(0).toUpperCase() + l.slice(1), "󰕰", Atelier.accent);
                return l;
            }
            // scripting: `qs ipc call settings set windows gapsOut 14` (value is JSON)
            function set(section: string, key: string, value: string): string {
                try { Settings[section][key] = JSON.parse(value); return "ok"; } catch (e) { return "error: " + e; }
            }
            function get(section: string, key: string): string {
                try { return JSON.stringify(Settings[section][key]); } catch (e) { return "error: " + e; }
            }
        }

        IpcHandler {
            target: "profiles"
            function list(): string { return Profiles.list.map(p => p.name).join("\n"); }
            function save(name: string): string { return Profiles.save(name) || "error: bad name"; }
            function apply(name: string): string {
                return Profiles.apply(name) ? "ok" : "error: no profile " + name;
            }
            function active(): string { return Profiles.active; }
        }
        // switching profile automatically (display plugged in / out) says so
        Connections {
            target: Profiles
            function onActiveChanged() { if (Profiles.ready && Profiles.active) toastPopup.showToast("Profile: " + Profiles.active, "󰆓", Atelier.accent); }
        }

        IpcHandler {
            target: "lock"
            function lock(): void { shellRoot.closeAllOverlays(); lockScreen.lock(); }
            function preview(): void { shellRoot.closeAllOverlays(); lockScreen.preview(); }   // try the design, no real lock
            // try a built-in style without switching to it: cupertino, hyper, harmony, oxygen, material, dot, depth, atelier
            function previewStyle(style: string): void { shellRoot.closeAllOverlays(); lockScreen.previewStyle(style); }
            function isLocked(): bool { return lockScreen.isLocked; }
            function previewAuth(): void { shellRoot.closeAllOverlays(); lockScreen.previewAuth(); }
            function stopPreview(): void { lockScreen.stopPreview(); }
            function edit(): void { shellRoot.closeAllOverlays(); lockScreen.edit(); }       // Depth lock editor (preview only)
            // no unlock() on purpose: only the password can unlock
        }

        IpcHandler {
            target: "phonecam"
            function start(): void { PhoneCam.start("user"); }
            function stop(): void { PhoneCam.stop(); }
            function toggle(): void { PhoneCam.toggle(); }
            function status(): string { return PhoneCam.summary; }
        }

        IpcHandler {
            target: "camera"
            function toggle(): void { shellRoot.toggleOverlay("camera"); }
            function open(): void  { if (shellRoot.activeOverlay !== "camera") shellRoot.toggleOverlay("camera"); }
            function close(): void { if (shellRoot.activeOverlay === "camera") shellRoot.closeAllOverlays(); }
            function gallery(): void { open(); cameraOverlay.call("showGallery"); }
        }

        IpcHandler {
            target: "airdrop"
            function on(): void { AirDrop.setEnabled(true); }
            function off(): void { AirDrop.setEnabled(false); }
            function toggle(): void { AirDrop.toggle(); }
            function status(): string { return AirDrop.summary + (AirDrop.phase !== "idle" ? " · " + AirDrop.phase : ""); }
            function send(path: string): void { AirDrop.send([path]); }
            // several files, one path per line (scripts/airdrop-send.sh, the Dolphin service menu)
            function sendFiles(paths: string): void { AirDrop.send(paths.split("\n").filter(p => p !== "")); }
            function accept(): void { AirDrop.accept(false); }
            function decline(): void { AirDrop.decline(); }
            function cancel(): void { AirDrop.cancelSend(); }
            function sendTo(name: string): void { AirDrop.sendTo(name); }   // pick from the card's list
        }

        IpcHandler {
            target: "screenshot"
            function region(): void { shellRoot.toggleOverlay("screenshot"); }
            function window(): void { shellRoot.toggleOverlay("screenshot-window"); }
            function screen(): void { shellRoot.toggleOverlay("screenshot-screen"); }   // instant, no picker
            function full(): void { shellRoot.toggleOverlay("screenshot-screen"); }
            function last(): string { return screenshotTool.lastPath; }
            function cancel(): void { screenshotTool.cancel(); }
        }

        IpcHandler {
            target: "media"
            function toggle(): void { shellRoot.toggleOverlay("media"); }
            function open(): void { if (shellRoot.activeOverlay !== "media") shellRoot.toggleOverlay("media"); }
            function close(): void { if (shellRoot.activeOverlay === "media") shellRoot.closeAllOverlays(); }
            // open on a tab: lyrics | output | recent | timer
            function tab(name: string): void { mediaOverlay.set("tab", name); if (shellRoot.activeOverlay !== "media") shellRoot.toggleOverlay("media"); }
        }

        IpcHandler {
            target: "record"
            function toggle(): void { shellRoot.toggleOverlay("record"); }          // pick a region, or stop
            function region(): void { if (!Recorder.recording) shellRoot.toggleOverlay("record"); }
            function window(): void { if (!Recorder.recording) shellRoot.toggleOverlay("record-window"); }
            function screen(): void { if (!Recorder.recording) shellRoot.toggleOverlay("record-screen"); }
            function stop(): void { Recorder.stop(); }
            function isRecording(): bool { return Recorder.recording; }
            function last(): string { return Recorder.lastPath; }
        }
        Connections {
            target: Recorder
            // the same preview card as a screenshot: thumbnail, open, folder, AirDrop, delete
            function onFinished(path, seconds) { screenshotTool.showRecording(path, seconds); }
            function onFailed(reason) { toastPopup.showToast(reason, "󰀦", Atelier.red); }
        }

        IpcHandler {
            target: "nightlight"
            function toggle(): void { NightLight.toggle(); }
            function on(): void { NightLight.set(true); }
            function off(): void { NightLight.set(false); }
            function isOn(): bool { return NightLight.active; }
            function setTemperature(k: int): void { Settings.nightLight.temperature = Math.max(2500, Math.min(6000, k)); }
        }
        Timer { id: nightLightToasts; property bool ready: false; interval: 3000; running: true; onTriggered: ready = true }
        Connections {
            target: NightLight
            function onActiveChanged() {
                if (!nightLightToasts.ready) return;   // not on shell start
                if (!NightLight.available) { toastPopup.showToast("Install hyprsunset for night light", "󰀦", Atelier.red); return; }
                toastPopup.showToast(NightLight.active ? "Night light on · " + NightLight.temperature + " K" : "Night light off",
                                     NightLight.active ? "󰖔" : "󰖙", Atelier.peach);
            }
        }

        IpcHandler {
            target: "osd"
            function brightnessUp(): void { osd.brightnessStep(0.05); }
            function brightnessDown(): void { osd.brightnessStep(-0.05); }
            function volumeUp(): void { Quickshell.execDetached(["wpctl", "set-volume", "-l", "1", "@DEFAULT_AUDIO_SINK@", "5%+"]); }
            function volumeDown(): void { Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"]); }
            function mute(): void { Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]); }
            function volume(): real { return osd.volume; }
            function brightness(): real { return SysState.brightness; }
            // same code paths the OSD sliders use when dragged
            function setVolume(v: real): void { osd.show("volume"); osd.setVolume(v); }
            function setBrightness(v: real): void { osd.setBrightness(v); }
        }

        IpcHandler {
            target: "mode"
            function set(name: string): void { Perf.set(name); }
            function cycle(): void { Perf.cycle(); }
            function toggleGame(): void { Perf.toggleGame(); }
            function toggleDev(): void { Perf.toggleDev(); }
            function get(): string { return Perf.mode; }
        }

        Connections {
            target: Perf
            function onSwitched(mode, automatic) {
                const icon = mode === "game" ? "󰊗" : mode === "dev" ? "󰅩" : "󰍹";
                const clr = mode === "game" ? Atelier.peach : mode === "dev" ? Atelier.sapphire : Atelier.green;
                toastPopup.showToast((automatic ? "Auto: " : "") + Perf.label + (mode === "normal" ? " restored" : " on"), icon, clr);
            }
        }

        IpcHandler {
            target: "notifications"
            function clear(): void { Notifs.clearAll(); }
            function toggleDnd(): void { Notifs.dnd = !Notifs.dnd; }
            function isDnd(): bool { return Notifs.dnd; }
            function count(): int { return Notifs.count; }
        }

        IpcHandler {
            target: "theme"
            function toggle(): void { shellRoot.toggleOverlay("theme"); }      // open/close the picker
            function mode(): void { SysState.toggleTheme(); }                  // light <-> dark
            function cycle(): void { SysState.toggleTheme(); }
            function apply(id: string): void { Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/atelier-theme", "apply", id]); }
            function current(): string { return Atelier.themeId; }
        }

        IpcHandler {
            target: "wallpaper"
            function set(path: string): void { Wallpaper.set(path); }
            function next(): void { Wallpaper.next(); }          // Super+Alt+Right
            function prev(): void { Wallpaper.prev(); }          // Super+Alt+Left
            function random(): void { Wallpaper.random(); }      // Super+Alt+I
            function toggle() { shellRoot.toggleOverlay("wallpaper"); }
            function open() { if (shellRoot.activeOverlay !== "wallpaper") shellRoot.toggleOverlay("wallpaper"); }
            function close() { if (shellRoot.activeOverlay === "wallpaper") shellRoot.closeAllOverlays(); }
            // open on the Wallhaven tab; a topic id (nature, space, …) or any search words
            function wallhaven(what: string): void {
                if (shellRoot.activeOverlay !== "wallpaper") shellRoot.toggleOverlay("wallpaper");
                const w = wallpaperOverlay;
                const t = w.topics.find(x => x.id === what);
                w.whTopic = t ? t.id : "";
                w.whQuery = t ? "" : what;
                w.activeTab = "wallhaven";
                w.searchWallhaven(true);
            }
        }
    }
}
