import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config
import qs.services

// Timers · Stopwatch · Focus (pomodoro): a bottom drawer. The state lives in services/Timers.qml,
// so everything keeps running while the drawer is closed.
// Open: Super+Alt+T · IPC `timers toggle|open|close|tab <timer|stopwatch|focus>|start "10m tea"` ·
// launcher "Timers".
Item {
    id: root
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool isLight: Atelier.isLight
    property bool animActive: false
    property string tab: "timer"
    property double openedAt: 0

    signal closedSignal()

    readonly property var tabs: [
        { id: "timer", label: "Timers", icon: "󱎫" },
        { id: "stopwatch", label: "Stopwatch", icon: "󱫍" },
        { id: "focus", label: "Focus", icon: "󰔟" }
    ]
    readonly property var presets: [["1 min", 60], ["3 min", 180], ["5 min", 300], ["10 min", 600],
                                     ["15 min", 900], ["25 min", 1500], ["30 min", 1800], ["45 min", 2700], ["1 hour", 3600]]
    readonly property color phaseTint: Timers.phase === "focus" ? Atelier.accent : Timers.phase === "short" ? Atelier.green : Atelier.teal
    readonly property int every: Math.max(1, Settings.behavior.pomoEvery)

    function toggle() { if (visible && animActive) close(); else open(); }
    function open(t) {
        if (t) tab = t;
        visible = true;
        animActive = true;
        openedAt = Date.now();
        Timers.now = Date.now();
        focusTimer.restart();
    }
    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }
    function setTab(t) { tab = t; focusTimer.restart(); }
    function cycle(dir) { setTab(tabs[(tabs.findIndex(t => t.id === tab) + dir + tabs.length) % tabs.length].id); }
    function startTyped() {
        const m = entry.text.trim().match(/^(\S+)\s*(.*)$/);
        if (m && Timers.add(Timers.parse(m[1]), m[2]) > 0) entry.text = "";
    }

    Timer { id: focusTimer; interval: 40; onTriggered: root.tab === "timer" ? entry.forceActiveFocus() : keys.forceActiveFocus() }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!root.animActive) root.visible = false }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    // a thin ring: how much of a countdown is left
    component Arc: Canvas {
        property real fraction: 1
        property color tint: Atelier.accent
        property real lineWidth: 6
        onFractionChanged: requestPaint()
        onTintChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.reset();
            const r = (Math.min(width, height) - lineWidth) / 2, cx = width / 2, cy = height / 2;
            c.lineWidth = lineWidth; c.lineCap = "round";
            c.strokeStyle = Atelier.containerHigh; c.beginPath(); c.arc(cx, cy, r, 0, Math.PI * 2); c.stroke();
            if (fraction > 0.003) {
                c.strokeStyle = tint; c.beginPath();
                c.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.min(1, fraction)); c.stroke();
            }
        }
    }
    // a list row inside a Panel: hairline above (not the first), soft hover wash
    component Row2: Item {
        id: r2
        property bool first: false
        default property alias content: r2Box.data
        Layout.fillWidth: true
        implicitHeight: 52
        Rectangle { visible: !r2.first; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 14; anchors.rightMargin: 14; height: 1; color: Atelier.outline }
        Rectangle { anchors.fill: parent; anchors.margins: 3; radius: Atelier.radiusMd; color: Atelier.containerHigh
                    opacity: r2Ma.containsMouse ? 0.6 : 0; Behavior on opacity { Anim { type: "effects" } } }
        MouseArea { id: r2Ma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
        RowLayout { id: r2Box; anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 8; spacing: 10 }
    }

    EdgeDrawer {
        id: drawer
        edge: "bottom"
        open: root.animActive
        bodyWidth: Math.min(root.width - 160, 720)
        bodyHeight: 390

        MouseArea { anchors.fill: parent }   // clicks inside don't close

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: (e) => {
                if (e.isAutoRepeat && Date.now() - root.openedAt < 350) { e.accepted = true; return; }
                if (e.key === Qt.Key_Escape) root.close();
                else if (e.key === Qt.Key_Tab) root.cycle(1);
                else if (e.key === Qt.Key_Backtab) root.cycle(-1);
                else if (e.key === Qt.Key_Space && root.tab === "stopwatch") Timers.swToggle();
                else if (e.key === Qt.Key_L && root.tab === "stopwatch") Timers.swLap();
                else if (e.key === Qt.Key_Space && root.tab === "focus") Timers.pomoToggle();
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
                    icon: "󱎫"; tint: Atelier.peach; title: "Timers"
                    subtitle: Timers.runningCount === 0 ? "Nothing running"
                        : Timers.runningCount + " running" + (Timers.nextLeft >= 0 ? "  ·  next ends in " + Timers.fmt(Timers.nextLeft + 900, false) : "")
                }
                Segmented { model: root.tabs; current: root.tab; segmentWidth: 112; onPicked: (id) => root.setTab(id) }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ── Timers: start one on the left, the running ones on the right ──
                RowLayout {
                    anchors.fill: parent
                    visible: root.tab === "timer"
                    spacing: 14

                    ColumnLayout {
                        Layout.preferredWidth: 250
                        Layout.fillHeight: true
                        spacing: 10
                        SmallCaps { text: "New timer"; Layout.leftMargin: 4 }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 36
                            radius: Atelier.radiusLg
                            color: Atelier.container
                            border.width: 1
                            border.color: entry.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                            Behavior on border.color { CAnim {} }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14; anchors.rightMargin: 4
                                spacing: 8
                                Text { text: "󰥔"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: Atelier.subtext }
                                TextInput {
                                    id: entry
                                    Layout.fillWidth: true
                                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: Atelier.text
                                    clip: true; selectByMouse: true
                                    Keys.onPressed: (e) => {
                                        if (e.isAutoRepeat && Date.now() - root.openedAt < 350) { e.accepted = true; return; }
                                        if (e.key === Qt.Key_Tab) { root.cycle(1); e.accepted = true; }
                                    }
                                    Keys.onEscapePressed: { if (text) text = ""; else root.close(); }
                                    Keys.onReturnPressed: root.startTyped()
                                    Keys.onEnterPressed: root.startTyped()
                                    Text { visible: !parent.text; anchors.verticalCenter: parent.verticalCenter
                                           text: "12m  or  5m tea"; font: entry.font; color: Atelier.subtext; opacity: 0.7 }
                                }
                                IconButton { accessibleLabel: "Start timer"; icon: "󰐊"; size: 28; glyphSize: 13; active: entry.text.trim() !== ""; onClicked: root.startTyped() }
                            }
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 3
                            rowSpacing: 6
                            columnSpacing: 6
                            Repeater {
                                model: root.presets
                                ChoicePill {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    label: modelData[0]
                                    onClicked: Timers.add(modelData[1], "")
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            SmallCaps { text: "Running"; Layout.leftMargin: 4 }
                            Item { Layout.fillWidth: true }
                            Text {
                                visible: Timers.timers.some(t => t.done)
                                text: "Clear finished"
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                                color: cfMa.containsMouse ? Atelier.text : Atelier.subtext
                                Behavior on color { CAnim {} }
                                MouseArea { id: cfMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Timers.clearFinished() }
                            }
                        }
                        Panel {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            EmptyState { anchors.centerIn: parent; visible: Timers.timers.length === 0; icon: "󱎫"; text: "Pick a length to start one" }
                            Flickable {
                                id: flick
                                anchors.fill: parent
                                anchors.margins: 3
                                contentHeight: tcol.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                SmoothWheel { flickable: flick }
                                ColumnLayout {
                                    id: tcol
                                    width: flick.width
                                    spacing: 0
                                    Repeater {
                                        model: Timers.timers
                                        Row2 {
                                            id: card
                                            required property var modelData
                                            required property int index
                                            readonly property real remain: modelData.running ? Math.max(0, modelData.end - Timers.now) : modelData.left
                                            readonly property color hue: modelData.done ? Atelier.green : Atelier.peach
                                            first: index === 0
                                            Item {
                                                implicitWidth: 34; implicitHeight: 34
                                                Arc { anchors.fill: parent; lineWidth: 3.5; tint: card.hue
                                                      fraction: card.modelData.done ? 1 : card.remain / card.modelData.total; opacity: card.modelData.running || card.modelData.done ? 1 : 0.5 }
                                                Text { anchors.centerIn: parent; text: card.modelData.done ? "󰄬" : card.modelData.running ? "" : "󰏤"
                                                       font.family: Atelier.font; font.pixelSize: Atelier.fsMd; color: card.hue }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                spacing: 0
                                                Text { text: card.modelData.done ? "Done" : Timers.fmt(card.remain + (card.modelData.running ? 900 : 0), false)
                                                       font.family: Atelier.font; font.pixelSize: Atelier.iconMd; font.weight: Font.Bold
                                                       color: card.modelData.done ? Atelier.green : card.modelData.running ? Atelier.text : Atelier.subtext1 }
                                                Text { Layout.fillWidth: true; elide: Text.ElideRight
                                                       text: (card.modelData.label ? card.modelData.label + "  ·  " : "") + Timers.fmt(card.modelData.total, false)
                                                       font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                                            }
                                            IconButton { accessibleLabel: card.modelData.done ? "Restart timer" : card.modelData.running ? "Pause timer" : "Resume timer"
                                                icon: card.modelData.done ? "󰑐" : card.modelData.running ? "󰏤" : "󰐊"
                                                         onClicked: Timers.toggle(card.modelData.id) }
                                            IconButton { accessibleLabel: "Restart timer"; visible: !card.modelData.done; icon: "󰑙"; onClicked: Timers.restart(card.modelData.id) }
                                            IconButton { accessibleLabel: "Remove timer"; icon: "󰅖"; hoverTint: Atelier.red; onClicked: Timers.remove(card.modelData.id) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Stopwatch: the time and controls, laps on the right ───────────
                RowLayout {
                    anchors.fill: parent
                    visible: root.tab === "stopwatch"
                    spacing: 14

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 22
                        Item { Layout.fillHeight: true }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Timers.fmt(Timers.swElapsed, true)
                            font.family: Atelier.font; font.pixelSize: 56; font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                            color: Timers.swRunning || Timers.swElapsed === 0 ? Atelier.text : Atelier.subtext1
                            Behavior on color { CAnim {} }
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 18
                            IconButton { accessibleLabel: "Reset stopwatch"; icon: "󰑙"; size: 40; glyphSize: 17; enabled: Timers.swElapsed > 0; onClicked: Timers.swReset() }
                            PrimaryButton { accessibleLabel: Timers.swRunning ? "Pause stopwatch" : "Start stopwatch"; icon: Timers.swRunning ? "󰏤" : "󰐊"; onClicked: Timers.swToggle() }
                            IconButton { accessibleLabel: "Record lap"; icon: "󰈻"; size: 40; glyphSize: 17; enabled: Timers.swRunning; onClicked: Timers.swLap() }
                        }
                        Item { Layout.fillHeight: true }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: 250
                        Layout.fillHeight: true
                        spacing: 10
                        SmallCaps { text: "Laps"; Layout.leftMargin: 4 }
                        Panel {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            EmptyState { anchors.centerIn: parent; visible: Timers.laps.length === 0; icon: "󰈻"; text: "No laps yet" }
                            Flickable {
                                id: lapFlick
                                anchors.fill: parent
                                anchors.margins: 3
                                contentHeight: lcol.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                SmoothWheel { flickable: lapFlick }
                                ColumnLayout {
                                    id: lcol
                                    width: lapFlick.width
                                    spacing: 0
                                    Repeater {
                                        model: Timers.laps
                                        Row2 {
                                            required property var modelData
                                            required property int index
                                            first: index === 0
                                            implicitHeight: 40
                                            Text { text: "Lap " + (Timers.laps.length - index); font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext }
                                            Item { Layout.fillWidth: true }
                                            Text { text: "+" + Timers.fmt(modelData - (index + 1 < Timers.laps.length ? Timers.laps[index + 1] : 0), true)
                                                   font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: Atelier.accent }
                                            Text { Layout.rightMargin: 6; text: Timers.fmt(modelData, true); font.family: Atelier.font; font.pixelSize: Atelier.fsMd; color: Atelier.text }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Focus: the ring on the left, the session on the right ─────────
                RowLayout {
                    anchors.fill: parent
                    visible: root.tab === "focus"
                    spacing: 26

                    Item {
                        Layout.preferredWidth: 230
                        Layout.fillHeight: true
                        Item {
                            anchors.centerIn: parent
                            width: Math.min(220, parent.height); height: width
                            Arc { anchors.fill: parent; lineWidth: 8; tint: root.phaseTint
                                  fraction: Timers.phaseMs > 0 ? Timers.pomoLeft / Timers.phaseMs : 0 }
                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                Text { anchors.horizontalCenter: parent.horizontalCenter
                                       text: Timers.fmt(Timers.pomoLeft + (Timers.pomoRunning ? 900 : 0), false)
                                       font.family: Atelier.font; font.pixelSize: 40; font.weight: Font.Bold; color: Atelier.text }
                                Text { anchors.horizontalCenter: parent.horizontalCenter
                                       text: Timers.pomoRunning ? (Timers.phase === "focus" ? "Focusing" : "On a break")
                                           : Timers.pomoPaused >= 0 ? "Paused" : "Ready"
                                       font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.Medium; color: root.phaseTint }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10
                        Item { Layout.fillHeight: true }
                        RowLayout {
                            spacing: 6
                            Repeater {
                                model: [["focus", "Focus"], ["short", "Short break"], ["long", "Long break"]]
                                ChoicePill {
                                    required property var modelData
                                    label: modelData[1]
                                    on: Timers.phase === modelData[0]
                                    onClicked: Timers.pomoSetPhase(modelData[0])
                                }
                            }
                        }
                        RowLayout {
                            Layout.topMargin: 4
                            spacing: 14
                            IconButton { accessibleLabel: "Reset Pomodoro"; icon: "󰑙"; size: 40; glyphSize: 17; onClicked: Timers.pomoReset() }
                            PrimaryButton { accessibleLabel: Timers.pomoRunning ? "Pause Pomodoro" : "Start Pomodoro"; icon: Timers.pomoRunning ? "󰏤" : "󰐊"; onClicked: Timers.pomoToggle() }
                            IconButton { accessibleLabel: "Skip Pomodoro phase"; icon: "󰒭"; size: 40; glyphSize: 17; onClicked: Timers.pomoSkip() }
                            Item { implicitWidth: 6 }
                            ColumnLayout {
                                spacing: 5
                                Row {
                                    spacing: 5
                                    Repeater {
                                        model: root.every
                                        Rectangle { required property int index; width: 9; height: 9; radius: 4.5
                                            color: index < Timers.rounds % root.every ? root.phaseTint : Atelier.containerHigh }
                                    }
                                }
                                Text { text: "Round " + (Timers.rounds % root.every + 1) + " of " + root.every
                                       font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                            }
                        }
                        SmallCaps { text: "Lengths"; Layout.leftMargin: 4; Layout.topMargin: 6 }
                        Panel {
                            Layout.fillWidth: true
                            implicitHeight: lens.implicitHeight + 6
                            ColumnLayout {
                                id: lens
                                x: 0; y: 3
                                width: parent.width
                                spacing: 0
                                Repeater {
                                    model: [["pomoFocus", "Focus", 5, 90, 5], ["pomoShort", "Short break", 1, 30, 1], ["pomoLong", "Long break", 5, 60, 5]]
                                    Row2 {
                                        id: len
                                        required property var modelData
                                        required property int index
                                        readonly property string key: modelData[0]
                                        first: index === 0
                                        implicitHeight: 38
                                        Text { Layout.fillWidth: true; Layout.leftMargin: 2; text: len.modelData[1]
                                               font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.text }
                                        IconButton { icon: "󰍴"; size: 26; glyphSize: 12
                                                     onClicked: Settings.behavior[len.key] = Math.max(len.modelData[2], Settings.behavior[len.key] - len.modelData[4]) }
                                        Text { Layout.preferredWidth: 54; horizontalAlignment: Text.AlignHCenter
                                               text: Settings.behavior[len.key] + " min"; font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: Atelier.text }
                                        IconButton { icon: "󰐕"; size: 26; glyphSize: 12
                                                     onClicked: Settings.behavior[len.key] = Math.min(len.modelData[3], Settings.behavior[len.key] + len.modelData[4]) }
                                    }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }

            HintLine {
                Layout.fillWidth: true
                text: root.tab === "timer" ? "Type a length and Enter  ·  Tab switches view  ·  Esc closes"
                    : root.tab === "stopwatch" ? "Space starts / pauses  ·  L adds a lap  ·  Tab switches view  ·  Esc closes"
                    : "Space starts / pauses  ·  a finished round flows into the break  ·  Esc closes"
            }
        }
    }
}
