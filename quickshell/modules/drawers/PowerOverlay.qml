import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.config

Item {
    id: powerRoot
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window



    property bool isLight: false
    property bool animActive: false
    property string uptimeStr: "…"
    property int selectedIndex: 0 // 0: Lock, 1: Sleep, 2: Logout, 3: Reboot, 4: Power

    // Space Mono Typography & Catppuccin Mocha colors
    readonly property string fontMono: Atelier.font
    readonly property color colBase: Atelier.surface
    readonly property color colBorder: Atelier.outline
    readonly property color colMauve:   Atelier.accent
    readonly property color colLavend:  Atelier.lavender
    readonly property color colBlue:    Atelier.blue
    readonly property color colGreen:   Atelier.green
    readonly property color colYellow:  Atelier.yellow
    readonly property color colRed:     Atelier.red
    readonly property color colText:    Atelier.text
    readonly property color colSubtext: Atelier.subtext
    readonly property color colSurface: Atelier.container
    readonly property color colSurf0: Atelier.container

    signal closedSignal()

    Process {
        id: uptimeProc
        command: ["sh", "-c", "uptime -p | sed -E 's/^up //; s/ weeks?/w/; s/ days?/d/; s/ hours?/h/; s/ minutes?/m/; s/,//g'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                powerRoot.uptimeStr = text.trim() || "up";
            }
        }
    }

    Process {
        id: powerProc
        command: ["sh", "-c", "true"]
        running: false
    }

    function runAction(cmd) {
        powerRoot.close();
        powerProc.running = false;
        powerProc.command = ["sh", "-c", cmd];
        powerProc.running = true;
    }

    function execSelected() {
        if (selectedIndex === 0) runAction("qs ipc call lock lock || hyprlock");
        else if (selectedIndex === 1) runAction("systemctl suspend");
        else if (selectedIndex === 2) runAction("hyprctl dispatch 'hl.dsp.exit()' 2>/dev/null || hyprctl dispatch exit");
        else if (selectedIndex === 3) runAction("systemctl reboot");
        else if (selectedIndex === 4) runAction("systemctl poweroff");
    }

    function toggle() {
        if (visible && animActive) {
            close();
        } else {
            open();
        }
    }

    function open() {
        visible = true;
        animActive = true;
        selectedIndex = 0;
        uptimeProc.running = true;
        focusTimer.restart();
    }

    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }

    Timer {
        id: focusTimer
        interval: 50
        repeat: false
        onTriggered: focusItem.forceActiveFocus()
    }

    Timer {
        id: closeTimer
        interval: Atelier.durClose + 40
        repeat: false
        onTriggered: {
            if (!powerRoot.animActive) {
                powerRoot.visible = false;
            }
        }
    }

    Item {
        id: focusItem
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: powerRoot.close()

        Keys.onUpPressed: {
            powerRoot.selectedIndex = (powerRoot.selectedIndex <= 0) ? 4 : powerRoot.selectedIndex - 1;
        }
        Keys.onDownPressed: {
            powerRoot.selectedIndex = (powerRoot.selectedIndex < 0 || powerRoot.selectedIndex >= 4) ? 0 : powerRoot.selectedIndex + 1;
        }
        Keys.onLeftPressed: {
            powerRoot.selectedIndex = (powerRoot.selectedIndex <= 0) ? 4 : powerRoot.selectedIndex - 1;
        }
        Keys.onRightPressed: {
            powerRoot.selectedIndex = (powerRoot.selectedIndex < 0 || powerRoot.selectedIndex >= 4) ? 0 : powerRoot.selectedIndex + 1;
        }
        Keys.onTabPressed: {
            powerRoot.selectedIndex = (powerRoot.selectedIndex < 0 || powerRoot.selectedIndex >= 4) ? 0 : powerRoot.selectedIndex + 1;
        }
        Keys.onBacktabPressed: {
            powerRoot.selectedIndex = (powerRoot.selectedIndex <= 0) ? 4 : powerRoot.selectedIndex - 1;
        }
        Keys.onReturnPressed: powerRoot.execSelected()
        Keys.onEnterPressed: powerRoot.execSelected()
        Keys.onSpacePressed: powerRoot.execSelected()

        Keys.onPressed: (event) => {
            var k = event.text.toLowerCase();
            if (k === "l") {
                powerRoot.runAction("qs ipc call lock lock || hyprlock");
            } else if (k === "s") {
                powerRoot.runAction("systemctl suspend");
            } else if (k === "e" || k === "q") {
                powerRoot.runAction("hyprctl dispatch 'hl.dsp.exit()' 2>/dev/null || hyprctl dispatch exit");
            } else if (k === "r") {
                powerRoot.runAction("systemctl reboot");
            } else if (k === "p") {
                powerRoot.runAction("systemctl poweroff");
            }
        }

        // Click-catcher for dismiss on outside click (no scrim: it was being blurred full-screen)
        Rectangle {
            anchors.fill: parent
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                onClicked: powerRoot.close()
            }
        }

        // ── Session drawer on the right edge (Caelestia-style) ─────────────────
        EdgeDrawer {
            id: powerCard
            edge: "right"
            open: powerRoot.animActive
            bodyWidth: 112
            bodyHeight: 5 * 72 + 4 * 10 + 2 * 18 + 44

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10

                Repeater {
                    // 0: Lock  1: Sleep  2: Logout  3: Reboot  4: Power Off
                    model: [
                        { icon: "󰌾", key: "L", label: "Lock", accent: powerRoot.colBlue,   cmd: "qs ipc call lock lock || hyprlock",                         idx: 0 },
                        { icon: "󰤄", key: "S", label: "Sleep", accent: powerRoot.colLavend, cmd: "systemctl suspend",                                                      idx: 1 },
                        { icon: "󰍃", key: "E", label: "Log out", accent: powerRoot.colYellow, cmd: "hyprctl dispatch 'hl.dsp.exit()' 2>/dev/null || hyprctl dispatch exit", idx: 2 },
                        { icon: "󰑓", key: "R", label: "Restart", accent: powerRoot.colGreen,  cmd: "systemctl reboot",                                                       idx: 3 },
                        { icon: "⏻",  key: "P", label: "Power", accent: powerRoot.colRed,    cmd: "systemctl poweroff",                                                     idx: 4 }
                    ]

                    Rectangle {
                        id: sessBtn
                        required property var modelData
                        readonly property bool isActive: powerRoot.selectedIndex === modelData.idx

                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 72
                        implicitHeight: 72
                        // M3-expressive shape morph: rounded square -> squircle when selected
                        radius: isActive ? 26 : 36
                        color: isActive
                            ? Qt.rgba(modelData.accent.r, modelData.accent.g, modelData.accent.b, 0.22)
                            : powerRoot.colSurf0
                        border.width: 1
                        border.color: isActive
                            ? Qt.rgba(modelData.accent.r, modelData.accent.g, modelData.accent.b, 0.6)
                            : Atelier.container
                        scale: btnMa.pressed ? 0.90 : (btnMa.containsMouse ? 1.06 : 1.0)

                        Behavior on radius { Anim { type: "spatial" } }
                        Behavior on scale { Anim { type: "fastSpatial" } }
                        Behavior on color { CAnim {} }
                        Behavior on border.color { CAnim {} }

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -7
                            text: sessBtn.modelData.icon
                            font.family: powerRoot.fontMono
                            font.pixelSize: Atelier.iconLg
                            color: sessBtn.isActive ? sessBtn.modelData.accent : powerRoot.colText
                            Behavior on color { CAnim {} }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 9
                            text: sessBtn.modelData.label
                            font.family: Atelier.fontUi
                            font.pixelSize: Atelier.fsMicro
                            font.weight: Font.Medium
                            color: sessBtn.isActive ? sessBtn.modelData.accent : powerRoot.colSubtext
                            Behavior on color { CAnim {} }
                            opacity: 0.8
                        }

                        MouseArea {
                            id: btnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: powerRoot.selectedIndex = sessBtn.modelData.idx
                            onClicked: powerRoot.runAction(sessBtn.modelData.cmd)
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 4
                    text: powerRoot.uptimeStr
                    font.family: powerRoot.fontMono
                    font.pixelSize: Atelier.fsMicro
                    color: powerRoot.colSubtext
                }
            }
        }
    }
}
