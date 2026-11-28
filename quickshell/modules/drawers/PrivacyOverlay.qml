import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config
import qs.services

// Privacy drawer: what is using the microphone, the camera or the screen right now, with the
// controls to do something about it (mute the mic, silence one app's mic, close the app, stop
// the recorder). State comes from services/Privacy.qml, so the bar pill and this agree.
// Open: click the bar's privacy pill · IPC `privacy toggle|open|close` · launcher "Privacy".
Item {
    id: root
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window
    readonly property Item bodyItem: drawer   // input area when opened by hover (DrawerHost mask)

    property bool isLight: Atelier.isLight
    property bool animActive: false
    property real centerY: 0
    property double openedAt: 0

    signal closedSignal()

    readonly property var kinds: [
        { id: "mic",    label: "Microphone", icon: "󰍬", tint: Atelier.peach },
        { id: "camera", label: "Camera",     icon: "󰄀", tint: Atelier.green },
        { id: "screen", label: "Screen",     icon: "󰍹", tint: Atelier.red }
    ]
    readonly property int rows: Privacy.entries.length
    readonly property int groups: (Privacy.mic ? 1 : 0) + (Privacy.camera ? 1 : 0) + (Privacy.screen ? 1 : 0)

    function toggle(cy) { if (visible && animActive) close(); else open(cy); }
    function open(cy) {
        centerY = cy || 0;
        visible = true;
        animActive = true;
        openedAt = Date.now();
        focusTimer.restart();
    }
    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }
    // hide at once, skipping the retract animation (hover-switching to a neighbouring drawer)
    function hideNow() { animActive = false; closeTimer.stop(); visible = false; }

    Timer { id: focusTimer; interval: 40; onTriggered: keys.forceActiveFocus() }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!root.animActive) root.visible = false }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    EdgeDrawer {
        id: drawer
        edge: Atelier.barEdge       // grows out of wherever the bar is
        open: root.animActive
        anchorPos: root.centerY > 0 ? root.centerY : -1
        bodyWidth: 340
        bodyHeight: content.implicitHeight + 32
        Behavior on bodyHeight { NumberAnimation { duration: 240; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }

        MouseArea { anchors.fill: parent }   // clicks inside don't close

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: (e) => {
                if (e.isAutoRepeat && Date.now() - root.openedAt < 350) { e.accepted = true; return; }
                if (e.key === Qt.Key_Escape) root.close();
                else if (e.key === Qt.Key_M) Privacy.toggleMicMute();
                else return;
                e.accepted = true;
            }
        }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 12

            DrawerTitle {
                Layout.fillWidth: true
                icon: "󰒃"; tint: Privacy.any ? Atelier.peach : Atelier.green; title: "Privacy"
                subtitle: Privacy.any ? root.rows + (root.rows === 1 ? " app in use" : " apps in use") : "Nothing is listening or watching"
            }

            // the global mic switch: always there, whatever is recording
            Panel {
                Layout.fillWidth: true
                implicitHeight: 52
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14; anchors.rightMargin: 12
                    spacing: 10
                    Text { text: Privacy.micMuted ? "󰍭" : "󰍬"; font.family: Atelier.font; font.pixelSize: Atelier.iconMd
                           color: Privacy.micMuted ? Atelier.red : Atelier.peach }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { text: "Microphone"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: Atelier.text }
                        Text { text: Privacy.source ? (Privacy.micMuted ? "Muted for every app" : "Live") : "No microphone found"
                               font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                    }
                    ToggleSwitch {
                        on: !Privacy.micMuted
                        enabled: !!Privacy.source
                        onToggled: Privacy.toggleMicMute()
                    }
                }
            }

            EmptyState {
                visible: !Privacy.any
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.bottomMargin: 8
                icon: "󰒃"
                text: "No mic, camera or screen in use"
            }

            // one block per kind that is in use
            Repeater {
                model: root.kinds
                ColumnLayout {
                    id: block
                    required property var modelData
                    readonly property var items: Privacy.entries.filter(e => e.kind === modelData.id)
                    visible: items.length > 0
                    Layout.fillWidth: true
                    spacing: 6

                    SmallCaps { text: block.modelData.label; Layout.leftMargin: 4 }
                    Panel {
                        Layout.fillWidth: true
                        implicitHeight: list.implicitHeight
                        ColumnLayout {
                            id: list
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 0
                            Repeater {
                                model: block.items
                                Item {
                                    id: row
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: 50
                                    Rectangle { visible: row.index > 0; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                                anchors.leftMargin: 14; anchors.rightMargin: 14; height: 1; color: Atelier.outline }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14; anchors.rightMargin: 8
                                        spacing: 8
                                        Rectangle {
                                            implicitWidth: 8; implicitHeight: 8; radius: 4
                                            color: block.modelData.tint
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text { Layout.fillWidth: true; text: row.modelData.name; elide: Text.ElideRight
                                                   font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: Atelier.text }
                                            Text { Layout.fillWidth: true; elide: Text.ElideRight
                                                   text: row.modelData.muted ? "Silenced" : row.modelData.pid > 0 ? "pid " + row.modelData.pid : row.modelData.nodeId < 0 ? "Atelier" : "PipeWire stream"
                                                   font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                                                   color: row.modelData.muted ? Atelier.red : Atelier.subtext }
                                        }
                                        // silence just this app's microphone stream
                                        IconButton {
                                            visible: row.modelData.kind === "mic" && row.modelData.nodeId >= 0
                                            icon: row.modelData.muted ? "󰍭" : "󰍬"
                                            active: row.modelData.muted
                                            hoverTint: Atelier.peach
                                            onClicked: Privacy.toggleStreamMute(row.modelData)
                                        }
                                        // close the app (stop the recorder / close Atelier's camera)
                                        IconButton {
                                            visible: Privacy.canQuit(row.modelData) || row.modelData.pid === Quickshell.processId
                                            icon: row.modelData.kind === "screen" && row.modelData.pid === 0 ? "󰓛" : "󰅖"
                                            hoverTint: Atelier.red
                                            onClicked: Privacy.quit(row.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                visible: Privacy.camera && Privacy.screen
                text: "A screen share also reads as a video stream, so the camera can't be told apart while one runs."
                wrapMode: Text.WordWrap
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.overlay1
            }
        }
    }
}
