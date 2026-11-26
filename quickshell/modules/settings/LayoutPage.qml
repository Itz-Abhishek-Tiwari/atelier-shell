import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config

// Settings → Atelier / Traditional: one page per desktop layout, with only that layout's
// settings. Either page can be edited while the other layout is in use; "Use this layout"
// switches (Settings.setLayout, which also restores the layout's bar edge and file manager).
//
//   which: "atelier" (tiling, bar on the left) | "classic" (Traditional: floating windows with
//          title bars, a menu bar on top and a dock)
ColumnLayout {
    id: page
    property string which: "atelier"
    readonly property bool classic: which === "classic"
    readonly property bool inUse: Settings.appearance.layout === which
    readonly property string barEdge: Settings.layoutBarOf(which)
    Layout.fillWidth: true
    spacing: 20

    readonly property var layoutInfo: ({
        dwindle: "Splits the space in half for each new window",
        master: "One big window plus a stack of the others",
        scrolling: "Windows in columns on an endless horizontal strip",
        monocle: "One window at a time, full size"
    })
    // installed file managers (FileManager in their .desktop Categories)
    readonly property var fileManagers: DesktopEntries.applications.values
        .filter(e => !e.noDisplay && e.categories.indexOf("FileManager") >= 0)
        .map(e => ({ id: e.id.endsWith(".desktop") ? e.id : e.id + ".desktop", label: e.name }))
        .sort((a, b) => a.label.localeCompare(b.label))

    // ── the layout itself ───────────────────────────────────────────────────
    SettingCard {
        title: "Layout"
        icon: page.classic ? "󰖯" : "󰕰"
        tint: Atelier.blue
        highlighted: page.inUse
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            Item {   // a picture of the layout
                Layout.preferredWidth: 150
                Layout.preferredHeight: 92
                Loader {
                    anchors.fill: parent
                    sourceComponent: thumb
                    readonly property var option: ({ id: page.which })
                    readonly property bool selected: page.inUse
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: page.classic
                        ? "Windows float and overlap, with title bars (close · maximise · minimise). A menu bar along the top names the focused app; a dock along the bottom holds your apps."
                        : "Windows tile: every new window takes a share of the screen and nothing overlaps. The bar runs down the side; everything opens from the keyboard or the bar."
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
                }
                Text {
                    visible: page.inUse
                    text: "󰄬  In use"
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; color: Atelier.accent
                }
                PrimaryButton {
                    visible: !page.inUse
                    label: page.classic ? "Use Traditional" : "Use Atelier"
                    icon: "󰁔"
                    onClicked: Settings.setLayout(page.which)
                }
            }
        }
    }
    Component {
        id: thumb
        Item {
            readonly property bool classic: parent.option.id === "classic"
            readonly property color ink: parent.selected ? Atelier.accent : Atelier.overlay1
            Rectangle { anchors.fill: parent; radius: 6; color: Atelier.container }
            // atelier: two tiled windows side by side
            Rectangle { visible: !parent.classic; x: 6; y: 6; width: parent.width / 2 - 9; height: parent.height - 12; radius: 4
                        color: "transparent"; border.width: 1.5; border.color: parent.ink }
            Rectangle { visible: !parent.classic; x: parent.width / 2 + 3; y: 6; width: parent.width / 2 - 9; height: parent.height - 12; radius: 4
                        color: "transparent"; border.width: 1.5; border.color: parent.ink }
            // traditional: overlapping windows with title bars + a dock
            Rectangle { visible: parent.classic; x: 8; y: 6; width: parent.width * 0.55; height: parent.height * 0.5; radius: 4
                        color: Atelier.container; border.width: 1.5; border.color: parent.ink
                        Rectangle { width: parent.width; height: 5; radius: 3; color: parent.border.color } }
            Rectangle { visible: parent.classic; x: parent.width * 0.38; y: parent.height * 0.24; width: parent.width * 0.52; height: parent.height * 0.45; radius: 4
                        color: Atelier.surface; border.width: 1.5; border.color: parent.ink
                        Rectangle { width: parent.width; height: 5; radius: 3; color: parent.border.color } }
            Rectangle { visible: parent.classic; anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 10
                        width: parent.width * 0.4; height: 6; radius: 3; color: parent.ink }
            }
    }

    // ── Atelier ─────────────────────────────────────────────────────────────
    SettingCard {
        visible: !page.classic
        title: "Tiling"; icon: "󰕰"; tint: Atelier.accent
        SettingTiles {
            label: "Tiling layout"
            description: page.layoutInfo[Settings.windows.layout] + "  ·  Super+Alt+Space cycles"
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
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext; wrapMode: Text.Wrap
        }
    }

    // ── Traditional ─────────────────────────────────────────────────────────
    SettingCard {
        visible: page.classic
        title: "Windows"; icon: "󰖯"; tint: Atelier.mauve
        SettingChoice { label: "Title bar buttons"; description: "Double-click a title bar to maximise"
            options: [{ id: "left", label: "Left" }, { id: "right", label: "Right" }]
            value: Settings.appearance.titlebarButtons; onPicked: (id) => Settings.appearance.titlebarButtons = id }
    }

    SettingCard {
        visible: page.classic
        title: "Dock"; icon: "󰍹"; tint: Atelier.teal
        SettingRow { visible: page.barEdge === "bottom"; label: "The bar is on the bottom edge"
            description: "The dock needs that edge. Move the bar to show it." }
        SettingChoice { label: "Style"; description: "Shelf rises from a thin frame, sized to the icons. Bar fills the whole bottom edge."
            options: [{ id: "shelf", label: "Shelf" }, { id: "bar", label: "Bar" }]
            value: Settings.dock.style; onPicked: (id) => Settings.dock.style = id }
        SettingSlider { label: "Icon size"; description: "Also sets the height of the bottom bar"; from: 28; to: 56; step: 2; suffix: " px"; tint: Atelier.teal
            value: Settings.dock.iconSize; onMoved: (v) => Settings.dock.iconSize = Math.round(v) }
        SettingSwitch { label: "Magnify under the pointer"; tint: Atelier.teal
            checked: Settings.dock.magnify; onToggled: (v) => Settings.dock.magnify = v }
        SettingSwitch { label: "Show open apps"; description: "Apps not kept in the dock appear after a divider while open"; tint: Atelier.teal
            checked: Settings.dock.showRunning; onToggled: (v) => Settings.dock.showRunning = v }
        SettingSwitch { label: "Downloads and Trash"; description: "At the right end. Right-click the Trash to empty it"; tint: Atelier.teal
            checked: Settings.dock.showFolders; onToggled: (v) => Settings.dock.showFolders = v }
    }

    // ── both: this layout's bar edge and file manager ───────────────────────
    SettingCard {
        title: "Bar & files"; icon: "󰉋"; tint: Atelier.teal
        SettingChoice { label: "Bar position"; description: page.classic ? "Top keeps the menu bar; the dock needs the bottom edge free"
                                                                         : "Where the bar sits in this layout (Bar has its size and sections)"
            options: [{ id: "left", label: "Left" }, { id: "top", label: "Top" }, { id: "right", label: "Right" }, { id: "bottom", label: "Bottom" }]
            value: page.barEdge; onPicked: (id) => Settings.setLayoutBar(page.which, id) }
        SettingChoice { visible: page.fileManagers.length > 1; label: "File manager"; description: "Folders, Super+E and the dock open this"
            options: page.fileManagers
            value: Settings.layoutFilesOf(page.which); onPicked: (id) => Settings.setLayoutFiles(page.which, id) }
    }
}
