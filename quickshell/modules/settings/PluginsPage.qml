import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config
import qs.services

// Settings → Plugins: install, review, switch on/off and remove plugins from ~/.config/atelier/plugins.
ColumnLayout {
    id: page
    required property var win
    Layout.fillWidth: true
    spacing: 20

    // look for new folders whenever the page is opened
    readonly property bool shown: win.visible && win.page === "plugins"
    onShownChanged: if (shown) Plugins.reload()

    // "2 lock styles, a bar item …" from a plugin's manifest, so it is clear what switching it on adds
    function summary(p) {
        const names = { lockStyles: "lock style", desktopWidgets: "desktop widget", settingsPages: "settings page",
                        barItems: "bar item", launcherActions: "launcher action", controlTiles: "control-centre tile" };
        const parts = [];
        for (const k in names) if (p[k] && p[k].length) parts.push(p[k].length + " " + names[k] + (p[k].length > 1 ? "s" : ""));
        return parts.length ? "Adds " + parts.join(", ") : "Adds nothing";
    }

    SettingCard {
        title: "Plugins"; icon: "󰐱"; tint: Atelier.mauve
        SettingRow {
            label: "Your plugins folder"
            description: Plugins.dir + " — one folder per plugin, each with a plugin.json"
            RowLayout {
                spacing: 6
                Chip { icon: "󰉋"; text: "Open"; tint: Atelier.mauve; interactive: true; implicitHeight: 30; onClicked: Plugins.openFolder() }
                Chip { icon: "󰑐"; text: "Reload"; tint: Atelier.accent; interactive: true; implicitHeight: 30; onClicked: Plugins.reload() }
            }
        }
        SettingField {
            label: "Install a plugin"
            description: "A git URL, a .zip link or a folder on this computer. It stays off until you approve it below."
            placeholder: "https://github.com/…/my-plugin"
            fieldWidth: 320
            onCommitted: (t) => Plugins.install(t)
        }
        Text {
            visible: Plugins.status !== ""
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Plugins.status
            color: Plugins.status.indexOf("Failed") === 0 ? Atelier.red : Atelier.subtext
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd
        }
    }

    // not approved yet: show what it contains first
    SettingCard {
        title: "Needs your approval"; icon: "󰒃"; tint: Atelier.peach
        visible: pending.count > 0
        Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "A plugin is code that runs inside your shell, with your permissions. Read its files before you approve it. Editing a plugin's files asks for approval again."
            color: Atelier.subtext; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd
        }
        Repeater {
            id: pending
            model: Plugins.all.filter(p => !p.trusted)
            delegate: SettingRow {
                required property var modelData
                label: modelData.name + (modelData.version ? "  " + modelData.version : "")
                description: (modelData.error ? "Has a problem: " + modelData.error
                    : page.summary(modelData) + (modelData.author ? " · " + modelData.author : "")) + "  ·  " + modelData.dir
                RowLayout {
                    spacing: 6
                    Chip { icon: "󰈔"; text: "Review"; tint: Atelier.accent; interactive: true; implicitHeight: 30
                           onClicked: Quickshell.execDetached(["xdg-open", modelData.dir]) }
                    Chip { icon: "󰄬"; text: "Approve"; tint: Atelier.green; interactive: true; implicitHeight: 30
                           visible: !modelData.error; onClicked: Plugins.setEnabled(modelData.id, true) }
                    Chip { icon: "󰆴"; text: "Remove"; tint: Atelier.red; interactive: true; implicitHeight: 30
                           onClicked: Plugins.remove(modelData.id) }
                }
            }
        }
    }

    SettingCard {
        title: "Installed"; icon: "󰏓"; tint: Atelier.accent
        visible: installed.count > 0
        Repeater {
            id: installed
            model: Plugins.all.filter(p => p.trusted)
            delegate: SettingRow {
                required property var modelData
                readonly property string problem: modelData.error || Plugins.loadErrors[modelData.id] || ""
                label: modelData.name + (modelData.version ? "  " + modelData.version : "")
                description: problem ? "Problem: " + problem
                    : (modelData.description || page.summary(modelData)) + (modelData.author ? " · " + modelData.author : "")
                RowLayout {
                    spacing: 8
                    Chip { icon: "󰆴"; text: "Remove"; tint: Atelier.red; interactive: true; implicitHeight: 30
                           onClicked: Plugins.remove(modelData.id) }
                    ToggleSwitch { implicitWidth: 44; implicitHeight: 26; on: modelData.enabled
                                   onToggled: Plugins.setEnabled(modelData.id, !modelData.enabled) }
                }
            }
        }
    }

    Text {
        visible: Plugins.all.length === 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: "No plugins yet. Install one above, or copy a folder into the plugins folder and press Reload. See docs/plugins.md for how to write your own."
        color: Atelier.subtext; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd
    }
}
