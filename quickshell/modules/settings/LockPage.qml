import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.components
import qs.config
import qs.modules.lock
import qs.modules.background
import qs.services

// Settings → Lock screen.
ColumnLayout {
    required property var win
    Layout.fillWidth: true
    spacing: 20

    SettingCard {
        title: "Lock screen"; icon: "󰌾"; tint: Atelier.mauve
        SettingRow {
            label: "In use"
            description: {
                const own = lockPage.ownStyles.find(x => x.id === Settings.lock.theme);
                return own ? own.name + " · " + own.note : "Atelier · Glass panel, this shell's own";
            }
            Chip { icon: "󰌾"; text: "Lock now"; tint: Atelier.mauve; interactive: true; implicitHeight: 30
                onClicked: Quickshell.execDetached(["qs", "ipc", "call", "lock", "lock"]) }
        }
        SettingSwitch { label: "Show notifications"; description: "App name and title only, never the message text"
            checked: Settings.notifications.lockShowCount; onToggled: (v) => Settings.notifications.lockShowCount = v }
        SettingChoice { label: "Clock"; description: Settings.lock.clock === "system" ? "Follows Appearance → 24-hour clock (now " + (Atelier.clock24 ? "24" : "12") + "-hour)" : "For every built-in style"
            options: [{ id: "system", label: "System" }, { id: "12", label: "12-hour" }, { id: "24", label: "24-hour" }]
            value: Settings.lock.clock; onPicked: (id) => Settings.lock.clock = id }
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
        SettingSlider { visible: Settings.lock.depthStyle === "glass"; label: "    Frost"; description: "Blur inside the digits"; from: 20; to: 100; step: 5; suffix: "%"
            value: Math.round((Settings.lock.depthGlassFrost ?? 0.9) * 100); onMoved: (v) => Settings.lock.depthGlassFrost = v / 100 }
        SettingSlider { visible: Settings.lock.depthStyle === "glass"; label: "    Tint"; description: "Clock colour in the glass"; from: 0; to: 70; step: 5; suffix: "%"
            value: Math.round((Settings.lock.depthGlassTint ?? 0.2) * 100); onMoved: (v) => Settings.lock.depthGlassTint = v / 100 }
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
                        width: 24; height: 24; radius: Atelier.radiusMd
                        color: modelData.id === "auto" ? "transparent" : modelData.c
                        border.width: on ? 2 : 1
                        border.color: on ? Atelier.accent : Atelier.outline
                        // auto: a split wallpaper-ish swatch
                        Text { anchors.centerIn: parent; visible: parent.modelData.id === "auto"; text: "󰍉"
                            font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: Atelier.text }
                        Text { anchors.centerIn: parent; visible: parent.on && parent.modelData.id !== "auto"; text: "󰄬"
                            font.family: Atelier.font; font.pixelSize: Atelier.fsMd
                            color: (0.2126 * parent.color.r + 0.7152 * parent.color.g + 0.0722 * parent.color.b) > 0.5 ? "#161616" : "#ffffff" }
                        scale: swMa.containsMouse ? 1.15 : 1
                        Behavior on scale { NumberAnimation { duration: Atelier.durFast } }
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
        SettingChoice { label: "Date"
            options: [{ id: "long", label: "Monday, 23 November" }, { id: "short", label: "Mon 23 Nov" }, { id: "off", label: "Off" }]
            value: Settings.lock.depthDate || "long"; onPicked: (id) => Settings.lock.depthDate = id }
        SettingSwitch { label: "Weather"; description: "The temperature after the date"
            checked: Settings.lock.depthWeather ?? true; onToggled: (v) => Settings.lock.depthWeather = v }
        SettingSwitch { visible: !Atelier.lockClock24; label: "AM / PM"; description: "Small, beside the digits"
            checked: Settings.lock.depthAmPm ?? true; onToggled: (v) => Settings.lock.depthAmPm = v }
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
        readonly property bool shown: win.visible && win.page === "lock"

        readonly property var ownStyles: Settings.lockStyles
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

        function use(t) { Settings.lock.theme = t.id; }
        function preview(t) { Quickshell.execDetached(["qs", "ipc", "call", "lock", "previewStyle", t.id]); }

        Column {
            id: gallery
            width: parent.width
            spacing: 14

            // ── ours: built into the shell ──
            GalleryHead {
                title: "Styles"
                sub: "Built into the shell, drawn on your wallpaper. The phone-inspired ones echo each phone's clock and layout, made for a laptop: a keyboard login, Wi-Fi and battery top right."
            }
            Flow {
                width: parent.width
                spacing: 12
                Repeater { model: lockPage.ownStyles; delegate: LockThemeCard {} }
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
                Text { text: parent.parent.title; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsXl; font.weight: Font.DemiBold; color: Atelier.text }
                Text { Layout.fillWidth: true; text: parent.parent.sub; wrapMode: Text.Wrap
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
            }
        }

        // ── A lock-screen theme in the gallery (Settings → Lock screen) ─────────
        component LockThemeCard: Rectangle {
            id: tc
            required property var modelData
            readonly property bool inUse: Settings.lock.theme === modelData.id
            width: Math.floor((gallery.width - 2 * 12) / 3)
            height: shot.height + 66
            radius: Atelier.radiusMd
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
                radius: Atelier.radiusSm
                color: Atelier.base

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
                        text: Atelier.lockHour(new Date()).replace(/^0(?=\d)/, Atelier.lockClock24 ? "0" : "") + ":" + Qt.formatTime(new Date(), "mm")
                        font.family: Atelier.fontDisplay; font.pixelSize: parent.height * 0.3; font.weight: Font.Bold
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
                        radius: Atelier.radiusSm
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
                                    text: Atelier.lockHour(new Date()) + ":" + Qt.formatTime(new Date(), "mm")
                                    font.family: Atelier.font; font.pixelSize: Atelier.fsXl; font.bold: true; color: Atelier.text
                                }
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 16; height: 16; radius: Atelier.radiusSm
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

            }

            RowLayout {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.leftMargin: 12; anchors.rightMargin: 10; anchors.bottomMargin: 11
                spacing: 6
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { Layout.fillWidth: true; text: tc.modelData.name; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold; color: Atelier.text; elide: Text.ElideRight }
                    Text {
                        Layout.fillWidth: true
                        text: tc.modelData.note
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMicro
                        color: Atelier.subtext
                        elide: Text.ElideRight
                    }
                }
                Chip {
                    icon: "󰈈"; text: ""
                    tint: Atelier.subtext; interactive: true; implicitHeight: 26
                    onClicked: lockPage.preview(tc.modelData)
                }
                Chip {
                    icon: tc.inUse ? "󰄬" : ""
                    text: tc.inUse ? "In use" : "Use"
                    tint: Atelier.mauve; interactive: !tc.inUse; implicitHeight: 26
                    onClicked: lockPage.use(tc.modelData)
                }
            }
        }

}
