pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Shared design tokens for the Caelestia-style frame + drawers.
// Colours come from the active system theme (~/.config/atelier/theme.json, written by
// `atelier-theme apply <id>`) and update live; Catppuccin Mocha is the fallback.
// Geometry and motion follow Caelestia.
Singleton {
    id: root

    // ── Active theme ─────────────────────────────────────────────────────────
    readonly property var fallback: ({
        id: "catppuccin-mocha", name: "Catppuccin Mocha", variant: "dark",
        colors: {
            base: "#1e1e2e", mantle: "#181825", crust: "#11111b", surface0: "#313244", surface1: "#45475a",
            surface2: "#585b70", overlay0: "#6c7086", overlay1: "#7f849c", text: "#cdd6f4", subtext1: "#bac2de",
            subtext0: "#a6adc8", red: "#f38ba8", peach: "#fab387", yellow: "#f9e2af", green: "#a6e3a1",
            teal: "#94e2d5", sky: "#89dceb", sapphire: "#74c7ec", blue: "#89b4fa", lavender: "#b4befe",
            mauve: "#cba6f7", pink: "#f5c2e7", accent: "#cba6f7", onAccent: "#11111b"
        }
    })
    readonly property var theme: {
        try {
            const t = JSON.parse(themeFile.text() || "null");
            if (t && t.colors && t.colors.base) return t;
        } catch (e) {}
        return fallback;
    }
    readonly property var c: theme.colors
    readonly property string themeId: theme.id
    readonly property string themeName: theme.name
    readonly property string mode: theme.variant === "light" ? "light" : "dark"
    readonly property bool isLight: mode === "light"

    FileView {
        id: themeFile
        path: Quickshell.env("HOME") + "/.config/atelier/theme.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    // "Caffeine": keeps the screen awake (IdleInhibitor lives in Frame.qml)
    property bool caffeine: false

    // ── Geometry ─────────────────────────────────────────────────────────────
    // (user-adjustable in the Settings app → Settings.qml / settings.json)
    // Traditional with the bar on top: a slim, flat macOS-style bar (no pills; Waybar.qml)
    readonly property bool flatBar: Settings.appearance.layout === "classic" && Settings.appearance.barPosition === "top"
    readonly property int barWidth: flatBar ? 32 : Settings.appearance.barWidth   // bar thickness (part of the frame)
    readonly property int frame: Settings.appearance.frame          // border thickness on top/right/bottom
    readonly property int rounding: Settings.appearance.rounding    // inner frame corners + drawer corners
    // Traditional layout (Settings → Bar → Layout): floating windows with title bars, and the
    // bottom frame edge becomes a bar holding the dock (part of the frame, like the top bar).
    // Not while the bar itself is on the bottom edge.
    readonly property bool classic: Settings.appearance.layout === "classic"
    readonly property bool dockOn: classic && Settings.appearance.barPosition !== "bottom"
    readonly property int dockHeight: Settings.dock.iconSize + 14
    // the dock as a shelf: only the middle of the bottom edge rises to dockHeight (Frame.qml Ring);
    // the rest of the edge stays a thin frame. Windows still keep clear of the full height.
    readonly property bool dockShelf: dockOn && Settings.dock.style !== "bar"
    readonly property int fillet: Math.min(22, rounding)            // concave join between drawer and frame

    // Where the bar lives. The bar is `barWidth` thick on that edge; the other edges get `frame`.
    readonly property string barEdge: ["left", "right", "top", "bottom"].indexOf(Settings.appearance.barPosition) >= 0
        ? Settings.appearance.barPosition : "left"
    readonly property bool barVertical: barEdge === "left" || barEdge === "right"
    readonly property int insetLeft: barEdge === "left" ? barWidth : frame
    readonly property int insetRight: barEdge === "right" ? barWidth : frame
    readonly property int insetTop: barEdge === "top" ? barWidth : frame
    readonly property int insetBottom: barEdge === "bottom" ? barWidth : dockOn ? dockHeight : frame
    readonly property int maxInset: Math.max(barWidth, frame, dockOn ? dockHeight : 0)
    function inset(edge) { return edge === "left" ? insetLeft : edge === "right" ? insetRight : edge === "top" ? insetTop : insetBottom; }

    // ── Palette roles (live) ─────────────────────────────────────────────────
    readonly property string font:      "SpaceMono Nerd Font Propo"   // numbers, glyphs, clocks
    readonly property string fontUi: "Inter"                         // labels and body text
    readonly property string fontDisplay: "Inter Display"            // big clocks and headings
    readonly property string fontEmoji: "Noto Color Emoji"

    // Type scale (px). Use these instead of bare numbers so the whole shell scales together.
    readonly property int fsMicro: 10
    readonly property int fsSm: 11      // captions, chips
    readonly property int fsMd: 12      // body
    readonly property int fsLg: 13      // emphasised body, buttons
    readonly property int fsXl: 15      // card and drawer titles
    readonly property int fsTitle: 22   // page titles

    // Corner radii: small controls / cards / panels
    readonly property int radiusSm: 10
    readonly property int radiusMd: 14
    readonly property int radiusLg: 18

    // 12-hour clock helpers (the atelier style: "03:49" + an AM/PM chip)
    readonly property bool clock24: Settings.general.clock24
    function hour12(d) { const h = clock24 ? d.getHours() : (d.getHours() % 12 || 12); return (h < 10 ? "0" : "") + h; }
    function ampm(d) { return clock24 ? "" : (d.getHours() < 12 ? "AM" : "PM"); }   // "" in 24h mode (chips hide)
    // the lock screens' own choice (Settings → Lock screen → Clock): system | 12 | 24
    readonly property bool lockClock24: Settings.lock.clock === "24" ? true : Settings.lock.clock === "12" ? false : clock24
    function lockHour(d) { const h = lockClock24 ? d.getHours() : (d.getHours() % 12 || 12); return (h < 10 ? "0" : "") + h; }
    function lockAmpm(d) { return lockClock24 ? "" : (d.getHours() < 12 ? "AM" : "PM"); }

    readonly property string userName: {
        const n = Settings.general.userName;
        if (n) return n;
        const u = Quickshell.env("USER") || "";
        return u ? u.charAt(0).toUpperCase() + u.slice(1) : "there";
    }

    readonly property color base: c.base
    readonly property color mantle: c.mantle
    readonly property color crust: c.crust
    readonly property color surface0: c.surface0
    readonly property color surface1: c.surface1
    readonly property color surface2: c.surface2
    readonly property color overlay0: c.overlay0
    readonly property color overlay1: c.overlay1
    readonly property color text: c.text
    readonly property color subtext1: c.subtext1
    readonly property color subtext: c.subtext0
    readonly property color red: c.red
    readonly property color peach: c.peach
    readonly property color yellow: c.yellow
    readonly property color green: c.green
    readonly property color teal: c.teal
    readonly property color sky: c.sky
    readonly property color sapphire: c.sapphire
    readonly property color blue: c.blue
    readonly property color lavender: c.lavender
    readonly property color mauve: c.mauve
    readonly property color pink: c.pink
    readonly property color accent: c.accent           // for coloured text, icons, rings and borders

    // ── Filled colours (selected chips, switches, active workspace, buttons) ──
    // Text on a filled colour is always the theme's light ink. fill(c) deepens c just enough
    // for that ink to reach 4.5:1 contrast, so no theme ends up with dark text on a mid-tone
    // colour (wallpaper themes did) or washed-out light text (light themes did). Use
    //   color: Atelier.fill(tint)   with   text color: Atelier.onFill
    readonly property color onFill: isLight ? c.base : c.text
    // (no "onAccent" alias: QML reads on+Capital names as signal handlers, so a property called
    // onAccent came out black and every chip/switch/OSD using it had black text on its fill)
    readonly property color accentFill: fill(accent)
    function luminance(col) {
        const f = u => u <= 0.04045 ? u / 12.92 : Math.pow((u + 0.055) / 1.055, 2.4);
        return 0.2126 * f(col.r) + 0.7152 * f(col.g) + 0.0722 * f(col.b);
    }
    function contrast(a, b) {
        const x = luminance(a), y = luminance(b);
        return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
    }
    function fill(col) {
        const ink = onFill, h = col.hslHue < 0 ? 0 : col.hslHue, sat = col.hslSaturation;
        let l = col.hslLightness, out = col;
        for (let i = 0; i < 40 && contrast(ink, out) < 4.5 && l > 0; i++) {
            l = Math.max(0, l - 0.02);
            out = Qt.hsla(h, sat, l, 1);
        }
        return out;
    }

    // The glass surface of the frame, bar and drawers
    // Game mode turns the compositor blur off, so translucent glass would show whatever is
    // behind it as ghost text: go fully opaque there (same colour, so the UI looks the same).
    // Hyprland applies layer rules (the glass blur threshold) only when a surface maps, so after
    // the glass opacity changes the frame and drawer host re-map themselves (remapToken).
    property int remapToken: 0
    Timer { id: remapTimer; interval: 1200; onTriggered: root.remapToken++ }
    readonly property real _glass: Settings.shellGlass
    on_GlassChanged: remapTimer.restart()
    // layer blur is also a map-time rule: re-map when the shell blur is switched
    readonly property bool _shellBlur: Settings.appearance.shellBlur
    on_ShellBlurChanged: remapTimer.restart()

    readonly property color surface: Qt.alpha(isLight || Settings.appearance.glassTone === "base" ? c.base : c.crust,
                                              Perf.lean ? 1 : Math.min(1, Settings.shellGlass + (isLight ? 0.02 : 0)))
    readonly property color shadow: isLight ? Qt.rgba(0, 0, 0, 0.22) : Qt.rgba(0, 0, 0, 0.42)
    readonly property color scrim: Qt.alpha(c.crust, 0.45)

    // Surfaces layered on top of `surface` (M3 "surface container" tones)
    readonly property color container: Qt.alpha(c.text, isLight ? 0.06 : 0.06)
    readonly property color containerHigh: Qt.alpha(c.text, isLight ? 0.11 : 0.11)
    readonly property color outline: Qt.alpha(c.text, 0.08)
    readonly property color hover: Qt.alpha(c.text, 0.05)      // row under the pointer
    readonly property color pressed: Qt.alpha(c.text, 0.10)    // selected / pressed row

    // ── Motion (Caelestia / M3 expressive curves) ───────────────────────────
    // One motion language everywhere: things that arrive or move ease in with one soft
    // overshoot; things that leave, hovers and colour fades stay smooth (an overshooting colour
    // or a bouncing close looks like a glitch). Hyprland's own set is in hypr/atelier-mode.lua
    // (M.motion), one profile per performance mode, and so is this one:
    //
    //   normal  expressive: 500 ms opens with the M3 overshoot
    //   dev     crisp: ~25 % shorter, no overshoot (decelerate only), nothing pulls the eye
    //   game    quick: about half as long, no overshoot, so drawers over a game are on screen
    //           (and redrawing) for as few frames as possible
    //
    // curveElastic: Material 3 "expressive default spatial", the curve Caelestia uses for
    // everything that moves: ONE cubic with a single smooth overshoot (no joins, so no jerk
    // where segments meet). The 1.21 sets the bounce: higher = springier.
    readonly property var curveElastic: [0.38, 1.21, 0.22, 1, 1, 1]
    readonly property var curveSmooth: [0.05, 0.7, 0.1, 1, 1, 1]      // M3 emphasizedDecel, no overshoot
    readonly property var curveOpen: Perf.mode === "normal" ? curveElastic : curveSmooth   // drawers, popups, indicators
    readonly property var curveClose: [0.3, 0, 0.8, 0.15, 1, 1]       // emphasizedAccel
    readonly property var curveStandard: [0.2, 0, 0, 1, 1, 1]         // standard (hovers, colours)
    readonly property real modeSpeed: Perf.game ? 1.9 : Perf.dev ? 1.3 : 1
    readonly property real speed: Math.max(0.25, Settings.general.animSpeed) * modeSpeed    // 2 = twice as fast
    readonly property int durOpen: Math.round(500 / speed)             // Caelestia's expressiveDefaultSpatial
    readonly property int durClose: Math.round(200 / speed)
    readonly property int durFast: Math.round(180 / speed)       // hovers, colour changes
    readonly property int durMedium: Math.round(300 / speed)     // small moves (indicators, toggles)
}
