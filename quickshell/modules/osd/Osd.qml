import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.components
import qs.config
import qs.services

// Volume + brightness OSD (Caelestia-style): a drawer out of the right border with two
// live, draggable sliders. Whatever just changed is highlighted; hovering keeps it open.
//  - volume reacts to any change of the default sink (media keys, scripts, apps, bar)
//  - brightness: `qs ipc call osd brightnessUp/Down`, SysState changes, or scripts'
//    sys-brightness notifications (routed here by Notifs.qml)
Item {
    id: root

    // a strip along the right edge of the shared DrawerHost window
    anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
    width: drawer.itemDepth + Atelier.maxInset
    visible: drawer.visible || shown
    readonly property Item inputItem: drawer        // the host makes only this clickable

    property bool suppressed: false       // e.g. while the control center (with its own sliders) is open
    property bool shown: false
    property bool choosingOutput: false
    onShownChanged: if (!shown) choosingOutput = false

    readonly property var outputs: choosingOutput ? Pipewire.nodes.values
        .filter(node => node.isSink && !node.isStream && node.audio)
        .map(node => ({ id: node.id, label: node.description || node.nickname || node.name || "Audio device" })) : []

    function selectOutput(id) {
        const output = Pipewire.nodes.values.find(node => node.id === id && node.isSink && !node.isStream && node.audio);
        if (output) Pipewire.preferredDefaultAudioSink = output;
    }
    property string focusKind: "volume"   // which slider triggered the OSD

    signal opening(var screen)

    function show(kind, screen) {
        if (suppressed || !armed) return;
        if (!shown || screen) opening(screen || null);
        focusKind = kind;
        shown = true;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: Math.round(Settings.behavior.osdSeconds * 1000)
        onTriggered: if (!hover.hovered) root.shown = false; else restart()
    }

    // Don't pop up while things settle (startup, default sink switching)
    property bool armed: false
    Timer { id: armTimer; interval: 1500; running: true; onTriggered: root.armed = true }

    // ── Volume ──────────────────────────────────────────────────────────────
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink && sink.audio ? sink.audio : null
    readonly property real volume: audio ? audio.volume : 0
    readonly property bool muted: audio ? audio.muted : false
    onSinkChanged: { armed = false; armTimer.restart(); }
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    Connections {
        target: root.audio
        function onVolumeChanged() { root.show("volume"); }
        function onMutedChanged() { root.show("volume"); }
    }

    function setVolume(v) {
        if (!audio) return;
        audio.volume = Math.max(0, Math.min(1, v));
        if (audio.muted && v > 0) audio.muted = false;
    }

    // ── Brightness ──────────────────────────────────────────────────────────
    function setBrightness(v) {
        SysState.setBrightness(v);
        show("brightness");
    }

    function brightnessStep(delta) {
        SysState.setBrightness(SysState.brightness + delta);
        show("brightness");
    }

    Connections {
        target: Notifs
        function onOsdRequested(kind, value) {
            if (kind === "brightness") {
                if (value >= 0) SysState.brightness = value;
                else SysState.refreshBrightness();
            }
            root.show(kind);
        }
    }

    // ── Look ────────────────────────────────────────────────────────────────
    EdgeDrawer {
        id: drawer
        edge: "right"
        open: root.shown
        bodyWidth: root.choosingOutput ? 270 : 124
        bodyHeight: 274
        color: root.choosingOutput ? Atelier.base : Atelier.surface

        HoverHandler { id: hover; onHoveredChanged: if (!hovered) hideTimer.restart() }

        Column {
            anchors.centerIn: parent
            visible: !root.choosingOutput
            spacing: 8

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                OsdLevel {
                    focused: root.focusKind === "volume"
                    hovered: hover.hovered
                    value: root.volume
                    dimmed: root.muted
                    tint: Atelier.accent
                    icon: root.muted || root.volume === 0 ? "󰝟" : root.volume > 0.66 ? "󰕾" : root.volume > 0.33 ? "󰖀" : "󰕿"
                    onMoved: (v) => root.setVolume(v)
                    onIconClicked: if (root.audio) root.audio.muted = !root.audio.muted
                }

                OsdLevel {
                    focused: root.focusKind === "brightness"
                    hovered: hover.hovered
                    value: SysState.brightness
                    tint: Atelier.yellow
                    icon: SysState.brightness > 0.66 ? "󰃠" : SysState.brightness > 0.33 ? "󰃟" : "󰃞"
                    onMoved: (v) => root.setBrightness(v)
                }
            }

            Chip {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Output"
                variant: "secondary"
                icon: "󰅀"
                interactive: true
                onClicked: {
                    root.choosingOutput = true;
                    hideTimer.restart();
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            visible: root.choosingOutput
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "Audio output"
                    font.family: Atelier.fontUi
                    font.pixelSize: Atelier.fsLg
                    font.weight: Font.DemiBold
                    color: Atelier.text
                }
                Chip {
                    text: "Back"
                    icon: "󰅁"
                    variant: "secondary"
                    interactive: true
                    onClicked: root.choosingOutput = false
                }
            }

            ListView {
                id: outputList
                Layout.fillHeight: true
                Layout.fillWidth: true
                clip: true
                spacing: 3
                model: root.outputs
                Controls.ScrollBar.vertical: Controls.ScrollBar {}

                delegate: Controls.ItemDelegate {
                    id: outputRow
                    required property var modelData
                    readonly property bool selected: !!root.sink && root.sink.id === modelData.id
                    width: outputList.width
                    height: 42
                    text: modelData.label
                    onClicked: root.selectOutput(modelData.id)

                    contentItem: RowLayout {
                        Text {
                            Layout.fillWidth: true
                            text: outputRow.text
                            elide: Text.ElideRight
                            font.family: Atelier.fontUi
                            font.pixelSize: Atelier.fsMd
                            color: Atelier.text
                        }
                        Text {
                            visible: outputRow.selected
                            text: "󰄬"
                            font.family: Atelier.font
                            font.pixelSize: Atelier.fsMd
                            color: Atelier.accent
                        }
                    }
                    background: Rectangle {
                        radius: Atelier.radiusSm
                        color: outputRow.selected ? Qt.alpha(Atelier.accent, 0.16)
                            : outputRow.hovered ? Atelier.containerHigh : Atelier.container
                        border.color: outputRow.activeFocus ? Atelier.accent : "transparent"
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: outputList.count === 0
                    text: "No audio outputs found"
                    font.family: Atelier.fontUi
                    font.pixelSize: Atelier.fsMd
                    color: Atelier.subtext
                }
            }
        }
    }
}
