import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config

// Settings → Default apps: which app opens links, folders, text, pictures, videos, music, PDFs
// and archives, plus the terminal. Backed by scripts/default-apps.py, which reads the installed
// .desktop files and writes ~/.config/mimeapps.list (xdg-open, GTK, Qt and Electron apps follow it).
// The terminal is Settings.behavior.terminal (Super+T, the launcher's $ command).
ColumnLayout {
    id: page
    Layout.fillWidth: true
    spacing: 20

    property var cats: []
    property string expanded: ""
    property bool loaded: false

    readonly property var hints: ({
        browser: "Links from every app, and web pages on disk",
        mail: "Email links (mailto:)",
        files: "Folders, and Super+E",
        text: "Plain text, code, config and log files",
        image: "PNG, JPEG, WebP, GIF, SVG…",
        video: "MP4, MKV, WebM, MOV…",
        audio: "MP3, FLAC, Ogg, WAV, M4A…",
        pdf: "PDF and EPUB",
        archive: "ZIP, TAR, 7z, RAR…",
        document: "Word and OpenDocument text (DOCX, DOC, ODT, RTF)",
        sheet: "Excel and OpenDocument sheets (XLSX, XLS, ODS)",
        slides: "PowerPoint and OpenDocument slides (PPTX, PPT, ODP)",
        terminal: "Super+T, the launcher's $ command, and apps that run in a terminal"
    })
    readonly property var glyphs: ({
        browser: "󰖟", mail: "󰇮", files: "󰉋", text: "󰈙", image: "󰋩", video: "󰕧",
        audio: "󰝚", pdf: "󰈦", archive: "󰗄", terminal: "󰆍",
        document: "󰈬", sheet: "󰈛", slides: "󰈧"
    })

    function cat(id) { return cats.find(c => c.id === id) || null; }
    function iconUrl(icon) {
        if (!icon) return Quickshell.iconPath("application-x-executable", true);
        return icon.startsWith("/") ? "file://" + icon : Quickshell.iconPath(icon, "application-x-executable");
    }
    function refresh() { listProc.running = true; }
    function choose(cid, appId) {
        page.expanded = "";
        setProc.cid = cid;
        setProc.command = ["python3", Quickshell.shellDir + "/scripts/default-apps.py", "set", cid, appId];
        setProc.running = true;
    }

    onVisibleChanged: if (visible) refresh()

    Process {
        id: listProc
        command: ["python3", Quickshell.shellDir + "/scripts/default-apps.py", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { page.cats = JSON.parse(text); page.loaded = true; } catch (e) { console.warn("default-apps:", e); }
            }
        }
    }
    Process {
        id: setProc
        property string cid: ""
        stdout: StdioCollector {
            // `set terminal` prints the command to run; the shell owns settings.json
            onStreamFinished: if (setProc.cid === "terminal" && text.trim() !== "") Settings.behavior.terminal = text.trim()
        }
        onExited: page.refresh()
    }

    SettingCard {
        title: "Internet"
        CategoryRow { cid: "browser" }
        CategoryRow { cid: "mail" }
    }
    SettingCard {
        title: "Files & documents"
        CategoryRow { cid: "files" }
        CategoryRow { cid: "text" }
        CategoryRow { cid: "pdf" }
        CategoryRow { cid: "archive" }
    }
    SettingCard {
        title: "Office"
        CategoryRow { cid: "document" }
        CategoryRow { cid: "sheet" }
        CategoryRow { cid: "slides" }
    }
    SettingCard {
        title: "Media"
        CategoryRow { cid: "image" }
        CategoryRow { cid: "video" }
        CategoryRow { cid: "audio" }
    }
    SettingCard {
        title: "Terminal"
        CategoryRow { cid: "terminal" }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        wrapMode: Text.Wrap
        text: "Saved in ~/.config/mimeapps.list, which every app's \"Open with\" follows. Only installed apps that can open the type are listed."
        font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext
    }

    // one category: the current app on the right; tap to list the alternatives below
    component CategoryRow: ColumnLayout {
        id: cr
        property string cid: ""
        readonly property var c: page.cat(cid)
        readonly property bool open: page.expanded === cid
        readonly property var current: c ? (c.apps.find(a => a.id === c.current) || null) : null

        Layout.fillWidth: true
        spacing: 0

        Rectangle {
            visible: cr.y > 1
            Layout.fillWidth: true
            implicitHeight: 1
            color: Atelier.outline
        }

        SettingRow {
            label: (page.glyphs[cr.cid] || "") + "  " + (cr.c ? cr.c.label : "")
            description: cr.c && cr.c.mixed ? "Some of these types open in another app. Pick one to use it for all."
                                             : (page.hints[cr.cid] || "")

            Rectangle {
                implicitWidth: pill.implicitWidth + 20
                implicitHeight: 32
                radius: 16
                color: pillMa.containsMouse || cr.open ? Atelier.containerHigh : "transparent"
                border.width: 1
                border.color: cr.open ? Qt.alpha(Atelier.accent, 0.5) : Atelier.outline
                Behavior on color { ColorAnimation { duration: Atelier.durFast } }

                RowLayout {
                    id: pill
                    anchors.centerIn: parent
                    spacing: 8
                    Image {
                        visible: !!cr.current
                        Layout.preferredWidth: 18; Layout.preferredHeight: 18
                        sourceSize: Qt.size(36, 36)
                        source: cr.current ? page.iconUrl(cr.current.icon) : ""
                        asynchronous: true
                    }
                    Text {
                        text: !page.loaded ? "…" : cr.current ? cr.current.name
                            : (cr.c && cr.c.currentName ? cr.c.currentName : "Not set")
                        font.family: Atelier.fontUi; font.pixelSize: 12; font.weight: Font.Medium
                        color: cr.current || (cr.c && cr.c.currentName) ? Atelier.text : Atelier.peach
                        Layout.maximumWidth: 200
                        elide: Text.ElideRight
                    }
                    Text {
                        text: cr.open ? "󰅃" : "󰅀"
                        font.family: Atelier.font; font.pixelSize: 13; color: Atelier.subtext
                    }
                }
                MouseArea {
                    id: pillMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !!cr.c
                    onClicked: page.expanded = cr.open ? "" : cr.cid
                }
            }
        }

        // the alternatives
        Flow {
            visible: cr.open
            Layout.fillWidth: true
            Layout.bottomMargin: 14
            spacing: 8

            Text {
                visible: cr.c && cr.c.apps.length === 0
                text: "No installed app can open these. Install one (see the README's app list)."
                font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.subtext
            }

            Repeater {
                model: cr.open && cr.c ? cr.c.apps : []
                Rectangle {
                    id: opt
                    required property var modelData
                    readonly property bool on: cr.c && modelData.id === cr.c.current && !cr.c.mixed
                    implicitWidth: optRow.implicitWidth + 22
                    implicitHeight: 34
                    radius: 17
                    color: on ? Atelier.accentFill : (optMa.containsMouse ? Atelier.containerHigh : Atelier.surface)
                    border.width: 1
                    border.color: on ? "transparent" : Atelier.outline
                    Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                    scale: optMa.pressed ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutBack } }

                    RowLayout {
                        id: optRow
                        anchors.centerIn: parent
                        spacing: 8
                        Image {
                            Layout.preferredWidth: 18; Layout.preferredHeight: 18
                            sourceSize: Qt.size(36, 36)
                            source: page.iconUrl(opt.modelData.icon)
                            asynchronous: true
                        }
                        Text {
                            text: opt.modelData.name
                            font.family: Atelier.fontUi; font.pixelSize: 12; font.weight: Font.Medium
                            color: opt.on ? Atelier.onAccent : Atelier.text
                        }
                        Text {
                            visible: opt.on
                            text: "󰄬"
                            font.family: Atelier.font; font.pixelSize: 12; color: Atelier.onAccent
                        }
                    }
                    MouseArea {
                        id: optMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.choose(cr.cid, opt.modelData.id)
                    }
                }
            }
        }
    }
}
