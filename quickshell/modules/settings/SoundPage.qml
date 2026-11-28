import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.components
import qs.config

// Settings → Sound: output and input devices (default + volume), and the volume of each app
// that is playing or recording. All live Pipewire state, nothing saved in settings.json
// (Pipewire / WirePlumber remember defaults and volumes themselves).
ColumnLayout {
    id: page
    Layout.fillWidth: true
    spacing: 20

    // Only while the page is on screen: these are frozen copies of PipeWire's node list, and
    // apps start/stop streams all the time (the mic for voice input, a video tab…). A list rebuilt
    // from a copy that still holds a just-deleted stream segfaults Qt; that was the "shell crashes
    // when I use the mic" bug (2026-11-21). Hidden = empty lists = nothing to rebuild.
    readonly property var nodes: page.visible ? Pipewire.nodes.values : []
    readonly property var sinks: nodes.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var sources: nodes.filter(n => !n.isSink && !n.isStream && n.audio
                                                && !/\.monitor$/.test(n.name || ""))
    function isRecording(n) {
        const c = (n.properties || {})["media.class"];
        return c ? c === "Stream/Input/Audio" : (n.type & PwNodeType.AudioInStream) === PwNodeType.AudioInStream;
    }
    readonly property var streams: nodes.filter(n => n.isStream && n.audio)
    readonly property var playing: streams.filter(n => !isRecording(n))
    readonly property var recording: streams.filter(n => isRecording(n))
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    // volume/mute only update for nodes that are bound; bind only while the page shows
    PwObjectTracker {
        objects: page.visible ? [page.sink, page.source].filter(n => n).concat(page.playing, page.recording) : []
    }

    function nodeName(n) { return n ? (n.description || n.nickname || n.name || "Unknown") : "None"; }
    function appName(n) {
        const p = n.properties || {};
        return p["application.name"] || p["application.process.binary"] || n.description || n.name || "App";
    }
    function mediaName(n) { const p = n.properties || {}; return p["media.name"] || ""; }
    function deviceIcon(n, input) {
        const s = ((n.name || "") + " " + (n.description || "")).toLowerCase();
        if (s.includes("bluez") || s.includes("bluetooth")) return "󰂯";
        if (s.includes("hdmi") || s.includes("displayport")) return "󰡁";
        if (s.includes("headphone") || s.includes("headset")) return input ? "󰋎" : "󰋋";
        if (s.includes("usb")) return "󰕓";
        return input ? "󰍬" : "󰓃";
    }

    // ── Output ──────────────────────────────────────────────────────────────
    SettingCard {
        title: "Output"
        VolumeRow {
            node: page.sink
            label: page.nodeName(page.sink)
            icon: page.sink ? page.deviceIcon(page.sink, false) : "󰝟"
        }
        Repeater {
            model: page.sinks.length > 1 ? page.sinks : []
            DeviceRow {
                // modelData via context, not `required`: Qt's required-property path reads the node object
                node: modelData
                input: false
                current: page.sink && modelData.id === page.sink.id
                onChosen: Pipewire.preferredDefaultAudioSink = modelData
            }
        }
    }

    // ── Input ───────────────────────────────────────────────────────────────
    SettingCard {
        title: "Input"
        Text {
            visible: !page.source
            Layout.topMargin: 12; Layout.bottomMargin: 12
            text: "No microphone found"
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
        }
        VolumeRow {
            visible: !!page.source
            node: page.source
            label: page.nodeName(page.source)
            icon: page.source ? page.deviceIcon(page.source, true) : "󰍭"
            input: true
        }
        Repeater {
            model: page.sources.length > 1 ? page.sources : []
            DeviceRow {
                // modelData via context, not `required`: Qt's required-property path reads the node object
                node: modelData
                input: true
                current: page.source && modelData.id === page.source.id
                onChosen: Pipewire.preferredDefaultAudioSource = modelData
            }
        }
    }

    // ── Apps ────────────────────────────────────────────────────────────────
    SettingCard {
        title: "Apps"
        Text {
            visible: page.playing.length + page.recording.length === 0
            Layout.topMargin: 14; Layout.bottomMargin: 14
            text: "Apps that play or record sound show up here"
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
        }
        Repeater {
            model: page.playing.concat(page.recording)
            VolumeRow {
                // modelData via context, not `required`: Qt's required-property path reads the node object
                node: modelData
                label: page.appName(modelData)
                description: page.mediaName(modelData)
                icon: page.isRecording(modelData) ? "󰍬" : "󰎆"
                input: page.isRecording(modelData)
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        wrapMode: Text.Wrap
        text: "Pipewire remembers the device and each app's volume. The volume keys and the OSD change the output above."
        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
    }

    // a device or app: mute button, name, slider, percentage
    component VolumeRow: Item {
        id: vr
        property var node: null
        property string label: ""
        property string description: ""
        property string icon: "󰓃"
        property bool input: false
        readonly property bool ok: !!(node && node.audio)
        readonly property real vol: ok ? node.audio.volume : 0
        readonly property bool muted: ok && node.audio.muted

        Layout.fillWidth: true
        implicitHeight: 64
        Rectangle { visible: vr.y > 1; anchors.top: parent.top; width: parent.width; height: 1; color: Atelier.outline }

        RowLayout {
            anchors.fill: parent
            spacing: 14
            Rectangle {
                implicitWidth: 34; implicitHeight: 34; radius: Atelier.radiusLg
                color: vr.muted ? Qt.alpha(Atelier.red, 0.16) : Qt.alpha(Atelier.accent, 0.14)
                Behavior on color { CAnim {} }
                Text { anchors.centerIn: parent; text: vr.muted ? (vr.input ? "󰍭" : "󰝟") : vr.icon
                    font.family: Atelier.font; font.pixelSize: Atelier.fsXl; color: vr.muted ? Atelier.red : Atelier.accent }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: vr.ok
                    onClicked: vr.node.audio.muted = !vr.node.audio.muted }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: vr.label; elide: Text.ElideRight
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.Medium; color: Atelier.text }
                    Text { visible: vr.description !== ""; Layout.maximumWidth: 220; text: vr.description; elide: Text.ElideRight
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                }
                // slim bar with a gradient fill (0–150 %)
                Item {
                    id: track
                    Layout.fillWidth: true
                    implicitHeight: 16
                    readonly property real frac: Math.min(1, vr.vol / 1.5)
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: Atelier.containerHigh }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(6, parent.width * track.frac); height: 6; radius: 3
                        opacity: vr.muted ? 0.35 : 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Qt.alpha(Atelier.accent, 0.7) }
                            GradientStop { position: 1; color: Atelier.accent }
                        }
                    }
                    // 100 % mark
                    Rectangle { x: parent.width / 1.5 - 1; anchors.verticalCenter: parent.verticalCenter; width: 2; height: 10; radius: 1; color: Atelier.outline }
                    Rectangle {
                        x: parent.width * track.frac - 7; anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14; radius: 7; color: Atelier.text
                        visible: vr.ok
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        enabled: vr.ok
                        cursorShape: Qt.PointingHandCursor
                        function set(mx) { vr.node.audio.volume = Math.round(Math.max(0, Math.min(1, (mx - 6) / track.width)) * 150) / 100; }
                        onPressed: (e) => set(e.x)
                        onPositionChanged: (e) => { if (pressed) set(e.x); }
                        onWheel: (e) => { vr.node.audio.volume = Math.max(0, Math.min(1.5, Math.round((vr.vol + (e.angleDelta.y > 0 ? 0.05 : -0.05)) * 100) / 100)); }
                    }
                }
            }
            Text {
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignRight
                text: Math.round(vr.vol * 100) + "%"
                font.family: Atelier.font; font.pixelSize: Atelier.fsMd; color: vr.vol > 1 ? Atelier.peach : Atelier.subtext1
            }
        }
    }

    // pick a device as the default
    component DeviceRow: SettingRow {
        id: dr
        property var node: null
        property bool input: false
        property bool current: false
        signal chosen()
        label: page.nodeName(node)
        RowLayout {
            spacing: 8
            Text { text: page.deviceIcon(dr.node, dr.input); font.family: Atelier.font; font.pixelSize: Atelier.iconSm; color: Atelier.subtext }
            Chip {
                icon: dr.current ? "󰄬" : ""
                text: dr.current ? "In use" : "Use"
                tint: dr.current ? Atelier.green : Atelier.accent
                interactive: !dr.current
                implicitHeight: 30
                onClicked: dr.chosen()
            }
        }
    }
}
