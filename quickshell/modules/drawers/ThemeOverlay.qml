import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// Theme picker: a drawer from the bottom edge.
//   left   every theme as a calm, uniform list (same shape for every row; filter All/Dark/Light)
//   right  a miniature of YOUR desktop in the highlighted theme: your wallpaper, the frame and
//          bar, tiled windows with the gradient border, a widget card. Shapes never change
//          while browsing; only the colours crossfade.
// Picking one runs `atelier-theme apply <id>`, which re-themes Quickshell, Hyprland, terminals,
// VS Code, GTK, Qt, starship, zsh, btop.
// Keys: ↑/↓ browse · Tab filter · Enter apply · Esc close. Double-click a row to apply.
Item {
    id: root
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool animActive: false
    property var themes: []
    property string applying: ""
    property string filter: "all"                 // all | dark | light
    property int selected: 0                      // index into `shown`

    readonly property var shown: filter === "all" ? themes : themes.filter(t => t.variant === filter)
    readonly property var sel: selected >= 0 && selected < shown.length ? shown[selected] : null
    readonly property var sw: sel ? sel.swatch : null

    signal closedSignal()
    signal toastRequested(string msg, string icon, color clr)

    readonly property string cli: Quickshell.env("HOME") + "/.local/bin/atelier-theme"

    function toggle() { if (visible && animActive) close(); else open(); }
    function open() {
        visible = true;
        animActive = true;
        listProc.running = true;
        focusTimer.restart();
    }
    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }
    function apply(t) {
        if (!t || applying || t.id === Atelier.themeId) return;
        applying = t.id;
        applyProc.name = t.name;
        applyProc.command = [cli, "apply", t.id];
        applyProc.running = true;
    }
    function toggleMode() {
        if (applying) return;
        applying = "mode";
        applyProc.name = "";
        applyProc.command = [cli, "toggle-mode"];
        applyProc.running = true;
    }
    function setFilter(f) {
        filter = f;
        const i = shown.findIndex(t => t.id === Atelier.themeId);
        selected = i >= 0 ? i : 0;
        list.positionViewAtIndex(selected, ListView.Contain);
    }
    function move(n) {
        if (shown.length === 0) return;
        selected = Math.max(0, Math.min(shown.length - 1, selected + n));
        list.positionViewAtIndex(selected, ListView.Contain);
    }

    Process {
        id: listProc
        command: [root.cli, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const keep = root.sel ? root.sel.id : "";
                    root.themes = JSON.parse(text);
                    let i = root.shown.findIndex(t => t.id === keep);
                    if (i < 0) i = root.shown.findIndex(t => t.current);
                    root.selected = i >= 0 ? i : 0;
                    list.positionViewAtIndex(root.selected, ListView.Center);
                } catch (e) {}
            }
        }
    }

    Process {
        id: applyProc
        property string name: ""
        stdout: StdioCollector {
            onStreamFinished: {
                root.applying = "";
                listProc.running = true;
                try {
                    const r = JSON.parse(text.trim().split("\n").pop());
                    const label = applyProc.name || r.theme;
                    if (r.failed && r.failed.length) root.toastRequested("Theme: " + label + " (" + r.failed.length + " app(s) skipped)", "󰏘", Atelier.yellow);
                    else root.toastRequested("Theme: " + label, "󰏘", Atelier.accent);
                } catch (e) {}
            }
        }
    }

    Timer { id: focusTimer; interval: 40; onTriggered: keys.forceActiveFocus() }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!root.animActive) root.visible = false }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.close()
        Keys.onUpPressed: root.move(-1)
        Keys.onDownPressed: root.move(1)
        Keys.onLeftPressed: root.move(-1)
        Keys.onRightPressed: root.move(1)
        Keys.onTabPressed: root.setFilter(root.filter === "all" ? "dark" : root.filter === "dark" ? "light" : "all")
        Keys.onReturnPressed: root.apply(root.sel)
        Keys.onEnterPressed: root.apply(root.sel)

        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    // ── The previewed palette, crossfaded (geometry never depends on it) ────
    Item {
        id: pv
        visible: false
        readonly property var s: root.sw
        readonly property bool light: !!(root.sel && root.sel.variant === "light")
        readonly property int dur: 260
        property color base:     s ? s.base     : Atelier.base
        property color mantle:   s ? s.mantle   : Atelier.mantle
        property color crust:    s ? s.crust    : Atelier.crust
        property color surface0: s ? s.surface0 : Atelier.surface0
        property color surface2: s ? s.surface2 : Atelier.surface2
        property color text:     s ? s.text     : Atelier.text
        property color subtext:  s ? s.subtext0 : Atelier.subtext
        property color accent:   s ? s.accent   : Atelier.accent
        property color mauve:    s ? s.mauve    : Atelier.mauve
        property color red:      s ? s.red      : Atelier.red
        property color peach:    s ? s.peach    : Atelier.peach
        property color yellow:   s ? s.yellow   : Atelier.yellow
        property color green:    s ? s.green    : Atelier.green
        property color blue:     s ? s.blue     : Atelier.blue
        property color sapphire: s ? s.sapphire : Atelier.sapphire
        property color pink:     s ? s.pink     : Atelier.pink
        // the shell's glass (Atelier.surface) and card fills, in this palette
        readonly property color glass: Qt.alpha(light ? base : crust, 0.92)
        readonly property color card: Qt.alpha(text, 0.06)
        readonly property color line: Qt.alpha(text, 0.08)
        Behavior on base     { ColorAnimation { duration: pv.dur } }
        Behavior on mantle   { ColorAnimation { duration: pv.dur } }
        Behavior on crust    { ColorAnimation { duration: pv.dur } }
        Behavior on surface0 { ColorAnimation { duration: pv.dur } }
        Behavior on surface2 { ColorAnimation { duration: pv.dur } }
        Behavior on text     { ColorAnimation { duration: pv.dur } }
        Behavior on subtext  { ColorAnimation { duration: pv.dur } }
        Behavior on accent   { ColorAnimation { duration: pv.dur } }
        Behavior on mauve    { ColorAnimation { duration: pv.dur } }
        Behavior on red      { ColorAnimation { duration: pv.dur } }
        Behavior on peach    { ColorAnimation { duration: pv.dur } }
        Behavior on yellow   { ColorAnimation { duration: pv.dur } }
        Behavior on green    { ColorAnimation { duration: pv.dur } }
        Behavior on blue     { ColorAnimation { duration: pv.dur } }
        Behavior on sapphire { ColorAnimation { duration: pv.dur } }
        Behavior on pink     { ColorAnimation { duration: pv.dur } }
    }

    EdgeDrawer {
        id: drawer
        edge: "bottom"
        open: root.animActive
        bodyWidth: 940
        bodyHeight: 460

        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 18

            // ── Left: the list ──────────────────────────────────────────────
            ColumnLayout {
                Layout.preferredWidth: 310
                Layout.minimumWidth: 310
                Layout.maximumWidth: 310
                Layout.fillHeight: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Chip { icon: "󰏘"; text: "Themes"; tint: Atelier.accent }
                    Chip { text: root.shown.length; mono: true; tint: Atelier.subtext; pad: 8 }
                    Item { Layout.fillWidth: true }
                    Chip {
                        icon: Atelier.isLight ? "󰖔" : "󰖙"
                        text: Atelier.isLight ? "Dark" : "Light"
                        tint: Atelier.yellow
                        interactive: root.applying === ""
                        onClicked: root.toggleMode()
                    }
                }

                // filter (segmented, sliding pill)
                Rectangle {
                    id: seg
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: Atelier.radiusMd
                    color: Atelier.container
                    border.width: 1
                    border.color: Atelier.outline
                    readonly property var opts: ["all", "dark", "light"]
                    readonly property real cell: (width - 6) / 3
                    Rectangle {
                        x: 3 + seg.opts.indexOf(root.filter) * seg.cell
                        y: 3
                        width: seg.cell
                        height: parent.height - 6
                        radius: height / 2
                        color: Qt.alpha(Atelier.accent, 0.18)
                        border.width: 1
                        border.color: Qt.alpha(Atelier.accent, 0.4)
                        Behavior on x { Anim { type: "spatial" } }
                    }
                    Row {
                        anchors.fill: parent
                        anchors.margins: 3
                        Repeater {
                            model: [{ id: "all", label: "All", icon: "󰏘" }, { id: "dark", label: "Dark", icon: "󰖔" }, { id: "light", label: "Light", icon: "󰖙" }]
                            Item {
                                required property var modelData
                                width: seg.cell
                                height: parent.height
                                readonly property bool on: root.filter === modelData.id
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.icon; font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: parent.parent.on ? Atelier.accent : Atelier.subtext }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.label
                                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; font.weight: Font.DemiBold
                                        color: parent.parent.on ? Atelier.accent : Atelier.text
                                        Behavior on color { CAnim {} }
                                    }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setFilter(modelData.id) }
                            }
                        }
                    }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: root.shown
                    boundsBehavior: Flickable.StopAtBounds
                    highlightFollowsCurrentItem: false
                    SmoothWheel { flickable: list }

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property var s: modelData.swatch
                        readonly property bool isCurrent: modelData.id === Atelier.themeId
                        readonly property bool isSel: root.selected === index

                        width: list.width
                        height: 52
                        radius: Atelier.radiusMd
                        // selection only tints; the border is always there, so nothing shifts
                        color: isSel ? Qt.alpha(Atelier.accent, 0.12) : "transparent"
                        StateLayer { mouseArea: rowMa }
                        border.width: 1
                        border.color: isSel ? Qt.alpha(Atelier.accent, 0.35) : "transparent"
                        Behavior on color { CAnim {} }
                        Behavior on border.color { CAnim {} }

                        // the theme's own tile: its base with its accent
                        Rectangle {
                            id: tile
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36; height: 36; radius: Atelier.radiusSm
                            color: row.s.base
                            border.width: 1
                            border.color: Qt.alpha(row.s.text, 0.16)
                            Rectangle {
                                anchors.centerIn: parent
                                width: 16; height: 16; radius: Atelier.radiusSm
                                color: row.s.accent
                            }
                        }

                        ColumnLayout {
                            anchors.left: tile.right
                            anchors.leftMargin: 11
                            anchors.right: tail.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold
                                    color: Atelier.text
                                    elide: Text.ElideRight
                                }
                            }
                            // palette strip: same five roles, same size, for every theme
                            Row {
                                spacing: 4
                                Repeater {
                                    model: [row.s.red, row.s.peach, row.s.yellow, row.s.green, row.s.blue, row.s.mauve || row.s.pink]
                                    Rectangle { required property var modelData; width: 14; height: 6; radius: 3; color: modelData }
                                }
                            }
                        }

                        Row {
                            id: tail
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Chip {
                                visible: row.isCurrent
                                anchors.verticalCenter: parent.verticalCenter
                                icon: "󰄬"; text: "In use"; tint: Atelier.green
                                implicitHeight: 22; pad: 8
                            }
                            Text {
                                visible: !row.isCurrent
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.variant === "light" ? "󰖙" : "󰖔"
                                font.family: Atelier.font; font.pixelSize: Atelier.fsMd
                                color: Atelier.subtext
                                opacity: 0.6
                            }
                        }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selected = row.index
                            onDoubleClicked: root.apply(row.modelData)
                        }
                    }
                }
            }

            // ── Right: your desktop, in the highlighted theme ───────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                ClippingRectangle {
                    id: stage
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Atelier.radiusMd
                    color: pv.glass               // the frame + bar surface
                    border.width: 1
                    border.color: Atelier.outline

                    readonly property int bar: 30
                    readonly property int fr: 7
                    readonly property int gap: 7

                    // bar (left), like Waybar on the frame
                    Item {
                        x: 0; y: 0
                        width: stage.bar; height: stage.height
                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 12
                            spacing: 7
                            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 16; height: 16; radius: 6; color: Qt.alpha(pv.accent, 0.22); border.width: 1; border.color: Qt.alpha(pv.accent, 0.5)
                                Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: pv.accent } }
                            Item { width: 1; height: 4 }
                            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 6; height: 16; radius: 3; color: pv.accent }
                            Repeater {
                                model: 3
                                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 6; height: 6; radius: 3; color: Qt.alpha(pv.text, 0.3) }
                            }
                        }
                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 12
                            spacing: 7
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "12"; font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; font.bold: true; color: pv.text }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "47"; font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; font.bold: true; color: pv.text }
                            Item { width: 1; height: 2 }
                            Repeater {
                                model: [pv.sapphire, pv.blue, pv.green]
                                Rectangle { required property var modelData; anchors.horizontalCenter: parent.horizontalCenter; width: 6; height: 6; radius: 3; color: modelData }
                            }
                            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 12; height: 12; radius: 6; color: Qt.alpha(pv.red, 0.25); border.width: 1; border.color: Qt.alpha(pv.red, 0.6) }
                        }
                    }

                    // the desktop inside the frame: your wallpaper with rounded inner corners
                    ClippingRectangle {
                        id: desk
                        x: stage.bar; y: stage.fr
                        width: stage.width - stage.bar - stage.fr
                        height: stage.height - 2 * stage.fr
                        radius: Atelier.radiusMd
                        color: pv.base
                        Image {
                            anchors.fill: parent
                            source: Wallpaper.current ? "file://" + Wallpaper.current : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 640; sourceSize.height: 400
                        }

                        // tiled windows (dwindle): focused on the left, two stacked on the right
                        readonly property real leftW: (width - 3 * stage.gap) * 0.58
                        readonly property real rightW: width - 3 * stage.gap - leftW
                        readonly property real halfH: (height - 3 * stage.gap) / 2

                        // focused: a terminal, with the gradient border
                        MiniWindow {
                            x: stage.gap; y: stage.gap
                            width: desk.leftW; height: desk.height - 2 * stage.gap
                            focused: true
                            Column {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8
                                Row {
                                    spacing: 6
                                    Text { text: "󰣇"; font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: pv.accent }
                                    Text { text: "~/atelier"; font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; font.bold: true; color: pv.blue }
                                    Text { text: "on"; font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; color: pv.subtext }
                                    Text { text: " main"; font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; color: pv.mauve }
                                }
                                Row {
                                    spacing: 6
                                    Text { text: "❯"; font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; color: pv.green }
                                    Text { text: "atelier-theme apply"; font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; color: pv.text }
                                }
                                Repeater {
                                    model: [[0.55, pv.green], [0.8, pv.subtext], [0.66, pv.subtext], [0.42, pv.yellow], [0.72, pv.subtext]]
                                    Rectangle {
                                        required property var modelData
                                        width: (desk.leftW - 24) * modelData[0]; height: 5; radius: 2.5
                                        color: Qt.alpha(modelData[1], 0.55)
                                    }
                                }
                                Row {
                                    spacing: 6
                                    Text { text: "❯"; font.family: Atelier.font; font.pixelSize: Atelier.fsMicro; color: pv.green }
                                    Rectangle { width: 6; height: 11; color: pv.accent }
                                }
                            }
                        }

                        // right top: an editor
                        MiniWindow {
                            x: 2 * stage.gap + desk.leftW; y: stage.gap
                            width: desk.rightW; height: desk.halfH
                            Column {
                                anchors.fill: parent
                                anchors.margins: 11
                                spacing: 6
                                Repeater {
                                    model: [[0.3, pv.mauve, 0.5, pv.blue], [0.2, pv.peach, 0.45, pv.text], [0.25, pv.red, 0.3, pv.green], [0.15, pv.mauve, 0.55, pv.subtext]]
                                    Row {
                                        required property var modelData
                                        spacing: 4
                                        Rectangle { width: (desk.rightW - 22) * modelData[0]; height: 5; radius: 2.5; color: modelData[1] }
                                        Rectangle { width: (desk.rightW - 22) * modelData[2]; height: 5; radius: 2.5; color: Qt.alpha(modelData[3], 0.8) }
                                    }
                                }
                            }
                        }

                        // right bottom: a card in the shell's style (chip + clock + slim bar)
                        MiniWindow {
                            x: 2 * stage.gap + desk.leftW; y: 2 * stage.gap + desk.halfH
                            width: desk.rightW; height: desk.halfH
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 11
                                spacing: 4
                                Rectangle {
                                    implicitWidth: chipRow.implicitWidth + 14; implicitHeight: 16; radius: Atelier.radiusSm
                                    color: Qt.alpha(pv.mauve, 0.14); border.width: 1; border.color: Qt.alpha(pv.mauve, 0.35)
                                    Row { id: chipRow; anchors.centerIn: parent; spacing: 4
                                        Text { text: "󰌾"; font.family: Atelier.font; font.pixelSize: 8; color: pv.mauve }
                                        Text { text: "Good evening"; font.family: Atelier.fontUi; font.pixelSize: 8; font.weight: Font.DemiBold; color: pv.mauve } }
                                }
                                Item { Layout.fillHeight: true }
                                Row {
                                    spacing: 0
                                    Text { text: "12"; font.family: Atelier.font; font.pixelSize: 22; font.bold: true; color: pv.text }
                                    Text { text: ":"; font.family: Atelier.font; font.pixelSize: 22; font.bold: true; color: pv.accent }
                                    Text { text: "47"; font.family: Atelier.font; font.pixelSize: 22; font.bold: true; color: pv.text }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 5; radius: 2.5
                                    color: Qt.alpha(pv.pink, 0.16)
                                    Rectangle {
                                        width: parent.width * 0.62; height: parent.height; radius: parent.radius
                                        gradient: Gradient { orientation: Gradient.Horizontal
                                            GradientStop { position: 0; color: Qt.alpha(pv.pink, 0.7) }
                                            GradientStop { position: 1; color: pv.pink } }
                                    }
                                }
                            }
                        }
                    }

                    // applying: a small chip, not a veil
                    Rectangle {
                        anchors.centerIn: desk
                        visible: root.applying !== ""
                        width: busyRow.implicitWidth + 26; height: 34; radius: Atelier.radiusLg
                        color: Atelier.surface
                        border.width: 1
                        border.color: Qt.alpha(Atelier.accent, 0.4)
                        Row {
                            id: busyRow
                            anchors.centerIn: parent
                            spacing: 8
                            Text {
                                text: "󰑐"; font.family: Atelier.font; font.pixelSize: Atelier.iconSm; color: Atelier.accent
                                RotationAnimation on rotation { running: root.applying !== "" && root.visible; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                            }
                            Text { text: "Applying…"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; color: Atelier.text }
                        }
                    }
                }

                // footer: name + apply
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            spacing: 8
                            Text {
                                text: root.sel ? root.sel.name : ""
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsHead; font.weight: Font.DemiBold
                                color: Atelier.text
                            }
                            Chip {
                                visible: !!root.sel
                                icon: root.sel && root.sel.variant === "light" ? "󰖙" : "󰖔"
                                text: root.sel && root.sel.variant === "light" ? "Light" : "Dark"
                                tint: Atelier.subtext
                                implicitHeight: 20; pad: 7
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.sel ? root.sel.description : ""
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd
                            color: Atelier.subtext
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        id: applyBtn
                        readonly property bool inUse: !!(root.sel && root.sel.id === Atelier.themeId)
                        implicitWidth: applyRow.implicitWidth + 32
                        implicitHeight: 38
                        radius: Math.min(height / 2, Atelier.radiusSm)
                        color: inUse ? Qt.alpha(Atelier.green, 0.14) : Qt.alpha(Atelier.accent, applyMa.containsMouse ? 0.3 : 0.2)
                        border.width: 1
                        border.color: inUse ? Qt.alpha(Atelier.green, 0.4) : Qt.alpha(Atelier.accent, 0.5)
                        Behavior on color { CAnim {} }
                        scale: applyMa.pressed && !inUse ? 0.95 : 1
                        Behavior on scale { Anim { type: "fastSpatial" } }
                        Row {
                            id: applyRow
                            anchors.centerIn: parent
                            spacing: 7
                            Text { anchors.verticalCenter: parent.verticalCenter; text: applyBtn.inUse ? "󰄬" : "󰏘"; font.family: Atelier.font; font.pixelSize: Atelier.iconSm; color: applyBtn.inUse ? Atelier.green : Atelier.accent }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: applyBtn.inUse ? "In use" : "Apply"
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold
                                color: applyBtn.inUse ? Atelier.green : Atelier.accent
                                Behavior on color { CAnim {} }
                            }
                            Rectangle {
                                visible: !applyBtn.inUse
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 18; radius: 5
                                color: Qt.alpha(Atelier.accent, 0.18)
                                Text { anchors.centerIn: parent; text: "↵"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.accent }
                            }
                        }
                        MouseArea {
                            id: applyMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: applyBtn.inUse ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: root.apply(root.sel)
                        }
                    }
                }
            }
        }
    }

    // A window in the preview: the theme's base, rounded, with the Hyprland border
    // (focused: mauve -> red gradient, like hypr/theme.lua; otherwise a muted grey).
    component MiniWindow: Rectangle {
        id: mw
        property bool focused: false
        default property alias content: inner.data
        radius: Atelier.radiusSm
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: mw.focused ? pv.mauve : Qt.alpha(pv.surface2, 0.67) }
            GradientStop { position: 1; color: mw.focused ? pv.red : Qt.alpha(pv.surface2, 0.67) }
        }
        Rectangle {
            id: inner
            anchors.fill: parent
            anchors.margins: 2
            radius: mw.radius - 2
            color: Qt.alpha(pv.base, 0.95)
        }
    }
}
