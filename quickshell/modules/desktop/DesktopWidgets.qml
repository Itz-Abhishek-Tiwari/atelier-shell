import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.components
import qs.config
import qs.services

// Desktop widget: typography straight on the wallpaper, behind windows (Bottom layer). No cards,
// no chips. Bottom-left by default so it never covers the wallpaper's subject. Everything below
// is adjustable in Settings → Widgets (position, clock font/weight/size/colour, text colour,
// shadow, opacity, date format, greeting, which lines show):
//   DATE (small caps) · a large light clock · greeting
//   then a few quiet lines you pick: weather · now playing (click: play/pause)
//   · next task (click: open the file) · system (cpu · memory · disk · battery)
// A soft shadow keeps it readable on any wallpaper. Not drawn in Game mode.
PanelWindow {
    id: root
    visible: Settings.widgets.enabled && !Perf.game   // not drawn (or refreshed) in Game mode

    property bool isLight: Atelier.isLight
    signal requestOverlay(string name)

    // ── Placement ───────────────────────────────────────────────────────────
    readonly property var w: Settings.widgets
    readonly property bool atLeft: w.hAlign === "left"
    readonly property bool atRight: w.hAlign === "right"
    readonly property bool atTop: w.vAlign === "top"
    readonly property bool atBottom: w.vAlign === "bottom"
    readonly property int halign: atLeft ? Qt.AlignLeft : atRight ? Qt.AlignRight : Qt.AlignHCenter
    readonly property int pad: 40                     // room for the shadow around the text
    readonly property int gutter: Math.round(w.gutter * k)   // distance from the frame's inner edge

    // an unanchored axis is centred by layer-shell; otherwise anchor that edge
    anchors { left: atLeft; right: atRight; top: atTop; bottom: atBottom }
    margins {
        left: Atelier.insetLeft + gutter - pad
        right: Atelier.insetRight + gutter - pad
        top: Atelier.insetTop + gutter - pad
        bottom: Atelier.insetBottom + gutter - pad
    }
    implicitWidth: column.implicitWidth + 2 * pad
    implicitHeight: column.implicitHeight + 2 * pad
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-desktop-widgets"

    readonly property string home: Quickshell.env("HOME")
    readonly property string userName: Atelier.userName

    // ── Time ─────────────────────────────────────────────────────────────────
    property date now: new Date()
    Timer {
        running: true
        interval: (60 - root.now.getSeconds()) * 1000 + 50     // wake on the minute
        onTriggered: { root.now = new Date(); restart(); }
    }
    readonly property int hour: now.getHours()
    readonly property string greeting: hour >= 5 && hour < 12 ? "Good morning"
        : hour < 17 && hour >= 12 ? "Good afternoon" : hour < 21 && hour >= 17 ? "Good evening" : "Working late"

    // ── Weather (wttr.in via scripts/weather.sh, cached 15 min) ─────────────
    property string weatherRaw: ""
    readonly property string temp: (weatherRaw.match(/[+-]?\d+°[CF]/) || [""])[0].replace("+", "")
    readonly property string condition: weatherRaw.replace(/[+-]?\d+°[CF]/, "").trim()
    readonly property string weatherIcon: {
        const c = condition.toLowerCase(), night = hour < 6 || hour >= 19;
        if (/thunder|storm/.test(c)) return "󰖓";
        if (/snow|sleet|blizzard/.test(c)) return "󰖘";
        if (/rain|drizzle|shower/.test(c)) return "󰖗";
        if (/fog|mist|haze|smoke/.test(c)) return "󰖑";
        if (/partly/.test(c)) return night ? "󰼱" : "󰖕";
        if (/cloud|overcast/.test(c)) return "󰖐";
        return night ? "󰖔" : "󰖙";
    }
    Process {
        id: weatherProc
        running: true
        command: [Quickshell.shellDir + "/scripts/weather.sh", Settings.widgets.weatherLocation, Settings.widgets.weatherUnits]
        stdout: StdioCollector { onStreamFinished: if (text.trim()) root.weatherRaw = text.trim() }
    }
    // re-fetch when the location/units are changed in Settings
    readonly property string _weatherKey: Settings.widgets.weatherLocation + "|" + Settings.widgets.weatherUnits
    on_WeatherKeyChanged: { weatherProc.running = false; weatherProc.running = true; }
    Timer { interval: 900000; running: true; repeat: true; onTriggered: weatherProc.running = true }

    // ── System (read straight from /proc; disk via df once a minute) ────────
    property real cpu: 0
    property var _cpuPrev: null
    property real mem: 0
    property string memText: ""
    property real disk: 0
    property string diskText: ""

    FileView { id: procStat; path: "/proc/stat"; printErrors: false }
    FileView { id: procMem; path: "/proc/meminfo"; printErrors: false }
    Timer {
        interval: 4000      // stats update without animating: an idle desktop shouldn't redraw at 120 fps
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            procStat.reload();
            procMem.reload();
            const f = (procStat.text().split("\n")[0] || "").trim().split(/\s+/).slice(1).map(Number);
            if (f.length >= 4) {
                const idle = f[3] + (f[4] || 0), total = f.reduce((a, b) => a + b, 0);
                if (root._cpuPrev) {
                    const dt = total - root._cpuPrev.total, di = idle - root._cpuPrev.idle;
                    if (dt > 0) root.cpu = 1 - di / dt;
                }
                root._cpuPrev = { total: total, idle: idle };
            }
            const m = procMem.text();
            const kb = k => Number((m.match(new RegExp("^" + k + ":\\s+(\\d+)", "m")) || [0, 0])[1]);
            const tot = kb("MemTotal"), avail = kb("MemAvailable");
            if (tot > 0) {
                root.mem = (tot - avail) / tot;
                root.memText = ((tot - avail) / 1048576).toFixed(1) + " / " + (tot / 1048576).toFixed(1) + " GB";
            }
        }
    }
    Process {
        id: dfProc
        running: true
        command: ["df", "-B1", "--output=used,size", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = text.trim().split("\n").pop().trim().split(/\s+/).map(Number);
                if (n.length === 2 && n[1] > 0) {
                    root.disk = n[0] / n[1];
                    root.diskText = Math.round(n[0] / 1e9) + " / " + Math.round(n[1] / 1e9) + " GB";
                }
            }
        }
    }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: dfProc.running = true }

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!(battery && battery.isLaptopBattery)

    // ── Media ───────────────────────────────────────────────────────────────
    readonly property var player: {
        const ps = Mpris.players.values;
        return ps.find(p => p.isPlaying) || ps[0] || null;
    }
    Timer {   // MprisPlayer.position isn't reactive; poke it while playing
        interval: 1000
        running: !!(root.player && root.player.isPlaying)
        repeat: true
        onTriggered: if (root.player) root.player.positionChanged()
    }
    function fmt(s) {
        s = Math.max(0, Math.floor(s || 0));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    // ── Tasks (~/day_plan.md: "- [ ] task" / "- [x] task") ──────────────────
    FileView {
        id: planFile
        path: Settings.expand(Settings.widgets.tasksFile)
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property var tasks: {
        const lines = (planFile.text() || "").split("\n"), out = [];
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(/^\s*- \[([ xX])\]\s+(.*)$/);
            if (m) out.push({ line: i, done: m[1] !== " ", text: m[2] });
        }
        return out;
    }
    readonly property int tasksDone: tasks.filter(t => t.done).length
    function toggleTask(t) {
        const lines = planFile.text().split("\n");
        lines[t.line] = lines[t.line].replace(/- \[([ xX])\]/, t.done ? "- [ ]" : "- [x]");
        planFile.setText(lines.join("\n"));
    }

    // ═════════════════════════════════════════════════════════════════════════
    // UI: one column of text in Inter. A large light clock (Inter Display, tabular figures),
    // the date as small spaced capitals, a soft greeting, then quiet detail lines with a tinted
    // glyph each (the only colour: the accent comes from the wallpaper, so it can vanish on it).
    readonly property real k: Settings.widgets.scale            // 0.8 small · 1 medium · 1.25 large

    // ── Ink follows the wallpaper, not the theme ────────────────────────────
    // scripts/wall-luma.py measures the wallpaper right behind this block. Dark or mid-tone
    // there → light text with a dark shadow; bright → dark text with a faint light shadow.
    // Both inks come from the theme palette (its lightest / darkest roles) so they stay tinted.
    property real luma: -1          // -1 = not measured yet → light text
    property real spread: 0.1       // how busy the area is; busier → stronger shadow
    readonly property bool onBright: w.textColor === "dark" || (w.textColor === "auto" && luma >= 0.6)
    readonly property color lightInk: Atelier.isLight ? Atelier.base : Atelier.text
    readonly property color darkInk: Atelier.isLight ? Atelier.text : Atelier.crust
    readonly property var box: {
        const sw = root.screen ? root.screen.width : 1920, sh = root.screen ? root.screen.height : 1080;
        const w = root.implicitWidth, h = root.implicitHeight;
        const x = atLeft ? root.margins.left : atRight ? sw - root.margins.right - w : (sw - w) / 2;
        const y = atTop ? root.margins.top : atBottom ? sh - root.margins.bottom - h : (sh - h) / 2;
        return [sw, sh, x, y, w, h].map(Math.round);
    }
    readonly property string _lumaKey: Wallpaper.current + "|" + box.join(",")
    on_LumaKeyChanged: lumaDebounce.restart()
    Timer { id: lumaDebounce; interval: 400; onTriggered: { lumaProc.running = false; lumaProc.running = true; } }
    Process {
        id: lumaProc
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/wall-luma.py", Wallpaper.current].concat(root.box.map(String))
        stdout: StdioCollector {
            onStreamFinished: {
                try { const r = JSON.parse(text); root.luma = r.luma; root.spread = r.spread; } catch (e) {}
            }
        }
    }

    readonly property color ink: onBright ? darkInk : lightInk
    readonly property color inkSoft: Qt.alpha(ink, 0.88)
    readonly property color inkFaint: Qt.alpha(ink, 0.66)
    readonly property string hourText: {
        const h = Atelier.hour12(root.now);
        return w.leadingZero ? h : String(Number(h));            // 9:15 unless leading zero is on
    }
    readonly property string clockFamily: w.clockFont === "mono" ? Atelier.font
        : w.clockFont === "serif" ? "Noto Serif" : "Inter Display"
    readonly property int clockWeight: ({ thin: Font.Thin, light: Font.Light, regular: Font.Normal, bold: Font.Bold })[w.clockWeight] ?? Font.Light
    readonly property color clockInk: w.clockColor === "accent" ? Atelier.accent : ink
    readonly property string dateText: {
        const f = ({ long: "dddd, d MMMM", short: "ddd d MMM", numeric: "dd/MM/yyyy", iso: "yyyy-MM-dd" })[w.dateFormat] || "dddd, d MMMM";
        const t = Qt.formatDate(root.now, f);
        return w.dateCaps ? t.toUpperCase() : t;
    }
    readonly property real shadowK: w.shadow === "strong" ? 1.6 : 1

    ColumnLayout {
        id: column
        anchors.centerIn: parent
        spacing: 0
        opacity: Math.max(0.3, Math.min(1, root.w.opacity))

        // soft, wide shadow under all the text (re-rendered only when the text changes)
        layer.enabled: root.w.shadow !== "off"
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.onBright ? Qt.rgba(1, 1, 1, Math.min(0.6, (0.18 + root.spread * 0.6) * root.shadowK))
                                       : Qt.rgba(0, 0, 0, Math.min(0.85, (0.32 + root.spread * 0.8) * root.shadowK))
            shadowBlur: 1.0
            blurMax: 40
            shadowVerticalOffset: 2
            autoPaddingEnabled: true
        }

        Text {
            visible: Settings.widgets.showDate
            Layout.alignment: root.halign
            text: root.dateText
            font.family: Atelier.fontUi; font.pixelSize: Math.round((root.w.dateCaps ? 13 : 15) * root.k)
            font.weight: root.w.dateCaps ? Font.DemiBold : Font.Medium
            font.letterSpacing: (root.w.dateCaps ? 3 : 0.3) * root.k
            color: dateMa.containsMouse ? root.ink : root.inkSoft
            Behavior on color { ColorAnimation { duration: 150 } }
            MouseArea { id: dateMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.requestOverlay("calendar") }
        }

        // clock: light display numerals, the colon a touch softer, a small AM/PM at cap height
        Item {
            Layout.alignment: root.halign
            Layout.topMargin: Settings.widgets.showDate ? -Math.round(4 * root.k) : 0
            implicitWidth: clock.implicitWidth + (ampm.visible ? ampm.implicitWidth + ampm.anchors.leftMargin : 0)
            implicitHeight: clock.implicitHeight
            Text {
                id: clock
                readonly property int px: Math.round(Math.max(48, Math.min(240, root.w.clockSize)) * root.k)
                textFormat: Text.StyledText
                text: root.hourText + "<font color='" + Qt.alpha(root.clockInk, 0.66) + "'>:</font>" + Qt.formatTime(root.now, "mm")
                font.family: root.clockFamily; font.pixelSize: px; font.weight: root.clockWeight
                font.letterSpacing: (root.w.clockFont === "display" ? -px / 44 : root.w.clockFont === "serif" ? -px / 90 : 0)
                font.features: { "tnum": 1 }
                color: root.clockInk
            }
            Text {
                id: ampm
                visible: !Atelier.clock24 && root.w.showAmPm
                anchors.left: clock.right
                anchors.leftMargin: Math.round(10 * root.k)
                anchors.top: clock.top
                anchors.topMargin: Math.round(clock.px * 0.25)
                text: Atelier.ampm(root.now)
                font.family: Atelier.fontUi; font.pixelSize: Math.round(15 * root.k); font.weight: Font.DemiBold
                font.letterSpacing: 2 * root.k
                color: root.inkFaint
            }
        }

        Text {
            visible: Settings.widgets.showGreeting
            Layout.alignment: root.halign
            Layout.topMargin: -Math.round(6 * root.k)
            text: root.w.greetingText !== "" ? root.w.greetingText : root.greeting + ", " + root.userName
            font.family: Atelier.fontUi; font.pixelSize: Math.round(19 * root.k); font.weight: Font.Light
            color: root.inkSoft
        }

        ColumnLayout {
            id: lines
            Layout.alignment: root.halign
            Layout.topMargin: visibleCount > 0 ? Math.round(26 * root.k) : 0
            spacing: Math.round(10 * root.k)
            readonly property int visibleCount: children.filter(c => c.visible).length

            Line {
                visible: Settings.widgets.showWeather && root.temp !== ""
                glyph: root.weatherIcon; tint: Atelier.sapphire
                text: root.temp + "  " + root.condition
                    + (Settings.widgets.weatherLocation ? "   ·   " + Settings.widgets.weatherLocation.charAt(0).toUpperCase() + Settings.widgets.weatherLocation.slice(1) : "")
            }
            Line {
                visible: Settings.widgets.showMedia && root.player !== null
                glyph: root.player && root.player.isPlaying ? "󰎆" : "󰏤"; tint: Atelier.pink
                text: root.player ? (root.player.trackTitle || root.player.identity) + (root.player.trackArtist ? "   ·   " + root.player.trackArtist : "") : ""
                onClicked: if (root.player) root.player.togglePlaying()
            }
            Line {
                visible: Settings.widgets.showTasks && root.tasks.length > 0
                readonly property var next: root.tasks.find(t => !t.done)
                glyph: next ? "󰄱" : "󰄲"; tint: Atelier.green
                text: next ? next.text + "   ·   " + root.tasksDone + " of " + root.tasks.length
                           : "All " + root.tasks.length + " tasks done"
                onClicked: Quickshell.execDetached([Settings.behavior.terminal, "-e", "nvim", Settings.expand(Settings.widgets.tasksFile)])
            }
            Line {
                visible: Settings.widgets.showSystem
                glyph: "󰍛"; tint: Atelier.peach
                text: "CPU " + Math.round(root.cpu * 100) + "%   ·   RAM " + Math.round(root.mem * 100) + "%   ·   Disk " + Math.round(root.disk * 100) + "%"
                    + (root.hasBattery ? "   ·   Battery " + Math.round(root.battery.percentage * 100) + "%" : "")
            }
        }
    }

    // one detail line: a tinted glyph + quiet text, aligned with the clock
    component Line: Item {
        id: ln
        property string glyph
        property string text
        property color tint: Atelier.accent
        signal clicked()
        Layout.alignment: root.halign
        implicitWidth: lnRow.implicitWidth
        implicitHeight: lnRow.implicitHeight
        Row {
            id: lnRow
            spacing: Math.round(12 * root.k)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(16 * root.k)
                horizontalAlignment: Text.AlignHCenter
                text: ln.glyph; font.family: Atelier.font; font.pixelSize: Math.round(15 * root.k)
                color: Qt.tint(root.ink, Qt.alpha(ln.tint, 0.7))   // keeps the hue, borrows the ink's contrast
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 520 * root.k)
                elide: Text.ElideRight
                text: ln.text
                font.family: Atelier.fontUi; font.pixelSize: Math.round(14.5 * root.k)
                font.features: { "tnum": 1 }
                color: lnMa.containsMouse ? root.ink : root.inkSoft
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
        MouseArea {
            id: lnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ln.clicked()
        }
    }
}
