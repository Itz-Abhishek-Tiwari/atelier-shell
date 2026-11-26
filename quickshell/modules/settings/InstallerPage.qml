import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config
import qs.services

// Settings → Install & remove: find apps in the Arch repos and the AUR, install them, and
// remove what you installed. The data and the actions live in services/Packages.qml (shared with the
// Software drawer). Installing and removing run in the terminal: sudo / yay ask for the password
// there and pacman shows exactly what will change before you confirm.
ColumnLayout {
    id: page
    required property var win
    Layout.fillWidth: true
    spacing: 20

    readonly property bool shown: win.visible && win.page === "installer"

    property string filter: "apps"            // apps | all | aur
    property string localQuery: ""
    property int showCount: 30

    readonly property var installedShown: {
        const q = localQuery.trim().toLowerCase();
        return Packages.installed.filter(p => (filter === "all" || (filter === "apps" ? p.app !== "" : p.aur))
            && (!q || (p.name + " " + p.app + " " + p.desc).toLowerCase().includes(q)));
    }

    onShownChanged: if (shown) Packages.ensureReady()

    Timer { id: debounce; interval: 450; onTriggered: Packages.search(qIn.text) }

    // ── Find ────────────────────────────────────────────────────────────────
    SettingCard {
        title: "Find apps"
        // search field
        Item {
            Layout.fillWidth: true
            implicitHeight: 58
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 38; radius: Atelier.radiusLg
                color: Atelier.containerHigh
                border.width: 1
                border.color: qIn.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                Text { id: qGlyph; x: 14; anchors.verticalCenter: parent.verticalCenter; text: "󰍉"
                    font.family: Atelier.font; font.pixelSize: Atelier.fsXl; color: Atelier.subtext }
                TextInput {
                    id: qIn
                    anchors.left: qGlyph.right; anchors.leftMargin: 10
                    anchors.right: parent.right; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: Atelier.text
                    clip: true; selectByMouse: true
                    maximumLength: 60
                    onTextChanged: debounce.restart()
                    onAccepted: { debounce.stop(); Packages.search(text); }
                    Keys.onEscapePressed: (e) => { if (text) { text = ""; e.accepted = true; } else e.accepted = false; }
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: !qIn.text
                        text: Packages.helper ? "Search apps in the Arch repos and the AUR" : "Search apps in the Arch repos"
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: Atelier.subtext; opacity: 0.7 }
                }
            }
        }
        // status line
        Text {
            Layout.fillWidth: true
            Layout.bottomMargin: 10
            visible: text !== ""
            text: !Packages.searched ? ""
                : Packages.searchingRepo ? "Searching…"
                : Packages.hits.length === 0 && Packages.searchingAur ? "Searching the AUR…"
                : Packages.hits.length === 0 ? "Nothing found for “" + qIn.text.trim() + "”"
                : Packages.hits.length + (Packages.hits.length === 1 ? " result" : " results") + (Packages.searchingAur ? " · still searching the AUR…" : "")
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
        }
        Repeater {
            model: Packages.hits.slice(0, 40)
            PackageRow {
                required property var modelData
                required property int index
                first: index === 0
                pkg: modelData
                title: modelData.name
                subtitle: modelData.desc
                meta: modelData.version
                glyph: modelData.aur ? "󰣇" : "󰏖"
                glyphTint: modelData.aur ? Atelier.sapphire : Atelier.blue
                sourceLabel: modelData.aur ? (modelData.outdated ? "AUR · out of date" : "AUR") : modelData.repo
                sourceTint: modelData.aur ? (modelData.outdated ? Atelier.peach : Atelier.sapphire) : Atelier.blue
                isInstalled: modelData.installed
            }
        }
        Item { Layout.fillWidth: true; implicitHeight: 4; visible: Packages.searched }
    }

    Text {
        visible: Packages.helper === "" && Packages.helperChecked
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.topMargin: -12
        wrapMode: Text.WordWrap
        text: "AUR search is off: no AUR helper found (install yay or paru)."
        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
    }

    // ── Installed ───────────────────────────────────────────────────────────
    SettingCard {
        title: "Installed by you"
        Item {
            Layout.fillWidth: true
            implicitHeight: 54
            RowLayout {
                anchors.fill: parent
                spacing: 6
                Repeater {
                    model: [{ id: "apps", label: "Apps" }, { id: "aur", label: "From the AUR" }, { id: "all", label: "All packages" }]
                    Chip {
                        required property var modelData
                        text: modelData.label
                        interactive: true
                        implicitHeight: 28
                        tint: page.filter === modelData.id ? Atelier.accent : Atelier.subtext
                        onClicked: { page.filter = modelData.id; page.showCount = 30; }
                    }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: 170; implicitHeight: 30; radius: Atelier.radiusLg
                    color: Atelier.containerHigh
                    border.width: 1
                    border.color: fIn.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                    TextInput {
                        id: fIn
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                        verticalAlignment: Text.AlignVCenter
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.text
                        clip: true; selectByMouse: true
                        onTextChanged: { page.localQuery = text; page.showCount = 30; }
                        Text { anchors.verticalCenter: parent.verticalCenter; visible: !fIn.text; text: "Filter"
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext; opacity: 0.6 }
                    }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            Layout.bottomMargin: 10
            text: Packages.loadingInstalled && Packages.installed.length === 0 ? "Loading…"
                : page.installedShown.length === 0 ? "Nothing here"
                : page.installedShown.length + (page.filter === "apps" ? " apps" : " packages")
                  + (page.filter === "apps" ? " · libraries and tools without a launcher are under All packages" : "")
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
            elide: Text.ElideRight
        }
        Repeater {
            model: page.installedShown.slice(0, page.showCount)
            PackageRow {
                required property var modelData
                required property int index
                first: index === 0
                pkg: modelData
                title: modelData.app || modelData.name
                subtitle: modelData.desc
                meta: (modelData.app ? modelData.name + " · " : "") + modelData.version + (modelData.size ? " · " + modelData.size : "")
                glyph: modelData.aur ? "󰣇" : "󰏖"
                glyphTint: modelData.aur ? Atelier.sapphire : Atelier.blue
                sourceLabel: modelData.aur ? "AUR" : ""
                sourceTint: Atelier.sapphire
                isInstalled: true
            }
        }
        Chip {
            visible: page.installedShown.length > page.showCount
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8; Layout.bottomMargin: 10
            icon: "󰅀"; text: "Show " + Math.min(30, page.installedShown.length - page.showCount) + " more"
            interactive: true; implicitHeight: 28; tint: Atelier.subtext
            onClicked: page.showCount += 30
        }
    }
}
