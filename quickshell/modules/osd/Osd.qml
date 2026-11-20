import QtQuick
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
    width: 170 + Atelier.maxInset
    visible: drawer.visible || shown
    readonly property Item inputItem: drawer        // the host makes only this clickable

    property bool suppressed: false       // e.g. while the control center (with its own sliders) is open
    property bool shown: false
    property string focusKind: "volume"   // which slider triggered the OSD

    function show(kind) {
        if (suppressed || !armed) return;
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
        bodyWidth: 124
        bodyHeight: 246

        HoverHandler { id: hover; onHoveredChanged: if (!hovered) hideTimer.restart() }

        Row {
            anchors.centerIn: parent
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
    }
}
