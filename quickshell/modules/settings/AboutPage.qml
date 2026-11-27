import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// Settings → About.
ColumnLayout {
    required property var win
    id: about
    property string version: ""
    Process { running: win.visible; command: ["quickshell", "--version"]
        stdout: StdioCollector { onStreamFinished: about.version = text.trim() } }
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
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext1 }
                    Text { text: (about.sys[1] || "") + " · Atelier desktop"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext }
                    Text { visible: !!about.sys[6]; text: "Up " + (about.sys[6] || ""); font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext; opacity: 0.8 }
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
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext1
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        }
                        Text {
                            Layout.alignment: Qt.AlignRight
                            Layout.maximumWidth: 420
                            visible: !!modelData[2]
                            text: hwRow.copied ? "Copied" : (modelData[2] || "")
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }
    }
    SettingCard {
        title: "Updates"; icon: "󰚰"; tint: Atelier.teal
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
