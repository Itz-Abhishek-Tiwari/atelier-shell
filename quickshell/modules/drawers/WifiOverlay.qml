import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.config

Item {
    id: wifiOverlayRoot
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window
    readonly property Item bodyItem: popoutContainer   // input area when opened by hover (DrawerHost mask)



    property bool isLight: false

    // Functional state
    property bool wifiEnabled: true
    property string connectedSsid: ""
    property var scannedNetworks: []
    property string selectedSsid: ""
    property bool promptPassword: false

    // Animation & positioning
    property bool animActive: false
    property real centerY: 0

    // Geometry matching Caelestia Tokens (320px width)
    readonly property int cardWidth: 320
    readonly property int cardHeight: promptPassword ? 220 : Math.min(500, 140 + Math.min(scannedNetworks.length, 7) * 44 + 48)
    readonly property int barWidth: 44
    readonly property real cardY: {
        var cy = (centerY > 0) ? centerY : (wifiOverlayRoot.height / 2);
        return Math.max(30, Math.min(wifiOverlayRoot.height - cardHeight - 30, cy - cardHeight / 2));
    }

    // Space Mono Typography & Caelestia M3 Colors
    readonly property string fontMono: "SpaceMono Nerd Font Propo"
    readonly property color colSurface: isLight
        ? Qt.rgba(240/255, 242/255, 246/255, 0.96)
        : Qt.rgba(18/255, 16/255, 22/255, 0.94)
    readonly property color colBorder: isLight
        ? Qt.rgba(0, 0, 0, 0.08)
        : Qt.rgba(255, 255, 255, 0.08)
    readonly property color colPrimary: isLight ? Atelier.accent : Atelier.sky
    readonly property color colOnPrimary: isLight ? "#ffffff" : Atelier.crust
    readonly property color colText: isLight ? Atelier.text : Atelier.text
    readonly property color colSubtext: isLight ? Atelier.subtext : Atelier.subtext
    readonly property color colContainer: isLight ? Qt.rgba(0, 0, 0, 0.05) : Qt.rgba(255, 255, 255, 0.06)

    signal toastRequested(string msg, string icon, color clr)
    signal closedSignal()

    // ── Backend Processes ─────────────────────────────────────────────────────
    Process {
        id: wifiStateProc
        command: ["sh", "-c", "nmcli -fields WIFI g"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                wifiOverlayRoot.wifiEnabled = text.trim().indexOf("enabled") !== -1;
            }
        }
    }

    Process {
        id: wifiScanProc
        command: ["sh", "-c", "nmcli -t -f 'IN-USE,SSID,SIGNAL,SECURITY,BSSID' device wifi list"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split("\n");
                var list = [];
                var seen = {};
                var foundConn = "";
                for (var i = 0; i < lines.length; i++) {
                    var l = lines[i].trim();
                    if (!l) continue;
                    var parts = l.split(":");
                    if (parts.length >= 4) {
                        var inUse = parts[0] === "*";
                        var ssid = parts[1];
                        var signal = parseInt(parts[2]) || 50;
                        var sec = parts.slice(3, parts.length - 1).join(":");
                        if (ssid && !seen[ssid]) {
                            seen[ssid] = true;
                            list.push({ inUse: inUse, ssid: ssid, signal: signal, security: sec });
                            if (inUse) foundConn = ssid;
                        }
                    }
                }
                list.sort(function(a, b) {
                    if (a.inUse) return -1;
                    if (b.inUse) return 1;
                    return b.signal - a.signal;
                });
                wifiOverlayRoot.scannedNetworks = list;
                wifiOverlayRoot.connectedSsid = foundConn;
            }
        }
    }

    Process {
        id: wifiActionProc
        command: ["sh", "-c", "true"]
        running: false
        onExited: {
            wifiScanProc.running = true;
            wifiStateProc.running = true;
        }
    }

    function toggleWifi() {
        var cmd = wifiEnabled ? "nmcli radio wifi off" : "nmcli radio wifi on && nmcli device wifi rescan";
        wifiActionProc.running = false;
        wifiActionProc.command = ["sh", "-c", cmd];
        wifiActionProc.running = true;
        wifiOverlayRoot.toastRequested(wifiEnabled ? "Wi-Fi Disabled" : "Wi-Fi Enabled", "󰤨", Atelier.sky);
    }

    function disconnectCurrent() {
        if (!connectedSsid) return;
        wifiActionProc.running = false;
        wifiActionProc.command = ["sh", "-c", "nmcli connection down id \"" + connectedSsid + "\""];
        wifiActionProc.running = true;
        wifiOverlayRoot.toastRequested("Disconnected from " + connectedSsid, "󰤮", Atelier.red);
    }

    function connectToNetwork(ssid, sec) {
        if (sec && sec.length > 0) {
            selectedSsid = ssid;
            passInput.text = "";
            promptPassword = true;
            passInput.forceActiveFocus();
        } else {
            wifiActionProc.running = false;
            wifiActionProc.command = ["sh", "-c", "nmcli connection up id \"" + ssid + "\" 2>/dev/null || nmcli device wifi connect \"" + ssid + "\""];
            wifiActionProc.running = true;
            wifiOverlayRoot.toastRequested("Connecting to " + ssid, "󰤨", Atelier.sky);
        }
    }

    function submitPassword() {
        var pwd = passInput.text;
        var ssid = selectedSsid;
        promptPassword = false;
        wifiActionProc.running = false;
        var cmd = pwd ? "nmcli device wifi connect \"" + ssid + "\" password \"" + pwd + "\"" : "nmcli connection up id \"" + ssid + "\"";
        wifiActionProc.command = ["sh", "-c", cmd];
        wifiActionProc.running = true;
        wifiOverlayRoot.toastRequested("Connecting to " + ssid, "󰤨", Atelier.sky);
    }

    function openSettings() {
        wifiOverlayRoot.close();
        wifiActionProc.running = false;
        wifiActionProc.command = ["sh", "-c", "nm-connection-editor || ghostty -e nmtui &"];
        wifiActionProc.running = true;
    }

    // ── Public API ────────────────────────────────────────────────────────────
    function open(newCenterY: real) {
        centerY = newCenterY;
        visible = true;
        animActive = true;
        promptPassword = false;
        wifiStateProc.running = true;
        wifiScanProc.running = true;
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
            if (!wifiOverlayRoot.animActive) {
                wifiOverlayRoot.visible = false;
            }
        }
    }

    Item {
        id: focusItem
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: wifiOverlayRoot.close()

        // Translucent glass backdrop for dismiss on outside click
        Rectangle {
            anchors.fill: parent
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                onClicked: wifiOverlayRoot.close()
            }
        }

        // ── Drawer growing out of the bar (Caelestia-style) ──────────────
        EdgeDrawer {
            id: popoutContainer
            edge: Atelier.barEdge        // grows out of wherever the bar is
            open: wifiOverlayRoot.animActive
            anchorPos: wifiOverlayRoot.centerY > 0 ? wifiOverlayRoot.centerY : -1
            bodyWidth: wifiOverlayRoot.cardWidth
            bodyHeight: wifiOverlayRoot.cardHeight
            Behavior on bodyHeight { NumberAnimation { duration: 240; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }

            // ── Menu Content Container (Offset by R=22) ───────────────────────
            Item {
                anchors.fill: parent
                id: contentBody

                // View 1: Password Dialog
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12
                    visible: wifiOverlayRoot.promptPassword

                    Text {
                        text: "Password for " + wifiOverlayRoot.selectedSsid
                        font.family: wifiOverlayRoot.fontMono
                        font.pixelSize: 13
                        font.bold: true
                        color: wifiOverlayRoot.colText
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 40
                        radius: 12
                        color: wifiOverlayRoot.colContainer
                        border.color: wifiOverlayRoot.colBorder
                        border.width: 1

                        TextInput {
                            id: passInput
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: wifiOverlayRoot.fontMono
                            font.pixelSize: 13
                            color: wifiOverlayRoot.colText
                            echoMode: TextInput.Password
                            selectByMouse: true

                            Text {
                                text: "Enter Wi-Fi password..."
                                font.family: wifiOverlayRoot.fontMono
                                font.pixelSize: 12
                                color: wifiOverlayRoot.colSubtext
                                opacity: 0.6
                                visible: !passInput.text
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Keys.onReturnPressed: wifiOverlayRoot.submitPassword()
                            Keys.onEscapePressed: wifiOverlayRoot.promptPassword = false
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 12
                            color: cancelMa.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                font.family: wifiOverlayRoot.fontMono
                                font.pixelSize: 12
                                color: wifiOverlayRoot.colSubtext
                            }

                            MouseArea {
                                id: cancelMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: wifiOverlayRoot.promptPassword = false
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 12
                            color: wifiOverlayRoot.colPrimary

                            Text {
                                anchors.centerIn: parent
                                text: "Connect"
                                font.family: wifiOverlayRoot.fontMono
                                font.pixelSize: 12
                                font.bold: true
                                color: wifiOverlayRoot.colOnPrimary
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: wifiOverlayRoot.submitPassword()
                            }
                        }
                    }
                }

                // View 2: Caelestia Wireless List
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10
                    visible: !wifiOverlayRoot.promptPassword

                    // Title: Wireless
                    Text {
                        text: "Wireless"
                        font.family: wifiOverlayRoot.fontMono
                        font.pixelSize: 15
                        font.bold: true
                        color: wifiOverlayRoot.colText
                    }

                    // Toggle Row: Enabled
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Enabled"
                            font.family: wifiOverlayRoot.fontMono
                            font.pixelSize: 13
                            color: wifiOverlayRoot.colText
                            Layout.fillWidth: true
                        }

                        // Sleek Pill Switch
                        Rectangle {
                            id: switchPill
                            width: 40; height: 22
                            radius: 11
                            color: wifiOverlayRoot.wifiEnabled ? wifiOverlayRoot.colPrimary : Qt.rgba(255, 255, 255, 0.12)
                            Behavior on color { ColorAnimation { duration: 140 } }

                            Rectangle {
                                width: 16; height: 16
                                radius: 8
                                anchors.verticalCenter: parent.verticalCenter
                                x: wifiOverlayRoot.wifiEnabled ? (switchPill.width - width - 3) : 3
                                color: wifiOverlayRoot.wifiEnabled ? wifiOverlayRoot.colOnPrimary : Atelier.subtext
                                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: wifiOverlayRoot.toggleWifi()
                            }
                        }
                    }

                    // Subtitle: X networks available
                    Text {
                        text: wifiOverlayRoot.scannedNetworks.length + " networks available"
                        font.family: wifiOverlayRoot.fontMono
                        font.pixelSize: 11
                        color: wifiOverlayRoot.colSubtext
                    }

                    // Divider line
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: wifiOverlayRoot.colBorder
                    }

                    // Networks List
                    ListView {
                        id: netList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds

                        model: wifiOverlayRoot.scannedNetworks.slice(0, 8)

                        delegate: Item {
                            id: netRow
                            required property var modelData
                            required property int index

                            width: netList.width
                            height: 38

                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: netRowMa.containsMouse ? wifiOverlayRoot.colContainer : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                // Signal Strength Icon
                                Text {
                                    text: modelData.signal >= 75 ? "󰤨" : (modelData.signal >= 50 ? "󰤥" : (modelData.signal >= 25 ? "󰤢" : "󰤟"))
                                    font.family: wifiOverlayRoot.fontMono
                                    font.pixelSize: 14
                                    color: modelData.inUse ? wifiOverlayRoot.colPrimary : wifiOverlayRoot.colSubtext
                                }

                                // Lock icon
                                Text {
                                    visible: Boolean(modelData.security && modelData.security.length > 0)
                                    text: "󰌾"
                                    font.family: wifiOverlayRoot.fontMono
                                    font.pixelSize: 10
                                    color: wifiOverlayRoot.colSubtext
                                }

                                // SSID Name
                                Text {
                                    text: modelData.ssid
                                    font.family: wifiOverlayRoot.fontMono
                                    font.pixelSize: 12
                                    font.bold: modelData.inUse
                                    color: modelData.inUse ? wifiOverlayRoot.colPrimary : wifiOverlayRoot.colText
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                // Action Button (link / link_off pill button)
                                Rectangle {
                                    width: 28; height: 28
                                    radius: 14
                                    color: modelData.inUse
                                        ? wifiOverlayRoot.colPrimary
                                        : (actionMa.containsMouse ? Qt.rgba(255, 255, 255, 0.12) : "transparent")
                                    border.color: modelData.inUse ? "transparent" : Qt.rgba(255, 255, 255, 0.12)
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.inUse ? "󰌺" : "󰌹"
                                        font.family: wifiOverlayRoot.fontMono
                                        font.pixelSize: 12
                                        color: modelData.inUse ? wifiOverlayRoot.colOnPrimary : wifiOverlayRoot.colText
                                    }

                                    MouseArea {
                                        id: actionMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (modelData.inUse) {
                                                wifiOverlayRoot.disconnectCurrent();
                                            } else {
                                                wifiOverlayRoot.connectToNetwork(modelData.ssid, modelData.security);
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: netRowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.inUse) {
                                        wifiOverlayRoot.disconnectCurrent();
                                    } else {
                                        wifiOverlayRoot.connectToNetwork(modelData.ssid, modelData.security);
                                    }
                                }
                            }
                        }
                    }

                    // Bottom: Open Settings button
                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: 12
                        color: settingsMa.containsMouse
                            ? Qt.alpha(Atelier.accent, 0.22)
                            : Qt.alpha(Atelier.accent, 0.14)
                        border.color: Qt.alpha(Atelier.accent, 0.20)
                        border.width: 1

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: "󰒓"
                                font.family: wifiOverlayRoot.fontMono
                                font.pixelSize: 13
                                color: isLight ? Atelier.accent : Atelier.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "Open settings"
                                font.family: wifiOverlayRoot.fontMono
                                font.pixelSize: 12
                                font.bold: true
                                color: isLight ? Atelier.accent : Atelier.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: settingsMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wifiOverlayRoot.openSettings()
                        }
                    }
                }
            }
        }
    }
}
