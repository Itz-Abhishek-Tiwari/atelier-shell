import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// Software: find apps in the Arch repos and the AUR, install them, and remove what you installed.
// The same data and actions as Settings → Install & remove (services/Packages.qml). Installing and
// removing open a terminal: sudo / yay ask for the password there and pacman shows what will change.
// Open: IPC `software toggle|open|close` · launcher "Software".
Item {
    id: root
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool isLight: Atelier.isLight
    property bool animActive: false
    property double openedAt: 0
    property string tab: "find"               // find | installed
    property string filter: "apps"            // installed tab: apps | aur | all
    property string localQuery: ""
    property int showCount: 40

    signal closedSignal()

    readonly property var installedShown: {
        const q = localQuery.trim().toLowerCase();
        return Packages.installed.filter(p => (filter === "all" || (filter === "apps" ? p.app !== "" : p.aur))
            && (!q || (p.name + " " + p.app + " " + p.desc).toLowerCase().includes(q)));
    }
    readonly property string status: tab === "find"
        ? (!Packages.searched ? "Install apps from the Arch repos and the AUR"
           : Packages.searchingRepo ? "Searching…"
           : Packages.hits.length === 0 && Packages.searchingAur ? "Searching the AUR…"
           : Packages.hits.length === 0 ? "Nothing found for “" + findIn.text.trim() + "”"
           : Packages.hits.length + (Packages.hits.length === 1 ? " result" : " results") + (Packages.searchingAur ? " · still searching the AUR…" : ""))
        : (Packages.loadingInstalled && Packages.installed.length === 0 ? "Loading…"
           : installedShown.length + (filter === "apps" ? " apps" : " packages"))

    function toggle() { if (visible && animActive) close(); else open(); }
    function open() {
        visible = true;
        animActive = true;
        openedAt = Date.now();
        Packages.ensureReady();
        focusTimer.restart();
    }
    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }
    function setTab(t) { tab = t; showCount = 40; focusTimer.restart(); }

    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!root.animActive) root.visible = false }
    Timer { id: focusTimer; interval: 60; onTriggered: (root.tab === "find" ? findIn : listKeys).forceActiveFocus() }
    Timer { id: debounce; interval: 450; onTriggered: Packages.search(findIn.text) }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    EdgeDrawer {
        id: drawer
        edge: "bottom"
        open: root.animActive
        bodyWidth: Math.min(root.width - 160, 760)
        bodyHeight: Math.min(root.height - 120, 640)

        MouseArea { anchors.fill: parent }   // clicks inside don't close

        Item {
            id: listKeys
            anchors.fill: parent
            focus: true
            Keys.onPressed: (e) => {
                if (e.isAutoRepeat && Date.now() - root.openedAt < 350) { e.accepted = true; return; }
                if (e.key === Qt.Key_Escape) root.close();
                else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Slash) root.setTab(root.tab === "find" ? "installed" : "find");
                else return;
                e.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                DrawerTitle {
                    Layout.fillWidth: true
                    icon: "󰏖"; tint: Atelier.green; title: "Software"
                    subtitle: root.status
                }
                // updates waiting: opens the terminal with the system update
                Chip {
                    visible: Updates.count > 0
                    icon: "󰚰"; text: Updates.count + (Updates.count === 1 ? " update" : " updates")
                    tint: Atelier.peach; interactive: true; implicitHeight: 32
                    onClicked: Updates.run()
                }
                // tabs: a pill track with a sliding highlight
                Rectangle {
                    id: tabs
                    implicitWidth: 2 * 124 + 8; implicitHeight: 38; radius: height / 2
                    color: Atelier.container
                    border.width: 1; border.color: Atelier.outline
                    Rectangle {
                        y: 4; height: parent.height - 8; width: 124; radius: height / 2
                        x: 4 + (root.tab === "find" ? 0 : 124)
                        color: Atelier.accentFill
                        Behavior on x { Anim { type: "spatial" } }
                    }
                    Row {
                        x: 4; y: 4
                        Repeater {
                            model: [{ id: "find", label: "Discover", icon: "󰍉" }, { id: "installed", label: "Installed", icon: "󰄬" }]
                            Item {
                                id: tb
                                required property var modelData
                                readonly property bool on: root.tab === modelData.id
                                width: 124; height: tabs.height - 8
                                Row {
                                    anchors.centerIn: parent; spacing: 7
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: tb.modelData.icon
                                           font.family: Atelier.font; font.pixelSize: Atelier.fsLg
                                           color: tb.on ? Atelier.onFill : Atelier.subtext
                                           Behavior on color { CAnim {} } }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: tb.modelData.label
                                           font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold
                                           color: tb.on ? Atelier.onFill : Atelier.text
                                           Behavior on color { CAnim {} } }
                                    Text { visible: tb.modelData.id === "installed" && Packages.installed.length > 0
                                           anchors.verticalCenter: parent.verticalCenter; text: Packages.installed.length
                                           font.family: Atelier.font; font.pixelSize: Atelier.fsMicro
                                           color: tb.on ? Qt.alpha(Atelier.onFill, 0.7) : Atelier.subtext }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setTab(tb.modelData.id) }
                            }
                        }
                    }
                }
                IconButton { accessibleLabel: "Refresh packages"; icon: "󰑐"; size: 36; glyphSize: 15; onClicked: Packages.refresh() }
            }

            // Find: the search field
            Rectangle {
                visible: root.tab === "find"
                Layout.fillWidth: true
                implicitHeight: 44; radius: height / 2
                color: Atelier.containerHigh
                border.width: 1
                border.color: findIn.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                Text { id: fGlyph; x: 18; anchors.verticalCenter: parent.verticalCenter; text: "󰍉"
                    font.family: Atelier.font; font.pixelSize: Atelier.fsXl; color: Atelier.subtext }
                TextInput {
                    id: findIn
                    anchors.left: fGlyph.right; anchors.leftMargin: 10
                    anchors.right: parent.right; anchors.rightMargin: findIn.text !== "" ? 44 : 18
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: Atelier.text
                    clip: true; selectByMouse: true; maximumLength: 60
                    text: Packages.query
                    onTextChanged: debounce.restart()
                    onAccepted: { debounce.stop(); Packages.search(text); }
                    Keys.onEscapePressed: (e) => { if (text) { text = ""; } else root.close(); e.accepted = true; }
                    Keys.onTabPressed: (e) => { root.setTab("installed"); e.accepted = true; }
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: !findIn.text
                        text: Packages.helper ? "Search apps in the Arch repos and the AUR" : "Search apps in the Arch repos"
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: Atelier.subtext; opacity: 0.7 }
                }
                IconButton {
                    id: clearBtn
                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    visible: findIn.text !== ""
                    icon: "󰅖"; size: 28; glyphSize: 13
                    onClicked: { findIn.text = ""; findIn.forceActiveFocus(); }
                }
            }

            // Installed: filters
            RowLayout {
                visible: root.tab === "installed"
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [{ id: "apps", label: "Apps", icon: "󰀻" }, { id: "aur", label: "From the AUR", icon: "󰣇" }, { id: "all", label: "Everything", icon: "󰏖" }]
                    ChoicePill {
                        required property var modelData
                        icon: modelData.icon; label: modelData.label
                        on: root.filter === modelData.id
                        onClicked: { root.filter = modelData.id; root.showCount = 40; }
                    }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: 200; implicitHeight: 30; radius: height / 2
                    color: Atelier.containerHigh
                    border.width: 1
                    border.color: fIn.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                    TextInput {
                        id: fIn
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                        verticalAlignment: Text.AlignVCenter
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.text
                        clip: true; selectByMouse: true
                        onTextChanged: { root.localQuery = text; root.showCount = 40; }
                        Keys.onEscapePressed: (e) => { if (text) text = ""; else root.close(); e.accepted = true; }
                        Text { anchors.verticalCenter: parent.verticalCenter; visible: !fIn.text; text: "Filter"
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext; opacity: 0.6 }
                    }
                }
            }

            Panel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                readonly property bool discover: root.tab === "find" && !Packages.searched

                EmptyState {
                    anchors.centerIn: parent
                    visible: !parent.discover && (root.tab === "find" ? (Packages.hits.length === 0 && !Packages.searchingRepo && !Packages.searchingAur)
                                                 : root.installedShown.length === 0 && !Packages.loadingInstalled)
                    icon: "󰏖"; text: "Nothing here"
                }

                // ── Discover: browse by kind, then popular apps ──
                Flickable {
                    id: disc
                    visible: parent.discover
                    anchors.fill: parent
                    anchors.margins: 3
                    contentHeight: dcol.implicitHeight + 24
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    SmoothWheel { flickable: disc }
                    ColumnLayout {
                        id: dcol
                        x: 16; y: 14
                        width: disc.width - 32
                        spacing: 12
                        SmallCaps { text: "Browse" }
                        Grid {
                            Layout.fillWidth: true
                            columns: 4; spacing: 8
                            readonly property real tileW: (width - 3 * spacing) / 4
                            Repeater {
                                model: Packages.categories
                                Rectangle {
                                    id: tile
                                    required property var modelData
                                    readonly property color hue: Atelier[modelData.tint] !== undefined ? Atelier[modelData.tint] : Atelier.accent
                                    width: parent.tileW; height: 58
                                    radius: Atelier.radiusMd
                                    color: tMa.containsMouse ? Qt.alpha(hue, 0.16) : Atelier.container
                                    border.width: 1
                                    border.color: tMa.containsMouse ? Qt.alpha(hue, 0.45) : Atelier.outline
                                    scale: tMa.pressed ? 0.97 : 1
                                    Behavior on color { CAnim {} }
                                    Behavior on scale { Anim { type: "fastSpatial" } }
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left; anchors.leftMargin: 12
                                        spacing: 10
                                        Rectangle {
                                            width: 34; height: 34; radius: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: Qt.alpha(tile.hue, 0.16)
                                            Text { anchors.centerIn: parent; text: tile.modelData.icon
                                                   font.family: Atelier.font; font.pixelSize: 17; color: tile.hue }
                                        }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: tile.modelData.label
                                               font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold
                                               color: Atelier.text }
                                    }
                                    MouseArea { id: tMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { findIn.text = tile.modelData.q; debounce.stop(); Packages.search(tile.modelData.q); } }
                                }
                            }
                        }
                        SmallCaps { Layout.topMargin: 6; text: "Popular"; visible: Packages.featured.length > 0 }
                        Repeater {
                            model: Packages.featured
                            PackageRow {
                                required property var modelData
                                required property int index
                                first: index === 0
                                pkg: modelData
                                title: modelData.name
                                subtitle: modelData.desc
                                meta: modelData.version
                                sourceLabel: modelData.repo
                                isInstalled: modelData.installed
                            }
                        }
                    }
                }

                // ── Results / installed list ──
                Flickable {
                    id: flick
                    visible: !parent.discover
                    anchors.fill: parent
                    anchors.margins: 3
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    contentHeight: col.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    SmoothWheel { flickable: flick }
                    ColumnLayout {
                        id: col
                        width: flick.width
                        spacing: 0
                        Repeater {
                            model: root.tab === "find" ? Packages.hits.slice(0, 50) : root.installedShown.slice(0, root.showCount)
                            PackageRow {
                                required property var modelData
                                required property int index
                                first: index === 0
                                pkg: modelData
                                readonly property bool inst: root.tab === "installed"
                                title: inst ? (modelData.app || modelData.name) : modelData.name
                                subtitle: modelData.desc
                                meta: inst ? (modelData.app ? modelData.name + " · " : "") + modelData.version + (modelData.size ? " · " + modelData.size : "")
                                          : modelData.version
                                glyph: modelData.aur ? "󰣇" : "󰏖"
                                glyphTint: modelData.aur ? Atelier.sapphire : Atelier.blue
                                sourceLabel: modelData.aur ? (modelData.outdated ? "AUR · out of date" : "AUR") : (inst ? "" : modelData.repo)
                                sourceTint: modelData.aur ? (modelData.outdated ? Atelier.peach : Atelier.sapphire) : Atelier.blue
                                isInstalled: inst || modelData.installed
                            }
                        }
                        Chip {
                            visible: root.tab === "installed" && root.installedShown.length > root.showCount
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 8; Layout.bottomMargin: 10
                            icon: "󰅀"; text: "Show " + Math.min(40, root.installedShown.length - root.showCount) + " more"
                            interactive: true; implicitHeight: 28; tint: Atelier.subtext
                            onClicked: root.showCount += 40
                        }
                    }
                }
            }
            HintLine { Layout.fillWidth: true; text: "Tab  Find / Installed   ·   Enter  search   ·   Esc  close   ·   installs open in a terminal" }
        }
    }
}
