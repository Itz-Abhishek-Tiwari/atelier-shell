import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// Settings → Desktop (widget).
ColumnLayout {
    required property var win
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
                radius: Atelier.radiusSm
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
                    color: !parent.selected ? Atelier.subtext
                        : Settings.widgets.clockColor.startsWith("#") ? Settings.widgets.clockColor
                        : Atelier[Settings.widgets.clockColor] !== undefined ? Atelier[Settings.widgets.clockColor] : Atelier.text
                }
            }
        }
        SettingChoice { label: "Weight"
            options: [{ id: "thin", label: "Thin" }, { id: "light", label: "Light" }, { id: "regular", label: "Regular" }, { id: "bold", label: "Bold" }]
            value: Settings.widgets.clockWeight; onPicked: (id) => Settings.widgets.clockWeight = id }
        SettingSlider { label: "Size"; from: 64; to: 220; step: 4; suffix: " px"
            value: Settings.widgets.clockSize; onMoved: (v) => Settings.widgets.clockSize = Math.round(v) }
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
        title: "Colours"
        enabled: Settings.widgets.enabled; opacity: enabled ? 1 : 0.5
        SettingSwatches { label: "Clock"
            value: Settings.widgets.clockColor; onPicked: (id) => Settings.widgets.clockColor = id }
        SettingSwatches { label: "Date"
            value: Settings.widgets.dateColor; onPicked: (id) => Settings.widgets.dateColor = id }
        SettingSwatches { label: "Icons"; allowColourful: true
            value: Settings.widgets.glyphColor; onPicked: (id) => Settings.widgets.glyphColor = id }
    }

    SettingCard {
        title: "Glass"
        enabled: Settings.widgets.enabled; opacity: enabled ? 1 : 0.5
        SettingSwitch { label: "Glass clock"; description: "The digits turn to glass, the wallpaper blurred inside them (like iOS)"
            checked: Settings.widgets.glass; onToggled: (v) => Settings.widgets.glass = v }
        SettingSlider { visible: Settings.widgets.glass; label: "    Frost"; from: 10; to: 100; step: 5; suffix: "%"
            value: Math.round(Settings.widgets.glassBlur * 100); onMoved: (v) => Settings.widgets.glassBlur = v / 100 }
        SettingSlider { visible: Settings.widgets.glass; label: "    Colour"; description: "How much of the clock colour shows in the glass"; from: 0; to: 85; step: 5; suffix: "%"
            value: Math.round(Settings.widgets.glassTint * 100); onMoved: (v) => Settings.widgets.glassTint = v / 100 }
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
