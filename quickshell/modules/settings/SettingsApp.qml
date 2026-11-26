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
        { id: "profile",       group: "Personalise", icon: "󰀄", label: "Profile",           sub: "Picture, name and greetings",
          keys: "profile picture photo avatar face image name display greeting account user login full computer hostname" },
        { id: "appearance",    group: "Personalise", icon: "󰏘", label: "Appearance",        sub: "Theme, wallpaper, glass, blur and shadows",
          keys: "theme colour color wallpaper transition fade wipe slide roundness corners frame border glass opacity blur transparency translucent vibrancy dim solid shadows windows control center layout tiles icons cards list header shortcuts 24-hour clock time animation speed shell" },
        { id: "bar",           group: "Personalise", icon: "󰍜", label: "Bar",               sub: "Position, sections and pinned apps",
          keys: "bar panel position workspaces tray clock pinned apps hover logo power title" },
        { id: "widgets",       group: "Personalise", icon: "󰕮", label: "Desktop",           sub: "The clock and text on your wallpaper",
          keys: "desktop widget clock date weather greeting tasks media music font shadow colour color accent icons glass frosted blur card" },
        { id: "controlcenter", group: "Personalise", icon: "󰒓", label: "Control center",    sub: "Switches layout, header and shortcuts",
          keys: "control center quick settings toggles tiles icons cards list header shortcuts notifications" },
        { id: "notifications", group: "Personalise", icon: "󰂚", label: "Notifications",     sub: "Pop-ups and Do Not Disturb",
          keys: "notifications pop-ups popups do not disturb dnd" },
        { id: "lock",          group: "Personalise", icon: "󰌾", label: "Lock screen",       sub: "Eight built-in styles and their options",
          keys: "lock screen themes styles notifications privacy" },
        { id: "login",         group: "Personalise", icon: "󰍂", label: "Login screen",      sub: "Matches your lock screen; sync and boot options",
          keys: "login greeter greetd sddm boot quiet sync" },
        { id: "atelier",       group: "Layouts",     icon: "󰕰", label: "Atelier",           sub: "Tiling windows, bar on the side",
          keys: "atelier layout tiling tile dwindle master scrolling monocle split bar position file manager dolphin" },
        { id: "classic",       group: "Layouts",     icon: "󰖯", label: "Traditional",       sub: "Floating windows, menu bar and dock",
          keys: "traditional classic layout floating title bar buttons menu bar global menu dock shelf magnify trash downloads file manager nautilus" },
        { id: "windows",       group: "Workspace",   icon: "󰖲", label: "Windows",           sub: "Tiling, gaps, corners and animations",
          keys: "windows tiling layout dwindle master scrolling monocle gaps rounding corners animations hyprland" },
        { id: "modes",         group: "Workspace",   icon: "󰊗", label: "Modes",             sub: "Normal, Programming, Game, Battery saver and Showcase",
          keys: "modes performance game programming dev developer blur opacity opaque shadows animations tearing power profile do not disturb dnd caffeine awake widgets auto detect steam games mode" },
        { id: "shortcuts",     group: "Workspace",   icon: "󰘳", label: "Shortcuts",         sub: "Change keys and add your own",
          keys: "shortcuts keybinds keybindings hotkeys keys bind rebind custom command" },
        { id: "defaults",      group: "Workspace",   icon: "󰀻", label: "Default apps",      sub: "Which app opens what, and web search",
          keys: "default apps applications open with browser web email mail file manager folders text editor code images pictures photos viewer video player music audio pdf documents archives zip terminal mime xdg search engine google duckduckgo bing" },
        { id: "tools",         group: "Workspace",   icon: "󰦬", label: "Tools",             sub: "Screen recording, emoji & GIFs, focus timer",
          keys: "tools screen recording record fps sound folder emoji emoticon gif gifs giphy tenor skin tone timer pomodoro focus break stopwatch" },
        { id: "displays",      group: "Hardware",    icon: "󰍺", label: "Displays",          sub: "Monitors, night light, volume pop-up",
          keys: "monitor monitors screen resolution refresh rate hz scale rotation rotate portrait mirror hdmi external vrr freesync position arrangement night light warmth schedule osd on-screen display volume brightness pop-up" },
        { id: "sound",         group: "Hardware",    icon: "󰕾", label: "Sound",             sub: "Output, microphone and app volumes",
          keys: "sound audio volume speaker headphones output input microphone mic mute apps pipewire bluetooth" },
        { id: "input",         group: "Hardware",    icon: "󰌌", label: "Keyboard & mouse",  sub: "Layouts, key repeat, pointer, touchpad",
          keys: "keyboard layout language repeat delay caps lock escape numlock mouse pointer speed sensitivity acceleration scroll natural touchpad trackpad tap click left-handed focus" },
        { id: "power",         group: "Hardware",    icon: "󰂄", label: "Power & battery",   sub: "Sleep, keep awake, battery alerts",
          keys: "power battery sleep suspend idle dim lock screen off caffeine awake low critical charger alerts" },
        { id: "phone",         group: "Hardware",    icon: "󰏲", label: "iPhone",            sub: "Use your iPhone as a webcam",
          keys: "iphone phone camera webcam droidcam usb hotspot wifi" },
        { id: "installer",     group: "System",      icon: "󰏓", label: "Install & remove",  sub: "Get apps from Arch and the AUR, remove them",
          keys: "install installer uninstall uninstaller remove delete apps applications software store packages package pacman aur yay paru download get" },
        { id: "storage",       group: "System",      icon: "󰋊", label: "Storage",           sub: "Disk use, clean up, drives",
          keys: "storage disk space clean trash cache folders drives usb sd card eject" },
        { id: "profiles",      group: "System",      icon: "󰆓", label: "Backup & profiles", sub: "Save, switch and back up your setup",
          keys: "profiles profile backup export import save restore docked laptop hot-plug automatic switch" },
        { id: "about",         group: "System",      icon: "󰋽", label: "About",             sub: "This laptop, updates, reset",
          keys: "about version files reset json hardware specs specifications laptop model computer cpu processor gpu graphics ram memory disk ssd storage battery health cycles display screen wifi bios updates pacman aur check" }
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
        const old = { behavior: "appearance", general: "appearance", display: "power" };   // pages that were renamed or merged
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
    // starts (photo picker, terminal for chfn/pacman, file manager) would open
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
                        Text { text: "Settings · " + Atelier.themeName; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                    }
                }

                // search
                Rectangle {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 8
                    implicitHeight: 34
                    radius: Atelier.radiusSm
                    color: Atelier.container
                    border.width: 1
                    border.color: searchIn.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : "transparent"
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 11
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰍉"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: Atelier.subtext
                    }
                    TextInput {
                        id: searchIn
                        anchors.fill: parent
                        anchors.leftMargin: 32; anchors.rightMargin: 10
                        verticalAlignment: Text.AlignVCenter
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd
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
                                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; font.weight: Font.DemiBold
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
                                            font.family: Atelier.font; font.pixelSize: Atelier.fsXl
                                            color: srow.on ? Atelier.accent : Atelier.subtext1
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: srow.modelData.label || ""
                                            font.family: Atelier.fontUi
                                            font.pixelSize: Atelier.fsLg
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
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
                        }
                    }
                }
                Text {
                    Layout.margins: 10
                    text: "Changes are saved automatically"
                    font.family: Atelier.fontUi
                    font.pixelSize: Atelier.fsMicro
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
                        Text { text: win.current.sub; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext }
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 16
                        anchors.top: parent.top
                        implicitWidth: 28; implicitHeight: 28; radius: Atelier.radiusMd
                        color: closeMa.containsMouse ? Qt.alpha(Atelier.red, 0.2) : Atelier.container
                        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                        Text { anchors.centerIn: parent; text: "󰅖"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: closeMa.containsMouse ? Atelier.red : Atelier.subtext }
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


                        AppearancePage { win: win; visible: win.page === "appearance" }

                        BarPage { win: win; visible: win.page === "bar" }

                        WidgetsPage { win: win; visible: win.page === "widgets" }

                        AccountPage { win: win; visible: win.page === "profile" }

                        WindowsPage { win: win; visible: win.page === "windows" }

                        ControlCenterPage { win: win; visible: win.page === "controlcenter" }

                        NotificationsPage { win: win; visible: win.page === "notifications" }

                        PowerPage { win: win; visible: win.page === "power" }

                        ModesPage { win: win; visible: win.page === "modes" }

                        LockPage { win: win; visible: win.page === "lock" }

                        LoginPage { win: win; visible: win.page === "login" }

                        ToolsPage { win: win; visible: win.page === "tools" }

                        PhonePage { win: win; visible: win.page === "phone" }

                        StoragePage { win: win; visible: win.page === "storage" }

                        InstallerPage { win: win; visible: win.page === "installer" }

                        // ═════════ Hardware + Profiles (own files) ═════════
                        ColumnLayout {
                            visible: win.page === "displays"
                            Layout.fillWidth: true
                            spacing: 20
                            DisplaysPage { Layout.fillWidth: true }
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
                        }
                        LayoutPage { which: "atelier"; visible: win.page === "atelier" }
                        LayoutPage { which: "classic"; visible: win.page === "classic" }
                        InputPage { visible: win.page === "input" }
                        SoundPage { visible: win.page === "sound" }
                        ColumnLayout {
                            visible: win.page === "defaults"
                            Layout.fillWidth: true
                            spacing: 20
                            DefaultAppsPage { Layout.fillWidth: true }
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
                        }
                        ShortcutsPage { visible: win.page === "shortcuts" }
                        ProfilesPage { visible: win.page === "profiles" }

                        AboutPage { win: win; visible: win.page === "about" }
                    }
                }
            }
        }
    }
    }
}
