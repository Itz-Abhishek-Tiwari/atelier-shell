import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// Settings → Bar.
ColumnLayout {
    required property var win
    Layout.fillWidth: true
    spacing: 20

    SettingCard {
        title: "Position & size"; icon: "󰍜"; tint: Atelier.blue
        SettingTiles {
            label: "Bar position"
            description: "Moves the whole bar. Pop-ups, drawers and window margins follow it."
            options: [{ id: "left", label: "Left" }, { id: "top", label: "Top" }, { id: "right", label: "Right" }, { id: "bottom", label: "Bottom" }]
            value: Settings.appearance.barPosition
            onPicked: (id) => Settings.setLayoutBar(Settings.appearance.layout, id)   // remembered per layout
            preview: Component {
                Item {
                    readonly property string e: parent.option.id
                    readonly property bool sel: parent.selected
                    Rectangle { anchors.fill: parent; radius: 6; color: Atelier.container }
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
        SettingTiles {
            label: "Bar design"
            description: "Pills groups everything into rounded blocks. Gauge shows volume and battery as rings, the song playing and a big clock. Dock is a bare icon rail."
            options: [{ id: "pills", label: "Pills" }, { id: "gauge", label: "Gauge" }, { id: "dock", label: "Dock" }]
            value: Settings.bar.design
            onPicked: (id) => Settings.bar.design = id
            tileHeight: 108
            // a miniature screen: the bar on the left drawn in that design, a window beside it
            preview: Component {
                Item {
                    id: pv
                    readonly property string d: parent.option.id
                    readonly property bool sel: parent.selected
                    // [width, height, radius, colour] per mark, [0, h] = a gap; a top group and a bottom group like the real bar
                    readonly property var shapes: ({
                        pills: { top: [[7,7,3.5,"accent"], [0,4], [14,24,7,"pill"], [0,3], [14,16,7,"pill"]],
                                 bottom: [[14,12,6,"pill"], [0,4], [6,6,3,"red"]] },
                        gauge: { top: [[9,9,3,"fill"], [0,5], [2,5,1,"accent"], [0,3], [5,5,2.5,"text"], [0,3], [5,5,2.5,"faint"], [0,5], [7,7,3.5,"peach"]],
                                 bottom: [[10,10,5,"gring"], [0,4], [10,3,1,"text"], [0,2], [10,3,1,"accent"], [0,4], [10,10,5,"bring"], [0,3], [10,10,5,"ring"], [0,4], [6,6,3,"red"]] },
                        dock:  { top: [[7,7,3.5,"accent"], [0,5], [3,9,1.5,"accent"], [0,2], [3,3,1.5,"text"], [0,2], [3,3,1.5,"faint"], [0,5], [7,7,3.5,"peach"], [0,3], [7,7,3.5,"green"]],
                                 bottom: [[7,7,3.5,"sky"], [0,3], [7,7,3.5,"red"]] }
                    })
                    function col(k) {
                        return k === "accent" ? Atelier.accent : k === "pill" ? Atelier.containerHigh : k === "text" ? Atelier.text
                             : k === "sub" ? Atelier.subtext : k === "faint" ? Atelier.overlay1 : k === "sky" ? Atelier.sky
                             : k === "peach" ? Atelier.peach : k === "green" ? Atelier.green : k === "blue" ? Atelier.blue
                             : k === "red" ? Atelier.red : k === "fill" ? Atelier.accentFill : "transparent";
                    }
                    Rectangle { anchors.fill: parent; radius: 6; color: Atelier.container }
                    Rectangle {   // the bar
                        id: strip
                        x: 0; y: 0; width: 22; height: parent.height
                        radius: 6
                        color: Qt.darker(Atelier.container, 1.35)
                        Repeater {
                            model: ["top", "bottom"]
                            Column {
                                required property string modelData
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: modelData === "top" ? 6 : strip.height - implicitHeight - 6
                                spacing: 0
                                Repeater {
                                    model: pv.shapes[pv.d][parent.modelData]
                                    Item {
                                        required property var modelData
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Math.max(1, modelData[0]); height: modelData[1]
                                        Rectangle {
                                            anchors.fill: parent
                                            visible: parent.modelData.length > 2
                                            radius: parent.modelData[2] || 0
                                            color: pv.col(parent.modelData[3] || "")
                                            opacity: parent.modelData[3] === "faint" ? 0.6 : 1
                                                            border.width: ["ring", "gring", "bring"].indexOf(parent.modelData[3]) >= 0 ? 1.5 : 0
                                            border.color: parent.modelData[3] === "gring" ? Atelier.green : parent.modelData[3] === "bring" ? Atelier.blue : Qt.alpha(Atelier.text, 0.5)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Rectangle {   // a window
                        x: strip.width + 6; y: 6
                        width: parent.width - x - 6; height: parent.height - 12
                        radius: 4
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Atelier.text, pv.sel ? 0.3 : 0.18)
                        Rectangle { x: 6; y: 6; width: parent.width * 0.4; height: 3; radius: 1.5; color: Qt.alpha(Atelier.text, 0.18) }
                        Rectangle { x: 6; y: 13; width: parent.width * 0.6; height: 3; radius: 1.5; color: Qt.alpha(Atelier.text, 0.1) }
                    }
                }
            }
        }
        SettingChoice {
            visible: Settings.bar.design === "pills"
            label: "Bar style"
            description: "How the Pills design draws its groups"
            options: [{ id: "pills", label: "Pills" }, { id: "square", label: "Square" }, { id: "accent", label: "Accent" },
                      { id: "outline", label: "Outline" }, { id: "flat", label: "Flat" }]
            value: Settings.bar.style
            onPicked: (id) => Settings.bar.style = id
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
        SettingSwitch { label: "Git status"; description: "Branch and changes of the focused window's project"; tint: Atelier.blue
            checked: Settings.bar.showGit; onToggled: (v) => Settings.bar.showGit = v }
        SettingSwitch { label: "Privacy indicators"; description: "Dots when an app uses the microphone or camera, or the screen is shared"; tint: Atelier.blue
            checked: Settings.bar.showPrivacy; onToggled: (v) => Settings.bar.showPrivacy = v }
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
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext; wrapMode: Text.Wrap
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
                    implicitWidth: 52; implicitHeight: 34; radius: Atelier.radiusLg
                    color: Atelier.containerHigh
                    border.width: 1; border.color: iconIn.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                    TextInput {
                        id: iconIn
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: Atelier.font; font.pixelSize: Atelier.iconMd
                        color: Atelier[appRow.modelData.color] !== undefined ? Atelier[appRow.modelData.color] : Atelier.text
                        text: appRow.modelData.icon
                        onEditingFinished: if (text !== appRow.modelData.icon) win.setPinned(appRow.index, "icon", text)
                    }
                }
                // colour: click to cycle
                Rectangle {
                    implicitWidth: 34; implicitHeight: 34; radius: Atelier.radiusLg
                    color: Atelier.containerHigh
                    border.width: 1; border.color: Atelier.outline
                    Rectangle {
                        anchors.centerIn: parent
                        width: 16; height: 16; radius: Atelier.radiusSm
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
                    implicitHeight: 34; radius: Atelier.radiusLg
                    color: Atelier.containerHigh
                    border.width: 1; border.color: cmdIn.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                    TextInput {
                        id: cmdIn
                        anchors.fill: parent
                        anchors.leftMargin: 14; anchors.rightMargin: 14
                        verticalAlignment: Text.AlignVCenter
                        font.family: Atelier.font; font.pixelSize: Atelier.fsMd
                        color: Atelier.text
                        clip: true
                        selectByMouse: true
                        text: appRow.modelData.cmd
                        onEditingFinished: if (text !== appRow.modelData.cmd) win.setPinned(appRow.index, "cmd", text)
                    }
                }
                Rectangle {
                    implicitWidth: 34; implicitHeight: 34; radius: Atelier.radiusLg
                    color: delMa.containsMouse ? Qt.alpha(Atelier.red, 0.22) : Atelier.containerHigh
                    Text { anchors.centerIn: parent; text: "󰆴"; font.family: Atelier.font; font.pixelSize: Atelier.iconSm; color: delMa.containsMouse ? Atelier.red : Atelier.subtext }
                    MouseArea { id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.removePinned(appRow.index) }
                }
            }
        }
        Chip { Layout.topMargin: 8; Layout.bottomMargin: 12; icon: "󰐕"; text: "Add app"; tint: Atelier.accent; interactive: true; implicitHeight: 32; onClicked: win.addPinned() }
    }
}
