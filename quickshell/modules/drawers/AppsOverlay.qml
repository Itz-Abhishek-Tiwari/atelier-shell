import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.components
import qs.config

// App grid drawer: every installed app, browsable by category, rising from the bottom edge.
// The launcher (Super+Space) is for searching; this is for looking around.
//   Type to filter · ←↑↓→ move · Enter launch · Tab / Shift+Tab switch category · Esc close
// Launches count towards the same usage file as the launcher, so "Frequent" and the
// launcher's ranking agree.
Item {
    id: root
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window
    readonly property Item bodyItem: drawer

    property bool isLight: false
    property bool animActive: false
    property real openedAt: 0

    signal closedSignal()

    readonly property int cols: 6
    readonly property int cellW: 92
    readonly property int cellH: 98
    readonly property int visibleRows: 4
    readonly property int bodyW: cols * cellW + 2 * 18
    readonly property int bodyH: 18 + 36 + 12 + 30 + 12 + visibleRows * cellH + 14

    // ── Data ─────────────────────────────────────────────────────────────────
    readonly property var apps: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))

    // freedesktop main categories → our tabs (first match wins)
    readonly property var groups: [
        { id: "dev",      label: "Dev",      tint: Atelier.green,    cats: ["Development", "IDE", "TextEditor"] },
        { id: "internet", label: "Internet", tint: Atelier.blue,     cats: ["Network", "WebBrowser", "Email", "Chat", "InstantMessaging"] },
        { id: "media",    label: "Media",    tint: Atelier.pink,     cats: ["AudioVideo", "Audio", "Video", "Graphics", "Photography", "Music"] },
        { id: "games",    label: "Games",    tint: Atelier.peach,    cats: ["Game"] },
        { id: "office",   label: "Office",   tint: Atelier.yellow,   cats: ["Office", "Education", "Science", "Documentation"] },
        { id: "system",   label: "System",   tint: Atelier.sky,      cats: ["System", "Settings", "Utility", "Monitor", "TerminalEmulator", "FileManager", "Accessories"] }
    ]

    function groupOf(app) {
        const cs = app.categories || [];
        for (const g of groups)
            if (g.cats.some(c => cs.includes(c))) return g.id;
        return "other";
    }

    // tabs that actually have apps
    readonly property var tabs: {
        const used = {};
        for (const a of apps) used[groupOf(a)] = true;
        const t = [{ id: "all", label: "All", tint: Atelier.accent }];
        for (const g of groups) if (used[g.id]) t.push(g);
        if (used.other) t.push({ id: "other", label: "Other", tint: Atelier.lavender });
        return t;
    }
    property string tab: "all"

    property var usage: ({})
    FileView {
        id: usageFile
        path: Quickshell.statePath("launcher-usage.json")   // shared with the launcher
        printErrors: false
        onLoaded: { try { root.usage = JSON.parse(text()) || {}; } catch (e) { root.usage = {}; } }
    }

    readonly property var frequent: apps
        .filter(a => (usage["app:" + a.id] || 0) > 0)
        .sort((a, b) => (usage["app:" + b.id] || 0) - (usage["app:" + a.id] || 0))
        .slice(0, cols)

    readonly property string query: filter.text.trim().toLowerCase()
    readonly property var shown: {
        const q = query;
        return apps.filter(a => {
            if (q) {
                const hay = (a.name + " " + (a.genericName || "") + " " + (a.keywords || []).join(" ")).toLowerCase();
                return hay.includes(q);     // a filter spans every category
            }
            return tab === "all" || groupOf(a) === tab;
        });
    }
    onShownChanged: grid.currentIndex = 0

    function iconFor(app) {
        const icon = app.icon || "";
        return icon.startsWith("/") ? "file://" + icon : (icon ? Quickshell.iconPath(icon, true) : "");
    }

    function launch(app) {
        const u = Object.assign({}, usage);
        u["app:" + app.id] = (u["app:" + app.id] || 0) + 1;
        usage = u;
        usageFile.setText(JSON.stringify(u));
        if (app.runInTerminal) Quickshell.execDetached([Settings.behavior.terminal, "-e"].concat(app.command));
        else app.execute();
        close();
    }

    function stepTab(d) {
        const i = tabs.findIndex(t => t.id === tab);
        tab = tabs[(i + d + tabs.length) % tabs.length].id;
        filter.text = "";
    }

    // ── Open / close ─────────────────────────────────────────────────────────
    function toggle() { if (visible && animActive) close(); else open(); }

    function open() {
        visible = true;
        animActive = true;
        openedAt = Date.now();
        filter.text = "";
        tab = "all";
        usageFile.reload();
        grid.currentIndex = 0;
        grid.positionViewAtBeginning();
        focusTimer.restart();
    }

    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }

    Timer { id: focusTimer; interval: 30; onTriggered: filter.forceActiveFocus() }
    Timer {
        id: closeTimer
        interval: Atelier.durClose + 40
        onTriggered: if (!root.animActive) root.visible = false
    }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    EdgeDrawer {
        id: drawer
        edge: Atelier.barEdge === "bottom" ? "top" : "bottom"   // from the bottom (top if the bar lives there)
        open: root.animActive
        bodyWidth: root.bodyW
        bodyHeight: root.bodyH

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            anchors.bottomMargin: 14
            spacing: 12

            // header: title + filter field
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                spacing: 12
                Text {
                    text: "Applications"
                    font.family: Atelier.fontUi
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                    color: Atelier.text
                }
                Text {
                    text: root.shown.length
                    font.family: Atelier.font
                    font.pixelSize: 11
                    color: Atelier.subtext
                    opacity: 0.7
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 34
                    radius: 17
                    color: Atelier.containerHigh
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 13
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰍉"
                        font.family: Atelier.font
                        font.pixelSize: 14
                        color: Atelier.subtext
                    }
                    TextField {
                        id: filter
                        anchors.fill: parent
                        anchors.leftMargin: 34
                        anchors.rightMargin: 12
                        background: null
                        placeholderText: "Filter"
                        placeholderTextColor: Qt.alpha(Atelier.subtext, 0.6)
                        color: Atelier.text
                        font.family: Atelier.fontUi
                        font.pixelSize: 13
                        verticalAlignment: TextInput.AlignVCenter

                        Keys.onPressed: (e) => {
                            if (e.isAutoRepeat && Date.now() - root.openedAt < 350) { e.accepted = true; return; }
                            const n = root.shown.length;
                            if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; }
                            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                if (n > 0) root.launch(root.shown[grid.currentIndex]);
                                e.accepted = true;
                            }
                            else if (e.key === Qt.Key_Tab) { root.stepTab(1); e.accepted = true; }
                            else if (e.key === Qt.Key_Backtab) { root.stepTab(-1); e.accepted = true; }
                            else if (e.key === Qt.Key_Down) { grid.currentIndex = Math.min(n - 1, grid.currentIndex + root.cols); e.accepted = true; }
                            else if (e.key === Qt.Key_Up) { grid.currentIndex = Math.max(0, grid.currentIndex - root.cols); e.accepted = true; }
                            else if (e.key === Qt.Key_Right && filter.cursorPosition === filter.text.length) { grid.currentIndex = Math.min(n - 1, grid.currentIndex + 1); e.accepted = true; }
                            else if (e.key === Qt.Key_Left && filter.cursorPosition === filter.text.length) { grid.currentIndex = Math.max(0, grid.currentIndex - 1); e.accepted = true; }
                        }
                    }
                }
            }

            // category tabs (hidden while filtering: the filter spans everything)
            Row {
                Layout.preferredHeight: 30
                spacing: 6
                opacity: root.query ? 0.35 : 1
                Behavior on opacity { NumberAnimation { duration: Atelier.durFast } }
                Repeater {
                    model: root.tabs
                    Rectangle {
                        required property var modelData
                        readonly property bool on: root.tab === modelData.id && !root.query
                        width: tabLabel.implicitWidth + 26
                        height: 30
                        radius: 15
                        color: on ? Qt.alpha(modelData.tint, 0.18) : (tabMa.containsMouse ? Atelier.container : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: parent.modelData.label
                            font.family: Atelier.fontUi
                            font.pixelSize: 12
                            font.weight: parent.on ? Font.DemiBold : Font.Normal
                            color: parent.on ? parent.modelData.tint : Atelier.subtext
                        }
                        MouseArea {
                            id: tabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.tab = parent.modelData.id; filter.text = ""; filter.forceActiveFocus(); }
                        }
                    }
                }
            }

            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: root.cellW
                cellHeight: root.cellH
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                model: root.shown
                // "Frequent" strip on top of All (not while filtering)
                header: Item {
                    width: grid.width
                    height: root.tab === "all" && !root.query && root.frequent.length > 0 ? root.cellH + 26 : 0
                    visible: height > 0
                    Text {
                        y: 0
                        text: "FREQUENT"
                        font.family: Atelier.fontUi
                        font.pixelSize: 10
                        font.letterSpacing: 1.6
                        color: Atelier.subtext
                        opacity: 0.7
                    }
                    Row {
                        y: 18
                        Repeater {
                            model: root.frequent
                            AppCell { required property var modelData; app: modelData; current: false }
                        }
                    }
                    Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: 4; width: parent.width; height: 1; color: Atelier.container }
                }
                delegate: AppCell {
                    required property var modelData
                    required property int index
                    app: modelData
                    current: grid.currentIndex === index
                }
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

                Text {
                    anchors.centerIn: parent
                    visible: root.shown.length === 0
                    text: "Nothing matches “" + filter.text + "”"
                    font.family: Atelier.fontUi
                    font.pixelSize: 13
                    color: Atelier.subtext
                }
            }
        }
    }

    component AppCell: Item {
        id: cell
        property var app
        property bool current: false
        width: root.cellW
        height: root.cellH

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 16
            color: cell.current ? Atelier.containerHigh : (cellMa.containsMouse ? Atelier.container : "transparent")
            Behavior on color { ColorAnimation { duration: 100 } }
        }

        Item {
            id: iconBox
            width: 44
            height: 44
            anchors.horizontalCenter: parent.horizontalCenter
            y: 12
            scale: cellMa.pressed ? 0.9 : 1
            Behavior on scale { NumberAnimation { duration: 120 } }
            readonly property string src: cell.app ? root.iconFor(cell.app) : ""
            IconImage { anchors.fill: parent; visible: iconBox.src !== ""; source: iconBox.src; asynchronous: true }
            Rectangle {   // letter tile when the theme lacks the icon
                anchors.fill: parent
                visible: iconBox.src === ""
                radius: 13
                color: Qt.alpha(Atelier.lavender, 0.16)
                Text {
                    anchors.centerIn: parent
                    text: cell.app ? cell.app.name.charAt(0).toUpperCase() : ""
                    font.family: Atelier.fontUi
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                    color: Atelier.lavender
                }
            }
        }

        Text {
            anchors.top: iconBox.bottom
            anchors.topMargin: 7
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.cellW - 12
            horizontalAlignment: Text.AlignHCenter
            text: cell.app ? cell.app.name : ""
            font.family: Atelier.fontUi
            font.pixelSize: 11
            color: cell.current ? Atelier.text : Atelier.subtext
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            lineHeight: 0.95
        }

        MouseArea {
            id: cellMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (cell.app) root.launch(cell.app)
        }
    }
}
