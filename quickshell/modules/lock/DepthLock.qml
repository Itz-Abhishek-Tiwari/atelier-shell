import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.components
import qs.config
import qs.services

// "Depth" lock screen, after Samsung One UI's depth effect: the wallpaper stays sharp, a big
// clock sits in the sky, and the wallpaper's subject (cut out by services/DepthWall) is drawn
// again on top, so the clock looks tucked *behind* it.
//
//   layers   wallpaper · top/bottom shade · date + clock · subject cut-out · blur (typing) · UI
//   placing  the clock's bottom edge goes ~40 % into the subject's top (from DepthWall.profile,
//            under the clock's own width). If the subject would hide most of it, or there is no
//            cut-out yet (busy, not set up, no clear subject), the clock simply sits in front.
//   typing   any key: the wallpaper blurs, the subject fades, the password pill comes up.
//
// Same contract as LockContent.qml (lockRoot / screen / isPreview); PAM lives in LockScreen.qml.
Item {
    id: c

    required property var lockRoot
    property var screen: null
    property bool isPreview: false
    property bool editing: false            // the customise sheet (DepthEditor) is open

    focus: true
    Component.onCompleted: { forceActiveFocus(); if (imagesReady) start(); }

    property date now: new Date()
    Timer { interval: 1000; running: c.lockRoot.active; repeat: true; triggeredOnStart: true; onTriggered: c.now = new Date() }

    readonly property bool auth: lockRoot.authMode || lockRoot.buffer.length > 0 || !!lockRoot.message

    // ── Entrance / exit ─────────────────────────────────────────────────────
    // Nothing moves until the wallpaper (and its cut-out, if there is one) has decoded, so the
    // lock never flashes black or pops pieces in late. Then one choreographed entrance:
    //   fade    the picture comes up from black            (0 → 380 ms)
    //   settle  the picture eases from a slight zoom to 1   (0 → 1100 ms)
    //   rise    date + clock drift up into place           (140 → 840 ms)
    //   ui      bottom row, battery, buttons fade in        (320 → 720 ms)
    // The wallpaper and the cut-out always share one transform (any difference would show the
    // subject twice); the clock moves on its own, which is what sells the depth.
    readonly property bool cutWanted: DepthWall.ok && DepthWall.forWall === Wallpaper.current && DepthWall.cutout !== ""
    readonly property bool imagesReady: wall.status === Image.Ready
        && (!cutWanted || cut.status === Image.Ready || cut.status === Image.Error)
    onImagesReadyChanged: if (imagesReady) start()
    Timer { interval: 900; running: true; onTriggered: c.start() }   // never wait longer than this

    property bool started: false
    property bool entered: false
    property real fade: 0
    property real settle: 0
    property real rise: 0
    property real ui: 0
    function start() {
        if (started) return;
        started = true;
        enter.start();
    }
    ParallelAnimation {
        id: enter
        onFinished: c.entered = true
        NumberAnimation { target: c; property: "fade"; to: 1; duration: 380; easing.type: Easing.OutCubic }
        NumberAnimation { target: c; property: "settle"; to: 1; duration: 1100; easing.type: Easing.OutQuint }
        SequentialAnimation {
            PauseAnimation { duration: 140 }
            NumberAnimation { target: c; property: "rise"; to: 1; duration: 700; easing.type: Easing.OutQuint }
        }
        SequentialAnimation {
            PauseAnimation { duration: 320 }
            NumberAnimation { target: c; property: "ui"; to: 1; duration: 400; easing.type: Easing.OutCubic }
        }
    }
    // typing (password view) and unlocking, as 0..1 so they combine with the entrance values
    property real authT: auth ? 1 : 0
    Behavior on authT { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    property real out: lockRoot.unlocking ? 1 : 0
    Behavior on out { NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveClose } }

    // ── Data ────────────────────────────────────────────────────────────────
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!(battery && battery.isLaptopBattery)
    readonly property bool charging: !!(battery && battery.state === UPowerDeviceState.Charging)
    readonly property var player: {
        const ps = Mpris.players.values;
        return ps.find(p => p.isPlaying) || ps[0] || null;
    }
    readonly property var notifs: Settings.notifications.lockShowCount ? Notifs.list : []

    // LockScreen keeps the weather fetched ahead of time; fetch here only if it can't
    readonly property string weather: c.lockRoot.weather !== undefined && c.lockRoot.weather !== "" ? c.lockRoot.weather : ownWeather
    property string ownWeather: ""
    Process {
        running: c.lockRoot.weather === undefined
        command: [Quickshell.shellDir + "/scripts/weather.sh", Settings.widgets.weatherLocation, Settings.widgets.weatherUnits]
        stdout: StdioCollector { onStreamFinished: c.ownWeather = text.trim() }
    }
    readonly property string temp: (weather.match(/[+-]?\d+°[CF]?/) || [""])[0].replace("+", "")

    // ── Input: typing always goes to the password ───────────────────────────
    Keys.onPressed: (e) => {
        const r = c.lockRoot;
        if (c.editing) {                        // editor: no password; Esc closes (keeps changes)
            if (e.key === Qt.Key_Escape) r.stopPreview();
            e.accepted = true;
            return;
        }
        if (r.unlocking) return;
        if (e.key === Qt.Key_Print) {           // screenshot of this screen (see LockScreen.screenshot)
            if (r.screenshot) r.screenshot(c.screen ? c.screen.name : "");
            e.accepted = true;
            return;
        }
        if (e.key === Qt.Key_Escape) {
            if (r.buffer.length > 0 || r.message) { r.buffer = ""; r.message = ""; }
            else if (c.isPreview && !r.authMode) r.previewing = false;
            r.authMode = false;
        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            r.authMode = true;
            r.submit();
        } else if (e.key === Qt.Key_Backspace) {
            r.authMode = true;
            r.buffer = (e.modifiers & Qt.ControlModifier) ? "" : r.buffer.slice(0, -1);
        } else if (e.text && e.text.length === 1 && e.text.charCodeAt(0) >= 32 && !r.checking) {
            r.authMode = true;
            r.buffer += e.text;
            r.message = "";
        }
        e.accepted = true;
    }
    MouseArea {
        anchors.fill: parent
        onClicked: { if (!c.editing) c.lockRoot.authMode = true; c.forceActiveFocus(); }
    }

    // ── Where the wallpaper lands (PreserveAspectCrop) ──────────────────────
    readonly property real imgAspect: wall.implicitHeight > 0 ? wall.implicitWidth / wall.implicitHeight : width / Math.max(1, height)
    readonly property real paintW: Math.max(width, height * imgAspect)
    readonly property real paintH: paintW / imgAspect
    readonly property real paintX: (width - paintW) / 2
    readonly property real paintY: (height - paintH) / 2

    // Settings.lock.depthEffect off: no cut-out, the clock just sits at the top, full size
    readonly property bool haveCut: Settings.lock.depthEffect && DepthWall.ok && DepthWall.forWall === Wallpaper.current
        && DepthWall.cutout !== "" && cut.status === Image.Ready

    // The subject's outline (64 columns, top of the subject 0..1, 1 = none) with thin things
    // removed: a pole, a wire or an antenna is a tall spike one or two columns wide and used to
    // decide where the clock went (it ended up floating at the height of a lamp post). An opening
    // (erode then dilate over 3 columns) keeps anything at least 3 columns wide.
    readonly property var profile: {
        const p = DepthWall.profile || [];
        const n = p.length;
        if (n < 3) return p;
        const e = [], o = [];
        for (let i = 0; i < n; i++) e.push(Math.max(p[Math.max(0, i - 1)], p[i], p[Math.min(n - 1, i + 1)]));
        for (let i = 0; i < n; i++) o.push(Math.min(e[Math.max(0, i - 1)], e[i], e[Math.min(n - 1, i + 1)]));
        return o;
    }
    // top of the subject (screen px) under the horizontal span [x0, x1]
    function subjectTop(x0, x1) {
        const p = c.profile;
        if (!p || p.length === 0) return height;
        const n = p.length;
        const a = Math.max(0, Math.floor((x0 - paintX) / paintW * n));
        const b = Math.min(n - 1, Math.floor((x1 - paintX) / paintW * n));
        let t = 1;
        for (let i = a; i <= b; i++) t = Math.min(t, p[i]);
        return paintY + t * paintH;
    }

    // clock placement
    //   1. find the subject's top under the clock (natural width, so nothing here depends on 2.)
    //   2. auto-fit, like One UI: if the clock at full size can't sit above the subject with only
    //      its lower ~40 % hidden, shrink it (down to 80 %); past that the subject simply covers more
    //   3. put its bottom edge 40 % into the subject; if that still hides too much, or there is
    //      no cut-out, the clock just sits in front
    readonly property real minY: height * 0.07
    readonly property real defaultY: height * 0.11
    // share of the clock's height the subject may cover: 40 % of one line (stacked = 2 lines)
    // Stacked is used only while the minutes stay readable: at >= 80 % size with at most 40 %
    // of the minutes line hidden. Otherwise this wallpaper gets the one-line clock.
    readonly property bool wantStacked: Settings.lock.depthLayout === "stacked"
    // ── position: auto (around the subject) or custom (dragged in the editor) ──
    readonly property bool custom: Settings.lock.depthPos === "custom"
    property bool dragging: false
    property real dragX: 0.5
    property real dragY: 0.1
    readonly property real posX: dragging ? dragX : Settings.lock.depthX
    readonly property real posY: dragging ? dragY : Settings.lock.depthY
    readonly property real groupW: Math.max(clock.implicitWidth, dateLine.implicitWidth)
    readonly property real clockX: custom ? Math.max(16, Math.min(width - groupW - 16, posX * width - groupW / 2)) : (width - groupW) / 2

    readonly property bool useStacked: wantStacked && (custom || !haveCut || measureStacked.implicitHeight <= 0
        || (subjTop - minY - dateH) / (measureStacked.implicitHeight * 0.8) >= 0.8)
    // share of the clock's height the subject may cover: 40 % of one line (stacked = 2 lines)
    readonly property real overlap: useStacked ? 0.2 : 0.4
    readonly property real dateH: dateLine.implicitHeight + 6
    readonly property real basePx: Math.round(height * Settings.lock.depthClockSize)
    // span: the wider of the two layouts, so this doesn't depend on which one is chosen
    readonly property real spanW: Math.max(measureFlat.implicitWidth, measureStacked.implicitWidth)
    readonly property real subjTop: !haveCut ? height
        : custom ? subjectTop(clockX, clockX + groupW)
        : subjectTop(width / 2 - spanW / 2, width / 2 + spanW / 2)
    readonly property real fit: {
        if (custom || !haveCut || measure.implicitHeight <= 0) return 1;   // custom: the size you picked
        const room = subjTop - minY - dateH;                    // space above the subject
        const s = room / (measure.implicitHeight * (1 - overlap));
        return Math.max(0.8, Math.min(1, s));                  // never below 80 %: a big clock IS the look
    }
    readonly property real clockH: clock.implicitHeight
    readonly property real maxY: height * 0.42 - clockH * 0.3
    readonly property real wantY: subjTop + clockH * overlap - clockH - dateH
    readonly property real clockY: custom ? Math.max(8, Math.min(height - clockGroup.height - 8, posY * height))
        : !haveCut ? defaultY : Math.max(minY, Math.min(maxY, wantY))
    // share of the clock digits the subject covers at that position (its highest point)
    readonly property real covered: haveCut ? Math.max(0, (clockY + dateH + clockH) - subjTop) / clockH : 0
    // custom: wherever you put it, as long as the subject doesn't swallow nearly all of it
    readonly property bool depthOn: haveCut && covered > 0.04 && covered < (custom ? 0.9 : 0.64)

    // clock colour from the wallpaper (DepthWall.ink): a deep tone of the picture's own colour
    // on a bright sky, a pale tint on a dark one. Theme ink until it's known.
    readonly property bool inkKnown: DepthWall.ink !== "" && DepthWall.forWall === Wallpaper.current
    // Settings.lock.depthColor: auto (from the wallpaper) | theme | white | black | a theme
    // colour role (accent, pink, peach, …) | "#rrggbb"
    readonly property string colorKey: Settings.lock.depthColor || "auto"
    readonly property color ink: {
        const k = colorKey;
        if (k === "auto") return inkKnown ? DepthWall.ink : Atelier.text;
        if (k === "theme") return Atelier.text;
        if (k === "white") return "#ffffff";
        if (k === "black") return "#161616";
        if (k.startsWith("#")) return k;
        return Atelier[k] !== undefined ? Atelier[k] : Atelier.text;
    }
    readonly property bool inkDark: colorKey === "auto" ? (inkKnown && DepthWall.inkDark)
        : (0.2126 * ink.r + 0.7152 * ink.g + 0.0722 * ink.b) < 0.5
    // glass: the digits are frosted glass (the wallpaper, blurred, seen through them), tinted
    // with the clock colour, with a soft shadow and a thin light rim
    readonly property bool glass: Settings.lock.depthStyle === "glass"
    readonly property real glassTint: Math.max(0, Math.min(0.7, Settings.lock.depthGlassTint ?? 0.2))
    readonly property real glassFrost: Math.max(0.2, Math.min(1, Settings.lock.depthGlassFrost ?? 0.9))
    // the small lines with the clock: date (long | short | off), weather, AM/PM (12-hour only)
    readonly property string dateMode: Settings.lock.depthDate || "long"
    readonly property bool showWeather: Settings.lock.depthWeather ?? true
    readonly property string ampm: (Settings.lock.depthAmPm ?? true) ? Atelier.lockAmpm(c.now) : ""
    readonly property string dateText: {
        const d = dateMode === "off" ? "" : Qt.formatDate(c.now, dateMode === "short" ? "ddd d MMM" : "dddd, d MMMM");
        const w = showWeather && c.temp ? c.temp : "";
        return d && w ? d + "   ·   " + w : (d || w);
    }

    // the clock at full size, never shown: measures it for the auto-fit
    Text {
        id: measure
        visible: false
        text: clock.text
        font.family: clock.font.family
        font.pixelSize: c.basePx
        font.weight: clock.font.weight
        font.features: { "tnum": 1 }
        font.letterSpacing: -c.basePx * 0.03
        lineHeightMode: Text.ProportionalHeight
        lineHeight: clock.lineHeight
    }
    Text {
        id: measureFlat
        visible: false
        text: "00:00"
        font.family: clock.font.family
        font.pixelSize: c.basePx
        font.weight: clock.font.weight
        font.features: { "tnum": 1 }
    }
    // the stacked clock at full size, to decide whether it fits (independent of useStacked)
    Text {
        id: measureStacked
        visible: false
        text: "00\n00"
        font.family: clock.font.family
        font.pixelSize: c.basePx
        font.weight: clock.font.weight
        font.features: { "tnum": 1 }
        lineHeightMode: Text.ProportionalHeight
        lineHeight: 0.8
    }

    // ═══ Layers ═══════════════════════════════════════════════════════════════
    Item {
        id: scene
        anchors.fill: parent
        // a slow settle on appear (the depth reads best while it moves), a push-in on unlock
        scale: 1 + 0.07 * (1 - c.settle) + 0.06 * c.out
        opacity: c.fade * (1 - c.out)

        Image {
            id: wall
            anchors.fill: parent
            source: Wallpaper.current ? "file://" + Wallpaper.current : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: c.width
            sourceSize.height: c.height
        }
        // the wallpaper blurred once, read by the glass clock (only built in glass mode)
        MultiEffect {
            id: wallBlur
            anchors.fill: parent
            source: wall
            visible: false
            layer.enabled: c.glass
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 64
            blur: c.glassFrost
        }

        // shade so the clock and the bottom row read on any picture
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: parent.height * 0.5
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(Atelier.crust, 0.34) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: parent.height * 0.4
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.alpha(Atelier.crust, 0.5) }
            }
        }

        // ── date · clock ──
        Item {
            id: clockGroup
            x: c.clockX
            y: c.clockY + (1 - c.rise) * 36
            width: Math.max(clock.implicitWidth, dateLine.implicitWidth)
            height: dateLine.implicitHeight + 6 + clock.implicitHeight
            scale: 0.965 + 0.035 * c.rise
            opacity: c.rise * (1 - c.authT) * (1 - c.out)
            // only after the entrance: a new cut-out or setting glides the clock instead of jumping
            Behavior on x { enabled: c.entered && !c.dragging; NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }
            Behavior on y { enabled: c.entered && !c.dragging; NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }

            layer.enabled: Settings.lock.depthShadow && !c.glass      // glass draws its own shadow
            layer.effect: MultiEffect {
                shadowEnabled: true
                // dark ink: a faint light halo; light ink: a soft dark shadow
                shadowColor: c.inkDark ? "transparent" : Qt.alpha(Atelier.crust, 0.45)   // dark ink needs none
                shadowBlur: 0.9
                shadowVerticalOffset: 3
                autoPaddingEnabled: true
            }

            Text {
                id: dateLine
                anchors.horizontalCenter: parent.horizontalCenter
                // only holds the space: the visible date is drawn above the subject (dateTop)
                text: c.dateText || " "
                font.family: Atelier.fontUi
                font.pixelSize: Math.round(c.height * 0.022)
                font.weight: Font.Medium
                font.letterSpacing: 0.6
                visible: false
            }

            Text {
                id: clock
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: dateLine.bottom
                anchors.topMargin: 6
                readonly property bool stacked: c.useStacked
                readonly property int px: Math.round(c.basePx * c.fit)
                readonly property string hh: {
                    const h = Atelier.lockClock24 ? c.now.getHours() : (c.now.getHours() % 12 || 12);
                    return (stacked || Atelier.lockClock24) && h < 10 ? "0" + h : "" + h;
                }
                text: stacked ? hh + "\n" + Qt.formatTime(c.now, "mm") : hh + ":" + Qt.formatTime(c.now, "mm")
                horizontalAlignment: Text.AlignHCenter
                font.family: Settings.lock.depthFont === "mono" ? Atelier.font
                           : Settings.lock.depthFont === "serif" ? "Noto Serif" : "Inter Display"
                font.pixelSize: px
                font.weight: ({ light: Font.Light, regular: Font.Normal, bold: Font.Bold, black: Font.Black })[Settings.lock.depthWeight] ?? Font.Bold
                font.features: { "tnum": 1 }
                font.letterSpacing: -px * 0.03
                lineHeightMode: Text.ProportionalHeight
                lineHeight: stacked ? 0.8 : 1.0
                color: c.glass ? "white" : c.ink
                // in glass mode this is only the shape (mask) for the pieces below
                visible: !c.glass
                layer.enabled: c.glass
            }

            // ── glass digits ──
            Item {
                id: glassDigits
                visible: c.glass
                x: clock.x; y: clock.y
                width: clock.width; height: clock.height
                // soft shadow from the finished glass glyphs (so it always matches their shape)
                layer.enabled: c.glass && Settings.lock.depthShadow
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, c.inkDark ? 0.18 : 0.3)
                    shadowBlur: 0.9
                    shadowVerticalOffset: 5
                    autoPaddingEnabled: true
                }

                // the blurred wallpaper right behind the digits (mapToItem isn't reactive: the
                // y/scale/size reads below re-run it whenever the clock moves)
                ShaderEffectSource {
                    id: glassSrc
                    anchors.fill: parent
                    visible: false
                    live: true
                    sourceItem: c.glass ? wallBlur : null
                    sourceRect: {
                        const _ = clockGroup.y + clockGroup.scale + clock.width + clock.height + c.width;
                        const p = clock.mapToItem(wallBlur, 0, 0);
                        // shifted a little: what's behind looks refracted, like real glass
                        return Qt.rect(p.x + clock.width * 0.012, p.y - clock.height * 0.05,
                                       clock.width * clockGroup.scale, clock.height * clockGroup.scale);
                    }
                }
                // the glass
                MultiEffect {
                    anchors.fill: parent
                    source: glassSrc
                    maskEnabled: true
                    maskSource: clock
                    maskThresholdMin: 0.3
                    maskSpreadAtMin: 0.3
                    brightness: c.inkDark ? -0.02 : 0.1
                    saturation: 0.25
                }
                // light falling on the glass: bright at the top, gone by the middle
                Rectangle {
                    id: sheen
                    anchors.fill: parent
                    visible: false
                    layer.enabled: c.glass
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.42) }
                        GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.06) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                }
                MultiEffect {
                    anchors.fill: parent
                    source: sheen
                    maskEnabled: true
                    maskSource: clock
                    maskThresholdMin: 0.3
                    maskSpreadAtMin: 0.3
                }
                // tint in the clock colour
                MultiEffect {
                    anchors.fill: parent
                    source: clock
                    colorization: 1.0
                    colorizationColor: c.ink
                    opacity: c.glassTint
                }
                // rim
                Text {
                    anchors.fill: parent
                    text: clock.text
                    font: clock.font
                    horizontalAlignment: clock.horizontalAlignment
                    lineHeightMode: clock.lineHeightMode
                    lineHeight: clock.lineHeight
                    color: "transparent"
                    style: Text.Outline
                    // on a bright picture a white rim vanishes: a dark one there, a light one on dark
                    styleColor: c.inkDark ? Qt.rgba(0, 0, 0, 0.32) : Qt.rgba(1, 1, 1, 0.75)
                }
            }
        }

        // ── the subject, again, on top of the clock ──
        Image {
            id: cut
            anchors.fill: parent
            source: DepthWall.ok && DepthWall.cutout ? "file://" + DepthWall.cutout : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: c.width
            sourceSize.height: c.height
            // drawn only while it actually overlaps the clock (it is identical to the wallpaper
            // everywhere else, so this changes nothing but the clock's depth)
            visible: c.depthOn
            opacity: 1 - c.authT
        }

        // ── the date and AM/PM, above the subject (a twin of clockGroup's transform) ──
        Item {
            id: dateTop
            // wider by `pad` on both sides (same centre, so it scales exactly like clockGroup):
            // the layer below clips to this box and AM/PM sits past the digits
            readonly property real pad: 160
            x: clockGroup.x - pad; y: clockGroup.y
            width: clockGroup.width + 2 * pad; height: clockGroup.height
            scale: clockGroup.scale
            opacity: clockGroup.opacity
            layer.enabled: Settings.lock.depthShadow
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: c.inkDark ? "transparent" : Qt.alpha(Atelier.crust, 0.5)
                shadowBlur: 0.8
                shadowVerticalOffset: 2
                autoPaddingEnabled: true
            }
            Text {
                x: dateTop.pad + dateLine.x; y: dateLine.y
                text: c.dateText
                font: dateLine.font
                color: c.ink
                opacity: 0.9
            }
            // AM/PM beside the hours (top right of the digits), like the phone lock screens
            Text {
                visible: c.ampm !== ""
                x: dateTop.pad + clock.x + clock.width + Math.round(clock.px * 0.05)
                y: clock.y + Math.round(clock.px * 0.16)
                text: c.ampm
                font.family: Atelier.fontUi
                font.pixelSize: Math.max(12, Math.round(clock.px * 0.13))
                font.weight: Font.DemiBold
                font.letterSpacing: 1.5
                color: c.ink
                opacity: 0.85
            }
        }
    }

    // ── typing: blur the scene behind the password ──
    MultiEffect {
        anchors.fill: parent
        source: scene
        visible: opacity > 0
        opacity: c.authT * (1 - c.out)
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blur: 1.0
        saturation: -0.1
    }
    Rectangle {
        anchors.fill: parent
        color: Atelier.crust
        opacity: 0.42 * c.authT * (1 - c.out)
        visible: opacity > 0
    }

    // ═══ Foreground UI ════════════════════════════════════════════════════════
    // battery, top right
    Row {
        anchors.top: parent.top; anchors.right: parent.right
        anchors.margins: 28
        spacing: 6
        visible: c.hasBattery
        opacity: 0.9 * c.ui * (1 - c.out)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: c.charging ? "󰂄" : "󰁹"
            font.family: Atelier.font; font.pixelSize: 15
            color: c.battery && c.battery.percentage <= 0.15 && !c.charging ? Atelier.red : Atelier.text
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: c.battery ? Math.round(c.battery.percentage * 100) + "%" : ""
            font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: Font.Medium
            color: Atelier.text
        }
    }

    // ── Password view (any key or click) ────────────────────────────────────
    //   top     the date and a smaller clock (the big clock hands over to it)
    //   centre  picture with an accent ring (breathes while checking), name, failed-attempt
    //           count, a glass pill with centred dots + caret, show-password eye, enter button
    //   status  one fixed-height line: wrong password · Caps Lock is on · how to go back
    property bool reveal: false
    property bool capsOn: false
    Connections {
        target: c.lockRoot
        function onBufferChanged() { if (c.lockRoot.buffer.length === 0) c.reveal = false; }
    }
    // Caps Lock from the keyboard LEDs (Qt key events don't carry it)
    Process {
        id: capsProc
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null | sort -r | head -n1"]
        stdout: StdioCollector { onStreamFinished: c.capsOn = parseInt(text.trim()) > 0 }
    }
    Timer { interval: 700; repeat: true; triggeredOnStart: true; running: c.auth && c.lockRoot.active; onTriggered: capsProc.running = true }

    Item {
        id: authView
        anchors.fill: parent
        visible: opacity > 0
        opacity: c.authT * (1 - c.out)

        // date + time, top centre
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: c.height * 0.085 - (1 - c.authT) * 24
            spacing: 2
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(c.now, "dddd, d MMMM")
                font.family: Atelier.fontUi; font.pixelSize: 15; font.weight: Font.Medium
                color: Atelier.subtext1
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (Atelier.lockClock24 ? Atelier.lockHour(c.now) : Atelier.lockHour(c.now).replace(/^0/, "")) + ":" + Qt.formatTime(c.now, "mm")
                font.family: "Inter Display"; font.pixelSize: 68; font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                font.letterSpacing: -1.5
                color: Atelier.text
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: c.height * 0.04
            width: Math.min(360, parent.width - 48)
            spacing: 0
            scale: 0.96 + 0.04 * c.authT

            // picture
            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 120; implicitHeight: 120
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -6
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: c.lockRoot.message ? Qt.alpha(Atelier.red, 0.8) : Qt.alpha(Atelier.text, 0.35)
                    Behavior on border.color { ColorAnimation { duration: 200 } }
                    // breathes while PAM checks
                    property real pulse: 1
                    opacity: c.lockRoot.checking ? pulse : 1
                    SequentialAnimation on pulse {
                        running: c.lockRoot.checking; loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 500; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Atelier.fill(Atelier.accent)
                    visible: face.status !== Image.Ready
                    Text {
                        anchors.centerIn: parent
                        text: Atelier.userName.charAt(0).toUpperCase()
                        font.family: Atelier.fontUi; font.pixelSize: 48; font.weight: Font.DemiBold
                        color: Atelier.onFill
                    }
                }
                ClippingRectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    visible: face.status === Image.Ready
                    Image {
                        id: face
                        anchors.fill: parent
                        source: Profile.faceUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 240; sourceSize.height: 240
                    }
                }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 18
                text: Atelier.userName
                font.family: Atelier.fontUi; font.pixelSize: 24; font.weight: Font.DemiBold
                color: Atelier.text
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                text: c.lockRoot.failCount > 0
                    ? c.lockRoot.failCount + (c.lockRoot.failCount === 1 ? " failed attempt" : " failed attempts")
                    : "Enter your password to unlock"
                font.family: Atelier.fontUi; font.pixelSize: 13
                color: c.lockRoot.failCount > 0 ? Atelier.text : Atelier.subtext1
            }

            // the pill
            Item {
                Layout.fillWidth: true
                Layout.topMargin: 22
                implicitHeight: 54
                transform: Translate { id: shake }

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.alpha(Atelier.crust, 0.5)
                    border.width: c.lockRoot.message ? 1.5 : 1
                    border.color: c.lockRoot.message ? Qt.alpha(Atelier.red, 0.8) : Qt.alpha(Atelier.text, 0.22)
                    Behavior on border.color { ColorAnimation { duration: 200 } }
                }

                // show / hide what's typed
                Rectangle {
                    id: eye
                    anchors.left: parent.left; anchors.leftMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40; radius: 20
                    color: eyeMa.containsMouse ? Qt.alpha(Atelier.text, 0.1) : "transparent"
                    opacity: c.lockRoot.buffer.length > 0 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Text { anchors.centerIn: parent; text: c.reveal ? "󰈉" : "󰈈"; font.family: Atelier.font; font.pixelSize: 17; color: Atelier.subtext1 }
                    MouseArea { id: eyeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        enabled: c.lockRoot.buffer.length > 0; onClicked: { c.reveal = !c.reveal; c.forceActiveFocus(); } }
                }

                // centre: placeholder, dots or the revealed text, with a caret
                Item {
                    anchors.left: eye.right; anchors.right: go.left
                    anchors.leftMargin: 4; anchors.rightMargin: 4
                    anchors.top: parent.top; anchors.bottom: parent.bottom
                    clip: true
                    Text {
                        anchors.centerIn: parent
                        visible: c.lockRoot.buffer.length === 0
                        text: c.lockRoot.checking ? "Checking…" : "Password"
                        font.family: Atelier.fontUi; font.pixelSize: 14
                        color: Atelier.subtext
                    }
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        visible: c.lockRoot.buffer.length > 0
                        Repeater {
                            model: c.reveal ? 0 : Math.min(c.lockRoot.buffer.length, 22)
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 10; height: 10; radius: 5
                                color: Atelier.text
                                scale: 0
                                Component.onCompleted: scale = 1
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen } }
                            }
                        }
                        Text {
                            visible: c.reveal
                            anchors.verticalCenter: parent.verticalCenter
                            text: c.lockRoot.buffer
                            font.family: Atelier.fontUi; font.pixelSize: 16; font.letterSpacing: 0.5
                            color: Atelier.text
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2; height: 20; radius: 1
                            color: Atelier.text
                            visible: !c.lockRoot.checking
                            SequentialAnimation on opacity {
                                running: c.auth && !c.lockRoot.checking; loops: Animation.Infinite
                                NumberAnimation { to: 0; duration: 520; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                }

                // enter
                Rectangle {
                    id: go
                    anchors.right: parent.right; anchors.rightMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40; radius: 20
                    color: c.lockRoot.buffer.length > 0 || c.lockRoot.checking
                        ? (goMa.containsMouse ? Qt.lighter(Atelier.accentFill, 1.12) : Atelier.accentFill)
                        : Qt.alpha(Atelier.text, 0.1)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    scale: goMa.pressed ? 0.9 : 1
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: c.lockRoot.checking ? "󰑐" : "󰁔"
                        font.family: Atelier.font; font.pixelSize: 18
                        color: c.lockRoot.buffer.length > 0 || c.lockRoot.checking ? Atelier.onFill : Atelier.subtext
                        RotationAnimation on rotation { running: c.lockRoot.checking; loops: Animation.Infinite; from: 0; to: 360; duration: 800 }
                        onTextChanged: rotation = 0
                    }
                    MouseArea { id: goMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: c.lockRoot.submit() }
                }
            }

            // status line (fixed height, so nothing jumps)
            Item {
                Layout.fillWidth: true
                Layout.topMargin: 14
                implicitHeight: 28
                Rectangle {
                    anchors.centerIn: parent
                    visible: !!c.lockRoot.message || c.capsOn
                    width: statusRow.implicitWidth + 22; height: 28; radius: 14
                    readonly property color tint: c.lockRoot.message ? Atelier.red : Atelier.yellow
                    color: Qt.alpha(tint, 0.16)
                    border.width: 1; border.color: Qt.alpha(tint, 0.4)
                    Row {
                        id: statusRow
                        anchors.centerIn: parent
                        spacing: 7
                        Text { anchors.verticalCenter: parent.verticalCenter; text: c.lockRoot.message ? "󰀦" : "󰘲"; font.family: Atelier.font; font.pixelSize: 13; color: parent.parent.tint }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: c.lockRoot.message || "Caps Lock is on"
                            font.family: Atelier.fontUi; font.pixelSize: 12; font.weight: Font.Medium; color: Atelier.text }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: !c.lockRoot.message && !c.capsOn
                    text: c.isPreview ? "Preview · Esc twice to close" : "Esc to go back"
                    font.family: Atelier.fontUi; font.pixelSize: 11
                    color: Atelier.subtext
                }
            }
        }
    }

    // bottom: notifications · now playing · hint (idle only)
    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 34 - (1 - c.ui) * 18
        spacing: 14
        opacity: c.editing ? 0 : c.ui * (1 - c.authT) * (1 - c.out)
        visible: opacity > 0

        // notification app icons (no text on the lock screen)
        Row {
            Layout.alignment: Qt.AlignHCenter
            visible: c.notifs.length > 0
            spacing: 8
            Repeater {
                model: {
                    const seen = {}, out = [];
                    for (const n of c.notifs) {
                        const k = n.appName || "?";
                        if (!seen[k]) { seen[k] = true; out.push(n); }
                        if (out.length >= 6) break;
                    }
                    return out;
                }
                Rectangle {
                    // no `required` on purpose (see LockContent: a dead notification object can crash Qt)
                    readonly property string src: Notifs.iconFor(modelData)
                    width: 34; height: 34; radius: 17
                    color: Qt.alpha(Atelier.crust, 0.45)
                    border.width: 1; border.color: Qt.alpha(Atelier.text, 0.14)
                    IconImage { anchors.centerIn: parent; implicitSize: 18; visible: parent.src !== ""; source: parent.src; asynchronous: true }
                    Text { anchors.centerIn: parent; visible: parent.src === ""; text: "󰂚"; font.family: Atelier.font; font.pixelSize: 14; color: Atelier.text }
                }
            }
        }

        // now playing
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            visible: !!c.player && (c.player.trackTitle || "") !== ""
            implicitWidth: Math.min(420, mediaRow.implicitWidth + 16)
            implicitHeight: 52
            radius: 26
            color: Qt.alpha(Atelier.crust, 0.45)
            border.width: 1; border.color: Qt.alpha(Atelier.text, 0.14)
            RowLayout {
                id: mediaRow
                anchors.fill: parent
                anchors.leftMargin: 8; anchors.rightMargin: 8
                spacing: 10
                ClippingRectangle {
                    implicitWidth: 36; implicitHeight: 36; radius: 18
                    color: Qt.alpha(Atelier.pink, 0.2)
                    Image {
                        anchors.fill: parent
                        source: c.player ? c.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 96; sourceSize.height: 96
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 280
                    spacing: 0
                    Text { Layout.fillWidth: true; text: c.player ? c.player.trackTitle : ""; font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: Atelier.text; elide: Text.ElideRight }
                    Text { Layout.fillWidth: true; text: c.player ? (c.player.trackArtist || c.player.identity) : ""; font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext1; elide: Text.ElideRight }
                }
                RoundButton { icon: "󰒮"; onClicked: c.player.previous() }
                RoundButton { icon: c.player && c.player.isPlaying ? "󰏤" : "󰐊"; onClicked: c.player.togglePlaying() }
                RoundButton { icon: "󰒭"; onClicked: c.player.next() }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "󰌾   " + (c.isPreview ? "Preview · type to try · Esc to close" : "Type to unlock")
            font.family: Atelier.fontUi; font.pixelSize: 12; font.letterSpacing: 0.4
            color: Atelier.text
            opacity: 0.8
        }
    }

    // sleep · power (power asks once), bottom right
    Row {
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.margins: 28
        spacing: 8
        opacity: c.ui * (1 - c.out)
        visible: !c.editing
        property bool confirm: false
        RoundButton { size: 40; icon: "󰄀"; onClicked: if (c.lockRoot.screenshot) c.lockRoot.screenshot(c.screen ? c.screen.name : "") }
        RoundButton { size: 40; icon: "󰤄"; onClicked: Quickshell.execDetached(["systemctl", "suspend"]) }
        RoundButton { size: 40; icon: "󰑓"; visible: parent.confirm; onClicked: Quickshell.execDetached(["systemctl", "reboot"]) }
        RoundButton { size: 40; icon: "⏻"; tint: Atelier.red; visible: parent.confirm; onClicked: Quickshell.execDetached(["systemctl", "poweroff"]) }
        RoundButton { size: 40; icon: parent.confirm ? "󰅖" : "󰐥"; onClicked: parent.confirm = !parent.confirm }
    }

    // wrong password: shake
    Connections {
        target: c.lockRoot
        function onFailed() { shakeAnim.restart(); }
    }
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: shake; property: "x"; to: -18; duration: 60 }
        NumberAnimation { target: shake; property: "x"; to: 16; duration: 70 }
        NumberAnimation { target: shake; property: "x"; to: -10; duration: 70 }
        NumberAnimation { target: shake; property: "x"; to: 6; duration: 60 }
        NumberAnimation { target: shake; property: "x"; to: 0; duration: 60 }
    }

    // Round glass button for the wallpaper (dark wash + hairline, theme ink)
    component RoundButton: Rectangle {
        id: rb
        property string icon
        property int size: 32
        property color tint: Atelier.text
        signal clicked()
        width: size; height: size; radius: size / 2
        implicitWidth: size; implicitHeight: size
        color: Qt.alpha(Atelier.crust, rbMa.containsMouse ? 0.6 : 0.4)
        border.width: 1; border.color: Qt.alpha(Atelier.text, 0.14)
        scale: rbMa.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: 120 } }
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Text { anchors.centerIn: parent; text: rb.icon; font.family: Atelier.font; font.pixelSize: rb.size * 0.42; color: rb.tint }
        MouseArea { id: rbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
    }

    LockShotFeedback { lockRoot: c.lockRoot }

    // ── editor ──
    // the clock gets a soft outline so it's clear what's being edited
    Rectangle {
        visible: c.editing
        x: clockGroup.x - 18
        y: clockGroup.y - 14
        width: clockGroup.width + 36
        height: clockGroup.height + 28
        radius: 22
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1.5
        border.color: Qt.rgba(1, 1, 1, 0.55)
        SequentialAnimation on opacity {
            running: c.editing; loops: Animation.Infinite
            NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
        }
    }
    // centre guide while dragging near the middle
    Rectangle {
        visible: c.editing && c.dragging && Math.abs(c.dragX - 0.5) < 0.0005
        x: c.width / 2 - 0.5; width: 1
        y: 0; height: c.height
        color: Qt.rgba(1, 1, 1, 0.6)
    }
    // drag the clock (editor only): switches the position to Custom
    Text {
        visible: c.editing
        x: clockGroup.x + clockGroup.width / 2 - width / 2
        y: Math.max(4, clockGroup.y - 40)
        text: c.dragging ? "Release to place" : (c.custom ? "Drag to move · double-click to centre" : "Drag the clock to place it yourself")
        font.family: Atelier.fontUi; font.pixelSize: 12; font.weight: Font.Medium
        color: "white"
        style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.5)
    }
    MouseArea {
        visible: c.editing
        x: clockGroup.x - 18; y: clockGroup.y - 14
        width: clockGroup.width + 36; height: clockGroup.height + 28
        cursorShape: c.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real offX: 0
        property real offY: 0
        onPressed: (m) => {
            offX = m.x - 18 - clockGroup.width / 2;          // grab point relative to the clock centre
            offY = m.y - 14;
            c.dragX = (clockGroup.x + clockGroup.width / 2) / c.width;
            c.dragY = clockGroup.y / c.height;
            c.dragging = true;
        }
        onPositionChanged: (m) => {
            if (!c.dragging) return;
            const p = mapToItem(c, m.x, m.y);
            let fx = (p.x - offX) / c.width;
            if (Math.abs(fx - 0.5) < 0.025) fx = 0.5;     // snap to the centre line
            c.dragX = Math.max(0, Math.min(1, fx));
            c.dragY = Math.max(0, Math.min(0.9, (p.y - offY) / c.height));
        }
        onReleased: {
            if (!c.dragging) return;
            Settings.lock.depthX = Math.round(c.dragX * 1000) / 1000;
            Settings.lock.depthY = Math.round(c.dragY * 1000) / 1000;
            Settings.lock.depthPos = "custom";
            c.dragging = false;
        }
        onDoubleClicked: { Settings.lock.depthX = 0.5; Settings.lock.depthPos = "custom"; }
    }
    Loader {
        anchors.fill: parent
        active: c.editing
        sourceComponent: Component { DepthEditor { lockRoot: c.lockRoot } }
    }
}
