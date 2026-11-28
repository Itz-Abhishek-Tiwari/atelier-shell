import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.components
import qs.config

// Clipboard history (cliphist) in a drawer dropping from the top edge.
// Atelier style: Inter text, tinted type chips, hairline borders, image thumbnails.
// Keys: type to filter · ↑/↓ move · Enter copy · Delete remove · Esc close
Item {
    id: clipRoot
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window



    property bool isLight: Atelier.isLight
    property bool animActive: false
    property var entries: []          // [{ id, text, kind: "text"|"link"|"image", meta }]
    property string filter: "all"     // all | text | link | image
    property int thumbsVersion: 0     // bumps when thumbnails are ready

    signal itemCopied(string msg)
    signal closedSignal()

    readonly property string thumbDir: Quickshell.cachePath("clipboard")

    readonly property var filtered: {
        const q = search.text.toLowerCase().trim();
        return entries.filter(e => (filter === "all" || e.kind === filter) && (!q || e.text.toLowerCase().includes(q)));
    }
    readonly property int imageCount: entries.filter(e => e.kind === "image").length

    // ── Data ────────────────────────────────────────────────────────────────
    function parse(line) {
        const tab = line.indexOf("\t");
        const id = line.slice(0, tab), text = line.slice(tab + 1);
        const img = text.match(/^\[\[ binary data (.+?) (png|jpe?g|webp|gif|bmp) (\d+x\d+) \]\]$/i);
        if (img) return { id: id, text: text, kind: "image", meta: img[3] + "  ·  " + img[1] + "  ·  " + img[2].toUpperCase() };
        if (/^\s*(https?:\/\/|www\.)\S+\s*$/i.test(text)) return { id: id, text: text.trim(), kind: "link", meta: "" };
        return { id: id, text: text, kind: "text", meta: "" };
    }

    Process {
        id: listProc
        command: ["sh", "-c", "cliphist list | head -n 80"]
        stdout: StdioCollector {
            onStreamFinished: {
                clipRoot.entries = text.split("\n").filter(l => l.indexOf("\t") > 0).map(clipRoot.parse);
                list.currentIndex = 0;
                // decode image entries once into small cached files for thumbnails
                const ids = clipRoot.entries.filter(e => e.kind === "image").map(e => e.id).slice(0, 24);
                if (ids.length) {
                    thumbProc.command = ["sh", "-c",
                        'd="$1"; shift; mkdir -p "$d"; for id in "$@"; do f="$d/$id.img"; [ -s "$f" ] || printf "%s\\t\\n" "$id" | cliphist decode > "$f" 2>/dev/null; done',
                        "sh", clipRoot.thumbDir].concat(ids);
                    thumbProc.running = true;
                }
            }
        }
    }
    Process { id: thumbProc; onExited: clipRoot.thumbsVersion++ }
    Process { id: actionProc }

    function copy(e) {
        if (!e) return;
        actionProc.command = ["sh", "-c", 'printf "%s\\t\\n" "$1" | cliphist decode | wl-copy', "sh", e.id];
        actionProc.running = true;
        itemCopied(e.kind === "image" ? "Image copied" : "Copied to clipboard");
        close();
    }
    function remove(e) {
        if (!e) return;
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\t%s\\n" "$1" "$2" | cliphist delete', "sh", e.id, e.text]);
        entries = entries.filter(x => x.id !== e.id);
    }
    function wipe() {
        Quickshell.execDetached(["cliphist", "wipe"]);
        entries = [];
        itemCopied("Clipboard history cleared");
    }

    function toggle() { if (visible && animActive) close(); else open(); }
    function open() {
        visible = true;
        animActive = true;
        search.text = "";
        filter = "all";
        listProc.running = true;
        focusTimer.restart();
    }
    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }

    Timer { id: focusTimer; interval: 40; onTriggered: search.forceActiveFocus() }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!clipRoot.animActive) clipRoot.visible = false }

    MouseArea { anchors.fill: parent; onClicked: clipRoot.close() }

    // ── Drawer ──────────────────────────────────────────────────────────────
    EdgeDrawer {
        id: drawer
        edge: "top"
        open: clipRoot.animActive
        bodyWidth: 580
        bodyHeight: Math.min(clipRoot.height * 0.7, content.implicitHeight + 32)
        Behavior on bodyHeight { NumberAnimation { duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "󰅌"; font.family: Atelier.font; font.pixelSize: Atelier.iconMd; color: Atelier.yellow }
                Text { text: "Clipboard"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsXl; font.weight: Font.DemiBold; color: Atelier.text }
                Chip { text: clipRoot.entries.length; mono: true; tint: Atelier.yellow; implicitHeight: 20; pad: 7 }
                Item { Layout.fillWidth: true }

                // search pill
                Rectangle {
                    implicitWidth: 220
                    implicitHeight: 32
                    radius: Atelier.radiusMd
                    color: Atelier.container
                    border.width: 1
                    border.color: search.activeFocus ? Qt.alpha(Atelier.accent, 0.5) : Atelier.outline
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 8
                        Text { text: "󰍉"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: Atelier.subtext }
                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            font.family: Atelier.fontUi
                            font.pixelSize: Atelier.fsMd
                            color: Atelier.text
                            clip: true
                            selectByMouse: true
                            onTextChanged: list.currentIndex = 0
                            Keys.onEscapePressed: { if (text) text = ""; else clipRoot.close(); }
                            Keys.onDownPressed: list.incrementCurrentIndex()
                            Keys.onUpPressed: list.decrementCurrentIndex()
                            Keys.onReturnPressed: clipRoot.copy(clipRoot.filtered[list.currentIndex])
                            Keys.onEnterPressed: clipRoot.copy(clipRoot.filtered[list.currentIndex])
                            Keys.onDeletePressed: (e) => { if (!text) clipRoot.remove(clipRoot.filtered[list.currentIndex]); else e.accepted = false; }
                            Keys.onTabPressed: {
                                const order = ["all", "text", "link", "image"];
                                clipRoot.filter = order[(order.indexOf(clipRoot.filter) + 1) % order.length];
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !search.text
                                text: "Search history…"
                                font.family: Atelier.fontUi
                                font.pixelSize: Atelier.fsMd
                                color: Atelier.subtext
                                opacity: 0.6
                            }
                        }
                    }
                }

                Chip { visible: clipRoot.entries.length > 0; icon: "󰎟"; text: "Clear"; tint: Atelier.red; interactive: true; implicitHeight: 32; onClicked: clipRoot.wipe() }
            }

            // filters
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [
                        { id: "all",   icon: "󰅍", label: "All",    tint: Atelier.accent },
                        { id: "text",  icon: "󰦨", label: "Text",   tint: Atelier.blue },
                        { id: "link",  icon: "󰌹", label: "Links",  tint: Atelier.sky },
                        { id: "image", icon: "󰋩", label: "Images", tint: Atelier.peach }
                    ]
                    Rectangle {
                        required property var modelData
                        readonly property bool on: clipRoot.filter === modelData.id
                        implicitWidth: fRow.implicitWidth + 20
                        implicitHeight: 28
                        radius: Atelier.radiusMd
                        color: on ? Qt.alpha(modelData.tint, 0.18) : Atelier.container
                        StateLayer { mouseArea: fMa }
                        border.width: 1
                        border.color: on ? Qt.alpha(modelData.tint, 0.45) : Atelier.outline
                        Behavior on color { CAnim {} }
                        RowLayout {
                            id: fRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text { text: modelData.icon; font.family: Atelier.font; font.pixelSize: Atelier.fsMd; color: parent.parent.on ? modelData.tint : Atelier.subtext }
                            Text { text: modelData.label; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; font.weight: Font.DemiBold; color: parent.parent.on ? modelData.tint : Atelier.text }
                        }
                        MouseArea { id: fMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { clipRoot.filter = modelData.id; list.currentIndex = 0; } }
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // list
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: Math.min(contentHeight, 420)
                clip: true
                spacing: 6
                model: clipRoot.filtered
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: Atelier.durFast
                SmoothWheel { flickable: list }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool current: ListView.isCurrentItem
                    readonly property color tint: modelData.kind === "image" ? Atelier.peach : modelData.kind === "link" ? Atelier.sky : Atelier.blue

                    width: list.width
                    implicitHeight: modelData.kind === "image" ? 74 : Math.max(48, rowText.implicitHeight + 24)
                    radius: Atelier.radiusMd
                    color: current ? Qt.alpha(Atelier.accent, 0.12) : Atelier.container
                    StateLayer { mouseArea: rowMa }
                    border.width: 1
                    border.color: current ? Qt.alpha(Atelier.accent, 0.4) : Atelier.outline
                    Behavior on color { CAnim {} }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: list.currentIndex = row.index
                        onClicked: clipRoot.copy(row.modelData)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12

                        // type chip, or the image itself
                        Rectangle {
                            visible: row.modelData.kind !== "image"
                            implicitWidth: 30
                            implicitHeight: 30
                            radius: Atelier.radiusSm
                            color: Qt.alpha(row.tint, 0.14)
                            border.width: 1
                            border.color: Qt.alpha(row.tint, 0.32)
                            Text {
                                anchors.centerIn: parent
                                text: row.modelData.kind === "link" ? "󰌹" : "󰦨"
                                font.family: Atelier.font
                                font.pixelSize: Atelier.iconSm
                                color: row.tint
                            }
                        }
                        ClippingRectangle {
                            visible: row.modelData.kind === "image"
                            implicitWidth: 96
                            implicitHeight: 56
                            radius: Atelier.radiusSm
                            color: Qt.alpha(row.tint, 0.14)
                            Image {
                                anchors.fill: parent
                                source: row.modelData.kind === "image" && clipRoot.thumbsVersion > 0      // after decoding finished
                                    ? "file://" + clipRoot.thumbDir + "/" + row.modelData.id + ".img?" + clipRoot.thumbsVersion : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                sourceSize.width: 192
                                sourceSize.height: 112
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                id: rowText
                                Layout.fillWidth: true
                                text: row.modelData.kind === "image" ? "Image" : row.modelData.text
                                font.family: row.modelData.kind === "text" && /[{};=<>]|^\s{2,}/.test(row.modelData.text) ? Atelier.font : Atelier.fontUi
                                font.pixelSize: Atelier.fsMd
                                font.weight: row.modelData.kind === "image" ? Font.DemiBold : Font.Normal
                                color: row.modelData.kind === "link" ? Atelier.sky : Atelier.text
                                Behavior on color { CAnim {} }
                                wrapMode: Text.WrapAnywhere
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: row.modelData.meta !== ""
                                text: row.modelData.meta
                                font.family: Atelier.font
                                font.pixelSize: Atelier.fsMicro
                                color: Atelier.subtext
                            }
                        }

                        // delete (hover / current)
                        Rectangle {
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: Atelier.radiusMd
                            opacity: rowMa.containsMouse || delMa.containsMouse || row.current ? 1 : 0
                            color: delMa.containsMouse ? Qt.alpha(Atelier.red, 0.22) : "transparent"
                            Behavior on opacity { Anim { type: "effects" } }
                            Text { anchors.centerIn: parent; text: "󰆴"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg; color: delMa.containsMouse ? Atelier.red : Atelier.subtext }
                            MouseArea { id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: clipRoot.remove(row.modelData) }
                        }
                    }
                }

                remove: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; to: 0; duration: Atelier.durClose }
                        NumberAnimation { property: "x"; to: 60; duration: Atelier.durClose; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveClose }
                    }
                }
                displaced: Transition { NumberAnimation { properties: "y"; duration: Atelier.durMedium; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }
            }

            // empty state
            Rectangle {
                Layout.fillWidth: true
                visible: clipRoot.filtered.length === 0
                implicitHeight: 64
                radius: Atelier.radiusMd
                color: Atelier.container
                border.width: 1
                border.color: Atelier.outline
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 10
                    Text { text: "󰅌"; font.family: Atelier.font; font.pixelSize: Atelier.iconMd; color: Atelier.subtext; opacity: 0.6 }
                    Text {
                        text: clipRoot.entries.length === 0 ? "Nothing copied yet" : "No matches"
                        font.family: Atelier.fontUi
                        font.pixelSize: Atelier.fsMd
                        color: Atelier.subtext
                    }
                }
            }

            // hints
            Text {
                Layout.alignment: Qt.AlignRight
                text: "↑↓ move  ·  Enter copy  ·  Del remove  ·  Tab filter  ·  Esc close"
                font.family: Atelier.fontUi
                font.pixelSize: Atelier.fsMicro
                color: Atelier.subtext
                opacity: 0.6
            }
        }
    }
}
