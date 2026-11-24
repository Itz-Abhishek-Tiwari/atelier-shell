//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
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
        if (prev === "wifi") wifiOverlay.hideNow();
        else if (prev === "bluetooth") bluetoothOverlay.hideNow();
        else if (prev === "calendar") calendarOverlay.hideNow();
        else if (prev === "media") mediaOverlay.hideNow();
    }
    property string edgeHover: ""         // "media" while the pointer is on the top-edge sensor

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
            emojiOverlay.setTab(name);
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
        if (name === "wifi") wifiOverlay.open(shellRoot.lastCenterY);
        else if (name === "bluetooth") bluetoothOverlay.open(shellRoot.lastCenterY);
        else if (name === "power") powerOverlay.open();
        else if (name === "launcher") launcherOverlay.open();
        else if (name === "apps") appsOverlay.open();
        else if (name === "calendar") calendarOverlay.open(shellRoot.lastCenterY);
        else if (name === "wallpaper") wallpaperOverlay.open();
        else if (name === "clipboard") clipboardOverlay.open();
        else if (name === "camera") cameraOverlay.open();
        else if (name === "controlcenter") controlCenter.open();
        else if (name === "theme") themeOverlay.open();
        else if (name === "overview") overviewOverlay.open();
        else if (name === "games") gamesOverlay.open();
        else if (name === "media") mediaOverlay.open();
        else if (name === "keybinds") keybindsOverlay.open();
        else if (name === "settings") settingsApp.open();
        else if (name === "emoji" || name === "gifs") emojiOverlay.open(name);
        else if (name === "sysmon") sysMonOverlay.open();
        else if (name === "timers") timerOverlay.open();
        else if (name === "colors") colorPickerOverlay.open();
        else if (name === "switcher") windowSwitcher.open();
        // keep the keyboard stacked above whatever just opened (it types into overlays too)
        if (osk.shown) oskRaise.restart();
    }

    function closeAllOverlays() {
        activeOverlay = "";
        hoverMode = false;
        wifiOverlay.close();
        bluetoothOverlay.close();
        powerOverlay.close();
        launcherOverlay.close();
        appsOverlay.close();
        calendarOverlay.close();
        wallpaperOverlay.close();
        clipboardOverlay.close();
        cameraOverlay.close();
        controlCenter.close();
        themeOverlay.close();
        overviewOverlay.close();
        gamesOverlay.close();
        mediaOverlay.close();
        keybindsOverlay.close();
        settingsApp.close();
        emojiOverlay.close();
        sysMonOverlay.close();
        timerOverlay.close();
        colorPickerOverlay.close();
        windowSwitcher.close();
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
            onTopHoverChanged: shellRoot.edgeHover = topHover ? "media" : ""

            Waybar {
                activeOverlay: shellRoot.activeOverlay
                onOpenWifi: (centerY) => shellRoot.toggleOverlay("wifi", centerY)
                onOpenBluetooth: (centerY) => shellRoot.toggleOverlay("bluetooth", centerY)
                onOpenPower: shellRoot.toggleOverlay("power")
                onOpenLauncher: shellRoot.toggleOverlay("apps")   // bar logo → app grid (Super+Space is search)
                onOpenCalendar: (centerY) => shellRoot.toggleOverlay("calendar", centerY)
                onOpenWallpaper: shellRoot.toggleOverlay("wallpaper")
                onOpenControlCenter: shellRoot.toggleOverlay("controlcenter")
                onHoverOpen: (name, centerY) => { shellRoot.barZones = zones(); shellRoot.hoverOverlay(name, centerY); }
                onHoverTargetChanged: shellRoot.barHover = hoverTarget
            }
        }
    }


    // On-screen keyboard (Super+/): types into the focused window via wtype, never takes focus itself
    OnScreenKeyboard { id: osk }
    Timer { id: oskRaise; interval: 150; onTriggered: osk.raise() }

    // Lock screen (iPhone-style; real WlSessionLock + PAM)
    LockScreen { id: lockScreen }

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
        drawerVisible: wifiOverlay.visible || bluetoothOverlay.visible || powerOverlay.visible
                       || launcherOverlay.visible || calendarOverlay.visible || wallpaperOverlay.visible
                       || clipboardOverlay.visible || cameraOverlay.visible || controlCenter.visible || themeOverlay.visible
                       || overviewOverlay.visible || gamesOverlay.visible || mediaOverlay.visible
                       || keybindsOverlay.visible || appsOverlay.visible || settingsApp.visible || emojiOverlay.visible
                       || sysMonOverlay.visible || timerOverlay.visible || colorPickerOverlay.visible || windowSwitcher.visible
        popupVisible: notificationPopups.visible || osd.visible || toastPopup.visible || airDropPopup.visible
        osdItem: osd.visible ? osd.inputItem : null
        notifItem: notificationPopups.visible ? notificationPopups.inputItem : null
        airdropItem: airDropPopup.visible ? airDropPopup.inputItem : null
        hoverMode: shellRoot.hoverMode
        barHover: shellRoot.barHover
        hoverBody: shellRoot.activeOverlay === "wifi" ? wifiOverlay.bodyItem
                 : shellRoot.activeOverlay === "bluetooth" ? bluetoothOverlay.bodyItem
                 : shellRoot.activeOverlay === "calendar" ? calendarOverlay.bodyItem
                 : shellRoot.activeOverlay === "media" ? mediaOverlay.bodyItem : null
        barZones: shellRoot.barZones
        edgeHover: shellRoot.edgeHover
        onHoverLeft: shellRoot.closeAllOverlays()
        onHoverSwitch: (name, centerY) => shellRoot.hoverOverlay(name, centerY)
        onHoverPin: shellRoot.hoverMode = false

        // Desktop overview (Super+Tab)
        OverviewOverlay {
            id: overviewOverlay
            onClosedSignal: {
                if (shellRoot.activeOverlay === "overview") shellRoot.activeOverlay = "";
            }
        }

        // Game library, bottom drawer (Super+G)
        GamesOverlay {
            id: gamesOverlay
            onClosedSignal: {
                if (shellRoot.activeOverlay === "games") shellRoot.activeOverlay = "";
            }
        }

        // Theme picker (system-wide themes via `atelier-theme`)
        ThemeOverlay {
            id: themeOverlay
            onToastRequested: (msg, icon, clr) => toastPopup.showToast(msg, icon, clr)
            onClosedSignal: {
                if (shellRoot.activeOverlay === "theme") shellRoot.activeOverlay = "";
            }
        }
        // Control center: toggles, sliders, notification history (music lives in the top-edge drawer)
        ControlCenter {
            id: controlCenter
            onRequestOverlay: (name) => shellRoot.toggleOverlay(name)
            onClosedSignal: {
                if (shellRoot.activeOverlay === "controlcenter") shellRoot.activeOverlay = "";
            }
        }
        // 2. Native Quickshell Overlays (Mutually Exclusive Slide-Out Drawers)
        WifiOverlay {
            id: wifiOverlay
            isLight: shellRoot.isLight
            onToastRequested: (msg, icon, clr) => toastPopup.showToast(msg, icon, clr)
            onClosedSignal: {
                if (shellRoot.activeOverlay === "wifi") shellRoot.activeOverlay = "";
            }
        }
        BluetoothOverlay {
            id: bluetoothOverlay
            isLight: shellRoot.isLight
            onToastRequested: (msg, icon, clr) => toastPopup.showToast(msg, icon, clr)
            onClosedSignal: {
                if (shellRoot.activeOverlay === "bluetooth") shellRoot.activeOverlay = "";
            }
        }
        PowerOverlay {
            id: powerOverlay
            isLight: shellRoot.isLight
            onClosedSignal: {
                if (shellRoot.activeOverlay === "power") shellRoot.activeOverlay = "";
            }
        }
        LauncherOverlay {
            id: launcherOverlay
            isLight: shellRoot.isLight
            onRequestOverlay: (name) => shellRoot.toggleOverlay(name)
            onToastRequested: (msg, icon, clr) => toastPopup.showToast(msg, icon, clr)
            onClosedSignal: {
                if (shellRoot.activeOverlay === "launcher") shellRoot.activeOverlay = "";
            }
        }
        // App grid (bar logo, Super+D)
        AppsOverlay {
            id: appsOverlay
            isLight: shellRoot.isLight
            onClosedSignal: {
                if (shellRoot.activeOverlay === "apps") shellRoot.activeOverlay = "";
            }
        }
        // Camera (Super+Shift+C): top drawer under the webcam; camera only on while it's open
        CameraOverlay {
            id: cameraOverlay
            isLight: shellRoot.isLight
            onClosedSignal: { if (shellRoot.activeOverlay === "camera") shellRoot.activeOverlay = ""; }
        }
        ClipboardOverlay {
            id: clipboardOverlay
            isLight: shellRoot.isLight
            onItemCopied: (msg) => toastPopup.showToast(msg, "󰅌", Atelier.blue)
            onClosedSignal: {
                if (shellRoot.activeOverlay === "clipboard") shellRoot.activeOverlay = "";
            }
        }
        // Music drawer (top edge: hover the middle of the top edge, Super+M)
        MediaOverlay {
            id: mediaOverlay
            isLight: shellRoot.isLight
            onClosedSignal: {
                if (shellRoot.activeOverlay === "media") shellRoot.activeOverlay = "";
            }
        }
        KeybindsOverlay {
            id: keybindsOverlay
            isLight: shellRoot.isLight
            onClosedSignal: {
                if (shellRoot.activeOverlay === "keybinds") shellRoot.activeOverlay = "";
            }
        }
        SysMonOverlay {
            id: sysMonOverlay
            isLight: shellRoot.isLight
            onClosedSignal: { if (shellRoot.activeOverlay === "sysmon") shellRoot.activeOverlay = ""; }
        }
        TimerOverlay {
            id: timerOverlay
            isLight: shellRoot.isLight
            onClosedSignal: { if (shellRoot.activeOverlay === "timers") shellRoot.activeOverlay = ""; }
        }
        ColorPickerOverlay {
            id: colorPickerOverlay
            isLight: shellRoot.isLight
            onClosedSignal: { if (shellRoot.activeOverlay === "colors") shellRoot.activeOverlay = ""; }
        }
        WindowSwitcher {
            id: windowSwitcher
            isLight: shellRoot.isLight
            onClosedSignal: { if (shellRoot.activeOverlay === "switcher") shellRoot.activeOverlay = ""; }
        }
        CalendarOverlay {
            id: calendarOverlay
            isLight: shellRoot.isLight
            onClosedSignal: {
                if (shellRoot.activeOverlay === "calendar") shellRoot.activeOverlay = "";
            }
        }
        WallpaperOverlay {
            id: wallpaperOverlay
            isLight: shellRoot.isLight
            onWallpaperApplied: (name) => toastPopup.showToast("Wallpaper: " + name, "󰸉", Atelier.accent)
            onToastRequested: (msg, icon, clr) => toastPopup.showToast(msg, icon, clr)
            onClosedSignal: {
                if (shellRoot.activeOverlay === "wallpaper") shellRoot.activeOverlay = "";
            }
        }
        // Emoji picker + GIF finder (bottom edge; Super+; / Super+Shift+;)
        EmojiOverlay {
            id: emojiOverlay
            isLight: shellRoot.isLight
            onToastRequested: (msg, icon, clr) => toastPopup.showToast(msg, icon, clr)
            onClosedSignal: {
                if (shellRoot.activeOverlay === "emoji" || shellRoot.activeOverlay === "gifs") shellRoot.activeOverlay = "";
            }
        }
        // Settings (right-edge drawer; edits settings.json live)
        SettingsApp {
            id: settingsApp
            isLight: shellRoot.isLight
            onRequestOverlay: (name) => shellRoot.toggleOverlay(name)
            onClosedSignal: {
                if (shellRoot.activeOverlay === "settings") shellRoot.activeOverlay = "";
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
        IpcHandler {
            target: "wifi"
            function toggle() { shellRoot.toggleOverlay("wifi"); }
            function open() { if (shellRoot.activeOverlay !== "wifi") shellRoot.toggleOverlay("wifi"); }
            function close() { if (shellRoot.activeOverlay === "wifi") shellRoot.closeAllOverlays(); }
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
                launcherOverlay.openWith(query);
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
                sysMonOverlay.setTab(t);
            }
        }
        IpcHandler {
            target: "timers"
            function toggle(): void { shellRoot.toggleOverlay("timers"); }
            function open(): void { if (shellRoot.activeOverlay !== "timers") shellRoot.toggleOverlay("timers"); }
            function close(): void { if (shellRoot.activeOverlay === "timers") shellRoot.closeAllOverlays(); }
            function tab(t: string): void {
                if (shellRoot.activeOverlay !== "timers") shellRoot.toggleOverlay("timers");
                timerOverlay.setTab(t);
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
                windowSwitcher.step(d);
            }
            function next(): void { _go(1); }
            function prev(): void { _go(-1); }
            function commit(): void { windowSwitcher.commit(); }
            function cancel(): void { windowSwitcher.cancel(); }
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
            function search(q: string): void { if (shellRoot.activeOverlay !== "emoji") shellRoot.toggleOverlay("emoji"); emojiOverlay.openSearch("emoji", q); }
            function searchGifs(q: string): void { if (shellRoot.activeOverlay !== "gifs") shellRoot.toggleOverlay("gifs"); emojiOverlay.openSearch("gifs", q); }
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
                gamesOverlay.query = q;
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
            function gallery(): void { open(); cameraOverlay.showGallery(); }
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
            function tab(name: string): void { mediaOverlay.tab = name; if (shellRoot.activeOverlay !== "media") shellRoot.toggleOverlay("media"); }
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
            function apply(id: string): void { Quickshell.execDetached([themeOverlay.cli, "apply", id]); }
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
