import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config
import qs.services

// System monitor: a bottom drawer with four tabs.
//   Overview  CPU (temperature + a 40 s graph), memory, graphics, network
//   Apps      the busiest apps by CPU and by memory, with a stop button
//   Battery   charge, power draw, health, the charge limit, the hungriest apps
//   Screen time  the last 7 days as a chart + the apps used most that day / week (services/ScreenTime)
// The data feed (scripts/sysmon.py) runs only while this drawer is open.
// Open: Super+Shift+M · IPC `sysmon toggle|open|close|tab <overview|apps|battery|screentime>` · launcher "System monitor".
Item {
    id: root
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool isLight: Atelier.isLight
    property bool animActive: false
    property string tab: "overview"
    property double openedAt: 0

    signal closedSignal()

    readonly property var d: SysMon.d
    readonly property var bat: d.battery || null
    readonly property var temps: d.temps || ({})
    readonly property var mem: d.mem || ({ used: 0, total: 1, swapUsed: 0, swapTotal: 0 })
    readonly property var tabs: [
        { id: "overview", label: "Overview", icon: "󰾆" },
        { id: "apps", label: "Apps", icon: "󰀻" },
        { id: "battery", label: "Battery", icon: "󰂁" },
        { id: "screentime", label: "Screen time", icon: "󰔛" }
    ]

    // Screen time: "" = today, a "yyyy-MM-dd" day from the chart, or "week"
    property string stDay: ""
    readonly property var stWeek: { ScreenTime.revision; return ScreenTime.week(); }
    readonly property string stKey: stDay === "" ? ScreenTime.dayKey() : stDay
    readonly property real stWeekTotal: stWeek.reduce((a, d) => a + d.t, 0)
    readonly property real stAvg: { const used = stWeek.filter(d => d.t > 0); return used.length ? stWeekTotal / used.length : 0; }
    readonly property real stShown: stKey === "week" ? stWeekTotal : (stWeek.find(d => d.key === stKey) || { t: 0 }).t
    readonly property var stApps: { ScreenTime.revision; return ScreenTime.apps(stKey === "week" ? stWeek.map(d => d.key) : [stKey]).slice(0, 6); }
    function stLabel(key) {
        if (key === "week") return "Last 7 days";
        if (key === ScreenTime.dayKey()) return "Today";
        if (key === ScreenTime.dayKey(new Date(Date.now() - 86400000))) return "Yesterday";
        const d = stWeek.find(x => x.key === key);
        return d ? Qt.formatDate(d.date, "dddd d MMM") : key;
    }

    function toggle() { if (visible && animActive) close(); else open(); }
    function open(t) {
        if (t) tab = t;
        visible = true;
        animActive = true;
        openedAt = Date.now();
        focusTimer.restart();
        stDay = "";
        ScreenTime.flushNow();
    }
    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }
    function setTab(t) { tab = t; }
    function cycle(dir) { tab = tabs[(tabs.findIndex(t => t.id === tab) + dir + tabs.length) % tabs.length].id; }
    onVisibleChanged: SysMon.active = visible

    function heat(c) { return c >= 85 ? Atelier.red : c >= 70 ? Atelier.peach : c >= 55 ? Atelier.yellow : Atelier.green; }
    function pct(v) { return Math.round(v || 0) + "%"; }

    Timer { id: focusTimer; interval: 40; onTriggered: keys.forceActiveFocus() }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!root.animActive) root.visible = false }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    // ── pieces ────────────────────────────────────────────────────────────────
    // a stat card: glyph + name, a big number, then whatever goes under it
    component Stat: Panel {
        id: st
        property string icon: ""
        property string name: ""
        property color tint: Atelier.accent
        property string big: ""
        property string unit: ""
        property string side: ""          // a small value at the top right (temperature…)
        property color sideTint: Atelier.subtext
        default property alias body: stBody.data
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    implicitWidth: 26; implicitHeight: 26; radius: 9
                    color: Qt.alpha(st.tint, 0.14)
                    Text { anchors.centerIn: parent; text: st.icon; font.family: Atelier.font; font.pixelSize: 13; color: st.tint }
                }
                Text { Layout.fillWidth: true; text: st.name; elide: Text.ElideRight
                       font.family: Atelier.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold; color: Atelier.text }
                Text { visible: st.side !== ""; text: st.side; font.family: Atelier.font; font.pixelSize: 11; color: st.sideTint }
            }
            Row {
                visible: st.big !== ""
                spacing: 4
                Text { id: bigT; text: st.big; font.family: Atelier.font; font.pixelSize: 28; font.weight: Font.Bold; color: Atelier.text }
                Text { anchors.baseline: bigT.baseline; text: st.unit; font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.subtext }
            }
            ColumnLayout {
                id: stBody
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 7
            }
        }
    }
    // label … value
    component Line: RowLayout {
        property string label: ""
        property string value: ""
        property color tint: Atelier.subtext1
        Layout.fillWidth: true
        spacing: 8
        Text { Layout.fillWidth: true; text: label; elide: Text.ElideRight; font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext }
        Text { text: value; font.family: Atelier.font; font.pixelSize: 11; color: tint }
    }
    // the last 40 seconds as thin rounded columns, newest on the right
    component Spark: Item {
        id: sp
        property var values: []
        property real maxValue: 100
        property color tint: Atelier.accent
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 26
        Row {
            anchors.fill: parent
            spacing: 2
            Repeater {
                model: 40
                Item {
                    required property int index
                    readonly property real v: {
                        const i = sp.values.length - 40 + index;
                        return i >= 0 ? sp.values[i] : -1;
                    }
                    width: (sp.width - 39 * 2) / 40
                    height: sp.height
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: parent.v < 0 ? 2 : Math.max(2, parent.height * Math.min(1, parent.v / Math.max(1, sp.maxValue)))
                        radius: width / 2
                        color: parent.v < 0 ? Atelier.containerHigh : Qt.alpha(sp.tint, parent.index === 39 ? 1 : 0.45)
                        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }
    }

    // ── Drawer ────────────────────────────────────────────────────────────────
    EdgeDrawer {
        id: drawer
        edge: "bottom"
        open: root.animActive
        bodyWidth: Math.min(root.width - 160, 960)
        bodyHeight: 400

        MouseArea { anchors.fill: parent }   // clicks inside don't close

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: (e) => {
                if (e.isAutoRepeat && Date.now() - root.openedAt < 350) { e.accepted = true; return; }
                if (e.key === Qt.Key_Escape) root.close();
                else if (e.key === Qt.Key_1) root.tab = "overview";
                else if (e.key === Qt.Key_2) root.tab = "apps";
                else if (e.key === Qt.Key_3) root.tab = "battery";
                else if (e.key === Qt.Key_4) root.tab = "screentime";
                else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Right) root.cycle(1);
                else if (e.key === Qt.Key_Backtab || e.key === Qt.Key_Left) root.cycle(-1);
                else return;
                e.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            // ── header: title · tabs ───────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                DrawerTitle {
                    Layout.fillWidth: true
                    icon: "󰍛"; tint: Atelier.accent; title: "System"
                    subtitle: root.d.uptime === undefined ? "Reading sensors…"
                        : "Up " + SysMon.fmtUptime(root.d.uptime) + "  ·  load " + root.d.load[0].toFixed(2) + "  ·  " + root.d.ncpu + " threads"
                }
                Segmented { model: root.tabs; current: root.tab; onPicked: (id) => root.tab = id }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                EmptyState { anchors.centerIn: parent; visible: !SysMon.ready && root.tab !== "screentime"; icon: "󰍛"; text: "Reading sensors…" }

                // ── Overview ─────────────────────────────────────────────────────
                RowLayout {
                    anchors.fill: parent
                    visible: SysMon.ready && root.tab === "overview"
                    spacing: 10

                    Stat {
                        icon: "󰻠"; name: "Processor"; tint: Atelier.accent
                        big: Math.round(root.d.cpu || 0); unit: "%"
                        side: root.temps.cpu ? Math.round(root.temps.cpu) + "°C" : ""; sideTint: root.heat(root.temps.cpu || 0)
                        Spark { values: SysMon.cpuHist; maxValue: 100; tint: Atelier.accent }
                        Line { label: "Busiest thread"; value: root.pct(root.d.cores ? Math.max.apply(null, root.d.cores) : 0) }
                    }
                    Stat {
                        icon: "󰘚"; name: "Memory"; tint: Atelier.blue
                        big: Math.round(100 * root.mem.used / root.mem.total); unit: "%"
                        side: SysMon.fmtBytes(root.mem.total)
                        LevelBar { Layout.fillWidth: true; value: root.mem.used / root.mem.total; tint: Atelier.blue }
                        Item { Layout.fillHeight: true }
                        Line { label: "In use"; value: SysMon.fmtBytes(root.mem.used) }
                        Line { label: "Available"; value: SysMon.fmtBytes(root.mem.total - root.mem.used) }
                        Line { visible: root.mem.swapTotal > 0; label: "Swap"; value: SysMon.fmtBytes(root.mem.swapUsed) }
                    }
                    Stat {
                        icon: "󰢮"; name: "Graphics"; tint: Atelier.green
                        side: root.temps.gpu ? Math.round(root.temps.gpu) + "°C" : ""; sideTint: root.heat(root.temps.gpu || 0)
                        Repeater {
                            model: root.d.gpus || []
                            ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 5
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { Layout.fillWidth: true; text: modelData.name; elide: Text.ElideRight
                                           font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.text }
                                    Text { text: modelData.asleep ? "asleep" : modelData.busy + "%"
                                           font.family: modelData.asleep ? Atelier.fontUi : Atelier.font; font.pixelSize: 11
                                           color: modelData.asleep ? Atelier.subtext : Atelier.green }
                                }
                                LevelBar { Layout.fillWidth: true; value: modelData.busy / 100; tint: Atelier.green; opacity: modelData.asleep ? 0.35 : 1 }
                                Line { visible: !!modelData.memTotal; label: "Video memory"
                                       value: SysMon.fmtBytes(modelData.mem || 0) + " / " + SysMon.fmtBytes(modelData.memTotal || 0) }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                    Stat {
                        icon: "󰛳"; name: "Network"; tint: Atelier.teal
                        big: SysMon.fmtRate(root.d.down || 0).split(" ")[0]; unit: SysMon.fmtRate(root.d.down || 0).split(" ")[1] + " down"
                        Spark { values: SysMon.netHist; tint: Atelier.teal
                                maxValue: Math.max(65536, SysMon.netHist.reduce((a, b) => Math.max(a, b), 0)) }
                        Line { label: "Upload"; value: SysMon.fmtRate(root.d.up || 0) }
                        Line { visible: !!root.temps.nvme; label: "Disk temperature"; value: Math.round(root.temps.nvme || 0) + "°C"; tint: root.heat(root.temps.nvme || 0) }
                    }
                }

                // ── Apps ──────────────────────────────────────────────────────────
                RowLayout {
                    anchors.fill: parent
                    visible: SysMon.ready && root.tab === "apps"
                    spacing: 10

                    Repeater {
                        model: [{ key: "byCpu", name: "Most processor", icon: "󰻠", tint: Atelier.accent },
                                { key: "byMem", name: "Most memory", icon: "󰘚", tint: Atelier.blue }]
                        Stat {
                            id: col
                            required property var modelData
                            icon: modelData.icon; name: modelData.name; tint: modelData.tint
                            Repeater {
                                model: (root.d[col.modelData.key] || []).slice(0, 6)
                                RowLayout {
                                    id: app
                                    required property var modelData
                                    readonly property bool cpu: col.modelData.key === "byCpu"
                                    Layout.fillWidth: true
                                    spacing: 10
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 4
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Text { Layout.fillWidth: true; text: app.modelData.name; elide: Text.ElideRight
                                                   font.family: Atelier.fontUi; font.pixelSize: 12; font.weight: Font.Medium; color: Atelier.text }
                                            Text { visible: app.modelData.n > 1; text: app.modelData.n + " processes"
                                                   font.family: Atelier.fontUi; font.pixelSize: 10; color: Atelier.subtext }
                                            Text { Layout.preferredWidth: 58; horizontalAlignment: Text.AlignRight
                                                   text: app.cpu ? app.modelData.cpu.toFixed(0) + "%" : SysMon.fmtBytes(app.modelData.mem)
                                                   font.family: Atelier.font; font.pixelSize: 11; color: col.tint }
                                        }
                                        LevelBar {
                                            Layout.fillWidth: true
                                            implicitHeight: 3
                                            tint: col.tint
                                            value: app.cpu ? app.modelData.cpu / (100 * Math.max(1, Math.min(4, root.d.ncpu)))
                                                           : app.modelData.mem / Math.max(1, root.mem.total)
                                        }
                                    }
                                    IconButton { icon: "󰅖"; size: 26; glyphSize: 12; hoverTint: Atelier.red; onClicked: SysMon.kill(app.modelData.pid) }
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }

                // ── Battery ───────────────────────────────────────────────────────
                Item {
                    anchors.fill: parent
                    visible: SysMon.ready && root.tab === "battery"

                    EmptyState { anchors.centerIn: parent; visible: !root.bat; icon: "󰂑"; text: "No battery in this computer" }

                    RowLayout {
                        anchors.fill: parent
                        visible: !!root.bat
                        spacing: 10

                        Stat {
                            id: chargeStat
                            readonly property bool charging: !!root.bat && root.bat.status === "Charging"
                            icon: charging ? "󰂄" : "󰂁"; name: "Charge"; tint: Atelier.green
                            big: root.bat ? root.bat.pct : ""; unit: "%"
                            side: root.bat ? root.bat.status : ""; sideTint: charging ? Atelier.green : Atelier.subtext
                            LevelBar { Layout.fillWidth: true; value: root.bat ? root.bat.pct / 100 : 0
                                       tint: root.bat && root.bat.pct <= 15 && !chargeStat.charging ? Atelier.red : Atelier.green }
                            Item { Layout.fillHeight: true }
                            Line { label: chargeStat.charging ? "Charging at" : "Using"; value: (root.bat ? root.bat.watts : 0) + " W" }
                            Line { visible: !!(root.bat && root.bat.hours); label: "Time left"
                                   value: root.bat && root.bat.hours ? Math.floor(root.bat.hours) + " h " + Math.round(root.bat.hours % 1 * 60) + " min" : "" }
                        }
                        Stat {
                            icon: "󰣐"; name: "Health"; tint: Atelier.pink
                            big: root.bat && root.bat.health ? root.bat.health : "–"; unit: "% of new"
                            LevelBar { Layout.fillWidth: true; value: root.bat && root.bat.health ? root.bat.health / 100 : 0; tint: Atelier.pink }
                            Item { Layout.fillHeight: true }
                            Line { label: "Holds now"; value: root.bat ? root.bat.fullWh + " Wh" : "" }
                            Line { label: "Held when new"; value: root.bat ? root.bat.designWh + " Wh" : "" }
                            Line { label: "Charge cycles"; value: root.bat ? String(root.bat.cycles) : "" }
                        }
                        Stat {
                            icon: "󱈑"; name: "Charge limit"; tint: Atelier.sapphire
                            RowLayout {
                                visible: !!(root.bat && root.bat.limitable)
                                Layout.fillWidth: true
                                spacing: 10
                                Text { Layout.fillWidth: true; text: "Conservation mode"
                                       font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: Font.Medium; color: Atelier.text }
                                ToggleSwitch { on: !!(root.bat && root.bat.limited); enabled: !SysMon.limitBusy
                                               onToggled: SysMon.setChargeLimit(!on) }
                            }
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                lineHeight: 1.15
                                text: !root.bat || !root.bat.limitable ? "This laptop doesn't let the system cap charging."
                                    : "Stops charging at about 80 % so the battery wears slower. Best when you're plugged in most of the day."
                                font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext
                            }
                            Item { Layout.fillHeight: true }
                        }
                        Stat {
                            icon: "󱐋"; name: "Using the most power"; tint: Atelier.peach
                            Repeater {
                                model: (root.d.byCpu || []).slice(0, 5)
                                Line { required property var modelData; label: modelData.name; value: modelData.cpu.toFixed(0) + "%"; tint: Atelier.peach }
                            }
                            Item { Layout.fillHeight: true }
                            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Ranked by CPU use, the main drain you can act on."
                                   font.family: Atelier.fontUi; font.pixelSize: 10; color: Atelier.subtext; opacity: 0.8 }
                        }
                    }
                }

                // ── Screen time ───────────────────────────────────────────────────
                Item {
                    anchors.fill: parent
                    visible: root.tab === "screentime"

                    EmptyState { anchors.centerIn: parent; visible: !ScreenTime.enabled; icon: "󰔛"
                                 text: "Screen time is off · Settings → Power & battery" }

                    RowLayout {
                        anchors.fill: parent
                        visible: ScreenTime.enabled
                        spacing: 10

                        Stat {
                            Layout.preferredWidth: 3
                            icon: "󰔛"; name: root.stLabel(root.stKey); tint: Atelier.green
                            big: ScreenTime.fmt(root.stShown)
                            side: root.stAvg > 0 ? "Daily average  " + ScreenTime.fmt(root.stAvg) : ""

                            // 7 days, today on the right; click a day to see its apps
                            RowLayout {
                                id: chart
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 10
                                readonly property real peak: Math.max(3600, root.stWeek.reduce((a, d) => Math.max(a, d.t), 0))
                                Repeater {
                                    model: root.stWeek
                                    ColumnLayout {
                                        id: dayCol
                                        required property var modelData
                                        readonly property bool picked: root.stKey === "week" || root.stKey === modelData.key
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 6
                                        Item {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            // the average as a faint line across every column
                                            Rectangle {
                                                visible: root.stAvg > 0
                                                width: parent.width; height: 1
                                                y: parent.height * (1 - root.stAvg / chart.peak)
                                                color: Qt.alpha(Atelier.subtext, 0.35)
                                            }
                                            Rectangle {
                                                anchors.bottom: parent.bottom
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: Math.min(34, parent.width)
                                                height: Math.max(4, parent.height * dayCol.modelData.t / chart.peak)
                                                radius: Math.min(8, width / 2)
                                                color: dayCol.modelData.t <= 0 ? Atelier.containerHigh
                                                     : Qt.alpha(Atelier.green, dayCol.picked ? 1 : (dayMa.containsMouse ? 0.7 : 0.4))
                                                Behavior on height { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.OutCubic } }
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }
                                            MouseArea {
                                                id: dayMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.stDay = dayCol.modelData.key
                                            }
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: dayMa.containsMouse && dayCol.modelData.t > 0 ? ScreenTime.fmt(dayCol.modelData.t)
                                                : dayCol.modelData.key === ScreenTime.dayKey() ? "Today" : Qt.formatDate(dayCol.modelData.date, "ddd")
                                            font.family: dayMa.containsMouse ? Atelier.font : Atelier.fontUi; font.pixelSize: 10
                                            color: dayCol.picked && root.stKey !== "week" ? Atelier.text : Atelier.subtext
                                        }
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Text { Layout.fillWidth: true; text: "7 days  " + ScreenTime.fmt(root.stWeekTotal)
                                       font.family: Atelier.font; font.pixelSize: 11; color: Atelier.subtext }
                                Chip { icon: "󰸗"; text: "Whole week"; implicitHeight: 24; interactive: true
                                       tint: root.stKey === "week" ? Atelier.green : Atelier.subtext
                                       onClicked: root.stDay = root.stKey === "week" ? "" : "week" }
                            }
                        }

                        Stat {
                            Layout.preferredWidth: 2
                            icon: "󰀻"; name: "Most used"; tint: Atelier.teal
                            side: root.stLabel(root.stKey)

                            EmptyState { Layout.alignment: Qt.AlignCenter; Layout.fillHeight: true; visible: root.stApps.length === 0
                                         icon: "󰔛"; text: "Nothing counted yet" }
                            Repeater {
                                model: root.stApps
                                RowLayout {
                                    id: use
                                    required property var modelData
                                    readonly property string iconSrc: ScreenTime.appIcon(modelData.id)
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Item {
                                        implicitWidth: 22; implicitHeight: 22
                                        Image { anchors.fill: parent; visible: use.iconSrc !== ""; source: use.iconSrc
                                                sourceSize: Qt.size(44, 44); smooth: true; asynchronous: true }
                                        Text { anchors.centerIn: parent; visible: use.iconSrc === ""; text: "󰣆"
                                               font.family: Atelier.font; font.pixelSize: 14; color: Atelier.teal }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 4
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { Layout.fillWidth: true; text: ScreenTime.appName(use.modelData.id); elide: Text.ElideRight
                                                   font.family: Atelier.fontUi; font.pixelSize: 12; font.weight: Font.Medium; color: Atelier.text }
                                            Text { text: ScreenTime.fmt(use.modelData.secs); font.family: Atelier.font; font.pixelSize: 11; color: Atelier.teal }
                                        }
                                        LevelBar { Layout.fillWidth: true; implicitHeight: 3; tint: Atelier.teal
                                                   value: use.modelData.secs / Math.max(1, root.stShown) }
                                    }
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }

            HintLine { Layout.fillWidth: true; text: "1–4 or Tab switch views  ·  ✕ stops an app  ·  Esc closes" }
        }
    }
}
