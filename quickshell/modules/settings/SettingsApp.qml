import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.components
import qs.config
import qs.modules.background
import qs.modules.bar
import qs.modules.lock
import qs.services

// The Atelier Settings app: a drawer out of the right edge (an Item inside DrawerHost, so no
// window, render thread or GL context of its own), edits settings.json live through the
// Settings singleton. Open with Super+, · `qs ipc call settings open <page>` ·
// the launcher ("settings") · the control center's gear.
// Layout follows desktop system-settings apps: searchable, grouped sidebar; one page at a
// time in a centred column; one accent colour for every control.
Item {
    id: win
    visible: false
    anchors.fill: parent     // fills the shared DrawerHost window

    signal requestOverlay(string name)
    signal closedSignal()
    property bool isLight: false
    property bool animActive: false
    property real openedAt: 0

    property string page: "appearance"
    readonly property var pages: [
        { id: "profile",       group: "Personalise", icon: "󰀄", label: "Profile",         sub: "Your picture, name and greetings",
          keys: "profile picture photo avatar face image name display greeting account user login full name computer hostname" },
        { id: "appearance",    group: "Personalise", icon: "󰏘", label: "Appearance",      sub: "Theme, wallpaper and the shell's shape",
          keys: "theme colour color wallpaper transition fade wipe slide roundness corners frame border glass opacity control center layout tiles icons cards list header shortcuts" },
        { id: "bar",           group: "Personalise", icon: "󰍜", label: "Bar",             sub: "Position, sections and pinned apps",
          keys: "bar panel position workspaces tray clock pinned apps hover logo power title" },
        { id: "widgets",       group: "Personalise", icon: "󰕮", label: "Desktop",         sub: "The clock and text on your desktop",
          keys: "desktop widget clock date weather greeting tasks media music font shadow" },
        { id: "general",       group: "System",      icon: "󰒓", label: "General",         sub: "Clock, web search, camera, recording, emoji, updates",
          keys: "name 24-hour clock time search engine google duckduckgo bing web recording record screen fps sound animation speed motion iphone camera webcam droidcam emoji emoticon gif gifs giphy tenor skin tone" },
        { id: "defaults",      group: "System",      icon: "󰀻", label: "Default apps",    sub: "Browser, files, editor, media and terminal",
          keys: "default apps applications open with browser web email mail file manager folders text editor code images pictures photos viewer video player music audio pdf documents archives zip terminal mime xdg" },
        { id: "windows",       group: "System",      icon: "󰖲", label: "Windows",         sub: "Tiling layout, gaps, blur and animations",
          keys: "windows tiling layout dwindle master scrolling monocle gaps blur opacity transparency shadow animations hyprland rounding" },
        { id: "notifications", group: "System",      icon: "󰂚", label: "Notifications",   sub: "Pop-ups and Do Not Disturb",
          keys: "notifications pop-ups popups do not disturb dnd" },
        { id: "display",       group: "System",      icon: "󰍹", label: "Display & power", sub: "Night light, idle & sleep, battery, performance modes",
          keys: "night light warmth display volume brightness osd caffeine awake sleep performance game mode programming power" },
        { id: "modes",         group: "System",      icon: "󰊗", label: "Modes",           sub: "What Programming and Game mode change",
          keys: "modes performance game programming dev developer blur opacity opaque shadows animations tearing power profile do not disturb dnd caffeine awake widgets auto detect steam games" },
        { id: "displays",      group: "Hardware",    icon: "󰍺", label: "Displays",        sub: "Resolution, scale, rotation, arrangement",
          keys: "monitor monitors screen resolution refresh rate hz scale rotation rotate portrait mirror hdmi external vrr freesync position arrangement" },
        { id: "input",         group: "Hardware",    icon: "󰌌", label: "Keyboard & mouse", sub: "Layouts, key repeat, pointer and touchpad",
          keys: "keyboard layout language repeat delay caps lock escape numlock mouse pointer speed sensitivity acceleration scroll natural touchpad trackpad tap click left-handed focus" },
        { id: "sound",         group: "Hardware",    icon: "󰕾", label: "Sound",           sub: "Output, microphone and app volumes",
          keys: "sound audio volume speaker headphones output input microphone mic mute apps pipewire bluetooth" },
        { id: "shortcuts",     group: "Hardware",    icon: "󰘳", label: "Shortcuts",       sub: "Change keys and add your own",
          keys: "shortcuts keybinds keybindings hotkeys keys bind rebind custom command" },
        { id: "lock",          group: "Security",    icon: "󰌾", label: "Lock screen",     sub: "Built-in styles, or a qylock theme from GitHub",
          keys: "lock screen qylock themes notifications privacy" },
        { id: "login",         group: "Security",    icon: "󰍂", label: "Login screen",    sub: "The greetd login: layout, look, sync",
          keys: "login greeter greetd sddm boot quiet sync" },
        { id: "storage",       group: "Device",      icon: "󰋊", label: "Storage",         sub: "What is using your disk",
          keys: "storage disk space clean trash cache folders" },
        { id: "profiles",      group: "Device",      icon: "󰆓", label: "Profiles",        sub: "Save, switch and back up your setup",
          keys: "profiles profile backup export import save restore docked laptop hot-plug automatic switch" },
        { id: "about",         group: "Device",      icon: "󰋽", label: "About",           sub: "This laptop's model and specs, version, reset",
          keys: "about version files reset json hardware specs specifications laptop model computer cpu processor gpu graphics ram memory disk ssd storage battery health cycles display screen wifi bios" }
    ]
    readonly property var current: pages.find(p => p.id === page) || pages[0]

    // sidebar search: matches page names, descriptions and the settings on them
    property string query: ""
    readonly property var matches: {
        const q = query.trim().toLowerCase();
        if (!q) return pages;
        return pages.filter(p => (p.label + " " + p.sub + " " + p.keys).toLowerCase().includes(q));
    }
    // sidebar rows: a group header before the first page of each group
    readonly property var sideRows: {
        const out = [];
        let g = "";
        for (const p of matches) {
            if (p.group !== g) { g = p.group; out.push({ header: g }); }
            out.push(p);
        }
        return out;
    }

    readonly property var layoutInfo: ({
        dwindle: "Splits the space in half for each new window",
        master: "One big window plus a stack of the others",
        scrolling: "Windows in columns on an endless horizontal strip",
        monocle: "One window at a time, full size"
    })
    readonly property var searchPresets: [
        { id: "https://duckduckgo.com/?q=", label: "DuckDuckGo" },
        { id: "https://www.google.com/search?q=", label: "Google" },
        { id: "https://www.bing.com/search?q=", label: "Bing" },
        { id: "custom", label: "Custom" }
    ]
    readonly property bool customSearch: !searchPresets.some(p => p.id === Settings.behavior.searchUrl)

    function toggle() { if (visible && animActive) close(); else open(); }
    function open(p) {
        const old = { behavior: "general" };          // pages that were renamed or merged
        if (p) page = old[p] || (pages.some(x => x.id === p) ? p : page);
        if (!animActive) openedAt = Date.now();
        visible = true;
        animActive = true;
        focusTimer.restart();
    }
    function close() {
        if (!animActive) return;
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }
    Timer { id: focusTimer; interval: 40; onTriggered: keys.forceActiveFocus() }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!win.animActive) win.visible = false }

    // The drawer sits above every window and holds the keyboard, so a window that Settings
    // starts (photo picker, terminal for chfn/pacman, file manager, qylock preview) would open
    // behind it. Step aside as soon as a new window maps.
    Connections {
        target: Hyprland
        function onRawEvent(ev) { if (win.animActive && ev.name === "openwindow") win.close(); }
    }

    // ── helpers ─────────────────────────────────────────────────────────────
    readonly property var colorNames: ["accent", "blue", "sky", "teal", "green", "yellow", "peach", "red", "pink", "lavender"]
    function setPinned(i, key, val) {
        const a = Settings.bar.pinned.map(x => Object.assign({}, x));
        a[i][key] = val;
        Settings.bar.pinned = a;
    }
    function removePinned(i) { Settings.bar.pinned = Settings.bar.pinned.filter((x, k) => k !== i); }
    function addPinned() { Settings.bar.pinned = Settings.bar.pinned.concat([{ icon: "󰣆", color: "accent", cmd: "" }]); }

    property bool confirmReset: false
    Timer { id: resetTimer; interval: 4000; onTriggered: win.confirmReset = false }

    Process { id: opener }
    Process {
        id: versionProc
        running: win.visible
        command: ["quickshell", "--version"]
        stdout: StdioCollector { onStreamFinished: about.version = text.trim() }
    }

    // outside click closes (the drawer body below swallows its own clicks)
    MouseArea { anchors.fill: parent; onClicked: win.close() }

    EdgeDrawer {
        id: drawer
        edge: "right"
        open: win.animActive
        bodyWidth: Math.min(1000, win.width - Atelier.insetLeft - Atelier.insetRight - 120)
        bodyHeight: Math.min(780, win.height - Atelier.insetTop - Atelier.insetBottom - 2 * Atelier.fillet - 24)

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (w) => w.accepted = false }   // no click-through to the closer
        // Esc closes; ignore auto-repeat and keys in the first moment (the opening key may still be held)
        Keys.onEscapePressed: (e) => { if (!e.isAutoRepeat && Date.now() - win.openedAt > 350) win.close(); }
        Keys.onPressed: (e) => {          // Ctrl+F jumps to search
            if (e.key === Qt.Key_F && (e.modifiers & Qt.ControlModifier)) { searchIn.forceActiveFocus(); e.accepted = true; }
        }

        // ── Sidebar ─────────────────────────────────────────────────────────
        Rectangle {
            id: sidebar
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 8
            width: 240
            radius: Math.max(8, Atelier.rounding - 8)      // concentric with the drawer's corners
            color: Qt.alpha(Atelier.crust, 0.32)
            border.width: 1
            border.color: Atelier.outline

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                anchors.topMargin: 16
                spacing: 2

                // you: avatar-ish monogram + name, like the account row of a system app
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.bottomMargin: 12
                    spacing: 11
                    Avatar {
                        size: 38
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.page = "profile" }
                    }
                    ColumnLayout {
                        spacing: 0
                        Text { text: Atelier.userName; font.family: Atelier.fontUi; font.pixelSize: 14; font.weight: Font.DemiBold; color: Atelier.text }
                        Text { text: "Settings · " + Atelier.themeName; font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext }
                    }
                }

                // search
                Rectangle {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 8
                    implicitHeight: 34
                    radius: 10
                    color: Atelier.container
                    border.width: 1
                    border.color: searchIn.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : "transparent"
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 11
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰍉"; font.family: Atelier.font; font.pixelSize: 13; color: Atelier.subtext
                    }
                    TextInput {
                        id: searchIn
                        anchors.fill: parent
                        anchors.leftMargin: 32; anchors.rightMargin: 10
                        verticalAlignment: Text.AlignVCenter
                        font.family: Atelier.fontUi; font.pixelSize: 12
                        color: Atelier.text
                        clip: true
                        selectByMouse: true
                        onTextChanged: win.query = text
                        Keys.onReturnPressed: if (win.matches.length) { win.page = win.matches[0].id; text = ""; }
                        Keys.onEscapePressed: (e) => { if (text) { text = ""; e.accepted = true; } else e.accepted = false; }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !searchIn.text
                            text: "Search settings"
                            font: searchIn.font
                            color: Atelier.subtext
                            opacity: 0.7
                        }
                    }
                }

                // the page list scrolls when it is taller than the window
                Flickable {
                    id: sideScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: sideCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    SmoothWheel { flickable: sideScroll }

                    ColumnLayout {
                        id: sideCol
                        width: sideScroll.width
                        spacing: 2

                        Repeater {
                            model: win.sideRows
                            Item {
                                id: srow
                                required property var modelData
                                required property int index
                                readonly property bool isHeader: !!modelData.header
                                readonly property bool on: !isHeader && win.page === modelData.id
                            // keep the open page in view (opened by IPC/launcher further down the list)
                            onOnChanged: if (on) Qt.callLater(() => {
                                if (y < sideScroll.contentY) sideScroll.contentY = y;
                                else if (y + height > sideScroll.contentY + sideScroll.height)
                                    sideScroll.contentY = y + height - sideScroll.height;
                            })
                                Layout.fillWidth: true
                                implicitHeight: isHeader ? (index === 0 ? 22 : 32) : 36

                                Text {
                                    visible: srow.isHeader
                                    anchors.left: parent.left; anchors.leftMargin: 10
                                    anchors.bottom: parent.bottom; anchors.bottomMargin: 5
                                    text: srow.modelData.header || ""
                                    font.family: Atelier.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold
                                    color: Atelier.subtext
                                }

                                Rectangle {
                                    visible: !srow.isHeader
                                    anchors.fill: parent
                                    radius: 9
                                    color: srow.on ? Qt.alpha(Atelier.accent, 0.16) : (ma.containsMouse ? Atelier.container : "transparent")
                                    Behavior on color { ColorAnimation { duration: Atelier.durFast } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 11
                                        Text {
                                            Layout.preferredWidth: 18
                                            horizontalAlignment: Text.AlignHCenter
                                            text: srow.modelData.icon || ""
                                            font.family: Atelier.font; font.pixelSize: 15
                                            color: srow.on ? Atelier.accent : Atelier.subtext1
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: srow.modelData.label || ""
                                            font.family: Atelier.fontUi
                                            font.pixelSize: 13
                                            font.weight: srow.on ? Font.DemiBold : Font.Normal
                                            color: srow.on ? Atelier.text : Atelier.subtext1
                                            elide: Text.ElideRight
                                        }
                                    }
                                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.page = srow.modelData.id }
                                }
                            }
                        }
                        Text {
                            visible: win.matches.length === 0
                            Layout.margins: 10
                            text: "No settings match"
                            font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.subtext
                        }
                    }
                }
                Text {
                    Layout.margins: 10
                    text: "Changes are saved automatically"
                    font.family: Atelier.fontUi
                    font.pixelSize: 10
                    color: Atelier.subtext
                    opacity: 0.7
                }
            }
        }

        // ── Content ─────────────────────────────────────────────────────────
        Item {
            anchors.left: sidebar.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 14
                spacing: 6

                // header bar: page title, close button
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 66
                    ColumnLayout {
                        x: Math.max(28, (parent.width - pageCol.width) / 2)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text { text: win.current.label; font.family: Atelier.fontUi; font.pixelSize: 24; font.weight: Font.Bold; color: Atelier.text }
                        Text { text: win.current.sub; font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.subtext }
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 16
                        anchors.top: parent.top
                        implicitWidth: 28; implicitHeight: 28; radius: 14
                        color: closeMa.containsMouse ? Qt.alpha(Atelier.red, 0.2) : Atelier.container
                        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                        Text { anchors.centerIn: parent; text: "󰅖"; font.family: Atelier.font; font.pixelSize: 13; color: closeMa.containsMouse ? Atelier.red : Atelier.subtext }
                        MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.close() }
                    }
                }

                Flickable {
                    id: scroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: pageCol.implicitHeight + 36
                    boundsBehavior: Flickable.StopAtBounds
                    SmoothWheel { flickable: scroll }

                    // back to the top when switching pages
                    Connections { target: win; function onPageChanged() { scroll.contentY = 0; } }

                    ColumnLayout {
                        id: pageCol
                        // a centred, readable column (system settings apps clamp their content)
                        width: Math.min(scroll.width - 56, 720)
                        x: (scroll.width - width) / 2
                        spacing: 20


                        // ═════════ Appearance ═════════
                        ColumnLayout {
                            visible: win.page === "appearance"
                            Layout.fillWidth: true
                            spacing: 20

                            // hero: a live miniature of your desktop + the theme
                            SettingCard {
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 196
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.topMargin: 14
                                        anchors.bottomMargin: 14
                                        spacing: 22

                                        ClippingRectangle {
                                            id: mini
                                            Layout.preferredWidth: 280
                                            Layout.preferredHeight: 166
                                            radius: 10
                                            color: Atelier.base
                                            // screen px → preview px, exaggerated a little so thin things stay visible
                                            readonly property real k: width / 1920 * 1.7
                                            readonly property string edge: Settings.appearance.barPosition
                                            readonly property real fr: Math.max(2, Settings.appearance.frame * k)
                                            readonly property real bw: Math.max(7, Settings.appearance.barWidth * k)
                                            readonly property real gap: Math.max(2, Settings.windows.gapsOut * k)
                                            readonly property real inL: (edge === "left" ? bw : fr) + gap
                                            readonly property real inR: (edge === "right" ? bw : fr) + gap
                                            readonly property real inT: (edge === "top" ? bw : fr) + gap
                                            readonly property real inB: (edge === "bottom" ? bw : fr) + gap

                                            Image {
                                                anchors.fill: parent
                                                source: win.visible && Wallpaper.current ? "file://" + Wallpaper.current : ""
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                sourceSize.width: 560
                                            }
                                            // the frame
                                            Rectangle { anchors.fill: parent; color: "transparent"; border.width: mini.fr; border.color: Atelier.surface }
                                            // the bar
                                            Rectangle {
                                                color: Atelier.surface
                                                x: mini.edge === "right" ? mini.width - mini.bw : 0
                                                y: mini.edge === "bottom" ? mini.height - mini.bw : 0
                                                width: mini.edge === "left" || mini.edge === "right" ? mini.bw : mini.width
                                                height: mini.edge === "top" || mini.edge === "bottom" ? mini.bw : mini.height
                                                Rectangle {   // logo + workspace dots
                                                    readonly property bool v: mini.edge === "left" || mini.edge === "right"
                                                    x: v ? (parent.width - width) / 2 : 6
                                                    y: v ? 6 : (parent.height - height) / 2
                                                    width: v ? 4 : 16; height: v ? 16 : 4; radius: 2
                                                    color: Atelier.accent
                                                }
                                            }
                                            // two windows, with your corners and gaps
                                            Repeater {
                                                model: 2
                                                Rectangle {
                                                    required property int index
                                                    readonly property real aw: mini.width - mini.inL - mini.inR
                                                    readonly property real g: Math.max(2, Settings.windows.gapsIn * mini.k)
                                                    x: mini.inL + (index === 0 ? 0 : aw * 0.58 + g / 2)
                                                    y: mini.inT
                                                    width: index === 0 ? aw * 0.58 - g / 2 : aw * 0.42 - g / 2
                                                    height: mini.height - mini.inT - mini.inB
                                                    radius: Settings.windowRounding * mini.k
                                                    color: Qt.alpha(Atelier.base, Settings.windows.activeOpacity)
                                                    border.width: 1
                                                    border.color: index === 0 ? Qt.alpha(Atelier.accent, 0.7) : Atelier.outline
                                                    Column {
                                                        x: 8; y: 9; spacing: 4
                                                        Repeater {
                                                            model: 4
                                                            Rectangle { required property int index; width: [44, 30, 52, 24][index]; height: 3; radius: 1.5; color: Qt.alpha(Atelier.text, 0.25) }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            spacing: 6
                                            Text { text: Atelier.themeName; font.family: Atelier.fontUi; font.pixelSize: 20; font.weight: Font.Bold; color: Atelier.text }
                                            Text {
                                                Layout.fillWidth: true
                                                text: (Atelier.isLight ? "Light" : "Dark") + " theme · the shell, Hyprland, terminals, VS Code, GTK and Qt apps follow it"
                                                font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext; wrapMode: Text.Wrap
                                            }
                                            Row {
                                                Layout.topMargin: 6
                                                spacing: 6
                                                Repeater {
                                                    model: ["accent", "red", "peach", "yellow", "green", "teal", "blue", "mauve", "pink"]
                                                    Rectangle {
                                                        required property string modelData
                                                        width: 18; height: 18; radius: 9
                                                        color: Atelier[modelData]
                                                        border.width: modelData === "accent" ? 2 : 0
                                                        border.color: Atelier.text
                                                    }
                                                }
                                            }
                                            Item { Layout.fillHeight: true }
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                Chip { icon: "󰏘"; text: "Change theme"; tint: Atelier.accent; interactive: true; implicitHeight: 32; onClicked: win.requestOverlay("theme") }
                                                Chip { icon: "󰸉"; text: "Wallpaper"; tint: Atelier.accent; interactive: true; implicitHeight: 32; onClicked: win.requestOverlay("wallpaper") }
                                                Chip { icon: Atelier.isLight ? "󰖔" : "󰖨"; text: Atelier.isLight ? "Dark" : "Light"; tint: Atelier.accent; interactive: true; implicitHeight: 32; onClicked: SysState.toggleTheme() }
                                            }
                                        }
                                    }
                                }
                            }

                            SettingCard {
                                title: "Wallpaper transition"; icon: "󰸉"; tint: Atelier.blue
                                SettingChoice { label: "Style"; description: "How a new wallpaper appears"; tint: Atelier.blue
                                    options: [{ id: "none", label: "None" }, { id: "fade", label: "Fade" }, { id: "wipe", label: "Wipe" },
                                              { id: "slide", label: "Slide" }, { id: "grow", label: "Grow" }, { id: "zoom", label: "Zoom" }, { id: "spread", label: "Spread" }, { id: "outline", label: "Outline" }]
                                    value: Settings.appearance.wallTransition; onPicked: (id) => Settings.appearance.wallTransition = id }
                                // Outline needs each wallpaper's subject cut out once (scripts/wallfx.py)
                                SettingRow {
                                    id: fxRow
                                    visible: ["outline", "random"].includes(Settings.appearance.wallTransition)
                                    property var st: ({})
                                    readonly property bool busy: warmProc.running
                                    label: "Outline maps"
                                    description: !st.installed ? "The cut-out model isn't installed yet (about 1 GB)."
                                        : busy ? "Preparing… " + (st.prepared || 0) + " of " + (st.total || 0) + " (in the background, at low priority)"
                                        : (st.prepared || 0) + " of " + (st.total || 0) + " wallpapers prepared. New ones play Spread once while theirs is made."
                                    Chip {
                                        visible: !!fxRow.st.installed
                                        icon: "󰑐"; text: fxRow.busy ? "Preparing…" : "Prepare all"; tint: Atelier.accent
                                        interactive: !fxRow.busy && (fxRow.st.prepared || 0) < (fxRow.st.total || 0); implicitHeight: 30
                                        onClicked: warmProc.running = true
                                    }
                                    Process {
                                        id: fxStatus
                                        command: ["python3", Quickshell.shellDir + "/scripts/wallfx.py", "status"]
                                        stdout: StdioCollector { onStreamFinished: { try { fxRow.st = JSON.parse(text); } catch (e) {} } }
                                    }
                                    Process { id: warmProc; command: ["nice", "-n", "15", "python3", Quickshell.shellDir + "/scripts/wallfx.py", "warm"]; onExited: fxStatus.running = true }
                                    Timer {
                                        interval: fxRow.busy ? 3000 : 20000; repeat: true; triggeredOnStart: true
                                        running: fxRow.visible && win.visible && win.page === "appearance"
                                        onTriggered: fxStatus.running = true
                                    }
                                }
                                SettingSwitch { label: "Surprise me"; description: "Pick a different style each time"; tint: Atelier.blue
                                    checked: Settings.appearance.wallTransition === "random"
                                    onToggled: (v) => Settings.appearance.wallTransition = v ? "random" : "fade" }
                                SettingChoice { label: "Direction"; description: "Where wipe and slide come from"; tint: Atelier.blue
                                    visible: ["wipe", "slide", "random"].includes(Settings.appearance.wallTransition)
                                    options: [{ id: "left", label: "Left" }, { id: "right", label: "Right" }, { id: "top", label: "Top" }, { id: "bottom", label: "Bottom" }]
                                    value: Settings.appearance.wallDirection; onPicked: (id) => Settings.appearance.wallDirection = id }
                                SettingSlider { label: "Duration"; tint: Atelier.blue
                                    visible: Settings.appearance.wallTransition !== "none"
                                    from: 200; to: 2000; step: 50; suffix: " ms"
                                    value: Settings.appearance.wallDuration; onMoved: (v) => Settings.appearance.wallDuration = v }
                            }

                            SettingCard {
                                title: "Corners"; icon: "󰝤"; tint: Atelier.accent
                                SettingSlider { label: "Corner roundness"; description: "The frame, bar pop-ups and drawers"; from: 0; to: 36; step: 2; suffix: " px"
                                    value: Settings.appearance.rounding; onMoved: (v) => Settings.appearance.rounding = v }
                                SettingSwitch {
                                    label: "Match window corners"
                                    description: Settings.appearance.linkRounding
                                        ? "Windows use " + Settings.windowRounding + " px — concentric with the frame, so the corners line up"
                                        : "Windows have their own roundness (Windows page)"
                                    checked: Settings.appearance.linkRounding; onToggled: (v) => Settings.appearance.linkRounding = v }
                            }

                            SettingCard {
                                title: "Frame & glass"; icon: "󰹑"; tint: Atelier.blue
                                SettingSlider { label: "Border thickness"; description: "The frame around the screen"; from: 4; to: 20; step: 1; suffix: " px"; tint: Atelier.blue
                                    value: Settings.appearance.frame; onMoved: (v) => Settings.appearance.frame = v }
                                SettingSlider { label: "Glass opacity"; description: "How solid the bar and drawers are"; from: 0.6; to: 1; step: 0.02; decimals: 2; tint: Atelier.blue
                                    value: Settings.appearance.glass; onMoved: (v) => Settings.appearance.glass = v }
                            }

                            SettingCard {
                                id: ccCard
                                title: "Control center"; icon: "󰒓"; tint: Atelier.lavender
                                readonly property var all: [
                                    { id: "screenshot", label: "Screenshot" }, { id: "record", label: "Record" },
                                    { id: "wallpaper", label: "Wallpaper" }, { id: "theme", label: "Theme" },
                                    { id: "emoji", label: "Emoji" }, { id: "clipboard", label: "Clipboard" },
                                    { id: "camera", label: "Camera" }, { id: "keyboard", label: "On-screen keyboard" },
                                    { id: "keybinds", label: "Shortcuts list" }, { id: "settings", label: "Settings" }]
                                readonly property var picked: Settings.controlCenter.shortcuts || []
                                function setShortcut(id, on) {
                                    // keep the order of `all`; at most five
                                    const next = all.map(x => x.id).filter(x => x === id ? on : picked.indexOf(x) >= 0);
                                    Settings.controlCenter.shortcuts = next.slice(0, 5);
                                }
                                SettingChoice { label: "Layout"; description: "How the switches are drawn (also the grid button in its header)"; tint: Atelier.lavender
                                    options: [{ id: "list", label: "List" }, { id: "tiles", label: "Tiles" }, { id: "icons", label: "Icons" }, { id: "cards", label: "Cards" }]
                                    value: Settings.controlCenter.layout; onPicked: (id) => Settings.controlCenter.layout = id }
                                SettingChoice { label: "Header"; description: "Big clock with the date, or one compact line"; tint: Atelier.lavender
                                    options: [{ id: "full", label: "Big clock" }, { id: "compact", label: "Compact" }]
                                    value: Settings.controlCenter.header; onPicked: (id) => Settings.controlCenter.header = id }
                                SettingSlider { label: "Notifications shown"; description: "The rest behind \"Show more\""; from: 1; to: 10; step: 1; tint: Atelier.lavender
                                    value: Settings.controlCenter.notifLimit; onMoved: (v) => Settings.controlCenter.notifLimit = Math.round(v) }
                                Repeater {
                                    model: ccCard.all
                                    SettingSwitch {
                                        required property var modelData
                                        label: "Shortcut: " + modelData.label
                                        description: !checked && ccCard.picked.length >= 5 ? "Up to five; turn one off first" : ""
                                        tint: Atelier.lavender
                                        checked: ccCard.picked.indexOf(modelData.id) >= 0
                                        onToggled: (v) => { if (!v || ccCard.picked.length < 5) ccCard.setShortcut(modelData.id, v); }
                                    }
                                }
                            }
                        }

                        // ═════════ Bar ═════════
                        ColumnLayout {
                            visible: win.page === "bar"
                            Layout.fillWidth: true
                            spacing: 20

                            SettingCard {
                                title: "Position & size"; icon: "󰍜"; tint: Atelier.blue
                                SettingTiles {
                                    label: "Bar position"
                                    description: "Moves the whole bar. Pop-ups, drawers and window margins follow it."
                                    options: [{ id: "left", label: "Left" }, { id: "top", label: "Top" }, { id: "right", label: "Right" }, { id: "bottom", label: "Bottom" }]
                                    value: Settings.appearance.barPosition
                                    onPicked: (id) => Settings.appearance.barPosition = id
                                    preview: Component {
                                        Item {
                                            readonly property string e: parent.option.id
                                            readonly property bool sel: parent.selected
                                            Rectangle { anchors.fill: parent; radius: 6; color: Qt.alpha(Atelier.text, 0.05) }
                                            Rectangle {
                                                readonly property bool v: parent.e === "left" || parent.e === "right"
                                                x: parent.e === "right" ? parent.width - width : 0
                                                y: parent.e === "bottom" ? parent.height - height : 0
                                                width: v ? 9 : parent.width
                                                height: v ? parent.height : 9
                                                radius: 4
                                                color: parent.sel ? Atelier.accent : Atelier.overlay1
                                            }
                                            Rectangle {   // a window
                                                x: (parent.e === "left" ? 15 : 6); y: (parent.e === "top" ? 15 : 6)
                                                width: parent.width - 21; height: parent.height - 21
                                                radius: 4
                                                color: "transparent"
                                                border.width: 1
                                                border.color: Qt.alpha(Atelier.text, 0.22)
                                            }
                                        }
                                    }
                                }
                                SettingSlider { label: "Bar thickness"; from: 36; to: 64; step: 2; suffix: " px"; tint: Atelier.blue
                                    value: Settings.appearance.barWidth; onMoved: (v) => Settings.appearance.barWidth = v }
                            }

                            SettingCard {
                                title: "Sections"; icon: "󰕮"; tint: Atelier.blue
                                SettingSwitch { label: "Launcher button"; description: "The logo at the start of the bar"; tint: Atelier.blue
                                    checked: Settings.bar.showLogo; onToggled: (v) => Settings.bar.showLogo = v }
                                SettingSwitch { label: "Workspaces"; tint: Atelier.blue
                                    checked: Settings.bar.showWorkspaces; onToggled: (v) => Settings.bar.showWorkspaces = v }
                                SettingSlider { visible: Settings.bar.showWorkspaces; label: "Workspaces shown"; description: "More appear automatically as you use them"; from: 3; to: 10; step: 1; tint: Atelier.blue
                                    value: Settings.bar.minWorkspaces; onMoved: (v) => Settings.bar.minWorkspaces = v }
                                SettingSwitch { label: "Pinned apps"; description: "The launcher shortcuts under the workspaces"; tint: Atelier.blue
                                    checked: Settings.bar.showApps; onToggled: (v) => Settings.bar.showApps = v }
                                SettingSwitch { label: "Window title"; description: "The focused window's title"; tint: Atelier.blue
                                    checked: Settings.bar.showTitle; onToggled: (v) => Settings.bar.showTitle = v }
                                SettingSwitch { label: "System tray"; tint: Atelier.blue
                                    checked: Settings.bar.showTray; onToggled: (v) => Settings.bar.showTray = v }
                                SettingSwitch { label: "Clock"; tint: Atelier.blue
                                    checked: Settings.bar.showClock; onToggled: (v) => Settings.bar.showClock = v }
                                SettingSwitch { label: "Status icons"; description: "Wi-Fi, Bluetooth, volume, battery and the notification bell"; tint: Atelier.blue
                                    checked: Settings.bar.showStatus; onToggled: (v) => Settings.bar.showStatus = v }
                                SettingSwitch { label: "Power button"; tint: Atelier.blue
                                    checked: Settings.bar.showPower; onToggled: (v) => Settings.bar.showPower = v }
                            }

                            SettingCard {
                                title: "Behaviour"; icon: "󰆽"; tint: Atelier.mauve
                                SettingSwitch { label: "Open on hover"
                                    description: "Point at Wi-Fi, Bluetooth or the clock to open its menu; the right screen edge shows volume & brightness. Click an icon to keep its menu open."
                                    tint: Atelier.mauve
                                    checked: Settings.bar.openOnHover; onToggled: (v) => Settings.bar.openOnHover = v }
                            }

                            SettingCard {
                                title: "Pinned apps"; icon: "󰐃"; tint: Atelier.peach
                                Text {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 12
                                    Layout.bottomMargin: 6
                                    text: "Icon is any Nerd Font glyph (copy one from nerdfonts.com/cheat-sheet). The command runs in a shell, so \"firefox || chromium\" works."
                                    font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext; wrapMode: Text.Wrap
                                }
                                Repeater {
                                    model: Settings.bar.pinned
                                    RowLayout {
                                        id: appRow
                                        Layout.bottomMargin: 6
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Rectangle {
                                            implicitWidth: 52; implicitHeight: 34; radius: 17
                                            color: Atelier.containerHigh
                                            border.width: 1; border.color: iconIn.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                                            TextInput {
                                                id: iconIn
                                                anchors.fill: parent
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                font.family: Atelier.font; font.pixelSize: 16
                                                color: Atelier[appRow.modelData.color] !== undefined ? Atelier[appRow.modelData.color] : Atelier.text
                                                text: appRow.modelData.icon
                                                onEditingFinished: if (text !== appRow.modelData.icon) win.setPinned(appRow.index, "icon", text)
                                            }
                                        }
                                        // colour: click to cycle
                                        Rectangle {
                                            implicitWidth: 34; implicitHeight: 34; radius: 17
                                            color: Atelier.containerHigh
                                            border.width: 1; border.color: Atelier.outline
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 16; height: 16; radius: 8
                                                color: Atelier[appRow.modelData.color] !== undefined ? Atelier[appRow.modelData.color] : Atelier.text
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    const i = win.colorNames.indexOf(appRow.modelData.color);
                                                    win.setPinned(appRow.index, "color", win.colorNames[(i + 1) % win.colorNames.length]);
                                                }
                                            }
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 34; radius: 17
                                            color: Atelier.containerHigh
                                            border.width: 1; border.color: cmdIn.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                                            TextInput {
                                                id: cmdIn
                                                anchors.fill: parent
                                                anchors.leftMargin: 14; anchors.rightMargin: 14
                                                verticalAlignment: Text.AlignVCenter
                                                font.family: Atelier.font; font.pixelSize: 12
                                                color: Atelier.text
                                                clip: true
                                                selectByMouse: true
                                                text: appRow.modelData.cmd
                                                onEditingFinished: if (text !== appRow.modelData.cmd) win.setPinned(appRow.index, "cmd", text)
                                            }
                                        }
                                        Rectangle {
                                            implicitWidth: 34; implicitHeight: 34; radius: 17
                                            color: delMa.containsMouse ? Qt.alpha(Atelier.red, 0.22) : Atelier.containerHigh
                                            Text { anchors.centerIn: parent; text: "󰆴"; font.family: Atelier.font; font.pixelSize: 14; color: delMa.containsMouse ? Atelier.red : Atelier.subtext }
                                            MouseArea { id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.removePinned(appRow.index) }
                                        }
                                    }
                                }
                                Chip { Layout.topMargin: 8; Layout.bottomMargin: 12; icon: "󰐕"; text: "Add app"; tint: Atelier.accent; interactive: true; implicitHeight: 32; onClicked: win.addPinned() }
                            }
                        }

                        // ═════════ Desktop (widget) ═════════
                        ColumnLayout {
                            visible: win.page === "widgets"
                            Layout.fillWidth: true
                            spacing: 20

                            SettingCard {
                                title: "Desktop widget"
                                SettingSwitch { label: "Show on the desktop"; description: "Clock and a few lines of text on empty workspaces (hidden in Game mode)"
                                    checked: Settings.widgets.enabled; onToggled: (v) => Settings.widgets.enabled = v }
                                // position: click a spot on the little screen
                                SettingRow {
                                    enabled: Settings.widgets.enabled; opacity: enabled ? 1 : 0.5
                                    label: "Position"
                                    description: "Click where it should sit"
                                    Rectangle {
                                        id: posPad
                                        implicitWidth: 168; implicitHeight: 100
                                        radius: 8
                                        color: Atelier.containerHigh
                                        border.width: 1; border.color: Atelier.outline
                                        readonly property var hs: ["left", "center", "right"]
                                        readonly property var vs: ["top", "middle", "bottom"]
                                        Grid {
                                            anchors.fill: parent; anchors.margins: 6
                                            columns: 3; spacing: 4
                                            Repeater {
                                                model: 9
                                                Rectangle {
                                                    required property int index
                                                    readonly property string h: posPad.hs[index % 3]
                                                    readonly property string v: posPad.vs[Math.floor(index / 3)]
                                                    readonly property bool on: Settings.widgets.hAlign === h && Settings.widgets.vAlign === v
                                                    width: (posPad.width - 12 - 8) / 3; height: (posPad.height - 12 - 8) / 3
                                                    radius: 4
                                                    color: on ? Atelier.fill(Atelier.accent) : (cellMa.containsMouse ? Qt.alpha(Atelier.text, 0.10) : "transparent")
                                                    Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                                                    Rectangle { visible: !parent.on; anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: Qt.alpha(Atelier.text, 0.3) }
                                                    Column {   // the widget, as three lines of text
                                                        visible: parent.on
                                                        anchors.centerIn: parent; spacing: 2
                                                        Rectangle { width: 22; height: 5; radius: 2; color: Atelier.onFill }
                                                        Rectangle { width: 14; height: 2; radius: 1; color: Qt.alpha(Atelier.onFill, 0.7) }
                                                    }
                                                    MouseArea { id: cellMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: { Settings.widgets.hAlign = parent.h; Settings.widgets.vAlign = parent.v; } }
                                                }
                                            }
                                        }
                                    }
                                }
                                SettingSlider { enabled: Settings.widgets.enabled; opacity: enabled ? 1 : 0.5
                                    label: "Distance from edges"; from: 16; to: 240; step: 8; suffix: " px"
                                    value: Settings.widgets.gutter; onMoved: (v) => Settings.widgets.gutter = Math.round(v) }
                                SettingSlider { enabled: Settings.widgets.enabled; opacity: enabled ? 1 : 0.5
                                    label: "Opacity"; from: 30; to: 100; step: 5; suffix: "%"
                                    value: Math.round(Settings.widgets.opacity * 100); onMoved: (v) => Settings.widgets.opacity = v / 100 }
                            }

                            SettingCard {
                                title: "Clock"
                                enabled: Settings.widgets.enabled; opacity: enabled ? 1 : 0.5
                                SettingTiles {
                                    label: "Typeface"
                                    tileHeight: 64
                                    options: [{ id: "display", label: "Display" }, { id: "mono", label: "Mono" }, { id: "serif", label: "Serif" }]
                                    value: Settings.widgets.clockFont
                                    onPicked: (id) => Settings.widgets.clockFont = id
                                    preview: Component {
                                        Text {
                                            text: "9:41"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            font.family: parent.option.id === "mono" ? Atelier.font : parent.option.id === "serif" ? "Noto Serif" : "Inter Display"
                                            font.pixelSize: 30
                                            font.weight: ({ thin: Font.Thin, light: Font.Light, regular: Font.Normal, bold: Font.Bold })[Settings.widgets.clockWeight]
                                            color: parent.selected ? (Settings.widgets.clockColor === "accent" ? Atelier.accent : Atelier.text) : Atelier.subtext
                                        }
                                    }
                                }
                                SettingChoice { label: "Weight"
                                    options: [{ id: "thin", label: "Thin" }, { id: "light", label: "Light" }, { id: "regular", label: "Regular" }, { id: "bold", label: "Bold" }]
                                    value: Settings.widgets.clockWeight; onPicked: (id) => Settings.widgets.clockWeight = id }
                                SettingSlider { label: "Size"; from: 64; to: 220; step: 4; suffix: " px"
                                    value: Settings.widgets.clockSize; onMoved: (v) => Settings.widgets.clockSize = Math.round(v) }
                                SettingChoice { label: "Colour"
                                    options: [{ id: "text", label: "Text" }, { id: "accent", label: "Accent" }]
                                    value: Settings.widgets.clockColor; onPicked: (id) => Settings.widgets.clockColor = id }
                                SettingSwitch { visible: !Atelier.clock24; label: "AM / PM"; description: "Small label beside the time"
                                    checked: Settings.widgets.showAmPm; onToggled: (v) => Settings.widgets.showAmPm = v }
                                SettingSwitch { label: "Leading zero"; description: "09:15 instead of 9:15"
                                    checked: Settings.widgets.leadingZero; onToggled: (v) => Settings.widgets.leadingZero = v }
                            }

                            SettingCard {
                                title: "Lines under the clock"
                                enabled: Settings.widgets.enabled; opacity: enabled ? 1 : 0.5
                                SettingSwitch { label: "Greeting"; description: Settings.widgets.greetingText || ("Good evening, " + Atelier.userName)
                                    checked: Settings.widgets.showGreeting; onToggled: (v) => Settings.widgets.showGreeting = v }
                                SettingField { visible: Settings.widgets.showGreeting; label: "    Custom greeting"; description: "Empty greets you by time of day"; placeholder: "e.g. Stay curious"
                                    text: Settings.widgets.greetingText; onCommitted: (t) => Settings.widgets.greetingText = t.trim() }
                                SettingSwitch { label: "Date"; description: "Click it to open the calendar"
                                    checked: Settings.widgets.showDate; onToggled: (v) => Settings.widgets.showDate = v }
                                SettingChoice { visible: Settings.widgets.showDate; label: "    Format"
                                    options: [{ id: "long", label: "Friday, 20 November" }, { id: "short", label: "Fri 20 Nov" }, { id: "numeric", label: "20/11" }, { id: "iso", label: "ISO" }]
                                    value: Settings.widgets.dateFormat; onPicked: (id) => Settings.widgets.dateFormat = id }
                                SettingSwitch { visible: Settings.widgets.showDate; label: "    In capitals"; description: "Small spaced capitals"
                                    checked: Settings.widgets.dateCaps; onToggled: (v) => Settings.widgets.dateCaps = v }
                                SettingSwitch { label: "Weather"; description: "Temperature and sky"
                                    checked: Settings.widgets.showWeather; onToggled: (v) => Settings.widgets.showWeather = v }
                                SettingField { visible: Settings.widgets.showWeather; label: "    Location"; description: "City name. Empty finds it from your IP"; placeholder: "e.g. London"; fieldWidth: 200
                                    text: Settings.widgets.weatherLocation; onCommitted: (t) => Settings.widgets.weatherLocation = t.trim() }
                                SettingChoice { visible: Settings.widgets.showWeather; label: "    Units"
                                    options: [{ id: "metric", label: "°C" }, { id: "imperial", label: "°F" }]
                                    value: Settings.widgets.weatherUnits; onPicked: (id) => Settings.widgets.weatherUnits = id }
                                SettingSwitch { label: "Now playing"; description: "Only while music plays; click to pause"
                                    checked: Settings.widgets.showMedia; onToggled: (v) => Settings.widgets.showMedia = v }
                                SettingSwitch { label: "Next task"; description: "Click it to edit your tasks"
                                    checked: Settings.widgets.showTasks; onToggled: (v) => Settings.widgets.showTasks = v }
                                SettingField { visible: Settings.widgets.showTasks; label: "    Tasks file"; description: "Markdown with \"- [ ] task\" lines"; placeholder: "~/day_plan.md"; fieldWidth: 220
                                    text: Settings.widgets.tasksFile; onCommitted: (t) => Settings.widgets.tasksFile = t.trim() || "~/day_plan.md" }
                                SettingSwitch { label: "System"; description: "CPU, memory, disk and battery as one line"
                                    checked: Settings.widgets.showSystem; onToggled: (v) => Settings.widgets.showSystem = v }
                            }

                            SettingCard {
                                title: "Readability"
                                enabled: Settings.widgets.enabled; opacity: enabled ? 1 : 0.5
                                SettingChoice { label: "Text colour"; description: "Automatic reads the wallpaper behind the widget"
                                    options: [{ id: "auto", label: "Automatic" }, { id: "light", label: "Light" }, { id: "dark", label: "Dark" }]
                                    value: Settings.widgets.textColor; onPicked: (id) => Settings.widgets.textColor = id }
                                SettingChoice { label: "Shadow"
                                    options: [{ id: "off", label: "Off" }, { id: "soft", label: "Soft" }, { id: "strong", label: "Strong" }]
                                    value: Settings.widgets.shadow; onPicked: (id) => Settings.widgets.shadow = id }
                            }
                        }

                        // ═════════ Profile ═════════
                        ColumnLayout {
                            visible: win.page === "profile"
                            Layout.fillWidth: true
                            spacing: 20
                            onVisibleChanged: if (visible) Profile.refresh()

                            // hero: picture + name + account, with the picture actions
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 148
                                radius: 12
                                color: Atelier.container
                                border.width: 1
                                border.color: Atelier.outline
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 22; anchors.rightMargin: 22
                                    spacing: 20
                                    Avatar {
                                        size: 104
                                        ring: true
                                        Rectangle {
                                            anchors.right: parent.right; anchors.bottom: parent.bottom
                                            width: 32; height: 32; radius: 16
                                            color: Atelier.accentFill
                                            border.width: 3; border.color: Atelier.container
                                            Text { anchors.centerIn: parent; text: Profile.busy ? "…" : "󰄀"; font.family: Atelier.font; font.pixelSize: 14; color: Atelier.onFill }
                                        }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Profile.pick() }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text { Layout.fillWidth: true; text: Atelier.userName; elide: Text.ElideRight
                                            font.family: Atelier.fontUi; font.pixelSize: 22; font.weight: Font.DemiBold; color: Atelier.text }
                                        Text { Layout.fillWidth: true; elide: Text.ElideRight
                                            text: Profile.login + (Profile.host ? " @ " + Profile.host : "") + (Profile.realName && Profile.realName !== Atelier.userName ? "  ·  " + Profile.realName : "")
                                            font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.subtext }
                                        Text { Layout.fillWidth: true; Layout.topMargin: 4; wrapMode: Text.WordWrap
                                            visible: Profile.error !== ""; text: Profile.error
                                            font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.red }
                                        RowLayout {
                                            Layout.topMargin: 10
                                            spacing: 6
                                            Chip { icon: "󰄀"; text: Profile.hasFace ? "Change picture" : "Add picture"; tint: Atelier.accent
                                                interactive: !Profile.busy; implicitHeight: 30; onClicked: Profile.pick() }
                                            Chip { visible: Profile.hasFace; icon: "󰆴"; text: "Remove"; tint: Atelier.red
                                                interactive: !Profile.busy; implicitHeight: 30; onClicked: Profile.remove() }
                                            Chip { visible: Profile.hasBackup; icon: "󰕌"; text: "Previous"; tint: Atelier.subtext
                                                interactive: !Profile.busy; implicitHeight: 30; onClicked: Profile.restore() }
                                        }
                                    }
                                }
                            }

                            SettingCard {
                                title: "Name and greetings"
                                SettingField { label: "Display name"; description: "Shown on the lock screen, desktop and Settings. Empty uses " + (Profile.realName ? "your full name" : "your login name")
                                    placeholder: Profile.realName || Profile.login
                                    text: Settings.general.userName; onCommitted: (t) => Settings.general.userName = t.trim() }
                                SettingField { label: "Desktop greeting"; description: "Under the desktop clock. Empty = Good morning / afternoon / evening"
                                    placeholder: "By time of day"
                                    text: Settings.widgets.greetingText; onCommitted: (t) => Settings.widgets.greetingText = t.trim() }
                                SettingField { label: "Login screen greeting"; description: "Above the clock on the login screen"
                                    placeholder: "By time of day"
                                    text: Settings.greeter.greeting; onCommitted: (t) => Settings.greeter.greeting = t.trim() }
                            }

                            SettingCard {
                                title: "Account"
                                SettingRow {
                                    label: "Login name"
                                    description: "Your Linux user. It can't be changed from here"
                                    Text { text: Profile.login; font.family: Atelier.fontUi; font.pixelSize: 13; color: Atelier.subtext1 }
                                }
                                SettingRow {
                                    label: "Full name"
                                    description: Profile.realName ? "Stored in your account (GECOS); other apps show it" : "Not set. Other apps show your login name"
                                    RowLayout {
                                        spacing: 8
                                        Text { visible: Profile.realName !== ""; text: Profile.realName; font.family: Atelier.fontUi; font.pixelSize: 13; color: Atelier.subtext1 }
                                        Chip { icon: "󰏫"; text: "Edit"; tint: Atelier.subtext; interactive: true; implicitHeight: 28
                                            onClicked: Quickshell.execDetached([Settings.behavior.terminal, "-e", "sh", "-c",
                                                "echo 'Change your full name: type it at the Name prompt, press Enter to keep the other fields.'; echo; chfn; echo; read -p 'Done. Press Enter to close' x"]) }
                                    }
                                }
                                SettingRow {
                                    label: "Computer name"
                                    description: "How this PC shows up on the network and in Bluetooth"
                                    RowLayout {
                                        spacing: 8
                                        Text { text: Profile.host; font.family: Atelier.fontUi; font.pixelSize: 13; color: Atelier.subtext1 }
                                        Chip { icon: "󰏫"; text: "Rename"; tint: Atelier.subtext; interactive: true; implicitHeight: 28
                                            onClicked: Quickshell.execDetached([Settings.behavior.terminal, "-e", "sh", "-c",
                                                "printf 'New computer name: '; read n; [ -n \"$n\" ] && sudo hostnamectl hostname \"$n\"; echo; read -p 'Done. Press Enter to close' x"]) }
                                    }
                                }
                                SettingRow {
                                    label: "Login screen"
                                    description: Settings.greeter.autoSync ? "Your picture and greeting follow to the login screen automatically" : "Turn on syncing in Login screen to use this picture there too"
                                    Chip { icon: "󰅂"; text: "Open"; tint: Atelier.subtext; interactive: true; implicitHeight: 28; onClicked: win.page = "login" }
                                }
                            }
                        }

                        // ═════════ General ═════════
                        ColumnLayout {
                            visible: win.page === "general"
                            Layout.fillWidth: true
                            spacing: 20

                            SettingCard {
                                title: "iPhone camera"
                                SettingRow {
                                    label: PhoneCam.live ? "Live over " + PhoneCam.linkLabel
                                        : PhoneCam.state === "connecting" ? "Connecting…"
                                        : PhoneCam.state === "error" ? "Not connected" : "Off"
                                    description: PhoneCam.state === "error" ? PhoneCam.error
                                        : "Open DroidCam on the iPhone. It shows up as \"iPhone Camera\" in the camera drawer, OBS, browsers and Discord."
                                    Chip { icon: "󰄜"; text: PhoneCam.running ? "Disconnect" : "Connect"; tint: PhoneCam.running ? Atelier.red : Atelier.accent
                                        interactive: true; implicitHeight: 30; onClicked: PhoneCam.toggle() }
                                }
                                SettingChoice { label: "Connect over"; description: "Auto tries the USB cable, then your iPhone hotspot, then Wi-Fi"
                                    options: [{ id: "auto", label: "Auto" }, { id: "usb", label: "USB" }, { id: "hotspot", label: "Hotspot" }, { id: "wifi", label: "Wi-Fi" }]
                                    value: Settings.phone.mode; onPicked: (id) => Settings.phone.mode = id }
                                SettingField { label: "iPhone address on Wi-Fi"; description: "Only for your router's Wi-Fi: the IP DroidCam shows. Empty = find it by name"
                                    placeholder: "192.168.1.23"
                                    text: Settings.phone.wifiAddress; onCommitted: (t) => Settings.phone.wifiAddress = t.trim() }
                            }

                            SettingCard {
                                title: "You"; icon: "󰥔"; tint: Atelier.peach
                                SettingSwitch { label: "24-hour clock"; description: "Bar, widgets, control center and lock screen"; tint: Atelier.peach
                                    checked: Settings.general.clock24; onToggled: (v) => Settings.general.clock24 = v }
                            }

                            SettingCard {
                                title: "Web search"; icon: "󰒓"
                                SettingRow { label: "Default apps"; description: "Browser, file manager, editor, players, terminal"
                                    Chip { icon: "󰅂"; text: "Open"; tint: Atelier.subtext; interactive: true; implicitHeight: 28; onClicked: win.page = "defaults" } }
                                SettingChoice { label: "Web search"; description: "The launcher's ? search"
                                    options: win.searchPresets
                                    value: win.customSearch ? "custom" : Settings.behavior.searchUrl
                                    onPicked: (id) => { if (id !== "custom") Settings.behavior.searchUrl = id; else if (!win.customSearch) Settings.behavior.searchUrl = "https://"; } }
                                SettingField { visible: win.customSearch; label: "Search URL"; description: "Your query is added at the end"; fieldWidth: 300
                                    placeholder: "https://example.com/search?q="
                                    text: Settings.behavior.searchUrl; onCommitted: (t) => Settings.behavior.searchUrl = t.trim() || "https://duckduckgo.com/?q=" }
                            }

                            SettingCard {
                                title: "Screen recording"; icon: "󰑋"; tint: Atelier.red
                                SettingRow { label: Recorder.available ? "Start / stop" : "Needs wf-recorder"
                                    description: Recorder.available ? "Super+Shift+R picks an area · Super+Alt+R records the whole screen · R in the screenshot picker"
                                                                    : "sudo pacman -S wf-recorder" }
                                SettingChoice { label: "Sound"; tint: Atelier.red
                                    options: [{ id: "none", label: "None" }, { id: "system", label: "System" }, { id: "mic", label: "Microphone" }]
                                    value: Settings.recorder.audio; onPicked: (id) => Settings.recorder.audio = id }
                                SettingChoice { label: "Frame rate"; tint: Atelier.red
                                    options: [{ id: "30", label: "30 fps" }, { id: "60", label: "60 fps" }]
                                    value: String(Settings.recorder.fps); onPicked: (id) => Settings.recorder.fps = Number(id) }
                                SettingField { label: "Save to"; placeholder: "~/Videos/Recordings"; fieldWidth: 260
                                    text: Settings.recorder.folder; onCommitted: (t) => Settings.recorder.folder = t.trim() || "~/Videos/Recordings" }
                            }
                            SettingCard {
                                title: "Emoji & GIFs"; icon: "󰞅"; tint: Atelier.yellow
                                SettingRow { label: "Open"
                                    description: "Super+; for emoji · Super+Shift+; for GIFs · Tab switches between them"
                                    Chip { icon: "󰞅"; text: "Emoji"; tint: Atelier.yellow; interactive: true; implicitHeight: 32
                                        onClicked: win.requestOverlay("emoji") } }
                                SettingSwitch { label: "Type the emoji for me"
                                    description: "Also types it into the window you were in (needs wtype). Off: only copies it"
                                    checked: Settings.emoji.typeOnPick; onToggled: (v) => Settings.emoji.typeOnPick = v }
                                SettingChoice { label: "Skin tone"; description: "For emoji that have one"
                                    options: [{ id: "0", label: "✋" }, { id: "1", label: "✋🏻" }, { id: "2", label: "✋🏼" },
                                              { id: "3", label: "✋🏽" }, { id: "4", label: "✋🏾" }, { id: "5", label: "✋🏿" }]
                                    value: String(Settings.emoji.tone); onPicked: (id) => Settings.emoji.tone = Number(id) }
                                SettingChoice { label: "GIF service"; description: "Both are free with a key; safe search is always on"
                                    options: [{ id: "giphy", label: "GIPHY" }, { id: "tenor", label: "Tenor" }]
                                    value: Settings.emoji.gifProvider; onPicked: (id) => Settings.emoji.gifProvider = id }
                                SettingField { label: "API key"; fieldWidth: 280
                                    description: Settings.emoji.gifProvider === "tenor" ? "console.cloud.google.com → enable the Tenor API → create a key"
                                                                                       : "developers.giphy.com → Create an app → API key"
                                    placeholder: "Paste your key"
                                    text: Settings.emoji.gifKey; onCommitted: (t) => Settings.emoji.gifKey = t.trim() }
                            }

                            SettingCard {
                                title: "Updates & drives"; icon: "󰚰"; tint: Atelier.teal
                                SettingSwitch { label: "Check for updates"; tint: Atelier.teal
                                    description: Updates.count > 0 ? Updates.count + " waiting: they're in the control center" : "Shows them in the control center (system and AUR, no password needed)"
                                    checked: Settings.updates.check; onToggled: (v) => Settings.updates.check = v }
                                SettingSlider { visible: Settings.updates.check; label: "Check every"; from: 1; to: 24; step: 1; suffix: " h"; tint: Atelier.teal
                                    value: Settings.updates.hours; onMoved: (v) => Settings.updates.hours = Math.round(v) }
                                SettingRow {
                                    visible: Settings.updates.check
                                    label: "Check now"
                                    description: Updates.checking ? "Checking…" : Updates.checkedAt > 0 ? "Last checked " + Notifs.ago(Updates.checkedAt) : "Not checked yet"
                                    Chip { icon: "󰑐"; text: "Check"; tint: Atelier.teal; interactive: !Updates.checking; implicitHeight: 30
                                        onClicked: Updates.check() }
                                }
                                SettingSwitch { label: "Plugged-in drives"; description: "A notification with Open and Eject when a USB drive or SD card goes in"; tint: Atelier.teal
                                    checked: Settings.drives.notify; onToggled: (v) => Settings.drives.notify = v }
                            }
                        }

                        // ═════════ Windows (Hyprland) ═════════
                        ColumnLayout {
                            visible: win.page === "windows"
                            Layout.fillWidth: true
                            spacing: 20

                            SettingCard {
                                title: "Layout"; icon: "󰕰"; tint: Atelier.accent
                                SettingTiles {
                                    label: "Tiling layout"
                                    description: win.layoutInfo[Settings.windows.layout] + "  ·  Super+Alt+Space cycles"
                                    options: [{ id: "dwindle", label: "Dwindle" }, { id: "master", label: "Master" }, { id: "scrolling", label: "Scrolling" }, { id: "monocle", label: "Monocle" }]
                                    value: Settings.windows.layout
                                    onPicked: (id) => Settings.windows.layout = id
                                    preview: Component {
                                        Item {
                                            id: lay
                                            readonly property string l: parent.option.id
                                            readonly property color c: parent.selected ? Atelier.accent : Atelier.overlay1
                                            // window rects as fractions [x, y, w, h] of the tile
                                            readonly property var rects: l === "dwindle" ? [[0, 0, .5, 1], [.5, 0, .5, .5], [.5, .5, .25, .5], [.75, .5, .25, .5]]
                                                : l === "master" ? [[0, 0, .6, 1], [.6, 0, .4, .333], [.6, .333, .4, .333], [.6, .666, .4, .334]]
                                                : l === "scrolling" ? [[-.25, 0, .45, 1], [.22, 0, .56, 1], [.8, 0, .45, 1]]
                                                : [[0, 0, 1, 1]]
                                            Repeater {
                                                model: lay.rects
                                                Rectangle {
                                                    required property var modelData
                                                    required property int index
                                                    x: modelData[0] * lay.width + 2; y: modelData[1] * lay.height + 2
                                                    width: modelData[2] * lay.width - 4; height: modelData[3] * lay.height - 4
                                                    radius: 4
                                                    color: Qt.alpha(lay.c, index === (lay.l === "scrolling" ? 1 : 0) ? 0.55 : 0.22)
                                                }
                                            }
                                        }
                                    }
                                }

                                // dwindle
                                SettingSwitch { visible: Settings.windows.layout === "dwindle"; label: "Keep split direction"; description: "New windows keep the split you chose instead of re-guessing"
                                    checked: Settings.windows.dwindlePreserveSplit; onToggled: (v) => Settings.windows.dwindlePreserveSplit = v }
                                SettingSwitch { visible: Settings.windows.layout === "dwindle"; label: "Smart split"; description: "Split on the side of the window your cursor is nearest"
                                    checked: Settings.windows.dwindleSmartSplit; onToggled: (v) => Settings.windows.dwindleSmartSplit = v }

                                // master
                                SettingChoice { visible: Settings.windows.layout === "master"; label: "Master position"; description: "Where the big window sits"
                                    options: [{ id: "left", label: "Left" }, { id: "right", label: "Right" }, { id: "top", label: "Top" }, { id: "bottom", label: "Bottom" }, { id: "center", label: "Center" }]
                                    value: Settings.windows.masterOrientation; onPicked: (id) => Settings.windows.masterOrientation = id }
                                SettingSlider { visible: Settings.windows.layout === "master"; label: "Master size"; description: "Share of the screen the master takes"; from: 0.3; to: 0.8; step: 0.01; decimals: 2
                                    value: Settings.windows.masterFactor; onMoved: (v) => Settings.windows.masterFactor = v }
                                SettingSwitch { visible: Settings.windows.layout === "master"; label: "New windows on top"; description: "Otherwise they go to the end of the stack"
                                    checked: Settings.windows.masterNewOnTop; onToggled: (v) => Settings.windows.masterNewOnTop = v }

                                // scrolling
                                SettingSlider { visible: Settings.windows.layout === "scrolling"; label: "Column width"; description: "Width of each column, as a share of the screen"; from: 0.2; to: 1; step: 0.05; decimals: 2
                                    value: Settings.windows.scrollColumnWidth; onMoved: (v) => Settings.windows.scrollColumnWidth = v }

                                Text {
                                    visible: Settings.windows.layout === "monocle"
                                    Layout.fillWidth: true
                                    text: "Monocle has no options: every window is full-size and you switch between them."
                                    font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext; wrapMode: Text.Wrap
                                }
                            }

                            SettingCard {
                                title: "Spacing & corners"; icon: "󰖲"; tint: Atelier.sky
                                SettingSlider { label: "Gap between windows"; from: 0; to: 20; step: 1; suffix: " px"; tint: Atelier.sky
                                    value: Settings.windows.gapsIn; onMoved: (v) => Settings.windows.gapsIn = v }
                                SettingSlider { label: "Gap to screen edge"; from: 0; to: 30; step: 1; suffix: " px"; tint: Atelier.sky
                                    value: Settings.windows.gapsOut; onMoved: (v) => Settings.windows.gapsOut = v }
                                SettingRow {
                                    visible: Settings.appearance.linkRounding
                                    label: "Window corner rounding"
                                    description: "Linked to the shell's roundness (Appearance), so corners line up with the frame"
                                    Chip { text: Settings.windowRounding + " px  ·  linked"; mono: true; tint: Atelier.sky; implicitHeight: 28 }
                                }
                                SettingSlider { visible: !Settings.appearance.linkRounding; label: "Window corner rounding"; from: 0; to: 28; step: 1; suffix: " px"; tint: Atelier.sky
                                    value: Settings.windows.rounding; onMoved: (v) => Settings.windows.rounding = v }
                            }

                            SettingCard {
                                title: "Transparency & blur"; icon: "󰂵"; tint: Atelier.sky
                                SettingSlider { label: "Focused window opacity"; from: 0.6; to: 1; step: 0.01; decimals: 2; tint: Atelier.sky
                                    value: Settings.windows.activeOpacity; onMoved: (v) => Settings.windows.activeOpacity = v }
                                SettingSlider { label: "Unfocused window opacity"; from: 0.5; to: 1; step: 0.01; decimals: 2; tint: Atelier.sky
                                    value: Settings.windows.inactiveOpacity; onMoved: (v) => Settings.windows.inactiveOpacity = v }
                                SettingSwitch { label: "Background blur"; tint: Atelier.sky
                                    checked: Settings.windows.blur; onToggled: (v) => Settings.windows.blur = v }
                                SettingSlider { label: "Blur quality"; description: "More passes look smoother but cost GPU"; from: 1; to: 4; step: 1; tint: Atelier.sky
                                    value: Settings.windows.blurPasses; onMoved: (v) => Settings.windows.blurPasses = v }
                                SettingSwitch { label: "Window shadows"; tint: Atelier.sky
                                    checked: Settings.windows.shadow; onToggled: (v) => Settings.windows.shadow = v }
                            }

                            SettingCard {
                                title: "Motion"; icon: "󰓅"; tint: Atelier.green
                                SettingSwitch { label: "Window animations"; description: "Opening, closing, moving and workspace switches"; tint: Atelier.green
                                    checked: Settings.windows.animations; onToggled: (v) => Settings.windows.animations = v }
                                SettingSlider { label: "Shell animation speed"; description: "Drawers, pop-ups and the bar. 1.0 is the default; higher is faster"; from: 0.5; to: 2; step: 0.1; decimals: 1; suffix: "×"
                                    value: Settings.general.animSpeed; onMoved: (v) => Settings.general.animSpeed = v }
                            }
                        }

                        // ═════════ Notifications ═════════
                        ColumnLayout {
                            visible: win.page === "notifications"
                            Layout.fillWidth: true
                            spacing: 20

                            SettingCard {
                                title: "Notifications"; icon: "󰂚"; tint: Atelier.yellow
                                SettingSwitch { label: "Do Not Disturb"; description: "Notifications still arrive in the control center, without pop-ups"; tint: Atelier.yellow
                                    checked: Notifs.dnd; onToggled: (v) => Notifs.dnd = v }
                                SettingSlider { label: "Pop-up duration"; description: "Apps can ask for longer; critical ones stay"; from: 2; to: 15; step: 1; suffix: " s"; tint: Atelier.yellow
                                    value: Settings.notifications.popupSeconds; onMoved: (v) => Settings.notifications.popupSeconds = v }
                                SettingSlider { label: "Pop-ups at once"; from: 1; to: 8; step: 1; tint: Atelier.yellow
                                    value: Settings.notifications.maxPopups; onMoved: (v) => Settings.notifications.maxPopups = v }
                            }

                            SettingCard {
                                title: "Pop-up look"; icon: "󰍡"; tint: Atelier.yellow
                                SettingChoice { label: "Position"; description: "Where pop-ups appear; they slide in from that side"; tint: Atelier.yellow
                                    options: [{ id: "top-left", label: "Top left" }, { id: "top-center", label: "Top" }, { id: "top-right", label: "Top right" },
                                              { id: "bottom-left", label: "Bottom left" }, { id: "bottom-right", label: "Bottom right" }]
                                    value: Settings.notifications.position; onPicked: (id) => Settings.notifications.position = id }
                                SettingSlider { label: "Width"; from: 320; to: 440; step: 10; suffix: " px"; tint: Atelier.yellow
                                    value: Settings.notifications.popupWidth; onMoved: (v) => Settings.notifications.popupWidth = Math.round(v) }
                                SettingSwitch { label: "Group by chat"; description: "Messages from the same app and sender become one card with +N; click it to see them all"; tint: Atelier.yellow
                                    checked: Settings.notifications.stack; onToggled: (v) => Settings.notifications.stack = v }
                                SettingSwitch { label: "Show message text"; description: "Off: only who it's from (handy when sharing your screen)"; tint: Atelier.yellow
                                    checked: Settings.notifications.showBody; onToggled: (v) => Settings.notifications.showBody = v }
                                SettingSwitch { label: "Show the app line"; description: "\"WhatsApp · iPhone\" under each message"; tint: Atelier.yellow
                                    checked: Settings.notifications.showSource; onToggled: (v) => Settings.notifications.showSource = v }
                                SettingRow {
                                    label: "Try it"
                                    description: Notifs.dnd ? "Do Not Disturb is on, so it only shows up in the control center" : "Sends a sample notification"
                                    RowLayout {
                                        spacing: 6
                                        Chip { icon: "󰂚"; text: "Send one"; tint: Atelier.accent; interactive: true; implicitHeight: 30
                                            onClicked: Quickshell.execDetached(["notify-send", "-a", "Atelier", "-i", "preferences-system-notifications", "This is a notification", "Pop-ups look like this, for " + Settings.notifications.popupSeconds + " seconds."]) }
                                        Chip { icon: "󰂞"; text: "Send all kinds"; tint: Atelier.accent; interactive: true; implicitHeight: 30
                                            onClicked: Quickshell.execDetached([Quickshell.shellDir + "/scripts/notify-test.sh"]) }
                                    }
                                }
                            }
                        }

                        // ═════════ Display & power ═════════
                        ColumnLayout {
                            visible: win.page === "display"
                            Layout.fillWidth: true
                            spacing: 20

                            SettingCard {
                                title: "Night light"; icon: "󰖔"; tint: Atelier.peach
                                SettingSwitch { label: "Night light"; description: NightLight.available ? "Warmer colours, easier on the eyes at night (Super+Shift+N)" : "Needs hyprsunset: sudo pacman -S hyprsunset"; tint: Atelier.peach
                                    checked: NightLight.active; onToggled: (v) => NightLight.set(v) }
                                SettingSlider { label: "Warmth"; description: "Lower is warmer"; from: 2500; to: 6000; step: 100; suffix: " K"; tint: Atelier.peach
                                    value: Settings.nightLight.temperature; onMoved: (v) => Settings.nightLight.temperature = Math.round(v) }
                                SettingSwitch { label: "On a schedule"; description: "Turns on and off by itself at the times below"; tint: Atelier.peach
                                    checked: Settings.nightLight.schedule; onToggled: (v) => Settings.nightLight.schedule = v }
                                SettingField { visible: Settings.nightLight.schedule; label: "From"; description: "24-hour time, e.g. 20:00"; placeholder: "20:00"; fieldWidth: 90
                                    text: Settings.nightLight.from; onCommitted: (t) => { if (/^\d{1,2}:\d{2}$/.test(t.trim())) Settings.nightLight.from = t.trim(); } }
                                SettingField { visible: Settings.nightLight.schedule; label: "To"; description: "24-hour time, e.g. 07:00"; placeholder: "07:00"; fieldWidth: 90
                                    text: Settings.nightLight.to; onCommitted: (t) => { if (/^\d{1,2}:\d{2}$/.test(t.trim())) Settings.nightLight.to = t.trim(); } }
                            }

                            SettingCard {
                                title: "On-screen display"; icon: "󰕾"; tint: Atelier.accent
                                SettingSlider { label: "Volume/brightness display time"; from: 0.5; to: 4; step: 0.1; decimals: 1; suffix: " s"; tint: Atelier.accent
                                    value: Settings.behavior.osdSeconds; onMoved: (v) => Settings.behavior.osdSeconds = v }
                            }

                            SettingCard {
                                title: "Keep awake"; icon: "󰅶"; tint: Atelier.peach
                                SettingSwitch { label: "Caffeine"; description: "Keep the screen awake"; tint: Atelier.peach
                                    checked: Atelier.caffeine; onToggled: (v) => Atelier.caffeine = v }
                            }

                            SettingCard {
                                title: "Idle & sleep"; icon: "󰒲"; tint: Atelier.lavender
                                SettingSlider { label: "Dim the screen after"; from: 0; to: 300; step: 15; suffix: " s"; zeroText: "Never"; tint: Atelier.lavender
                                    value: Settings.idle.dimAfter; onMoved: (v) => Settings.idle.dimAfter = Math.round(v) }
                                SettingSlider { label: "Lock after"; from: 0; to: 30; step: 1; suffix: " min"; zeroText: "Never"; tint: Atelier.lavender
                                    value: Settings.idle.lockAfter / 60; onMoved: (v) => Settings.idle.lockAfter = Math.round(v) * 60 }
                                SettingSlider { label: "Turn the screen off after"; from: 0; to: 60; step: 1; suffix: " min"; zeroText: "Never"; tint: Atelier.lavender
                                    value: Settings.idle.screenOffAfter / 60; onMoved: (v) => Settings.idle.screenOffAfter = Math.round(v) * 60 }
                                SettingSlider { label: "Sleep after"; from: 0; to: 120; step: 5; suffix: " min"; zeroText: "Never"; tint: Atelier.lavender
                                    value: Settings.idle.suspendAfter / 60; onMoved: (v) => Settings.idle.suspendAfter = Math.round(v) * 60 }
                                SettingSwitch { label: "Sleep while charging too"; description: "Off: plugged in, it only locks and turns the screen off (downloads and builds keep going)"; tint: Atelier.lavender
                                    checked: Settings.idle.suspendOnAC; onToggled: (v) => Settings.idle.suspendOnAC = v }
                            }

                            SettingCard {
                                title: "Battery"; icon: "󰂃"; tint: Atelier.yellow
                                SettingSwitch { label: "Low battery alerts"; description: "A notification when it runs low; the critical one stays up and gets through Do Not Disturb"; tint: Atelier.yellow
                                    checked: Settings.battery.alerts; onToggled: (v) => Settings.battery.alerts = v }
                                SettingSlider { visible: Settings.battery.alerts; label: "Low at"; from: 10; to: 40; step: 5; suffix: "%"; tint: Atelier.yellow
                                    value: Settings.battery.low; onMoved: (v) => Settings.battery.low = Math.round(v) }
                                SettingSlider { visible: Settings.battery.alerts; label: "Critical at"; from: 3; to: 15; step: 1; suffix: "%"; tint: Atelier.yellow
                                    value: Settings.battery.critical; onMoved: (v) => Settings.battery.critical = Math.round(v) }
                                SettingSwitch { label: "Charger toast"; description: "\"Charging · 64%\" when you plug in or unplug"; tint: Atelier.yellow
                                    checked: Settings.battery.chargerToast; onToggled: (v) => Settings.battery.chargerToast = v }
                            }

                            SettingCard {
                                title: "Performance modes"; icon: "󰊗"; tint: Atelier.sapphire
                                SettingChoice { label: "Mode"; tint: Atelier.sapphire
                                    options: [{ id: "normal", label: "Normal" }, { id: "dev", label: "Programming" }, { id: "game", label: "Game" }]
                                    value: Perf.mode; onPicked: (id) => Perf.set(id) }
                                SettingRow {
                                    label: "Customise modes"
                                    description: "Choose what Programming and Game mode change"
                                    Chip { icon: "󰒓"; text: "Modes"; tint: Atelier.sapphire; interactive: true; implicitHeight: 30
                                        onClicked: win.page = "modes" }
                                }
                            }
                        }

                        // ═════════ Modes ═════════
                        ColumnLayout {
                            id: modesPage
                            visible: win.page === "modes"
                            Layout.fillWidth: true
                            spacing: 20

                            readonly property var blurOpts: [{ id: "off", label: "Off" }, { id: "light", label: "Light" }, { id: "normal", label: "Your usual" }]
                            readonly property var powerOpts: [{ id: "performance", label: "Performance" }, { id: "balanced", label: "Balanced" },
                                                              { id: "power-saver", label: "Power saver" }, { id: "unchanged", label: "Don't change" }]
                            // must match the defaults in config/Settings.qml (modes)
                            readonly property var defaults: ({
                                dev:  { Opaque: true, Dim: false, Blur: "light", Shadows: true, Animations: true, AnimSpeed: 0.6,
                                        Power: "performance", Caffeine: true, Dnd: false },
                                game: { Opaque: true, Blur: "off", Shadows: false, Animations: false, Tearing: true,
                                        Power: "performance", Caffeine: true, Dnd: true, HideWidgets: true, LeanShell: true }
                            })
                            function reset(m) { const d = defaults[m]; for (const k in d) Settings.modes[m + k] = d[k]; }
                            function isDefault(m) { const d = defaults[m]; for (const k in d) if (Settings.modes[m + k] !== d[k]) return false; return true; }

                            SettingCard {
                                title: "Mode now"; icon: "󰊗"; tint: Atelier.sapphire
                                SettingChoice { label: "Mode"; tint: Atelier.sapphire
                                    description: "Normal is your own look from the Windows page"
                                    options: [{ id: "normal", label: "Normal" }, { id: "dev", label: "Programming" }, { id: "game", label: "Game" }]
                                    value: Perf.mode; onPicked: (id) => Perf.set(id) }
                            }

                            SettingCard {
                                title: "Programming mode"; icon: "󰅩"; tint: Atelier.teal
                                SettingSwitch { label: "Opaque windows"; description: "Crisp text, nothing blurred behind windows"; tint: Atelier.teal
                                    checked: Settings.modes.devOpaque; onToggled: (v) => Settings.modes.devOpaque = v }
                                SettingSwitch { label: "Dim unfocused windows"; tint: Atelier.teal
                                    checked: Settings.modes.devDim; onToggled: (v) => Settings.modes.devDim = v }
                                SettingChoice { label: "Blur"; description: "Light = one pass, cheaper"; tint: Atelier.teal
                                    options: modesPage.blurOpts; value: Settings.modes.devBlur; onPicked: (id) => Settings.modes.devBlur = id }
                                SettingSwitch { label: "Window shadows"; tint: Atelier.teal
                                    checked: Settings.modes.devShadows; onToggled: (v) => Settings.modes.devShadows = v }
                                SettingSwitch { label: "Animations"; tint: Atelier.teal
                                    checked: Settings.modes.devAnimations; onToggled: (v) => Settings.modes.devAnimations = v }
                                SettingSlider { visible: Settings.modes.devAnimations; label: "Animation length"; description: "100% = like Normal mode; smaller is snappier"
                                    from: 30; to: 100; step: 5; decimals: 0; suffix: "%"; tint: Atelier.teal
                                    value: Settings.modes.devAnimSpeed * 100; onMoved: (v) => Settings.modes.devAnimSpeed = v / 100 }
                                SettingChoice { label: "Power profile"; description: "Performance drops to Balanced on battery"; tint: Atelier.teal
                                    options: modesPage.powerOpts; value: Settings.modes.devPower; onPicked: (id) => Settings.modes.devPower = id }
                                SettingSwitch { label: "Keep the screen awake"; tint: Atelier.teal
                                    checked: Settings.modes.devCaffeine; onToggled: (v) => Settings.modes.devCaffeine = v }
                                SettingSwitch { label: "Do Not Disturb"; description: "Silence notification pop-ups"; tint: Atelier.teal
                                    checked: Settings.modes.devDnd; onToggled: (v) => Settings.modes.devDnd = v }
                                SettingRow {
                                    visible: !modesPage.isDefault("dev")
                                    label: "Back to the defaults"
                                    Chip { icon: "󰑓"; text: "Reset"; tint: Atelier.teal; interactive: true; implicitHeight: 30; onClicked: modesPage.reset("dev") }
                                }
                            }

                            SettingCard {
                                title: "Game mode"; icon: "󰊴"; tint: Atelier.red
                                SettingSwitch { label: "Opaque windows"; tint: Atelier.red
                                    checked: Settings.modes.gameOpaque; onToggled: (v) => Settings.modes.gameOpaque = v }
                                SettingChoice { label: "Blur"; tint: Atelier.red
                                    options: modesPage.blurOpts; value: Settings.modes.gameBlur; onPicked: (id) => Settings.modes.gameBlur = id }
                                SettingSwitch { label: "Window shadows"; tint: Atelier.red
                                    checked: Settings.modes.gameShadows; onToggled: (v) => Settings.modes.gameShadows = v }
                                SettingSwitch { label: "Animations"; tint: Atelier.red
                                    checked: Settings.modes.gameAnimations; onToggled: (v) => Settings.modes.gameAnimations = v }
                                SettingSwitch { label: "Allow tearing"; description: "Lowest latency for fullscreen games"; tint: Atelier.red
                                    checked: Settings.modes.gameTearing; onToggled: (v) => Settings.modes.gameTearing = v }
                                SettingChoice { label: "Power profile"; tint: Atelier.red
                                    options: modesPage.powerOpts; value: Settings.modes.gamePower; onPicked: (id) => Settings.modes.gamePower = id }
                                SettingSwitch { label: "Keep the screen awake"; tint: Atelier.red
                                    checked: Settings.modes.gameCaffeine; onToggled: (v) => Settings.modes.gameCaffeine = v }
                                SettingSwitch { label: "Do Not Disturb"; tint: Atelier.red
                                    checked: Settings.modes.gameDnd; onToggled: (v) => Settings.modes.gameDnd = v }
                                SettingSwitch { label: "Hide the desktop widget"; tint: Atelier.red
                                    checked: Settings.modes.gameHideWidgets; onToggled: (v) => Settings.modes.gameHideWidgets = v }
                                SettingSwitch { label: "Lighter shell"; description: "No shadows on the bar and drawers, solid instead of glass"; tint: Atelier.red
                                    checked: Settings.modes.gameLeanShell; onToggled: (v) => Settings.modes.gameLeanShell = v }
                                SettingRow {
                                    visible: !modesPage.isDefault("game")
                                    label: "Back to the defaults"
                                    Chip { icon: "󰑓"; text: "Reset"; tint: Atelier.red; interactive: true; implicitHeight: 30; onClicked: modesPage.reset("game") }
                                }
                            }

                            SettingCard {
                                title: "Game mode automatically"; icon: "󰐊"; tint: Atelier.peach
                                SettingSwitch { label: "Switch on for games"; description: "On when a game (Steam, gamescope, Lutris, Heroic…) is focused, back off when it closes"; tint: Atelier.peach
                                    checked: Settings.behavior.autoGameMode; onToggled: (v) => Settings.behavior.autoGameMode = v }
                                SettingField { visible: Settings.behavior.autoGameMode; label: "Also counts as a game"
                                    description: "Window classes, comma-separated (hyprctl activewindow shows a window's class)"
                                    placeholder: "e.g. osu!, retroarch"; fieldWidth: 220
                                    text: Settings.modes.gameApps; onCommitted: (t) => Settings.modes.gameApps = t.trim() }
                            }
                        }

                        // ═════════ Lock screen ═════════
                        ColumnLayout {
                            visible: win.page === "lock"
                            Layout.fillWidth: true
                            spacing: 20

                            SettingCard {
                                title: "Lock screen"; icon: "󰌾"; tint: Atelier.mauve
                                SettingRow {
                                    label: "In use"
                                    description: {
                                        const own = lockPage.ownStyles.find(x => x.id === Settings.lock.theme);
                                        return own ? own.name + " · " + own.note : lockPage.nameOf(Settings.lock.theme) + " (a qylock theme from GitHub)";
                                    }
                                    Chip { icon: "󰌾"; text: "Lock now"; tint: Atelier.mauve; interactive: true; implicitHeight: 30
                                        onClicked: Quickshell.execDetached(["qs", "ipc", "call", "lock", "lock"]) }
                                }
                                SettingSwitch { label: "Show notifications"; description: "App name and title only, never the message text"
                                    checked: Settings.notifications.lockShowCount; onToggled: (v) => Settings.notifications.lockShowCount = v }
                            }

                            SettingCard {
                                visible: Settings.lock.theme === "depth"
                                title: "Depth"; icon: "󰗆"; tint: Atelier.sky
                                SettingRow {
                                    label: DepthWall.settingUp ? (DepthWall.setupStep === "model"
                                            ? "Installing the model…"
                                            : "Setting up…")
                                        : !DepthWall.installed ? "Needs a one-time setup"
                                        : DepthWall.busy ? "Finding the subject…"
                                        : DepthWall.ok ? "Ready for this wallpaper"
                                        : "No depth on this wallpaper"
                                    description: !DepthWall.installed && !DepthWall.settingUp
                                        ? "Installs the subject-finding model (about 170 MB) shared with the Outline wallpaper transition. No sudo."
                                        : DepthWall.error && !DepthWall.ok && DepthWall.installed
                                        ? (DepthWall.error === "no clear subject in this wallpaper"
                                            ? "No clear subject was found, so the clock sits in front. Pictures with one main subject (a person, animal, building, tree) work best."
                                            : DepthWall.error)
                                        : "The clock goes behind your wallpaper's subject. Each wallpaper is processed once in the background (a few seconds) and cached."
                                    RowLayout {
                                        spacing: 6
                                        Chip { visible: !DepthWall.installed; icon: DepthWall.settingUp ? "󰑐" : "󰇚"; text: DepthWall.settingUp ? "…" : "Set up"
                                            tint: Atelier.sky; interactive: !DepthWall.settingUp; implicitHeight: 30
                                            onClicked: DepthWall.setup() }
                                        Chip { icon: "󰈈"; text: "Preview"; tint: Atelier.mauve; interactive: true; implicitHeight: 30
                                            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "lock", "preview"]) }
                                        Chip { icon: "󰏫"; text: "Customise"; tint: Atelier.accent; interactive: true; implicitHeight: 30
                                            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "lock", "edit"]) }
                                    }
                                }
                                SettingSwitch { label: "Depth effect"; description: "Tuck the clock behind your wallpaper's subject. Off: a plain big clock on top"; tint: Atelier.sky
                                    checked: Settings.lock.depthEffect; onToggled: (v) => Settings.lock.depthEffect = v }
                                SettingChoice { label: "Style"; description: "Glass shows the wallpaper, frosted, through the digits"; tint: Atelier.sky
                                    options: [{ id: "solid", label: "Solid" }, { id: "glass", label: "Glass" }]
                                    value: Settings.lock.depthStyle; onPicked: (id) => Settings.lock.depthStyle = id }
                                SettingRow {
                                    label: "Colour"
                                    description: Settings.lock.depthColor === "auto" ? "Auto: picked from your wallpaper (deep on a bright sky, pale on a dark one)"
                                        : Settings.lock.depthColor.startsWith("#") ? "Custom " + Settings.lock.depthColor
                                        : "The clock, date and glass tint use this colour"
                                    Row {
                                        spacing: 6
                                        Repeater {
                                            model: [
                                                { id: "auto",     c: Atelier.subtext },
                                                { id: "theme",    c: Atelier.text },
                                                { id: "white",    c: "#ffffff" },
                                                { id: "black",    c: "#161616" },
                                                { id: "accent",   c: Atelier.accent },
                                                { id: "pink",     c: Atelier.pink },
                                                { id: "peach",    c: Atelier.peach },
                                                { id: "yellow",   c: Atelier.yellow },
                                                { id: "green",    c: Atelier.green },
                                                { id: "sky",      c: Atelier.sky },
                                                { id: "lavender", c: Atelier.lavender }
                                            ]
                                            Rectangle {
                                                required property var modelData
                                                readonly property bool on: Settings.lock.depthColor === modelData.id
                                                width: 24; height: 24; radius: 12
                                                color: modelData.id === "auto" ? "transparent" : modelData.c
                                                border.width: on ? 2 : 1
                                                border.color: on ? Atelier.accent : Atelier.outline
                                                // auto: a split wallpaper-ish swatch
                                                Text { anchors.centerIn: parent; visible: parent.modelData.id === "auto"; text: "󰍉"
                                                    font.family: Atelier.font; font.pixelSize: 13; color: Atelier.text }
                                                Text { anchors.centerIn: parent; visible: parent.on && parent.modelData.id !== "auto"; text: "󰄬"
                                                    font.family: Atelier.font; font.pixelSize: 12
                                                    color: (0.2126 * parent.color.r + 0.7152 * parent.color.g + 0.0722 * parent.color.b) > 0.5 ? "#161616" : "#ffffff" }
                                                scale: swMa.containsMouse ? 1.15 : 1
                                                Behavior on scale { NumberAnimation { duration: 140 } }
                                                MouseArea { id: swMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: Settings.lock.depthColor = parent.modelData.id }
                                            }
                                        }
                                    }
                                }
                                SettingField { label: "Custom colour"; description: "Any hex colour, e.g. #f5c2e7. Empty goes back to Auto"; placeholder: "#rrggbb"
                                    text: Settings.lock.depthColor.startsWith("#") ? Settings.lock.depthColor : ""
                                    onCommitted: (t) => {
                                        const v = t.trim();
                                        if (!v) Settings.lock.depthColor = "auto";
                                        else if (/^#?[0-9a-fA-F]{6}$/.test(v)) Settings.lock.depthColor = v.startsWith("#") ? v : "#" + v;
                                    } }
                                SettingChoice { label: "Clock"; tint: Atelier.sky
                                    options: [{ id: "horizontal", label: "12:45" }, { id: "stacked", label: "Stacked" }]
                                    value: Settings.lock.depthLayout; onPicked: (id) => Settings.lock.depthLayout = id }
                                SettingChoice { label: "Font"; tint: Atelier.sky
                                    options: [{ id: "display", label: "Display" }, { id: "mono", label: "Mono" }, { id: "serif", label: "Serif" }]
                                    value: Settings.lock.depthFont; onPicked: (id) => Settings.lock.depthFont = id }
                                SettingChoice { label: "Weight"; tint: Atelier.sky
                                    options: [{ id: "light", label: "Light" }, { id: "regular", label: "Regular" }, { id: "bold", label: "Bold" }, { id: "black", label: "Black" }]
                                    value: Settings.lock.depthWeight; onPicked: (id) => Settings.lock.depthWeight = id }
                                SettingSlider { label: "Clock size"; from: 0.12; to: 0.34; step: 0.01; decimals: 2; tint: Atelier.sky
                                    value: Settings.lock.depthClockSize; onMoved: (v) => Settings.lock.depthClockSize = v }
                                SettingSwitch { label: "Soft shadow"; description: "Helps the clock read on bright pictures"; tint: Atelier.sky
                                    checked: Settings.lock.depthShadow; onToggled: (v) => Settings.lock.depthShadow = v }
                            }

                            // the phone-inspired style in use: its own options (config/Settings.qml lockStyle)
                            SettingCard {
                                id: styleCard
                                readonly property string sid: Settings.lock.theme
                                readonly property var info: lockPage.ownStyles.find(x => x.id === sid) || ({ name: "", note: "" })
                                visible: lockPage.phoneIds.indexOf(sid) >= 0
                                title: info.name + " options"; icon: "󰏘"; tint: Atelier.mauve
                                SettingRow {
                                    label: styleCard.info.note
                                    description: "Changes show on your next lock; Preview to see them now"
                                    RowLayout {
                                        spacing: 6
                                        Chip { icon: "󰈈"; text: "Preview"; tint: Atelier.mauve; interactive: true; implicitHeight: 30
                                            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "lock", "previewStyle", Settings.lock.theme]) }
                                        Chip { icon: "󰌾"; text: "Lock now"; tint: Atelier.accent; interactive: true; implicitHeight: 30
                                            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "lock", "lock"]) }
                                    }
                                }
                                SettingSlider { label: "Size"; description: "The clock, text and widgets; smaller shows more of your wallpaper"
                                    from: 0.5; to: 1.1; step: 0.02; decimals: 2; suffix: "×"
                                    value: Settings.lockStyle.size; onMoved: (v) => Settings.lockStyle.size = Math.round(v * 100) / 100 }
                                // Cupertino
                                SettingChoice { visible: styleCard.sid === "cupertino"; label: "Clock weight"
                                    options: [{ id: "regular", label: "Regular" }, { id: "bold", label: "Bold" }, { id: "heavy", label: "Heavy" }]
                                    value: Settings.lockStyle.cupertinoWeight; onPicked: (id) => Settings.lockStyle.cupertinoWeight = id }
                                SettingChoice { visible: styleCard.sid === "cupertino"; label: "Clock colour"
                                    options: [{ id: "white", label: "White" }, { id: "soft", label: "Soft" }, { id: "accent", label: "Accent" }]
                                    value: Settings.lockStyle.cupertinoTint; onPicked: (id) => Settings.lockStyle.cupertinoTint = id }
                                SettingSwitch { visible: styleCard.sid === "cupertino"; label: "Gauges"; description: "Round battery, weather, date and notification gauges under the clock"
                                    checked: Settings.lockStyle.cupertinoWidgets; onToggled: (v) => Settings.lockStyle.cupertinoWidgets = v }
                                SettingChoice { visible: styleCard.sid === "cupertino"; label: "Notifications"; description: "Pile: the newest on top of a stack"
                                    options: [{ id: "pile", label: "Pile" }, { id: "list", label: "List" }, { id: "count", label: "Count" }]
                                    value: Settings.lockStyle.cupertinoNotifs; onPicked: (id) => Settings.lockStyle.cupertinoNotifs = id }
                                // Hyper
                                SettingChoice { visible: styleCard.sid === "hyper"; label: "Clock gradient"
                                    options: [{ id: "accent", label: "Accent" }, { id: "sunset", label: "Sunset" }, { id: "ocean", label: "Ocean" }, { id: "mono", label: "Mono" }]
                                    value: Settings.lockStyle.hyperGradient; onPicked: (id) => Settings.lockStyle.hyperGradient = id }
                                SettingChoice { visible: styleCard.sid === "hyper"; label: "Clock weight"
                                    options: [{ id: "thin", label: "Thin" }, { id: "regular", label: "Regular" }, { id: "bold", label: "Bold" }]
                                    value: Settings.lockStyle.hyperWeight; onPicked: (id) => Settings.lockStyle.hyperWeight = id }
                                SettingSwitch { visible: styleCard.sid === "hyper"; label: "Cards"; description: "Weather, battery, notifications and media on the right"
                                    checked: Settings.lockStyle.hyperCards; onToggled: (v) => Settings.lockStyle.hyperCards = v }
                                // Harmony
                                SettingSwitch { visible: styleCard.sid === "harmony"; label: "Month calendar"; description: "This month on the right, today ringed"
                                    checked: Settings.lockStyle.harmonyCalendar; onToggled: (v) => Settings.lockStyle.harmonyCalendar = v }
                                SettingChoice { visible: styleCard.sid === "harmony" && Settings.lockStyle.harmonyCalendar; label: "Week starts on"
                                    options: [{ id: "mon", label: "Monday" }, { id: "sun", label: "Sunday" }]
                                    value: Settings.lockStyle.harmonyWeekStart; onPicked: (id) => Settings.lockStyle.harmonyWeekStart = id }
                                SettingSwitch { visible: styleCard.sid === "harmony"; label: "Coloured day"; description: "The big day number in your accent colour"
                                    checked: Settings.lockStyle.harmonyAccent; onToggled: (v) => Settings.lockStyle.harmonyAccent = v }
                                // Oxygen
                                SettingChoice { visible: styleCard.sid === "oxygen"; label: "Shelf"
                                    options: [{ id: "bottom", label: "Bottom" }, { id: "top", label: "Top" }]
                                    value: Settings.lockStyle.oxygenShelf; onPicked: (id) => Settings.lockStyle.oxygenShelf = id }
                                SettingChoice { visible: styleCard.sid === "oxygen"; label: "Accent"
                                    options: [{ id: "red", label: "Red" }, { id: "theme", label: "Theme" }]
                                    value: Settings.lockStyle.oxygenAccent; onPicked: (id) => Settings.lockStyle.oxygenAccent = id }
                                SettingSwitch { visible: styleCard.sid === "oxygen"; label: "Seconds"
                                    checked: Settings.lockStyle.oxygenSeconds; onToggled: (v) => Settings.lockStyle.oxygenSeconds = v }
                                // Material
                                SettingChoice { visible: styleCard.sid === "material"; label: "Clock tiles"
                                    options: [{ id: "grid", label: "2 × 2" }, { id: "line", label: "In a line" }]
                                    value: Settings.lockStyle.materialLayout; onPicked: (id) => Settings.lockStyle.materialLayout = id }
                                SettingSwitch { visible: styleCard.sid === "material"; label: "Make room for notifications"; description: "Smaller tiles while there are notifications"
                                    checked: Settings.lockStyle.materialShrink; onToggled: (v) => Settings.lockStyle.materialShrink = v }
                                // Dot
                                SettingChoice { visible: styleCard.sid === "dot"; label: "Dots"
                                    options: [{ id: "white", label: "White" }, { id: "red", label: "Red" }, { id: "theme", label: "Theme" }]
                                    value: Settings.lockStyle.dotColor; onPicked: (id) => Settings.lockStyle.dotColor = id }
                                SettingSwitch { visible: styleCard.sid === "dot"; label: "Seconds bar"; description: "60 dots under the clock, filling up each minute"
                                    checked: Settings.lockStyle.dotSeconds; onToggled: (v) => Settings.lockStyle.dotSeconds = v }
                                SettingChoice { visible: styleCard.sid === "dot"; label: "Background"
                                    options: [{ id: "mono", label: "Wallpaper, black & white" }, { id: "black", label: "Black" }]
                                    value: Settings.lockStyle.dotBackground; onPicked: (id) => Settings.lockStyle.dotBackground = id }
                            }

                            Item {
                                id: lockPage
                                Layout.fillWidth: true
                                implicitHeight: gallery.implicitHeight
                                readonly property string script: Quickshell.shellDir + "/scripts/qylock.py"
                                property var themes: []
                                property string busy: ""            // theme id being downloaded
                                readonly property bool shown: win.visible && win.page === "lock"
                                onShownChanged: if (shown) refresh()

                                readonly property var ownStyles: [
                                    { id: "atelier",   name: "Atelier",   note: "Glass panel, this shell's own" },
                                    { id: "depth",     name: "Depth",     note: "Clock behind the subject, Samsung-style" },
                                    { id: "cupertino", name: "Cupertino", note: "iOS-style" },
                                    { id: "hyper",     name: "Hyper",     note: "Xiaomi HyperOS-style" },
                                    { id: "harmony",   name: "Harmony",   note: "Huawei HarmonyOS-style" },
                                    { id: "oxygen",    name: "Oxygen",    note: "OnePlus OxygenOS-style" },
                                    { id: "material",  name: "Material",  note: "Pixel, Material You-style" },
                                    { id: "dot",       name: "Dot",       note: "Nothing OS-style" }
                                ].map(x => Object.assign({ builtin: true, downloaded: true, preview: "", sizeMB: 0 }, x))
                                readonly property var phoneIds: ["cupertino", "hyper", "harmony", "oxygen", "material", "dot"]
                                // what the live miniatures read instead of the real lock (never locks anything)
                                QtObject {
                                    id: lockStub
                                    property bool active: false
                                    property bool authMode: false
                                    property bool unlocking: false
                                    property bool checking: false
                                    property bool previewing: false
                                    property string buffer: ""
                                    property string message: ""
                                    property string weather: ""
                                }

                                function nameOf(id) { const t = themes.find(x => x.id === id); return t ? t.name : id; }
                                function refresh() { listProc.running = true; }
                                function fetchThen(t, then) {
                                    busy = t.id;
                                    fetchProc.target = t.id;
                                    fetchProc.then = then;
                                    fetchProc.command = [script, "fetch", t.id];
                                    fetchProc.running = true;
                                }
                                function use(t) {
                                    if (t.builtin || t.downloaded) Settings.lock.theme = t.id;
                                    else fetchThen(t, "use");
                                }
                                function preview(t) {
                                    if (t.builtin) Quickshell.execDetached(["qs", "ipc", "call", "lock", "previewStyle", t.id]);
                                    else if (t.downloaded) Quickshell.execDetached([script, "preview", t.id]);
                                    else fetchThen(t, "preview");
                                }

                                Process {
                                    id: listProc
                                    command: [lockPage.script, "list"]
                                    stdout: StdioCollector {
                                        onStreamFinished: { try { const d = JSON.parse(text); if (Array.isArray(d)) lockPage.themes = d; } catch (e) {} }
                                    }
                                }
                                Process {
                                    id: fetchProc
                                    property string target: ""
                                    property string then: ""
                                    onExited: (code) => {
                                        lockPage.busy = "";
                                        if (code === 0) {
                                            if (then === "use") Settings.lock.theme = target;
                                            else if (then === "preview") Quickshell.execDetached([lockPage.script, "preview", target]);
                                        }
                                        lockPage.refresh();
                                    }
                                }

                                Column {
                                    id: gallery
                                    width: parent.width
                                    spacing: 14

                                    // ── ours: built into the shell ──
                                    GalleryHead {
                                        title: "Atelier styles"
                                        sub: "Built into the shell: instant, on your wallpaper, nothing to download. The phone-inspired ones echo each phone's clock and layout, made for a laptop: a keyboard login, Wi-Fi and battery top right."
                                    }
                                    Flow {
                                        width: parent.width
                                        spacing: 12
                                        Repeater { model: lockPage.ownStyles; delegate: LockThemeCard {} }
                                    }

                                    // ── from the qylock repo on GitHub ──
                                    Item { width: 1; height: 10 }
                                    GalleryHead {
                                        title: "From GitHub · qylock"
                                        sub: "Lock screens by Darkkal44 (GPL-3.0). Hover a card to play its preview; a theme downloads the first time you preview or use it. If one ever fails, the Atelier lock takes over."
                                        Chip { icon: "󰊤"; text: "GitHub"; tint: Atelier.subtext; interactive: true; implicitHeight: 30
                                            onClicked: Quickshell.execDetached(["xdg-open", "https://github.com/Darkkal44/qylock"]) }
                                    }
                                    Flow {
                                        width: parent.width
                                        spacing: 12
                                        Repeater { model: lockPage.themes; delegate: LockThemeCard {} }
                                    }
                                    Text {
                                        visible: lockPage.themes.length === 0
                                        text: "Loading the list…"
                                        font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.subtext
                                    }
                                }
                            }
                        }

                        // ═════════ Login screen (greetd greeter) ═════════
                        ColumnLayout {
                            id: loginPage
                            visible: win.page === "login"
                            Layout.fillWidth: true
                            spacing: 20
                            readonly property bool shown: win.visible && win.page === "login"
                            onShownChanged: if (shown) Greeter.refresh()
                            Timer { interval: 3000; repeat: true; running: loginPage.shown; onTriggered: Greeter.refresh() }
                            readonly property bool on: Greeter.writable

                            SettingCard {
                                title: "Login screen"; icon: "󰍂"; tint: Atelier.pink
                                SettingRow {
                                    label: !Greeter.installed ? "Not installed"
                                        : Greeter.active ? "In use" : "Installed, not the login manager yet"
                                    description: !Greeter.installed ? "Installs greetd + cage and the Atelier greeter. Your current login manager stays until you switch."
                                        : Greeter.active ? "greetd shows the Atelier login screen at boot (it looks like your lock screen)."
                                        : "SDDM (or another manager) is still active. Switch when the preview looks right (password in the preview: demo)."
                                    RowLayout {
                                        spacing: 6
                                        Chip { icon: "󰈈"; text: "Preview"; tint: Atelier.pink; interactive: true; implicitHeight: 30
                                            onClicked: Greeter.preview() }
                                        Chip { visible: !Greeter.installed; icon: "󰏔"; text: "Install"; tint: Atelier.green; interactive: true; implicitHeight: 30
                                            onClicked: Greeter.runInstaller("") }
                                        Chip { visible: Greeter.installed && !Greeter.active; icon: "󰁔"; text: "Use at boot"; tint: Atelier.green; interactive: true; implicitHeight: 30
                                            onClicked: Greeter.runInstaller("--enable") }
                                    }
                                }
                                SettingRow {
                                    visible: Greeter.installed && (!Greeter.upToDate || !Greeter.writable)
                                    label: "Update needed"
                                    description: !Greeter.writable
                                        ? "Run the installer once so Settings can control the login screen (it hands /var/lib/atelier-greeter to you)."
                                        : "The installed greeter is older than the one in your dotfiles (new design, no window buttons, no text after login)."
                                    Chip { icon: "󰚰"; text: "Update"; tint: Atelier.peach; interactive: true; implicitHeight: 30
                                        onClicked: Greeter.runInstaller("--refresh") }
                                }
                            }

                            SettingCard {
                                title: "Layout"; icon: "󰕮"; tint: Atelier.mauve
                                enabled: loginPage.on; opacity: enabled ? 1 : 0.5
                                SettingChoice { label: "Style"; description: "Panel matches the lock screen; Minimal keeps only the centre column"; tint: Atelier.mauve
                                    options: [{ id: "panel", label: "Panel" }, { id: "minimal", label: "Minimal" }]
                                    value: Settings.greeter.layout; onPicked: (id) => Settings.greeter.layout = id }
                                SettingField { label: "Greeting"; description: "Empty = Good morning / afternoon / evening"; placeholder: "By time of day"
                                    text: Settings.greeter.greeting; onCommitted: (t) => Settings.greeter.greeting = t.trim() }
                                SettingSwitch { label: "Weather card"; description: "Place and units from Widgets"; tint: Atelier.sapphire
                                    checked: Settings.greeter.showWeather; onToggled: (v) => Settings.greeter.showWeather = v }
                                SettingSwitch { label: "System card"; description: "Computer name, battery, network"; tint: Atelier.green
                                    checked: Settings.greeter.showSystem; onToggled: (v) => Settings.greeter.showSystem = v }
                                SettingSwitch { label: "Sleep · restart · power buttons"; tint: Atelier.red
                                    checked: Settings.greeter.showPower; onToggled: (v) => Settings.greeter.showPower = v }
                            }

                            SettingCard {
                                title: "Background"; icon: "󰸉"; tint: Atelier.sky
                                enabled: loginPage.on; opacity: enabled ? 1 : 0.5
                                SettingSlider { label: "Wallpaper blur"; from: 0; to: 1; step: 0.05; decimals: 2; tint: Atelier.sky
                                    value: Settings.greeter.blur; onMoved: (v) => Settings.greeter.blur = v }
                                SettingSlider { label: "Dim"; from: 0; to: 0.8; step: 0.02; decimals: 2; tint: Atelier.sky
                                    value: Settings.greeter.dim; onMoved: (v) => Settings.greeter.dim = v }
                                SettingSwitch { label: "Follow theme & wallpaper"; description: "Copy your colours, wallpaper and ~/.face to the login screen whenever they change"; tint: Atelier.sky
                                    checked: Settings.greeter.autoSync; onToggled: (v) => { Settings.greeter.autoSync = v; if (v) Greeter.sync(); } }
                                SettingRow {
                                    label: "Sync now"
                                    description: Greeter.syncing ? "Copying…"
                                        : Greeter.syncedAt > 0 ? "Last synced " + Qt.formatDateTime(new Date(Greeter.syncedAt * 1000), "d MMM, hh:mm")
                                          + (Greeter.lastSyncResult ? "  ·  " + Greeter.lastSyncResult : "")
                                        : "Not synced yet"
                                    Chip { icon: "󰑐"; text: "Sync"; tint: Atelier.sky; interactive: !Greeter.syncing; implicitHeight: 30
                                        onClicked: Greeter.sync() }
                                }
                            }

                            SettingCard {
                                title: "Boot"; icon: "󰒓"; tint: Atelier.peach
                                SettingRow {
                                    label: "Quiet boot"
                                    description: Greeter.quietBoot ? "On: kernel and systemd messages are hidden at boot."
                                        : "Off: kernel messages can show on the login screen's console. Adds “quiet loglevel=3” to /etc/kernel/cmdline and rebuilds the boot image (takes effect next boot)."
                                    Chip { visible: !Greeter.quietBoot; icon: "󰒓"; text: "Turn on"; tint: Atelier.peach; interactive: true; implicitHeight: 30
                                        onClicked: Greeter.runInstaller("--quiet-boot") }
                                }
                                SettingRow {
                                    label: "Switch back to SDDM"
                                    description: "Removes the Atelier greeter. If a login ever fails: Ctrl+Alt+F3, sign in, run install-greeter.sh --uninstall."
                                    Chip { visible: Greeter.active; icon: "󰜺"; text: "Uninstall"; tint: Atelier.red; interactive: true; implicitHeight: 30
                                        onClicked: Greeter.runInstaller("--uninstall") }
                                }
                            }
                        }

                        // ═════════ Storage ═════════
                        ColumnLayout {
                            id: storage
                            visible: win.page === "storage"
                            Layout.fillWidth: true
                            spacing: 20

                            readonly property string script: Quickshell.shellDir + "/scripts/storage.py"
                            readonly property string foldersScript: Quickshell.shellDir + "/scripts/home-folders.sh"
                            property var d: ({})
                            property bool scanning: false
                            property var folders: []          // [{path, exists}]
                            property string confirm: ""       // cleanup id waiting for a second click
                            readonly property bool shown: win.visible && win.page === "storage"
                            readonly property var cats: d.categories || []
                            readonly property real used: d.used || 0
                            readonly property real total: d.total || 1
                            readonly property real counted: d.counted || 1
                            readonly property var clean: d.cleanup || ({})
                            onShownChanged: if (shown) { cachedProc.running = true; foldersProc.running = true; }

                            function fmt(b) {
                                if (!b || b < 1e6) return b > 0 ? "< 1 MB" : "0 MB";
                                if (b < 1e9) return Math.round(b / 1e6) + " MB";
                                return (b / 1e9).toFixed(b < 1e10 ? 2 : 1) + " GB";
                            }
                            function col(n) { return n === "overlay" ? Atelier.overlay1 : (Atelier[n] || Atelier.accent); }
                            function scan() { if (!scanning) { scanning = true; scanProc.running = true; } }
                            function openFolder(p) {
                                Quickshell.execDetached(["sh", "-c", 'for fm in nautilus dolphin thunar; do command -v "$fm" >/dev/null && exec "$fm" "$1"; done; exec xdg-open "$1"', "sh", p]);
                            }
                            function ago(t) {
                                const s = Math.max(0, Math.round(Date.now() / 1000 - t));
                                return s < 60 ? "just now" : s < 3600 ? Math.round(s / 60) + " min ago" : s < 86400 ? Math.round(s / 3600) + " h ago" : Math.round(s / 86400) + " d ago";
                            }
                            function ask(id, run) {
                                if (confirm === id) { confirm = ""; run(); }
                                else { confirm = id; confirmTimer.restart(); }
                            }
                            Timer { id: confirmTimer; interval: 4000; onTriggered: storage.confirm = "" }

                            Process {
                                id: cachedProc
                                command: [storage.script, "cached"]
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        try { const j = JSON.parse(text); if (j.categories) storage.d = j; } catch (e) {}
                                        // rescan when there is nothing yet or it is older than 10 minutes
                                        if (!storage.d.scannedAt || Date.now() / 1000 - storage.d.scannedAt > 600) storage.scan();
                                    }
                                }
                            }
                            Process {
                                id: scanProc
                                command: [storage.script, "scan"]
                                stdout: StdioCollector {
                                    onStreamFinished: { try { const j = JSON.parse(text); if (j.categories) storage.d = j; } catch (e) {} }
                                }
                                onExited: storage.scanning = false
                            }
                            Process {
                                id: foldersProc
                                command: [storage.foldersScript, "check"]
                                stdout: StdioCollector {
                                    onStreamFinished: storage.folders = text.trim().split("\n").filter(l => l).map(l => { const p = l.split("|"); return { path: p[0], exists: p[1] === "1" }; })
                                }
                            }
                            Process {
                                id: cleanProc
                                onExited: storage.scan()
                            }
                            function runClean(cmd) { cleanProc.command = ["sh", "-c", cmd]; cleanProc.running = true; }
                            Process { id: makeFolders; command: [storage.foldersScript]; onExited: foldersProc.running = true }

                            // ── Disk ──
                            SettingCard {
                                title: "Disk"; icon: "󰋊"; tint: Atelier.teal
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 12
                                    Layout.bottomMargin: 14
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text { text: storage.d.used ? storage.fmt(storage.used) : "…"; font.family: Atelier.font; font.pixelSize: 26; font.bold: true; color: Atelier.text }
                                        Text {
                                            Layout.alignment: Qt.AlignBottom
                                            Layout.bottomMargin: 5
                                            text: storage.d.total ? "of " + storage.fmt(storage.total) + " used" : "Measuring…"
                                            font.family: Atelier.fontUi; font.pixelSize: 13; color: Atelier.subtext
                                        }
                                        Item { Layout.fillWidth: true }
                                        Chip { visible: !!storage.d.free; icon: "󰄬"; text: storage.fmt(storage.d.free) + " free"; tint: Atelier.green }
                                    }

                                    // one bar for the whole disk; each category is its share of `used`
                                    ClippingRectangle {
                                        id: diskBar
                                        Layout.fillWidth: true
                                        implicitHeight: 14
                                        radius: 7
                                        color: Atelier.containerHigh
                                        Row {
                                            height: parent.height
                                            spacing: 2
                                            Repeater {
                                                model: storage.cats.filter(c => c.bytes > 0)
                                                Rectangle {
                                                    required property var modelData
                                                    height: parent.height
                                                    width: Math.max(2, diskBar.width * (storage.used / storage.total) * modelData.bytes / Math.max(storage.counted, storage.used) - 2)
                                                    color: storage.col(modelData.color)
                                                    Behavior on width { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }
                                                }
                                            }
                                        }
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 14
                                        Repeater {
                                            model: storage.cats.filter(c => c.bytes > 0)
                                            Row {
                                                required property var modelData
                                                spacing: 6
                                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: storage.col(modelData.color) }
                                                Text { text: modelData.label; font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext1 }
                                                Text { text: storage.fmt(modelData.bytes); font.family: Atelier.font; font.pixelSize: 11; color: Atelier.subtext }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        Text {
                                            Layout.fillWidth: true
                                            wrapMode: Text.Wrap
                                            text: (storage.d.compressionSaved > 0
                                                    ? "Your files add up to " + storage.fmt(storage.counted) + "; btrfs compression saves about "
                                                      + storage.fmt(storage.d.compressionSaved) + ", so the bar shows each share of what is really used. "
                                                    : "")
                                                + (storage.scanning ? "Scanning…" : storage.d.scannedAt ? "Scanned " + storage.ago(storage.d.scannedAt) + "." : "")
                                            font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext
                                        }
                                        Chip {
                                            icon: "󰑐"; text: storage.scanning ? "Scanning…" : "Rescan"; tint: Atelier.teal
                                            interactive: !storage.scanning; implicitHeight: 30
                                            onClicked: storage.scan()
                                        }
                                    }
                                }
                            }

                            // ── One-click clean (scripts/cleanup.sh) ──
                            SettingCard {
                                id: quick
                                title: "Clean up"
                                property bool withPacman: false
                                property bool ask: false              // waiting for the confirming click
                                property string result: ""
                                readonly property real safe: (storage.clean.trash || 0) + (storage.clean.aur || 0)
                                    + (storage.clean.thumbnails || 0) + (storage.clean.devcache || 0)
                                readonly property real total: safe + (withPacman ? (storage.clean.pacman || 0) : 0)
                                Timer { id: quickAsk; interval: 4000; onTriggered: quick.ask = false }
                                Process {
                                    id: quickProc
                                    command: [Quickshell.shellDir + "/scripts/cleanup.sh"].concat(quick.withPacman ? ["--pacman"] : [])
                                    stdout: StdioCollector {
                                        onStreamFinished: {
                                            try {
                                                const r = JSON.parse(text);
                                                quick.result = "Freed " + storage.fmt(r.freed)
                                                    + (r.pacman === "cancelled" ? " · package cache skipped (no password)" : "");
                                            } catch (e) { quick.result = "Done"; }
                                        }
                                    }
                                    onExited: storage.scan()
                                }

                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 92
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 16
                                        Rectangle {
                                            implicitWidth: 52; implicitHeight: 52; radius: 16
                                            color: Qt.alpha(Atelier.accent, 0.16)
                                            Text { anchors.centerIn: parent; text: "󰃢"; font.family: Atelier.font; font.pixelSize: 24; color: Atelier.accent }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1      // shrink to the leftover width; don't push the button out
                                            spacing: 3
                                            Text {
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                text: quickProc.running ? "Cleaning…"
                                                    : quick.result ? quick.result
                                                    : storage.d.cleanup ? storage.fmt(quick.total) + " can be freed" : "Measuring…"
                                                font.family: Atelier.fontUi; font.pixelSize: 18; font.weight: Font.Bold; color: Atelier.text
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                wrapMode: Text.Wrap
                                                text: "Trash, AUR build files, thumbnails and developer download caches (pip, npm, Go, pnpm, Cargo). They come back by themselves when needed."
                                                font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext
                                            }
                                        }
                                        Rectangle {
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.minimumWidth: implicitWidth
                                            implicitWidth: cleanLabel.implicitWidth + 40
                                            implicitHeight: 40
                                            radius: 20
                                            readonly property bool can: !quickProc.running && !storage.scanning && quick.total > 0
                                            opacity: can ? 1 : 0.45
                                            color: quick.ask ? Atelier.fill(Atelier.red) : Atelier.fill(Atelier.accent)
                                            Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                                            Text {
                                                id: cleanLabel
                                                anchors.centerIn: parent
                                                text: quickProc.running ? "Cleaning…" : quick.ask ? "Click to confirm" : "Clean now"
                                                font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: Atelier.onFill
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: parent.can
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (!quick.ask) { quick.ask = true; quick.result = ""; quickAsk.restart(); return; }
                                                    quick.ask = false; quickAsk.stop();
                                                    quickProc.running = true;
                                                }
                                            }
                                        }
                                    }
                                }
                                SettingSwitch {
                                    label: "Also empty the package cache · " + storage.fmt(storage.clean.pacman)
                                    description: "Every downloaded package in /var/cache/pacman/pkg. Asks for your password. Afterwards you can't roll back an update without internet."
                                    checked: quick.withPacman; onToggled: (v) => quick.withPacman = v
                                }
                            }

                            // ── Categories ──
                            SettingCard {
                                title: "By category"; icon: "󰕮"; tint: Atelier.blue
                                Repeater {
                                    model: storage.cats
                                    SettingRow {
                                        id: catRow
                                        required property var modelData
                                        label: modelData.label
                                        description: modelData.paths.join("  ·  ")
                                        RowLayout {
                                            spacing: 10
                                            Rectangle {
                                                implicitWidth: 110; implicitHeight: 6; radius: 3
                                                color: Qt.alpha(storage.col(catRow.modelData.color), 0.16)
                                                Rectangle {
                                                    width: parent.width * Math.min(1, catRow.modelData.bytes / Math.max(1, storage.cats[0] ? storage.cats[0].bytes : 1))
                                                    height: parent.height; radius: parent.radius
                                                    color: storage.col(catRow.modelData.color)
                                                }
                                            }
                                            Text {
                                                Layout.preferredWidth: 64
                                                horizontalAlignment: Text.AlignRight
                                                text: storage.fmt(catRow.modelData.bytes)
                                                font.family: Atelier.font; font.pixelSize: 12; font.bold: true; color: Atelier.text
                                            }
                                            Chip {
                                                icon: catRow.modelData.icon; text: "Open"; tint: storage.col(catRow.modelData.color)
                                                interactive: catRow.modelData.open !== ""; opacity: catRow.modelData.open ? 1 : 0.35
                                                implicitHeight: 28
                                                onClicked: storage.openFolder(catRow.modelData.open)
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Biggest folders ──
                            SettingCard {
                                title: "Biggest folders"; icon: "󰉋"; tint: Atelier.peach
                                SettingRow {
                                    visible: (storage.d.biggest || []).length === 0
                                    label: storage.scanning ? "Scanning…" : "Nothing over 50 MB"
                                }
                                Repeater {
                                    model: storage.d.biggest || []
                                    SettingRow {
                                        id: bigRow
                                        required property var modelData
                                        label: modelData.name
                                        RowLayout {
                                            spacing: 10
                                            Text { text: storage.fmt(bigRow.modelData.bytes); font.family: Atelier.font; font.pixelSize: 12; font.bold: true; color: Atelier.text }
                                            Chip { icon: "󰉋"; text: "Open"; tint: Atelier.peach; interactive: true; implicitHeight: 28
                                                onClicked: storage.openFolder(bigRow.modelData.path) }
                                        }
                                    }
                                }
                            }

                            // ── Clean up ──
                            SettingCard {
                                title: "Clean one at a time"; icon: "󰃢"; tint: Atelier.yellow
                                SettingRow {
                                    label: "Trash · " + storage.fmt(storage.clean.trash)
                                    description: "Files you deleted in the file manager"
                                    Chip {
                                        icon: "󰩹"; text: storage.confirm === "trash" ? "Click again to empty" : "Empty"
                                        tint: Atelier.red; interactive: storage.clean.trash > 0; opacity: storage.clean.trash > 0 ? 1 : 0.4
                                        implicitHeight: 28
                                        onClicked: storage.ask("trash", () => storage.runClean("gio trash --empty"))
                                    }
                                }
                                SettingRow {
                                    label: "AUR build files · " + storage.fmt(storage.clean.aur)
                                    description: "yay / paru keep every package they built in ~/.cache. Safe to delete; they download again when needed."
                                    Chip {
                                        icon: "󰃢"; text: storage.confirm === "aur" ? "Click again to clear" : "Clear"
                                        tint: Atelier.yellow; interactive: storage.clean.aur > 0; opacity: storage.clean.aur > 0 ? 1 : 0.4
                                        implicitHeight: 28
                                        onClicked: storage.ask("aur", () => storage.runClean('rm -rf "$HOME/.cache/yay" "$HOME/.cache/paru"'))
                                    }
                                }
                                SettingRow {
                                    label: "Package cache · " + storage.fmt(storage.clean.pacman)
                                    description: "Old versions of installed packages in /var/cache/pacman/pkg. Opens a terminal: sudo pacman -Sc"
                                    Chip {
                                        icon: "󰏗"; text: "Clean…"; tint: Atelier.yellow
                                        interactive: storage.clean.pacman > 0; opacity: storage.clean.pacman > 0 ? 1 : 0.4
                                        implicitHeight: 28
                                        onClicked: Quickshell.execDetached([Settings.behavior.terminal || "ghostty", "-e", "sh", "-c",
                                            "sudo pacman -Sc; echo; printf 'Press Enter to close… '; read _"])
                                    }
                                }
                                SettingRow {
                                    label: "Thumbnails · " + storage.fmt(storage.clean.thumbnails)
                                    description: "Picture previews; they are made again when needed"
                                    Chip {
                                        icon: "󰋩"; text: "Clear"; tint: Atelier.yellow
                                        interactive: storage.clean.thumbnails > 0; opacity: storage.clean.thumbnails > 0 ? 1 : 0.4
                                        implicitHeight: 28
                                        onClicked: storage.runClean('rm -rf "$HOME/.cache/thumbnails"')
                                    }
                                }
                            }

                            // ── Home folders ──
                            SettingCard {
                                title: "Home folders"; icon: "󰋜"; tint: Atelier.mauve
                                SettingRow {
                                    label: storage.folders.some(f => !f.exists) ? "Some folders are missing" : "All set"
                                    description: "Documents, Downloads, Pictures, Videos, Music, Projects and more, plus Pictures/Wallpapers (shows in the wallpaper picker), Pictures/Screenshots and Videos/Recordings. Also adds them to the file manager sidebar."
                                    Chip {
                                        icon: "󰉗"; text: storage.folders.some(f => !f.exists) ? "Create" : "Repair"
                                        tint: Atelier.mauve; interactive: !makeFolders.running; implicitHeight: 28
                                        onClicked: makeFolders.running = true
                                    }
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 10
                                    Layout.bottomMargin: 12
                                    spacing: 8
                                    Repeater {
                                        model: storage.folders
                                        Chip {
                                            required property var modelData
                                            icon: modelData.exists ? "󰉋" : "󰉖"
                                            text: modelData.path
                                            tint: modelData.exists ? Atelier.mauve : Atelier.subtext
                                            interactive: modelData.exists
                                            implicitHeight: 30
                                            onClicked: storage.openFolder(Quickshell.env("HOME") + "/" + modelData.path)
                                        }
                                    }
                                }
                            }
                        }

                        // ═════════ Hardware + Profiles (own files) ═════════
                        DisplaysPage { visible: win.page === "displays" }
                        InputPage { visible: win.page === "input" }
                        SoundPage { visible: win.page === "sound" }
                        DefaultAppsPage { visible: win.page === "defaults" }
                        ShortcutsPage { visible: win.page === "shortcuts" }
                        ProfilesPage { visible: win.page === "profiles" }

                        // ═════════ About ═════════
                        ColumnLayout {
                            id: about
                            property string version: ""
                            visible: win.page === "about"
                            Layout.fillWidth: true
                            spacing: 20

                            Process {
                                id: sysProc
                                running: win.visible && win.page === "about"
                                command: ["sh", "-c", "cat /etc/hostname; . /etc/os-release; echo \"$PRETTY_NAME\"; uname -r; hyprctl version | head -1 | cut -d' ' -f2; grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//; s/ with .*//'; awk '/MemTotal/ {printf \"%.0f GB\", $2/1048576}' /proc/meminfo; uptime -p | sed 's/^up //'"]
                                stdout: StdioCollector { onStreamFinished: about.sys = text.trim().split("\n") }
                            }
                            property var sys: []
                            // laptop model, CPU, GPUs, disks, displays, battery… (scripts/hardware.py)
                            property var hw: ({ device: {}, groups: [] })
                            Process {
                                id: hwProc
                                running: win.visible && win.page === "about"
                                command: ["python3", Quickshell.shellDir + "/scripts/hardware.py"]
                                stdout: StdioCollector { onStreamFinished: { try { about.hw = JSON.parse(text); } catch (e) {} } }
                            }

                            SettingCard {
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 150
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 22
                                        Rectangle {
                                            implicitWidth: 92; implicitHeight: 92; radius: 24
                                            color: Atelier.fill(Atelier.accent)
                                            Text { anchors.centerIn: parent; text: "󰣇"; font.family: Atelier.font; font.pixelSize: 50; color: Atelier.onFill }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3
                                            Text { text: about.sys[0] || "…"; font.family: Atelier.fontUi; font.pixelSize: 22; font.weight: Font.Bold; color: Atelier.text }
                                            Text { visible: !!about.hw.device.name; text: "󰌢  " + (about.hw.device.name || "")
                                                font.family: Atelier.fontUi; font.pixelSize: 14; font.weight: Font.Medium; color: Atelier.text }
                                            Text { visible: !!about.hw.device.summary; text: about.hw.device.summary || ""
                                                font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.subtext1 }
                                            Text { text: (about.sys[1] || "") + " · Atelier desktop"; font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.subtext }
                                            Text { visible: !!about.sys[6]; text: "Up " + (about.sys[6] || ""); font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext; opacity: 0.8 }
                                        }
                                    }
                                }
                            }
                            // one card per group: Device, Performance, Storage, Displays, Battery, Connectivity, Software
                            Repeater {
                                model: about.hw.groups
                                SettingCard {
                                    id: hwCard
                                    required property var modelData
                                    title: modelData.title
                                    Repeater {
                                        // the desktop's own versions belong with the software
                                        model: hwCard.modelData.rows.concat(hwCard.modelData.title === "Software"
                                            ? [["Hyprland", about.sys[3] || "…"], ["Quickshell", about.version || "…"],
                                               ["Theme", Atelier.themeName + " · " + Atelier.mode]] : [])
                                        SettingRow {
                                            id: hwRow
                                            required property var modelData
                                            // rows marked "copy" (the serial number) copy their value on click
                                            readonly property bool copyable: modelData[3] === "copy"
                                            property bool copied: false
                                            label: modelData[0]
                                            Timer { id: copiedT; interval: 1600; onTriggered: hwRow.copied = false }
                                            ColumnLayout {
                                                spacing: 2
                                                Text {
                                                Layout.alignment: Qt.AlignRight
                                                Layout.maximumWidth: 420
                                                font.features: hwRow.copyable ? { "tnum": 1 } : ({})
                                                MouseArea {
                                                    visible: hwRow.copyable
                                                    anchors.fill: parent
                                                    anchors.margins: -6
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        Quickshell.execDetached(["wl-copy", "--", hwRow.modelData[1]]);
                                                        hwRow.copied = true; copiedT.restart();
                                                    }
                                                }
                                                text: modelData[1] || "…"
                                                font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.subtext1
                                                horizontalAlignment: Text.AlignRight
                                                elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.alignment: Qt.AlignRight
                                                    Layout.maximumWidth: 420
                                                    visible: !!modelData[2]
                                                    text: hwRow.copied ? "Copied" : (modelData[2] || "")
                                                    font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext
                                                    elide: Text.ElideRight
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            SettingCard {
                                title: "Files"; icon: "󰉋"; tint: Atelier.lavender
                                SettingRow {
                                    label: "settings.json"
                                    description: Settings.path
                                    Chip { icon: "󰏫"; text: "Open"; tint: Atelier.lavender; interactive: true; implicitHeight: 32
                                        onClicked: { opener.command = ["xdg-open", Settings.path]; opener.running = true; } }
                                }
                                SettingRow {
                                    label: "Shell folder"
                                    description: Quickshell.shellDir
                                    Chip { icon: "󰉋"; text: "Open"; tint: Atelier.lavender; interactive: true; implicitHeight: 32
                                        onClicked: { opener.command = ["xdg-open", Quickshell.shellDir]; opener.running = true; } }
                                }
                            }
                            SettingCard {
                                title: "Reset"; icon: "󰦛"; tint: Atelier.red
                                SettingRow {
                                    label: "Reset all settings"
                                    description: "Back to the defaults. Your theme, wallpaper and files are not touched."
                                    Chip {
                                        icon: "󰦛"
                                        text: win.confirmReset ? "Click again to confirm" : "Reset"
                                        tint: Atelier.red
                                        interactive: true
                                        implicitHeight: 32
                                        onClicked: {
                                            if (win.confirmReset) { Settings.reset(); win.confirmReset = false; }
                                            else { win.confirmReset = true; resetTimer.restart(); }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    }
    // ── A section title in the lock gallery (title, a line of text, optional chips) ──
    component GalleryHead: RowLayout {
        property string title
        property string sub
        width: parent ? parent.width : 0
        spacing: 12
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text { text: parent.parent.title; font.family: Atelier.fontUi; font.pixelSize: 15; font.weight: Font.DemiBold; color: Atelier.text }
            Text { Layout.fillWidth: true; text: parent.parent.sub; wrapMode: Text.Wrap
                font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext }
        }
    }

    // ── A lock-screen theme in the gallery (Settings → Lock screen) ─────────
    component LockThemeCard: Rectangle {
        id: tc
        required property var modelData
        readonly property bool builtin: !!modelData.builtin
        readonly property bool inUse: Settings.lock.theme === modelData.id
        readonly property bool busy: lockPage.busy === modelData.id
        width: Math.floor((gallery.width - 2 * 12) / 3)
        height: shot.height + 66
        radius: 14
        color: Atelier.container
        border.width: inUse ? 2 : 1
        border.color: inUse ? Atelier.mauve : (hov.hovered ? Qt.alpha(Atelier.text, 0.25) : Atelier.outline)
        Behavior on border.color { ColorAnimation { duration: Atelier.durFast } }
        HoverHandler { id: hov }

        ClippingRectangle {
            id: shot
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 6
            height: Math.round((tc.width - 12) * 0.5625)
            radius: 10
            color: Atelier.base

            // qylock: the theme's own animated preview, playing only while hovered
            AnimatedImage {
                anchors.fill: parent
                visible: !tc.builtin && source != ""
                source: lockPage.shown && tc.modelData.preview ? "file://" + tc.modelData.preview : ""
                playing: hov.hovered
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
            }
            Text {
                anchors.centerIn: parent
                visible: !tc.builtin && !tc.modelData.preview
                text: "No preview"
                font.family: Atelier.fontUi; font.pixelSize: 11
                color: Atelier.subtext
            }

            // Depth: the wallpaper, a big clock, and the subject cut-out over it
            Item {
                anchors.fill: parent
                visible: tc.modelData.id === "depth"
                Image {
                    anchors.fill: parent
                    source: lockPage.shown && Wallpaper.current ? "file://" + Wallpaper.current : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 420
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.1
                    text: Atelier.hour12(new Date()).replace(/^0/, "") + ":" + Qt.formatTime(new Date(), "mm")
                    font.family: "Inter Display"; font.pixelSize: parent.height * 0.3; font.weight: Font.Bold
                    color: Atelier.text
                }
                Image {
                    anchors.fill: parent
                    visible: DepthWall.ok
                    source: lockPage.shown && DepthWall.ok ? "file://" + DepthWall.cutout : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 420
                }
            }

            // a phone style: the real PhoneLock, live and small (a stub instead of the lock)
            Loader {
                anchors.fill: parent
                active: lockPage.shown && lockPage.phoneIds.indexOf(tc.modelData.id) >= 0
                sourceComponent: Component {
                    PhoneLock { thumb: true; lockRoot: lockStub; variant: tc.modelData.id }
                }
            }

            // Atelier: a live miniature of the shell's lock (glass panel on your wallpaper)
            Item {
                anchors.fill: parent
                visible: tc.modelData.id === "atelier"
                Image {
                    anchors.fill: parent
                    source: lockPage.shown && Wallpaper.current ? "file://" + Wallpaper.current : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 420
                }
                Rectangle { anchors.fill: parent; color: Atelier.crust; opacity: 0.4 }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.74; height: parent.height * 0.66
                    radius: 10
                    color: Atelier.surface
                    border.width: 1; border.color: Atelier.outline
                    Row {
                        anchors.fill: parent; anchors.margins: 5; spacing: 5
                        Rectangle { width: (parent.width - 10) * 0.25; height: parent.height; radius: 5; color: Atelier.container }
                        Column {
                            width: (parent.width - 10) * 0.5; height: parent.height
                            topPadding: height * 0.14; spacing: 4
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Atelier.hour12(new Date()) + ":" + Qt.formatTime(new Date(), "mm")
                                font.family: Atelier.font; font.pixelSize: 15; font.bold: true; color: Atelier.text
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 16; height: 16; radius: 8
                                color: Qt.alpha(Atelier.accent, 0.3); border.width: 1; border.color: Atelier.accent
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.8; height: 9; radius: 4.5
                                color: Atelier.container; border.width: 1; border.color: Atelier.outline
                            }
                        }
                        Rectangle { width: (parent.width - 10) * 0.25; height: parent.height; radius: 5; color: Atelier.container }
                    }
                }
            }

            // "playing" hint
            Rectangle {
                visible: !tc.builtin && !!tc.modelData.preview && !hov.hovered
                anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 6
                width: 22; height: 22; radius: 11
                color: Qt.alpha(Atelier.crust, 0.7)
                Text { anchors.centerIn: parent; text: "󰐊"; font.family: Atelier.font; font.pixelSize: 11; color: Atelier.text }
            }
        }

        RowLayout {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.leftMargin: 12; anchors.rightMargin: 10; anchors.bottomMargin: 11
            spacing: 6
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text { Layout.fillWidth: true; text: tc.modelData.name; font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: Atelier.text; elide: Text.ElideRight }
                Text {
                    Layout.fillWidth: true
                    text: tc.builtin ? tc.modelData.note : tc.busy ? "Downloading…" : tc.modelData.downloaded ? "Downloaded" : tc.modelData.sizeMB + " MB"
                    font.family: Atelier.fontUi; font.pixelSize: 10
                    color: tc.busy ? Atelier.mauve : Atelier.subtext
                    elide: Text.ElideRight
                }
            }
            Chip {
                icon: "󰈈"; text: ""
                tint: Atelier.subtext; interactive: !tc.busy; implicitHeight: 26
                onClicked: lockPage.preview(tc.modelData)
            }
            Chip {
                icon: tc.inUse ? "󰄬" : ""
                text: tc.inUse ? "In use" : tc.busy ? "…" : "Use"
                tint: Atelier.mauve; interactive: !tc.inUse && !tc.busy; implicitHeight: 26
                onClicked: lockPage.use(tc.modelData)
            }
        }
    }

    // ── Profile picture (~/.face), else the initial on an accent fill ───────
    component Avatar: Item {
        id: av
        property int size: 38
        property bool ring: false
        implicitWidth: size; implicitHeight: size
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Atelier.fill(Atelier.accent)
            visible: avImg.status !== Image.Ready
            Text { anchors.centerIn: parent; text: Atelier.userName.charAt(0).toUpperCase(); font.family: Atelier.fontUi
                font.pixelSize: av.size * 0.42; font.weight: Font.DemiBold; color: Atelier.onFill }
        }
        ClippingRectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            visible: avImg.status === Image.Ready
            Image {
                id: avImg
                anchors.fill: parent
                source: Profile.faceUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: av.size * 2; sourceSize.height: av.size * 2
            }
        }
        Rectangle {
            visible: av.ring
            anchors.fill: parent
            anchors.margins: -4
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Qt.alpha(Atelier.accent, 0.55)
        }
    }
}
