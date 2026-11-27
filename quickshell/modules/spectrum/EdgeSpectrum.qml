import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.config
import qs.services

// Edge spectrum: a soft audio spectrum rising from the bottom frame edge while music plays.
// Performance first:
//  - its own thin, click-through layer ("quickshell-spectrum", no blur: hypr/conf/rules.lua),
//    never part of the always-mapped full-screen layers, so a 60 fps update only redraws a
//    strip, and nothing behind it is re-blurred;
//  - the window only exists while something plays, in Normal mode, with no fullscreen window
//    on the screen (a video / game), and Settings → Appearance → Edge spectrum on;
//  - cava runs only while it's shown (services/Spectrum.qml).
Scope {
    id: root

    readonly property bool playing: Mpris.players.values.some(p => p.isPlaying)
    readonly property bool fullscreenUp: {
        const m = Hyprland.focusedMonitor;
        return !!(m && m.activeWorkspace && m.activeWorkspace.hasFullscreen);
    }
    readonly property bool wanted: Settings.appearance.edgeSpectrum && playing
                                   && Perf.mode === "normal" && !fullscreenUp
    // a short grace period so a track change (stop → play) doesn't unmap / remap the window
    property bool shown: false
    onWantedChanged: if (wanted) { hide.stop(); shown = true; } else hide.restart()
    Timer { id: hide; interval: 2500; onTriggered: root.shown = false }
    Component.onCompleted: shown = wanted

    Binding { target: Spectrum; property: "active"; value: root.wanted }

    LazyLoader {
        active: root.shown
        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")) ?? Quickshell.screens[0]
            anchors { bottom: true; left: true; right: true }
            margins.left: Atelier.insetLeft
            margins.right: Atelier.insetRight
            implicitHeight: Atelier.insetBottom + 34
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-spectrum"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}                        // click-through

            Row {
                id: row
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                readonly property real gap: 3
                readonly property real bw: Math.max(2, (win.width - gap * (Spectrum.count - 1)) / Spectrum.count)
                spacing: gap
                opacity: Spectrum.bars.length ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 600 } }
                Repeater {
                    model: Spectrum.count
                    Rectangle {
                        required property int index
                        // mirrored: lows in the middle, highs towards both ends
                        readonly property int bin: Math.abs(index - Spectrum.count / 2) * 2
                        readonly property real level: Spectrum.bars.length ? (Spectrum.bars[Math.min(Spectrum.count - 1, bin)] || 0) : 0
                        anchors.bottom: parent.bottom
                        width: row.bw
                        height: Math.max(2, level * win.height)
                        radius: Math.min(row.bw / 2, 3)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.alpha(Atelier.accent, 0.05) }
                            GradientStop { position: 1.0; color: Qt.alpha(Atelier.accent, 0.55) }
                        }
                    }
                }
            }
        }
    }
}
