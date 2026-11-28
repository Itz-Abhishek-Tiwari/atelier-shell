import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// Settings → Storage.
ColumnLayout {
    required property var win
    id: storage
    Layout.fillWidth: true
    spacing: 20

    readonly property string script: Quickshell.shellDir + "/scripts/storage.py"
    readonly property string foldersScript: Quickshell.shellDir + "/scripts/home-folders.sh"
    property var d: ({})
    property bool scanning: false
    property var folders: []          // [{path, exists}]
    property string confirm: ""       // cleanup id waiting for a second click
    readonly property bool shown: win.visible && win.page === "storage"
    readonly property var cats: d.categories || []
    readonly property real used: d.used || 0
    readonly property real total: d.total || 1
    readonly property real counted: d.counted || 1
    readonly property var clean: d.cleanup || ({})
    onShownChanged: if (shown) { cachedProc.running = true; foldersProc.running = true; }

    function col(n) { return n === "overlay" ? Atelier.overlay1 : (Atelier[n] || Atelier.accent); }
    function scan() { if (!scanning) { scanning = true; scanProc.running = true; } }
    function openFolder(p) {
        Quickshell.execDetached(["sh", "-c", 'for fm in nautilus dolphin thunar; do command -v "$fm" >/dev/null && exec "$fm" "$1"; done; exec xdg-open "$1"', "sh", p]);
    }
    function ask(id, run) {
        if (confirm === id) { confirm = ""; run(); }
        else { confirm = id; confirmTimer.restart(); }
    }
    Timer { id: confirmTimer; interval: 4000; onTriggered: storage.confirm = "" }

    Process {
        id: cachedProc
        command: [storage.script, "cached"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const j = JSON.parse(text); if (j.categories) storage.d = j; } catch (e) {}
                // rescan when there is nothing yet or it is older than 10 minutes
                if (!storage.d.scannedAt || Date.now() / 1000 - storage.d.scannedAt > 600) storage.scan();
            }
        }
    }
    Process {
        id: scanProc
        command: [storage.script, "scan"]
        stdout: StdioCollector {
            onStreamFinished: { try { const j = JSON.parse(text); if (j.categories) storage.d = j; } catch (e) {} }
        }
        onExited: storage.scanning = false
    }
    Process {
        id: foldersProc
        command: [storage.foldersScript, "check"]
        stdout: StdioCollector {
            onStreamFinished: storage.folders = text.trim().split("\n").filter(l => l).map(l => { const p = l.split("|"); return { path: p[0], exists: p[1] === "1" }; })
        }
    }
    Process {
        id: cleanProc
        onExited: storage.scan()
    }
    function runClean(cmd) { cleanProc.command = ["sh", "-c", cmd]; cleanProc.running = true; }
    Process { id: makeFolders; command: [storage.foldersScript]; onExited: foldersProc.running = true }

    // ── Disk ──
    SettingCard {
        title: "Disk"; icon: "󰋊"; tint: Atelier.teal
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.bottomMargin: 14
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: storage.d.used ? Fmt.bytes(storage.used) : "…"; font.family: Atelier.font; font.pixelSize: 26; font.bold: true; color: Atelier.text }
                Text {
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 5
                    text: storage.d.total ? "of " + Fmt.bytes(storage.total) + " used" : "Measuring…"
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: Atelier.subtext
                }
                Item { Layout.fillWidth: true }
                Chip { visible: !!storage.d.free; icon: "󰄬"; text: Fmt.bytes(storage.d.free) + " free"; tint: Atelier.green }
            }

            // one bar for the whole disk; each category is its share of `used`
            ClippingRectangle {
                id: diskBar
                Layout.fillWidth: true
                implicitHeight: 14
                radius: 7
                color: Atelier.containerHigh
                Row {
                    height: parent.height
                    spacing: 2
                    Repeater {
                        model: storage.cats.filter(c => c.bytes > 0)
                        Rectangle {
                            required property var modelData
                            height: parent.height
                            width: Math.max(2, diskBar.width * (storage.used / storage.total) * modelData.bytes / Math.max(storage.counted, storage.used) - 2)
                            color: storage.col(modelData.color)
                            Behavior on width { Anim { type: "spatial" } }
                        }
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 14
                Repeater {
                    model: storage.cats.filter(c => c.bytes > 0)
                    Row {
                        required property var modelData
                        spacing: 6
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: storage.col(modelData.color) }
                        Text { text: modelData.label; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext1 }
                        Text { text: Fmt.bytes(modelData.bytes); font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: (storage.d.compressionSaved > 0
                            ? "Your files add up to " + Fmt.bytes(storage.counted) + "; btrfs compression saves about "
                              + Fmt.bytes(storage.d.compressionSaved) + ", so the bar shows each share of what is really used. "
                            : "")
                        + (storage.scanning ? "Scanning…" : storage.d.scannedAt ? "Scanned " + Fmt.ago(storage.d.scannedAt * 1000) + "." : "")
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
                }
                Chip {
                    icon: "󰑐"; text: storage.scanning ? "Scanning…" : "Rescan"; tint: Atelier.teal
                    interactive: !storage.scanning; implicitHeight: 30
                    onClicked: storage.scan()
                }
            }
        }
    }

    // ── One-click clean (scripts/cleanup.sh) ──
    SettingCard {
        id: quick
        title: "Clean up"
        property bool withPacman: false
        property bool ask: false              // waiting for the confirming click
        property string result: ""
        readonly property real safe: (storage.clean.trash || 0) + (storage.clean.aur || 0)
            + (storage.clean.thumbnails || 0) + (storage.clean.devcache || 0)
        readonly property real total: safe + (withPacman ? (storage.clean.pacman || 0) : 0)
        Timer { id: quickAsk; interval: 4000; onTriggered: quick.ask = false }
        Process {
            id: quickProc
            command: [Quickshell.shellDir + "/scripts/cleanup.sh"].concat(quick.withPacman ? ["--pacman"] : [])
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const r = JSON.parse(text);
                        quick.result = "Freed " + Fmt.bytes(r.freed)
                            + (r.pacman === "cancelled" ? " · package cache skipped (no password)" : "");
                    } catch (e) { quick.result = "Done"; }
                }
            }
            onExited: storage.scan()
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 92
            RowLayout {
                anchors.fill: parent
                spacing: 16
                Rectangle {
                    implicitWidth: 52; implicitHeight: 52; radius: Atelier.radiusMd
                    color: Qt.alpha(Atelier.accent, 0.16)
                    Text { anchors.centerIn: parent; text: "󰃢"; font.family: Atelier.font; font.pixelSize: Atelier.iconLg; color: Atelier.accent }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1      // shrink to the leftover width; don't push the button out
                    spacing: 3
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: quickProc.running ? "Cleaning…"
                            : quick.result ? quick.result
                            : storage.d.cleanup ? Fmt.bytes(quick.total) + " can be freed" : "Measuring…"
                        font.family: Atelier.fontUi; font.pixelSize: 18; font.weight: Font.Bold; color: Atelier.text
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "Trash, AUR build files, thumbnails and developer download caches (pip, npm, Go, pnpm, Cargo). They come back by themselves when needed."
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
                    }
                }
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.minimumWidth: implicitWidth
                    implicitWidth: cleanLabel.implicitWidth + 40
                    implicitHeight: 40
                    radius: Math.min(height / 2, Atelier.radiusSm)
                    readonly property bool can: !quickProc.running && !storage.scanning && quick.total > 0
                    opacity: can ? 1 : 0.45
                    color: quick.ask ? Atelier.fill(Atelier.red) : Atelier.fill(Atelier.accent)
                    Behavior on color { CAnim {} }
                    Text {
                        id: cleanLabel
                        anchors.centerIn: parent
                        text: quickProc.running ? "Cleaning…" : quick.ask ? "Click to confirm" : "Clean now"
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold; color: Atelier.onFill
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.can
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!quick.ask) { quick.ask = true; quick.result = ""; quickAsk.restart(); return; }
                            quick.ask = false; quickAsk.stop();
                            quickProc.running = true;
                        }
                    }
                }
            }
        }
        SettingSwitch {
            label: "Also empty the package cache · " + Fmt.bytes(storage.clean.pacman)
            description: "Every downloaded package in /var/cache/pacman/pkg. Asks for your password. Afterwards you can't roll back an update without internet."
            checked: quick.withPacman; onToggled: (v) => quick.withPacman = v
        }
    }

    // ── Categories ──
    SettingCard {
        title: "By category"; icon: "󰕮"; tint: Atelier.blue
        Repeater {
            model: storage.cats
            SettingRow {
                id: catRow
                required property var modelData
                label: modelData.label
                description: modelData.paths.join("  ·  ")
                RowLayout {
                    spacing: 10
                    Rectangle {
                        implicitWidth: 110; implicitHeight: 6; radius: 3
                        color: Qt.alpha(storage.col(catRow.modelData.color), 0.16)
                        Rectangle {
                            width: parent.width * Math.min(1, catRow.modelData.bytes / Math.max(1, storage.cats[0] ? storage.cats[0].bytes : 1))
                            height: parent.height; radius: parent.radius
                            color: storage.col(catRow.modelData.color)
                        }
                    }
                    Text {
                        Layout.preferredWidth: 64
                        horizontalAlignment: Text.AlignRight
                        text: Fmt.bytes(catRow.modelData.bytes)
                        font.family: Atelier.font; font.pixelSize: Atelier.fsMd; font.bold: true; color: Atelier.text
                    }
                    Chip {
                        icon: catRow.modelData.icon; text: "Open"; tint: storage.col(catRow.modelData.color)
                        interactive: catRow.modelData.open !== ""; opacity: catRow.modelData.open ? 1 : 0.35
                        implicitHeight: 28
                        onClicked: storage.openFolder(catRow.modelData.open)
                    }
                }
            }
        }
    }

    // ── Biggest folders ──
    SettingCard {
        title: "Biggest folders"; icon: "󰉋"; tint: Atelier.peach
        SettingRow {
            visible: (storage.d.biggest || []).length === 0
            label: storage.scanning ? "Scanning…" : "Nothing over 50 MB"
        }
        Repeater {
            model: storage.d.biggest || []
            SettingRow {
                id: bigRow
                required property var modelData
                label: modelData.name
                RowLayout {
                    spacing: 10
                    Text { text: Fmt.bytes(bigRow.modelData.bytes); font.family: Atelier.font; font.pixelSize: Atelier.fsMd; font.bold: true; color: Atelier.text }
                    Chip { icon: "󰉋"; text: "Open"; tint: Atelier.peach; interactive: true; implicitHeight: 28
                        onClicked: storage.openFolder(bigRow.modelData.path) }
                }
            }
        }
    }

    // ── Clean up ──
    SettingCard {
        title: "Clean one at a time"; icon: "󰃢"; tint: Atelier.yellow
        SettingRow {
            label: "Trash · " + Fmt.bytes(storage.clean.trash)
            description: "Files you deleted in the file manager"
            Chip {
                icon: "󰩹"; text: storage.confirm === "trash" ? "Click again to empty" : "Empty"
                tint: Atelier.red; interactive: storage.clean.trash > 0; opacity: storage.clean.trash > 0 ? 1 : 0.4
                implicitHeight: 28
                onClicked: storage.ask("trash", () => storage.runClean("gio trash --empty"))
            }
        }
        SettingRow {
            label: "AUR build files · " + Fmt.bytes(storage.clean.aur)
            description: "yay / paru keep every package they built in ~/.cache. Safe to delete; they download again when needed."
            Chip {
                icon: "󰃢"; text: storage.confirm === "aur" ? "Click again to clear" : "Clear"
                tint: Atelier.yellow; interactive: storage.clean.aur > 0; opacity: storage.clean.aur > 0 ? 1 : 0.4
                implicitHeight: 28
                onClicked: storage.ask("aur", () => storage.runClean('rm -rf "$HOME/.cache/yay" "$HOME/.cache/paru"'))
            }
        }
        SettingRow {
            label: "Package cache · " + Fmt.bytes(storage.clean.pacman)
            description: "Old versions of installed packages in /var/cache/pacman/pkg. Opens a terminal: sudo pacman -Sc"
            Chip {
                icon: "󰏗"; text: "Clean…"; tint: Atelier.yellow
                interactive: storage.clean.pacman > 0; opacity: storage.clean.pacman > 0 ? 1 : 0.4
                implicitHeight: 28
                onClicked: Quickshell.execDetached([Settings.behavior.terminal || "ghostty", "-e", "sh", "-c",
                    "sudo pacman -Sc; echo; printf 'Press Enter to close… '; read _"])
            }
        }
        SettingRow {
            label: "Thumbnails · " + Fmt.bytes(storage.clean.thumbnails)
            description: "Picture previews; they are made again when needed"
            Chip {
                icon: "󰋩"; text: "Clear"; tint: Atelier.yellow
                interactive: storage.clean.thumbnails > 0; opacity: storage.clean.thumbnails > 0 ? 1 : 0.4
                implicitHeight: 28
                onClicked: storage.runClean('rm -rf "$HOME/.cache/thumbnails"')
            }
        }
    }

    // ── Home folders ──
    SettingCard {
        title: "Home folders"; icon: "󰋜"; tint: Atelier.mauve
        SettingRow {
            label: storage.folders.some(f => !f.exists) ? "Some folders are missing" : "All set"
            description: "Documents, Downloads, Pictures, Videos, Music, Projects and more, plus Pictures/Wallpapers (shows in the wallpaper picker), Pictures/Screenshots and Videos/Recordings. Also adds them to the file manager sidebar."
            Chip {
                icon: "󰉗"; text: storage.folders.some(f => !f.exists) ? "Create" : "Repair"
                tint: Atelier.mauve; interactive: !makeFolders.running; implicitHeight: 28
                onClicked: makeFolders.running = true
            }
        }
        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.bottomMargin: 12
            spacing: 8
            Repeater {
                model: storage.folders
                Chip {
                    required property var modelData
                    icon: modelData.exists ? "󰉋" : "󰉖"
                    text: modelData.path
                    tint: modelData.exists ? Atelier.mauve : Atelier.subtext
                    interactive: modelData.exists
                    implicitHeight: 30
                    onClicked: storage.openFolder(Quickshell.env("HOME") + "/" + modelData.path)
                }
            }
        }
    }
    SettingCard {
        title: "Drives"; icon: "󰋊"; tint: Atelier.teal
        SettingSwitch { label: "Plugged-in drives"; description: "A notification with Open and Eject when a USB drive or SD card goes in"; tint: Atelier.teal
            checked: Settings.drives.notify; onToggled: (v) => Settings.drives.notify = v }
    }

}
