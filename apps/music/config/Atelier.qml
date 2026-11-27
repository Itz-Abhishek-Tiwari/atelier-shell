pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Atelier Music's stand-in for quickshell/config/Atelier.qml: the same token names and maths,
// minus the shell-only parts (bar, frame, performance modes). Colours follow the active system
// theme (~/.config/atelier/theme.json, written by `atelier-theme apply`) live, so the app changes
// with the desktop. The shell's components (symlinked into ../components) read these tokens.
Singleton {
    id: root

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
    readonly property bool isLight: theme.variant === "light"

    FileView {
        id: themeFile
        path: Quickshell.env("HOME") + "/.config/atelier/theme.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    // ── The shell's own appearance settings (~/.config/atelier/settings.json): the same glass,
    //    glass tone and corner rounding as the bar and drawers, so the app looks like part of it.
    FileView {
        id: shellSettings
        path: Quickshell.env("HOME") + "/.config/atelier/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property var shell: { try { return JSON.parse(shellSettings.text() || "{}"); } catch (e) { return {}; } }
    readonly property var appearance: shell.appearance || ({})
    readonly property real glass: {
        const a = appearance;
        const g = a.glassMatchWindows ? ((shell.windows || {}).activeOpacity ?? 0.9) : (a.glass ?? 0.88);
        return Math.max(0.6, Math.min(1, g));
    }
    readonly property int rounding: appearance.rounding ?? 14
    // The shell's performance mode (~/.config/atelier/mode, written by services/Perf.qml).
    // Programming, Game and Battery saver turn the compositor blur off, so — like the shell's
    // own surfaces — the window goes fully opaque there (translucent with no blur would show
    // whatever is behind it as ghost text).
    FileView {
        id: modeFile
        path: Quickshell.env("HOME") + "/.config/atelier/mode"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property string perfMode: { try { return JSON.parse(modeFile.text() || "{}").mode || "normal"; } catch (e) { return "normal"; } }
    readonly property bool opaque: perfMode !== "normal"

    // window surface: the shell's glass (Hyprland blurs what is behind a translucent window)
    readonly property color surface: Qt.alpha(isLight || appearance.glassTone === "base" ? c.base : c.crust, opaque ? 1 : glass)
    // inset panels inside it (sidebar, player bar): Settings' sidebar tint + hairline
    readonly property color panel: Qt.alpha(c.crust, isLight ? 0.10 : 0.32)
    readonly property int panelRadius: Math.max(8, rounding - 8)

    // ── Type ──
    readonly property string font: "SpaceMono Nerd Font Propo"
    readonly property string fontUi: "Inter"
    readonly property string fontDisplay: "Inter Display"
    readonly property int fsMicro: 10
    readonly property int fsSm: 11
    readonly property int fsMd: 12
    readonly property int fsLg: 13
    readonly property int fsXl: 15
    readonly property int fsTitle: 22

    // ── Shape ──
    readonly property int radiusSm: 10
    readonly property int radiusMd: 14
    readonly property int radiusLg: 18

    // ── Palette ──
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
    readonly property color blue: c.blue
    readonly property color lavender: c.lavender
    readonly property color mauve: c.mauve
    readonly property color pink: c.pink
    readonly property color accent: c.accent
    // Filled colours, same maths as the shell: text on a fill is the theme's light ink, and
    // fill(c) deepens c until that ink reaches 4.5:1 contrast. (No "onAccent" property: QML reads
    // on+Capital names as signal handlers.)
    readonly property color onFill: isLight ? c.base : c.text
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

    readonly property color container: Qt.alpha(c.text, 0.06)
    readonly property color containerHigh: Qt.alpha(c.text, 0.11)
    readonly property color outline: Qt.alpha(c.text, 0.08)
    readonly property color hover: Qt.alpha(c.text, 0.05)
    readonly property color pressed: Qt.alpha(c.text, 0.10)

    // ── Motion ──
    readonly property var curveStandard: [0.2, 0, 0, 1, 1, 1]
    readonly property var curveSmooth: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property int durFast: 180
    readonly property int durMedium: 300
    readonly property int durOpen: 420
    readonly property int durClose: 200

    // Motion tokens (same as quickshell/config/Atelier.qml; read by Anim / CAnim / StateLayer)
    readonly property var m3: ({
        standard:        [0.2, 0, 0, 1, 1, 1],
        standardAccel:   [0.3, 0, 1, 1, 1, 1],
        standardDecel:   [0, 0, 0, 1, 1, 1],
        emphasized:      [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1],
        emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1],
        emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1],
        fastSpatial:     [0.42, 1.67, 0.21, 0.9, 1, 1],
        spatial:         [0.38, 1.21, 0.22, 1, 1, 1],
        slowSpatial:     [0.39, 1.29, 0.35, 0.98, 1, 1],
        fastEffects:     [0.31, 0.94, 0.34, 1, 1, 1],
        effects:         [0.34, 0.8, 0.34, 1, 1, 1],
        slowEffects:     [0.34, 0.88, 0.34, 1, 1, 1]
    })
    readonly property var m3dur: ({
        small: 200, normal: 400, large: 600, extraLarge: 1000,
        standard: 400, standardAccel: 200, standardDecel: 400,
        emphasized: 500, emphasizedAccel: 200, emphasizedDecel: 400,
        fastSpatial: 350, spatial: 500, slowSpatial: 650,
        fastEffects: 150, effects: 200, slowEffects: 300
    })
}
