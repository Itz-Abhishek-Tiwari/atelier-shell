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
    property var knownSsids: ({})        // saved NetworkManager profiles, by name
    property string busySsid: ""         // network being connected to right now
    property string errorText: ""        // shown on the password view after a failed try
    property bool showPassword: false
    property int scanRetries: 0          // empty scans retried while the card rescans    // eye toggle on the password field
    property string _pendingPw: ""       // handed to wifi-connect.sh on stdin, then cleared

    // Animation & positioning
    property bool animActive: false
    property real centerY: 0

    // Geometry matching Caelestia Tokens (320px width)
    readonly property int cardWidth: 320
    readonly property int cardHeight: promptPassword ? (errorText ? 240 : 220) : Math.min(500, 140 + Math.min(scannedNetworks.length, 7) * 44 + 48)
    readonly property int barWidth: 44
    readonly property real cardY: {
        var cy = (centerY > 0) ? centerY : (wifiOverlayRoot.height / 2);
        return Math.max(30, Math.min(wifiOverlayRoot.height - cardHeight - 30, cy - cardHeight / 2));
    }

    // Space Mono Typography & Caelestia M3 Colors
    readonly property string fontMono: Atelier.font
    readonly property color colSurface: Atelier.surface
    readonly property color colBorder: Atelier.outline
    readonly property color colPrimary: isLight ? Atelier.accent : Atelier.sky
    readonly property color colOnPrimary: Atelier.onFill
    readonly property color colText: Atelier.text
    readonly property color colSubtext: Atelier.subtext
    readonly property color colContainer: Atelier.container

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
                    var parts = wifiOverlayRoot.splitTerse(lines[i]);
                    if (parts.length < 4) continue;
                    var inUse = parts[0].trim() === "*";
                    var ssid = parts[1];
                    var signal = parseInt(parts[2]) || 0;
                    var sec = parts[3].trim();
                    if (sec === "--") sec = "";
                    if (ssid && !seen[ssid]) {
                        seen[ssid] = true;
                        list.push({ inUse: inUse, ssid: ssid, signal: signal, security: sec });
                        if (inUse) foundConn = ssid;
                    } else if (ssid && inUse) {
                        for (var j = 0; j < list.length; j++)
                            if (list[j].ssid === ssid) list[j].inUse = true;
                        foundConn = ssid;
                    }
                }
                list.sort(function(a, b) {
                    if (a.inUse) return -1;
                    if (b.inUse) return 1;
                    return b.signal - a.signal;
                });
                // nmcli returns an empty list while the card is rescanning or
                // reconnecting: keep the last list and ask again shortly
                if (list.length === 0 && wifiOverlayRoot.wifiEnabled && wifiOverlayRoot.scanRetries < 8) {
                    wifiOverlayRoot.scanRetries++;
                    rescanTimer.restart();
                    if (wifiOverlayRoot.scanRetries === 1) rescanProc.running = true;
                    return;
                }
                wifiOverlayRoot.scanRetries = 0;
                wifiOverlayRoot.scannedNetworks = list;
                wifiOverlayRoot.connectedSsid = foundConn;
            }
        }
    }

    // ask the card for a fresh scan (nmcli lists nothing until it has one)
    Process {
        id: rescanProc
        command: ["nmcli", "device", "wifi", "rescan"]
        running: false
    }

    Timer {
        id: rescanTimer
        interval: 1500
        repeat: false
        onTriggered: wifiScanProc.running = true
    }

    Process {
        id: knownProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var known = {};
                var lines = text.trim().split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var f = wifiOverlayRoot.splitTerse(lines[i]);
                    if (f.length >= 2 && f[1] === "802-11-wireless") known[f[0]] = true;
                }
                wifiOverlayRoot.knownSsids = known;
            }
        }
    }

    // Connects through scripts/wifi-connect.sh; the password goes over stdin.
    Process {
        id: connectProc
        property string ssid: ""
        property bool withPassword: false
        running: false
        stdinEnabled: true
        onStarted: {
            write(wifiOverlayRoot._pendingPw + "\n");
            wifiOverlayRoot._pendingPw = "";
        }
        stdout: StdioCollector {
            onStreamFinished: {
                var out = text.trim().split("\n").pop() || "";
                var ssid = connectProc.ssid;
                wifiOverlayRoot.busySsid = "";
                if (out === "OK") {
                    wifiOverlayRoot.errorText = "";
                    wifiOverlayRoot.toastRequested("Connected to " + ssid, "󰤨", Atelier.green);
                } else if (out.indexOf("AUTH") === 0) {
                    // wrong / missing password: ask (again) if the drawer is still up
                    wifiOverlayRoot.errorText = connectProc.withPassword ? "Wrong password, try again" : "";
                    wifiOverlayRoot.toastRequested(connectProc.withPassword ? "Wrong password for " + ssid : "Password needed for " + ssid, "󰤬", Atelier.red);
                    if (wifiOverlayRoot.animActive) wifiOverlayRoot.askPassword(ssid);
                } else {
                    var why = out.replace(/^FAIL\s*/, "") || "could not connect";
                    wifiOverlayRoot.toastRequested("Couldn't connect: " + why, "󰤮", Atelier.red);
                }
                wifiScanProc.running = true;
                knownProc.running = true;
                wifiStateProc.running = true;
            }
        }
    }

    // nmcli -t output: fields split on ':', with '\:' and '\\' escaped inside a field
    function splitTerse(line) {
        var out = [], cur = "";
        for (var i = 0; i < line.length; i++) {
            var c = line[i];
            if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue; }
            if (c === ":") { out.push(cur); cur = ""; continue; }
            cur += c;
        }
        out.push(cur);
        return out;
    }

    function runConnect(ssid, pwd) {
        if (connectProc.running) return;      // one attempt at a time
        busySsid = ssid;
        _pendingPw = pwd || "";
        connectProc.ssid = ssid;
        connectProc.withPassword = !!pwd;
        connectProc.command = [Quickshell.shellDir + "/scripts/wifi-connect.sh", ssid];
        connectProc.running = true;
        toastRequested("Connecting to " + ssid + "…", "󰤨", Atelier.sky);
    }

    function askPassword(ssid) {
        selectedSsid = ssid;
        passInput.text = "";
        showPassword = false;
        promptPassword = true;
        passInput.forceActiveFocus();
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
        wifiActionProc.command = ["nmcli", "connection", "down", "id", connectedSsid];
        wifiActionProc.running = true;
        wifiOverlayRoot.toastRequested("Disconnected from " + connectedSsid, "󰤮", Atelier.red);
    }

    function connectToNetwork(ssid, sec) {
        errorText = "";
        // saved or open networks connect straight away; the script reports
        // back AUTH if the saved password is wrong, and we ask then
        if (!sec || knownSsids[ssid]) runConnect(ssid, "");
        else askPassword(ssid);
    }

    function submitPassword() {
        var pwd = passInput.text;
        if (!pwd) return;
        passInput.text = "";
        promptPassword = false;
        runConnect(selectedSsid, pwd);
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
        scanRetries = 0;
        wifiScanProc.running = true;
        knownProc.running = true;
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
                        font.family: Atelier.fontUi
                        font.pixelSize: Atelier.fsLg
                        font.bold: true
                        color: wifiOverlayRoot.colText
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: wifiOverlayRoot.errorText !== ""
                        text: wifiOverlayRoot.errorText
                        font.family: Atelier.fontUi
                        font.pixelSize: Atelier.fsMd
                        color: Atelier.red
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 40
                        radius: Atelier.radiusMd
                        color: wifiOverlayRoot.colContainer
                        border.color: wifiOverlayRoot.colBorder
                        border.width: 1

                        TextInput {
                            id: passInput
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 40
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Atelier.fontUi
                            font.pixelSize: Atelier.fsLg
                            color: wifiOverlayRoot.colText
                            echoMode: wifiOverlayRoot.showPassword ? TextInput.Normal : TextInput.Password
                            clip: true
                            selectByMouse: true

                            Text {
                                text: "Enter Wi-Fi password..."
                                font.family: Atelier.fontUi
                                font.pixelSize: Atelier.fsMd
                                color: wifiOverlayRoot.colSubtext
                                opacity: 0.6
                                visible: !passInput.text
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Keys.onReturnPressed: wifiOverlayRoot.submitPassword()
                            Keys.onEscapePressed: { wifiOverlayRoot.promptPassword = false; wifiOverlayRoot.errorText = ""; }
                        }

                        // show / hide password
                        Rectangle {
                            width: 28; height: 28
                            radius: Atelier.radiusMd
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            color: eyeMa.containsMouse ? wifiOverlayRoot.colContainer : "transparent"
                            Behavior on color { CAnim {} }
                            scale: eyeMa.pressed ? 0.86 : (eyeMa.containsMouse ? 1.18 : 1.0)
                            Behavior on scale { Anim { type: "fastSpatial" } }

                            Text {
                                anchors.centerIn: parent
                                text: wifiOverlayRoot.showPassword ? "\u{F06D1}" : "\u{F0208}"   // eye-off / eye
                                font.family: Atelier.fontUi
                                font.pixelSize: Atelier.fsXl
                                color: wifiOverlayRoot.showPassword ? wifiOverlayRoot.colPrimary : wifiOverlayRoot.colSubtext
                                Behavior on color { CAnim {} }
                            }

                            MouseArea {
                                id: eyeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    wifiOverlayRoot.showPassword = !wifiOverlayRoot.showPassword;
                                    passInput.forceActiveFocus();
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: Atelier.radiusMd
                            color: "transparent"
                            StateLayer { mouseArea: cancelMa }

                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                font.family: Atelier.fontUi
                                font.pixelSize: Atelier.fsMd
                                color: wifiOverlayRoot.colSubtext
                            }

                            MouseArea {
                                id: cancelMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { wifiOverlayRoot.promptPassword = false; wifiOverlayRoot.errorText = ""; }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: Atelier.radiusMd
                            color: wifiOverlayRoot.colPrimary

                            Text {
                                anchors.centerIn: parent
                                text: "Connect"
                                font.family: Atelier.fontUi
                                font.pixelSize: Atelier.fsMd
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
                        font.family: Atelier.fontUi
                        font.pixelSize: Atelier.fsXl
                        font.bold: true
                        color: wifiOverlayRoot.colText
                    }

                    // Toggle Row: Enabled
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Enabled"
                            font.family: Atelier.fontUi
                            font.pixelSize: Atelier.fsLg
                            color: wifiOverlayRoot.colText
                            Layout.fillWidth: true
                        }

                        // Sleek Pill Switch
                        ToggleSwitch { id: switchPill; on: wifiOverlayRoot.wifiEnabled; onToggled: wifiOverlayRoot.toggleWifi() }
                    }

                    // Subtitle: X networks available
                    Text {
                        text: !wifiOverlayRoot.wifiEnabled ? "Wi-Fi is off"
                            : (wifiOverlayRoot.scannedNetworks.length === 0 || wifiOverlayRoot.scanRetries > 0)
                                ? (wifiOverlayRoot.scanRetries >= 8 ? "No networks found" : "Scanning…")
                                : wifiOverlayRoot.scannedNetworks.length + " networks available"
                        font.family: Atelier.fontUi
                        font.pixelSize: Atelier.fsMd
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
                                radius: Atelier.radiusSm
                                color: netRowMa.containsMouse ? wifiOverlayRoot.colContainer : "transparent"
                                Behavior on color { CAnim {} }
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
                                    Behavior on color { CAnim {} }
                                }

                                // Lock icon
                                Text {
                                    visible: Boolean(modelData.security && modelData.security.length > 0)
                                    text: "󰌾"
                                    font.family: wifiOverlayRoot.fontMono
                                    font.pixelSize: Atelier.fsMicro
                                    color: wifiOverlayRoot.colSubtext
                                }

                                // SSID Name
                                Text {
                                    text: modelData.ssid + (wifiOverlayRoot.busySsid === modelData.ssid ? "  · connecting…" : "")
                                    font.family: Atelier.fontUi
                                    font.pixelSize: Atelier.fsMd
                                    font.bold: modelData.inUse
                                    color: modelData.inUse ? wifiOverlayRoot.colPrimary : wifiOverlayRoot.colText
                                    Behavior on color { CAnim {} }
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                // Action Button (link / link_off pill button)
                                Rectangle {
                                    width: 28; height: 28
                                    radius: Atelier.radiusMd
                                    color: modelData.inUse
                                        ? wifiOverlayRoot.colPrimary
                                        : (actionMa.containsMouse ? Qt.alpha(Atelier.text, 0.12) : "transparent")
                                    border.color: modelData.inUse ? "transparent" : Qt.alpha(Atelier.text, 0.12)
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.inUse ? "󰌺" : "󰌹"
                                        font.family: wifiOverlayRoot.fontMono
                                        font.pixelSize: Atelier.fsMd
                                        color: modelData.inUse ? wifiOverlayRoot.colOnPrimary : wifiOverlayRoot.colText
                                        Behavior on color { CAnim {} }
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
                        radius: Atelier.radiusMd
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
                                font.pixelSize: Atelier.fsLg
                                color: Atelier.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "Open settings"
                                font.family: Atelier.fontUi
                                font.pixelSize: Atelier.fsMd
                                font.bold: true
                                color: Atelier.accent
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
