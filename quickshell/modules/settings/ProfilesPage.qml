import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config
import qs.services

// Settings → Profiles: save everything (all settings + theme + wallpaper) under a name, switch
// between them, back them up as one file, and switch automatically when a display is plugged in.
ColumnLayout {
    id: page
    Layout.fillWidth: true
    spacing: 20

    onVisibleChanged: if (visible) Profiles.refresh()

    property string newName: ""
    property string note: ""
    property string confirmDelete: ""
    Timer { id: noteTimer; interval: 4000; onTriggered: page.note = "" }
    Timer { id: delTimer; interval: 4000; onTriggered: page.confirmDelete = "" }
    function say(t) { note = t; noteTimer.restart(); }
    Connections {
        target: Profiles
        function onImported(name, ok) { page.say(ok ? "Imported “" + name + "”" : "That file isn't a profile or settings.json"); }
    }

    function when(iso) {
        const d = new Date(iso);
        if (isNaN(d)) return "";
        return d.toLocaleDateString(Qt.locale(), "d MMM yyyy") + ", " + (Atelier.clock24 ? d.toLocaleTimeString(Qt.locale(), "HH:mm")
            : Atelier.hour12(d) + ":" + String(d.getMinutes()).padStart(2, "0") + " " + Atelier.ampm(d));
    }
    // every output we know of: connected now, or configured in Displays
    readonly property var knownOutputs: {
        const s = Profiles.outputs.slice();
        for (const m of (Settings.displays.monitors || [])) if (m.output && s.indexOf(m.output) < 0) s.push(m.output);
        for (const r of Profiles.auto.rules) if (s.indexOf(r.output) < 0) s.push(r.output);
        return s;
    }
    function ruleFor(name) { const r = Profiles.auto.rules.find(x => x.profile === name); return r ? r.output : ""; }
    function setRule(name, output) {
        const rules = Profiles.auto.rules.filter(r => r.profile !== name && (!output || r.output !== output));
        if (output) rules.push({ output: output, profile: name });
        Profiles.setAuto(Profiles.auto.enabled || !!output, rules, Profiles.auto.fallback === name && output ? "" : Profiles.auto.fallback);
    }

    // ── save ────────────────────────────────────────────────────────────────
    SettingCard {
        title: "Save the current setup"
        SettingRow {
            label: "New profile"
            description: "All settings, the theme and the wallpaper, as they are now"
            RowLayout {
                spacing: 8
                Rectangle {
                    implicitWidth: 180; implicitHeight: 34; radius: Atelier.radiusLg
                    color: Atelier.containerHigh
                    border.width: 1
                    border.color: nameIn.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                    TextInput {
                        id: nameIn
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                        verticalAlignment: Text.AlignVCenter
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.text
                        clip: true; selectByMouse: true
                        maximumLength: 40
                        onTextChanged: page.newName = text
                        onAccepted: saveChip.clicked()
                        Text { anchors.verticalCenter: parent.verticalCenter; visible: !nameIn.text; text: "e.g. Docked"
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext; opacity: 0.6 }
                    }
                }
                Chip {
                    id: saveChip
                    icon: "󰆓"; text: "Save"; tint: Atelier.accent; implicitHeight: 32
                    interactive: Profiles.safe(page.newName) !== ""
                    opacity: interactive ? 1 : 0.4
                    onClicked: {
                        const n = Profiles.save(page.newName);
                        if (!n) return;
                        page.say(Profiles.list.some(p => p.name === n) ? "Updated “" + n + "”" : "Saved “" + n + "”");
                        nameIn.text = "";
                    }
                }
            }
        }
        SettingRow {
            visible: page.note !== ""
            label: page.note
        }
    }

    // ── the profiles ────────────────────────────────────────────────────────
    SettingCard {
        title: "Profiles"
        Text {
            visible: Profiles.list.length === 0
            Layout.topMargin: 14; Layout.bottomMargin: 14
            text: "No profiles yet. Save one above, e.g. “Laptop” and “Docked”."
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
        }
        Repeater {
            model: Profiles.list
            Item {
                id: pr
                required property var modelData
                required property int index
                readonly property bool isActive: Profiles.active === modelData.name
                Layout.fillWidth: true
                implicitHeight: col.implicitHeight + 24
                Rectangle { visible: pr.index > 0; width: parent.width; height: 1; color: Atelier.outline }
                ColumnLayout {
                    id: col
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Rectangle {
                            implicitWidth: 34; implicitHeight: 34; radius: Atelier.radiusSm
                            color: pr.isActive ? Atelier.accentFill : Qt.alpha(Atelier.accent, 0.14)
                            Text { anchors.centerIn: parent; text: page.ruleFor(pr.modelData.name) ? "󰍹" : "󰒓"
                                font.family: Atelier.font; font.pixelSize: Atelier.fsXl; color: pr.isActive ? Atelier.onFill : Atelier.accent }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text { text: pr.modelData.name + (pr.isActive ? "  ·  in use" : ""); elide: Text.ElideRight; Layout.fillWidth: true
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.Medium; color: Atelier.text }
                            Text {
                                Layout.fillWidth: true; elide: Text.ElideRight
                                text: [page.when(pr.modelData.saved), pr.modelData.theme, pr.modelData.wallpaper ? pr.modelData.wallpaper.split("/").pop() : ""]
                                    .filter(x => x).join(" · ")
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
                            }
                        }
                        Chip { icon: "󰄬"; text: "Use"; tint: Atelier.green; interactive: true; implicitHeight: 30
                            onClicked: { Profiles.apply(pr.modelData.name); page.say("Switched to “" + pr.modelData.name + "”"); } }
                        Chip { icon: "󰆓"; tint: Atelier.accent; interactive: true; implicitHeight: 30
                            onClicked: { Profiles.save(pr.modelData.name); page.say("Updated “" + pr.modelData.name + "” with the current setup"); } }
                        Chip { icon: "󰈝"; tint: Atelier.lavender; interactive: true; implicitHeight: 30
                            onClicked: {
                                const path = "~/atelier-profile-" + pr.modelData.name.replace(/ /g, "-") + ".json";
                                Profiles.exportTo(pr.modelData.name, path);
                                page.say("Exported to " + path);
                            } }
                        Chip { icon: "󰆴"; text: page.confirmDelete === pr.modelData.name ? "Delete?" : ""; tint: Atelier.red; interactive: true; implicitHeight: 30
                            onClicked: {
                                if (page.confirmDelete === pr.modelData.name) { Profiles.remove(pr.modelData.name); page.confirmDelete = ""; }
                                else { page.confirmDelete = pr.modelData.name; delTimer.restart(); }
                            } }
                    }
                    SettingChoice {
                        visible: page.knownOutputs.length > 0
                        label: "Use automatically when connected"
                        options: [{ id: "", label: "Never" }].concat(page.knownOutputs.map(o => ({ id: o, label: o })))
                        value: page.ruleFor(pr.modelData.name)
                        onPicked: (id) => page.setRule(pr.modelData.name, id)
                    }
                }
            }
        }
    }

    // ── hot-plug ────────────────────────────────────────────────────────────
    SettingCard {
        visible: Profiles.list.length > 0
        title: "Switch automatically"
        SettingSwitch {
            label: "Follow the displays"
            description: "When a display above is plugged in, use its profile. Takes effect at the next plug or unplug."
            checked: Profiles.auto.enabled
            onToggled: (v) => Profiles.setAuto(v, Profiles.auto.rules, Profiles.auto.fallback)
        }
        SettingChoice {
            visible: Profiles.auto.enabled
            label: "Otherwise use"
            description: "When none of those displays is connected"
            options: [{ id: "", label: "Keep as is" }].concat(Profiles.list.filter(p => !page.ruleFor(p.name)).map(p => ({ id: p.name, label: p.name })))
            value: Profiles.auto.fallback
            onPicked: (id) => Profiles.setAuto(true, Profiles.auto.rules, id)
        }
    }

    // ── import ──────────────────────────────────────────────────────────────
    SettingCard {
        title: "Backup"
        SettingField {
            label: "Import a profile"
            description: "A file exported here, or any settings.json"
            placeholder: "~/atelier-profile-Docked.json"
            fieldWidth: 260
            onCommitted: (t) => { if (t.trim()) Profiles.importFrom(t.trim()); }
        }
        SettingRow {
            label: "Profiles folder"
            description: Profiles.dir
            Chip { icon: "󰉋"; text: "Open"; tint: Atelier.lavender; interactive: true; implicitHeight: 32
                onClicked: Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && xdg-open "$1"', "sh", Profiles.dir]) }
        }
    }
}
