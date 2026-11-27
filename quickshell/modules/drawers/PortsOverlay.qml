import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// Listening ports: what is serving on localhost (dev servers, databases, stray processes), with the
// owning process. Click a row to open http://localhost:PORT, copy the address, or kill the process.
// Open: IPC `ports toggle|open|close` · launcher "Ports". Refreshes every 3 s while open.
Item {
    id: root
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool isLight: Atelier.isLight
    property bool animActive: false
    property double openedAt: 0
    property bool localOnly: true
    property var ports: []

    signal closedSignal()

    readonly property var shown: ports.filter(p => !localOnly || p.local)

    function toggle() { if (visible && animActive) close(); else open(); }
    function open() {
        visible = true;
        animActive = true;
        openedAt = Date.now();
        refresh();
        keys.forceActiveFocus();
    }
    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }
    function refresh() { if (!scan.running) scan.running = true; }
    function kill(pid) { Quickshell.execDetached(["kill", String(pid)]); after.restart(); }

    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!root.animActive) root.visible = false }
    Timer { id: after; interval: 400; onTriggered: root.refresh() }
    Timer { interval: 3000; repeat: true; running: root.animActive; onTriggered: root.refresh() }

    // ss -ltnpH → rows { port, addr, proc, pid, local }
    Process {
        id: scan
        command: ["ss", "-ltnpH"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {}, rows = [];
                for (const line of text.split("\n")) {
                    const f = line.trim().split(/\s+/);
                    if (f.length < 5) continue;
                    const i = f[3].lastIndexOf(":");
                    const addr = f[3].slice(0, i), port = parseInt(f[3].slice(i + 1));
                    const u = line.match(/\(\("([^"]+)",pid=(\d+)/);
                    const key = port + (u ? u[2] : "");
                    if (seen[key]) continue;
                    seen[key] = true;
                    rows.push({ port: port, addr: addr, proc: u ? u[1] : "", pid: u ? parseInt(u[2]) : 0,
                                local: addr === "127.0.0.1" || addr === "[::1]" || addr === "0.0.0.0" || addr === "*" || addr === "[::]" });
                }
                rows.sort((a, b) => a.port - b.port);
                root.ports = rows;
            }
        }
    }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    EdgeDrawer {
        id: drawer
        edge: "bottom"
        open: root.animActive
        bodyWidth: Math.min(root.width - 160, 640)
        bodyHeight: Math.min(root.height - 160, 460)

        MouseArea { anchors.fill: parent }   // clicks inside don't close

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: (e) => {
                if (e.isAutoRepeat && Date.now() - root.openedAt < 350) { e.accepted = true; return; }
                if (e.key === Qt.Key_Escape) root.close();
                else if (e.key === Qt.Key_R) root.refresh();
                else return;
                e.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                DrawerTitle {
                    Layout.fillWidth: true
                    icon: "󰛳"; tint: Atelier.teal; title: "Ports"
                    subtitle: root.shown.length + " listening" + (root.localOnly ? " on this machine" : "")
                }
                Segmented {
                    model: [{ id: "local", label: "Local", icon: "󰋜" }, { id: "all", label: "All", icon: "󰖟" }]
                    current: root.localOnly ? "local" : "all"
                    segmentWidth: 84
                    onPicked: (id) => root.localOnly = id === "local"
                }
                IconButton { accessibleLabel: "Refresh ports"; icon: "󰑐"; size: 34; glyphSize: 15; onClicked: root.refresh() }
            }

            Panel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                EmptyState { anchors.centerIn: parent; visible: root.shown.length === 0; icon: "󰛳"; text: "Nothing is listening" }
                Flickable {
                    id: flick
                    anchors.fill: parent
                    anchors.margins: 3
                    contentHeight: col.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    SmoothWheel { flickable: flick }
                    ColumnLayout {
                        id: col
                        width: flick.width
                        spacing: 0
                        Repeater {
                            model: root.shown
                            Item {
                                id: row
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 48
                                Rectangle { visible: row.index > 0; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                            anchors.leftMargin: 14; anchors.rightMargin: 14; height: 1; color: Atelier.outline }
                                Rectangle { anchors.fill: parent; anchors.margins: 3; radius: Atelier.radiusMd; color: Atelier.containerHigh
                                            opacity: rowMa.containsMouse ? 0.6 : 0; Behavior on opacity { Anim { type: "effects" } } }
                                MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14; anchors.rightMargin: 8
                                    spacing: 10
                                    Text { Layout.preferredWidth: 64; text: row.modelData.port
                                           font.family: Atelier.font; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; color: Atelier.accent }
                                    Text { Layout.fillWidth: true; elide: Text.ElideRight
                                           text: (row.modelData.proc || "unknown process") + (row.modelData.pid ? "  ·  " + row.modelData.pid : "")
                                           font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.text }
                                    Text { text: row.modelData.addr; font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                                    IconButton { icon: "󰖟"; size: 30; glyphSize: 13; visible: row.modelData.local
                                                 onClicked: { Quickshell.execDetached(["xdg-open", "http://localhost:" + row.modelData.port]); root.close(); } }
                                    IconButton { icon: "󰆏"; size: 30; glyphSize: 13
                                                 onClicked: Quickshell.execDetached(["wl-copy", "localhost:" + row.modelData.port]) }
                                    IconButton { icon: "󰅖"; size: 30; glyphSize: 13; visible: row.modelData.pid > 0
                                                 onClicked: root.kill(row.modelData.pid) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
