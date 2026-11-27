pragma Singleton
import QtQuick
import Quickshell
import qs.services

// Login-screen stand-in for the shell's Atelier (theme + design tokens), fed by colors.json and
// lock.json. Same names and the same maths as quickshell/config/Atelier.qml, so the lock styles
// look identical here.
Singleton {
    id: root
    readonly property var c: GreeterData.c
    readonly property bool isLight: GreeterData.isLight

    readonly property string font: GreeterData.monoFont
    readonly property string fontUi: "Inter"
    readonly property int rounding: Settings.appearance.rounding

    // Type scale and corner radii: keep the same numbers as quickshell/config/Atelier.qml
    readonly property int fsMicro: 10
    readonly property int fsSm: 11
    readonly property int fsMd: 12
    readonly property int fsLg: 13
    readonly property int fsXl: 15
    readonly property int radiusSm: 10
    readonly property int radiusMd: 14
    readonly property int radiusLg: 18

    // the lock's own clock setting (12 / 24 / follow the system)
    readonly property bool clock24: !!Settings.general.clock24
    readonly property bool lockClock24: Settings.lock.clock === "24" ? true : Settings.lock.clock === "12" ? false : clock24
    function lockHour(d) { const h = lockClock24 ? d.getHours() : (d.getHours() % 12 || 12); return (h < 10 ? "0" : "") + h; }
    function lockAmpm(d) { return lockClock24 ? "" : (d.getHours() < 12 ? "AM" : "PM"); }
    function hour12(d) { const h = clock24 ? d.getHours() : (d.getHours() % 12 || 12); return (h < 10 ? "0" : "") + h; }
    function ampm(d) { return clock24 ? "" : (d.getHours() < 12 ? "AM" : "PM"); }
    // the person being signed in (their first name, like the lock screen greets you)
    readonly property string userName: {
        const n = (GreeterData.realName || GreeterData.user || "").split(" ")[0];
        return n ? n.charAt(0).toUpperCase() + n.slice(1) : "there";
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
    readonly property color accent: c.accent

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

    readonly property color surface: Qt.alpha(isLight ? c.base : c.crust, 0.92)
    readonly property color shadow: isLight ? Qt.rgba(0, 0, 0, 0.22) : Qt.rgba(0, 0, 0, 0.42)
    readonly property color scrim: Qt.alpha(c.crust, 0.45)
    readonly property color container: Qt.alpha(c.text, 0.06)
    readonly property color containerHigh: Qt.alpha(c.text, 0.11)
    readonly property color outline: Qt.alpha(c.text, 0.08)

    readonly property var curveElastic: [0.38, 1.21, 0.22, 1, 1, 1]
    readonly property var curveSmooth: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property var curveOpen: curveElastic
    readonly property var curveClose: [0.3, 0, 0.8, 0.15, 1, 1]
    readonly property var curveStandard: [0.2, 0, 0, 1, 1, 1]
    readonly property real speed: Math.max(0.25, Settings.general.animSpeed || 1)
    readonly property int durOpen: Math.round(500 / speed)
    readonly property int durClose: Math.round(200 / speed)
    readonly property int durFast: Math.round(180 / speed)
    readonly property int durMedium: Math.round(300 / speed)

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
    function ms(base) { return Math.round(base / speed); }
    readonly property var m3dur: ({
        small: ms(200), normal: ms(400), large: ms(600), extraLarge: ms(1000),
        standard: ms(400), standardAccel: ms(200), standardDecel: ms(400),
        emphasized: ms(500), emphasizedAccel: ms(200), emphasizedDecel: ms(400),
        fastSpatial: ms(350), spatial: ms(500), slowSpatial: ms(650),
        fastEffects: ms(150), effects: ms(200), slowEffects: ms(300)
    })
}
