import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.components
import qs.config

// Settings → Install & remove: find apps in the Arch repos and the AUR, install them, and
// remove what you installed. Data from scripts/packages.py (read-only). Installing and removing
// run in the terminal (Settings.behavior.terminal): sudo / yay ask for the password there and
// pacman shows exactly what will change before you confirm. The lists refresh on return.
ColumnLayout {
    id: page
    required property var win
    Layout.fillWidth: true
    spacing: 20

    readonly property string script: Quickshell.shellDir + "/scripts/packages.py"
    readonly property bool shown: win.visible && win.page === "installer"

    property string query: ""
    property var repoHits: []
    property var aurHits: []
    property bool searchingRepo: false
    property bool searchingAur: false
    property bool searched: false
    property string helper: ""                // yay | paru | "" (no AUR without one)

    property var installed: []
    property bool loadingInstalled: false
    property string filter: "apps"            // apps | all | aur
    property string localQuery: ""
    property int showCount: 30

    property string busy: ""                  // just sent to the terminal (a few seconds of feedback)
    property string confirmRemove: ""         // second click removes

    readonly property var hits: {
        // repo first (official, signed), then the AUR; one entry per name
        const seen = {}, out = [];
        for (const p of repoHits.concat(aurHits)) { if (!seen[p.name]) { seen[p.name] = true; out.push(p); } }
        return out;
    }
    readonly property var installedShown: {
        const q = localQuery.trim().toLowerCase();
        return installed.filter(p => (filter === "all" || (filter === "apps" ? p.app !== "" : p.aur))
            && (!q || (p.name + " " + p.app + " " + p.desc).toLowerCase().includes(q)));
    }

    function validName(n) { return /^[a-z0-9@._+-]+$/.test(n); }
    function runSearch() {
        const q = page.query.trim();
        if (q.length < 2) { repoHits = []; aurHits = []; searched = false; return; }
        const words = q.split(/\s+/).slice(0, 4);
        searched = true;
        repoProc.running = false; aurProc.running = false;
        repoProc.command = ["python3", "-I", script, "search"].concat(words);
        searchingRepo = true; repoProc.running = true;
        if (helper) {
            aurProc.command = ["python3", "-I", script, "aur"].concat(words);
            searchingAur = true; aurProc.running = true;
        }
    }
    function refreshInstalled() { loadingInstalled = true; instProc.running = true; }
    // install / remove in a terminal, fully detached: the Settings drawer closes when the
    // terminal maps and may be unloaded later, and that must never kill a running pacman.
    // The lists refresh when you come back to this page.
    function act(pkg, remove) {
        if (!validName(pkg.name)) return;
        const tail = "; echo; printf 'Done. Press Enter to close… '; read _";
        const cmd = remove ? "sudo pacman -Rns " + pkg.name
                  : pkg.aur ? helper + " -S --needed " + pkg.name
                  : "sudo pacman -S --needed " + pkg.name;
        page.busy = pkg.name;
        page.confirmRemove = "";
        busyReset.restart();
        Quickshell.execDetached([Settings.behavior.terminal || "kitty", "-e", "sh", "-c", cmd + tail]);
    }

    onShownChanged: if (shown) {
        if (!helperProc.ran) helperProc.running = true;
        refreshInstalled();
        if (searched) runSearch();             // fresh Installed marks after a terminal run
    }

    Timer { id: debounce; interval: 450; onTriggered: page.runSearch() }
    Timer { id: confirmReset; interval: 4000; onTriggered: page.confirmRemove = "" }
    Timer { id: busyReset; interval: 6000; onTriggered: page.busy = "" }

    Process {
        id: helperProc
        property bool ran: false
        command: ["python3", "-I", page.script, "helper"]
        stdout: StdioCollector { onStreamFinished: { page.helper = text.trim(); helperProc.ran = true; } }
    }
    Process {
        id: repoProc
        stdout: StdioCollector {
            onStreamFinished: { try { page.repoHits = JSON.parse(text); } catch (e) { page.repoHits = []; } page.searchingRepo = false; }
        }
    }
    Process {
        id: aurProc
        stdout: StdioCollector {
            onStreamFinished: { try { page.aurHits = JSON.parse(text); } catch (e) { page.aurHits = []; } page.searchingAur = false; }
        }
    }
    Process {
        id: instProc
        command: ["python3", "-I", page.script, "installed"]
        stdout: StdioCollector {
            onStreamFinished: { try { page.installed = JSON.parse(text); } catch (e) { console.warn("packages:", e); } page.loadingInstalled = false; }
        }
    }
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
                    onTextChanged: { page.query = text; debounce.restart(); }
                    onAccepted: { debounce.stop(); page.runSearch(); }
                    Keys.onEscapePressed: (e) => { if (text) { text = ""; e.accepted = true; } else e.accepted = false; }
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: !qIn.text
                        text: page.helper ? "Search apps in the Arch repos and the AUR" : "Search apps in the Arch repos"
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: Atelier.subtext; opacity: 0.7 }
                }
            }
        }
        // status line
        Text {
            Layout.fillWidth: true
            Layout.bottomMargin: 10
            visible: text !== ""
            text: !page.searched ? ""
                : page.searchingRepo ? "Searching…"
                : page.hits.length === 0 && page.searchingAur ? "Searching the AUR…"
                : page.hits.length === 0 ? "Nothing found for “" + page.query.trim() + "”"
                : page.hits.length + (page.hits.length === 1 ? " result" : " results") + (page.searchingAur ? " · still searching the AUR…" : "")
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
        }
        Repeater {
            model: page.hits.slice(0, 40)
            PkgRow {
                required property var modelData
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
        Item { Layout.fillWidth: true; implicitHeight: 4; visible: page.searched }
    }

    Text {
        visible: page.helper === "" && helperProc.ran
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
            text: page.loadingInstalled && page.installed.length === 0 ? "Loading…"
                : page.installedShown.length === 0 ? "Nothing here"
                : page.installedShown.length + (page.filter === "apps" ? " apps" : " packages")
                  + (page.filter === "apps" ? " · libraries and tools without a launcher are under All packages" : "")
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
            elide: Text.ElideRight
        }
        Repeater {
            model: page.installedShown.slice(0, page.showCount)
            PkgRow {
                required property var modelData
                pkg: modelData
                title: modelData.app || modelData.name
                subtitle: modelData.desc
                meta: (modelData.app ? modelData.name + " · " : "") + modelData.version + (modelData.size ? " · " + modelData.size : "")
                icon: modelData.icon
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

    // one package: icon/glyph · name, source chip, description, version · the action
    component PkgRow: Item {
        id: row
        property var pkg
        property string title
        property string subtitle
        property string meta
        property string icon: ""
        property string glyph: "󰏖"
        property color glyphTint: Atelier.blue
        property string sourceLabel: ""
        property color sourceTint: Atelier.blue
        property bool isInstalled: false
        readonly property bool working: page.busy === (pkg ? pkg.name : "")
        readonly property bool confirming: page.confirmRemove === (pkg ? pkg.name : "")

        Layout.fillWidth: true
        implicitHeight: 64

        Rectangle { visible: row.y > 1; anchors.top: parent.top; width: parent.width; height: 1; color: Atelier.outline }

        RowLayout {
            anchors.fill: parent
            spacing: 12
            Item {
                implicitWidth: 36; implicitHeight: 36
                IconImage {
                    id: appIcon
                    anchors.fill: parent
                    visible: row.icon !== "" && status === Image.Ready
                    source: row.icon === "" ? "" : row.icon.startsWith("/") ? "file://" + row.icon : Quickshell.iconPath(row.icon, true)
                    asynchronous: true
                }
                Rectangle {
                    anchors.fill: parent
                    visible: !appIcon.visible
                    radius: Atelier.radiusSm
                    color: Qt.alpha(row.glyphTint, 0.14)
                    border.width: 1; border.color: Qt.alpha(row.glyphTint, 0.3)
                    Text { anchors.centerIn: parent; text: row.glyph; font.family: Atelier.font; font.pixelSize: 18; color: row.glyphTint }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text { text: row.title; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold
                        color: Atelier.text; elide: Text.ElideRight; Layout.maximumWidth: 260 }
                    Chip { visible: row.sourceLabel !== ""; text: row.sourceLabel; tint: row.sourceTint; implicitHeight: 20; pad: 7 }
                    Text { Layout.fillWidth: true; text: row.meta; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                        color: Atelier.subtext; elide: Text.ElideRight }
                }
                Text { Layout.fillWidth: true; visible: text !== ""; text: row.subtitle
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext1; elide: Text.ElideRight }
            }
            // action
            Chip {
                visible: row.working
                icon: "󰆍"; text: "Opened in terminal"; tint: Atelier.peach; implicitHeight: 28
            }
            Chip {
                visible: !row.working && row.isInstalled && !row.pkg.protected
                icon: row.confirming ? "󰆴" : "󰩹"
                text: row.confirming ? "Remove?" : "Remove"
                tint: Atelier.red; interactive: true; implicitHeight: 28
                onClicked: {
                    if (!row.confirming) { page.confirmRemove = row.pkg.name; confirmReset.restart(); }
                    else page.act(row.pkg, true);
                }
            }
            Chip {
                visible: !row.working && row.isInstalled && row.pkg.protected
                icon: "󰌾"; text: "System"; tint: Atelier.subtext; implicitHeight: 28
            }
            Chip {
                visible: !row.working && !row.isInstalled
                icon: "󰇚"; text: "Install"; tint: Atelier.green; interactive: true; implicitHeight: 28
                onClicked: page.act(row.pkg, false)
            }
        }
    }
}
