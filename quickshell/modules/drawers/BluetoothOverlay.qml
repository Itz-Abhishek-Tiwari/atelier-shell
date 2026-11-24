import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.config

Item {
    id: btOverlayRoot
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window
    readonly property Item bodyItem: popoutContainer   // input area when opened by hover (DrawerHost mask)



    property bool isLight: false

    // Functional state
    property bool btPowered: false
    property bool isScanning: false
    property var deviceList: []

    // Animation state
    property bool animActive: false
    property real centerY: 0

    // Geometry matching Caelestia Tokens (300px width)
    readonly property int cardWidth: 300
    readonly property int cardHeight: Math.min(480, 160 + Math.min(deviceList.length, 6) * 44 + 48)
    readonly property int barWidth: 44
    readonly property real cardY: {
        var cy = (centerY > 0) ? centerY : (btOverlayRoot.height / 2);
        return Math.max(30, Math.min(btOverlayRoot.height - cardHeight - 30, cy - cardHeight / 2));
    }

    // Space Mono Typography & Caelestia M3 Colors
    readonly property string fontMono: Atelier.font
    readonly property color colSurface: Atelier.surface
    readonly property color colBorder: Atelier.outline
    readonly property color colPrimary: Atelier.accent
    readonly property color colOnPrimary: Atelier.onFill
    readonly property color colText: Atelier.text
    readonly property color colSubtext: Atelier.subtext
    readonly property color colContainer: Atelier.container

    signal toastRequested(string msg, string icon, color clr)
    signal closedSignal()

    // ── Backend Processes ─────────────────────────────────────────────────────
    Process {
        id: btStatusProc
        command: ["sh", "-c", "bluetoothctl show | grep -q 'Powered: yes' && echo on || echo off"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                btOverlayRoot.btPowered = text.trim() === "on";
            }
        }
    }

    Process {
        id: btDevicesProc
        command: ["python3", "-c", "
import subprocess, json

def get_devices():
    res = subprocess.run(['bluetoothctl', 'devices'], capture_output=True, text=True)
    conn_res = subprocess.run(['bluetoothctl', 'devices', 'Connected'], capture_output=True, text=True)
    conn_macs = set()
    for line in conn_res.stdout.splitlines():
        p = line.strip().split()
        if len(p) >= 2:
            conn_macs.add(p[1])
            
    devices = []
    for line in res.stdout.splitlines():
        parts = line.strip().split(maxsplit=2)
        if len(parts) >= 2:
            mac = parts[1]
            name = parts[2] if len(parts) > 2 else mac
            connected = mac in conn_macs
            icon = '󰂯'
            nl = name.lower()
            if any(w in nl for w in ['headphone', 'headset', 'airpods', 'buds', 'wh-', 'wf-']):
                icon = '󰋋'
            elif any(w in nl for w in ['mouse']):
                icon = '󰍽'
            elif any(w in nl for w in ['keyboard', 'keychron']):
                icon = '󰌌'
            elif any(w in nl for w in ['speaker', 'soundbar', 'echo']):
                icon = '󰓃'
            elif any(w in nl for w in ['phone', 'iphone', 'galaxy', 'pixel']):
                icon = '󰏲'
            devices.append({'mac': mac, 'name': name, 'connected': connected, 'icon': icon})
    devices.sort(key=lambda d: (not d['connected'], d['name'].lower()))
    print(json.dumps(devices))

get_devices()
"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    btOverlayRoot.deviceList = JSON.parse(text.trim());
                } catch(e) {
                    btOverlayRoot.deviceList = [];
                }
            }
        }
    }

    Process {
        id: btActionProc
        command: ["sh", "-c", "true"]
        running: false
        onExited: {
            btStatusProc.running = true;
            btDevicesProc.running = true;
        }
    }

    function togglePower() {
        var cmd = btPowered ? "bluetoothctl power off" : "bluetoothctl power on";
        btActionProc.running = false;
        btActionProc.command = ["sh", "-c", cmd];
        btActionProc.running = true;
        btOverlayRoot.toastRequested(btPowered ? "Bluetooth Disabled" : "Bluetooth Enabled", "󰂯", Atelier.accent);
    }

    function toggleScan() {
        var next = !isScanning;
        btOverlayRoot.isScanning = next;
        var cmd = next ? "bluetoothctl --timeout 15 scan on &" : "bluetoothctl scan off";
        btActionProc.running = false;
        btActionProc.command = ["sh", "-c", cmd];
        btActionProc.running = true;
        btOverlayRoot.toastRequested(next ? "Scanning for devices…" : "Scan stopped", "󰂰", Atelier.accent);
    }

    function toggleDevice(mac, connected, name) {
        var cmd = connected ? "bluetoothctl disconnect " + mac : "bluetoothctl connect " + mac;
        btActionProc.running = false;
        btActionProc.command = ["sh", "-c", cmd];
        btActionProc.running = true;
        btOverlayRoot.toastRequested(connected ? "Disconnecting " + name : "Connecting " + name + "…", "󰂱", Atelier.blue);
    }

    function openSettings() {
        btOverlayRoot.close();
        btActionProc.running = false;
        btActionProc.command = ["sh", "-c", "blueman-manager || ghostty -e bluetui &"];
        btActionProc.running = true;
    }

    // ── Public API ────────────────────────────────────────────────────────────
    function open(newCenterY: real) {
        centerY = newCenterY;
        visible = true;
        animActive = true;
        btStatusProc.running = true;
        btDevicesProc.running = true;
        focusTimer.restart();
    }

    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }

    // hide at once, skipping the retract animation (hover-switching to a neighbouring drawer)
    function hideNow() {
        animActive = false;
        closeTimer.stop();
        visible = false;
    }

    Timer {
        id: focusTimer
        interval: 40
        repeat: false
        onTriggered: focusItem.forceActiveFocus()
    }

    Timer {
        id: closeTimer
        interval: Atelier.durClose + 40
        repeat: false
        onTriggered: {
            if (!btOverlayRoot.animActive) {
                btOverlayRoot.visible = false;
            }
        }
    }

    Item {
        id: focusItem
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: btOverlayRoot.close()

        // Translucent glass backdrop for dismiss on outside click
        Rectangle {
            anchors.fill: parent
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                onClicked: btOverlayRoot.close()
            }
        }

        // ── Drawer growing out of the bar (Caelestia-style) ──────────────
        EdgeDrawer {
            id: popoutContainer
            edge: Atelier.barEdge        // grows out of wherever the bar is
            open: btOverlayRoot.animActive
            anchorPos: btOverlayRoot.centerY > 0 ? btOverlayRoot.centerY : -1
            bodyWidth: btOverlayRoot.cardWidth
            bodyHeight: btOverlayRoot.cardHeight
            Behavior on bodyHeight { NumberAnimation { duration: 240; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }

            // ── Menu Content Container (Offset by R=22) ───────────────────────
            Item {
                anchors.fill: parent

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    // Title: Bluetooth
                    Text {
                        text: "Bluetooth"
                        font.family: btOverlayRoot.fontMono
                        font.pixelSize: Atelier.fsXl
                        font.bold: true
                        color: btOverlayRoot.colText
                    }

                    // Toggle 1: Enabled
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Enabled"
                            font.family: btOverlayRoot.fontMono
                            font.pixelSize: Atelier.fsLg
                            color: btOverlayRoot.colText
                            Layout.fillWidth: true
                        }

                        ToggleSwitch { id: powerSwitch; on: btOverlayRoot.btPowered; onToggled: btOverlayRoot.togglePower() }
                    }

                    // Toggle 2: Discovering
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Discovering"
                            font.family: btOverlayRoot.fontMono
                            font.pixelSize: Atelier.fsLg
                            color: btOverlayRoot.colText
                            Layout.fillWidth: true
                        }

                        ToggleSwitch { id: scanSwitch; on: btOverlayRoot.isScanning; onToggled: btOverlayRoot.toggleScan() }
                    }

                    // Subtitle: X devices available (Y connected)
                    Text {
                        readonly property int connCount: {
                            var c = 0;
                            for (var i = 0; i < btOverlayRoot.deviceList.length; i++) {
                                if (btOverlayRoot.deviceList[i].connected) c++;
                            }
                            return c;
                        }
                        text: connCount > 0
                            ? btOverlayRoot.deviceList.length + " devices (" + connCount + " connected)"
                            : btOverlayRoot.deviceList.length + " devices available"
                        font.family: btOverlayRoot.fontMono
                        font.pixelSize: Atelier.fsSm
                        color: btOverlayRoot.colSubtext
                    }

                    // Divider line
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: btOverlayRoot.colBorder
                    }

                    // Devices List
                    ListView {
                        id: devList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds

                        model: btOverlayRoot.deviceList.slice(0, 6)

                        delegate: Item {
                            id: devRow
                            required property var modelData
                            required property int index

                            width: devList.width
                            height: 38

                            Rectangle {
                                anchors.fill: parent
                                radius: Atelier.radiusSm
                                color: devRowMa.containsMouse ? btOverlayRoot.colContainer : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                // Device Type Icon
                                Text {
                                    text: modelData.icon || "󰂯"
                                    font.family: btOverlayRoot.fontMono
                                    font.pixelSize: 14
                                    color: modelData.connected ? btOverlayRoot.colPrimary : btOverlayRoot.colSubtext
                                }

                                // Device Name
                                Text {
                                    text: modelData.name
                                    font.family: btOverlayRoot.fontMono
                                    font.pixelSize: Atelier.fsMd
                                    font.bold: modelData.connected
                                    color: modelData.connected ? btOverlayRoot.colPrimary : btOverlayRoot.colText
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                // Action Button (link / link_off pill button)
                                Rectangle {
                                    width: 28; height: 28
                                    radius: Atelier.radiusMd
                                    color: modelData.connected
                                        ? btOverlayRoot.colPrimary
                                        : (actionBtnMa.containsMouse ? Qt.alpha(Atelier.text, 0.12) : "transparent")
                                    border.color: modelData.connected ? "transparent" : Qt.alpha(Atelier.text, 0.12)
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.connected ? "󰌺" : "󰌹"
                                        font.family: btOverlayRoot.fontMono
                                        font.pixelSize: Atelier.fsMd
                                        color: modelData.connected ? btOverlayRoot.colOnPrimary : btOverlayRoot.colText
                                    }

                                    MouseArea {
                                        id: actionBtnMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: btOverlayRoot.toggleDevice(modelData.mac, modelData.connected, modelData.name)
                                    }
                                }
                            }

                            MouseArea {
                                id: devRowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: btOverlayRoot.toggleDevice(modelData.mac, modelData.connected, modelData.name)
                            }
                        }
                    }

                    // Bottom: Open Settings button
                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: Atelier.radiusMd
                        color: btSettingsMa.containsMouse
                            ? Qt.alpha(Atelier.accent, 0.22)
                            : Qt.alpha(Atelier.accent, 0.14)
                        border.color: Qt.alpha(Atelier.accent, 0.20)
                        border.width: 1

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: "󰒓"
                                font.family: btOverlayRoot.fontMono
                                font.pixelSize: Atelier.fsLg
                                color: Atelier.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "Open settings"
                                font.family: btOverlayRoot.fontMono
                                font.pixelSize: Atelier.fsMd
                                font.bold: true
                                color: Atelier.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: btSettingsMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: btOverlayRoot.openSettings()
                        }
                    }
                }
            }
        }
    }
}
