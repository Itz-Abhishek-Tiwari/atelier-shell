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

        readonly property var ownStyles: Settings.lockStyles.concat(Plugins.lockStyles)
        readonly property var phoneIds: ["cupertino", "hyper", "harmony", "oxygen", "material", "dot", "terminal", "analog", "aurora", "poster", "flip", "split", "hud"]
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

                // a phone style: the real PhoneLock, live and small (a stub instead of the lock)
                Loader {
                    anchors.fill: parent
                    active: lockPage.shown && (lockPage.phoneIds.indexOf(tc.modelData.id) >= 0 || !!tc.modelData.plugin)
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
