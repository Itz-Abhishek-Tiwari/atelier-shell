import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// Now playing: cover, title, seek, controls and time-synced lyrics (lrclib.net via lyrics.py).
// Wide windows put the cover beside the lyrics; narrow ones stack a compact header above them,
// so nothing ever overlaps. Click a lyric line to jump there.
Item {
    id: root
    property bool active: false
    signal fullscreenRequested()
    readonly property bool has: Music.current !== null
    readonly property bool compact: width < 860

    // ══ wide: cover column | lyrics ══
    RowLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 32
        visible: !root.compact

        ColumnLayout {
            id: side
            readonly property real w: Math.max(280, Math.min(400, Math.min((root.width - 96) * 0.44, root.height - 330)))
            Layout.preferredWidth: w
            Layout.maximumWidth: w
            Layout.minimumWidth: w
            Layout.alignment: Qt.AlignVCenter
            spacing: 16

            CrossfadeCover {
                Layout.preferredWidth: side.w
                Layout.preferredHeight: side.w
                radius: Atelier.radiusLg + 4
            }
            TrackTitle { Layout.fillWidth: true }
            SeekBar { Layout.fillWidth: true; visible: root.has }
            TransportControls { Layout.alignment: Qt.AlignHCenter; Layout.maximumWidth: side.w; visible: root.has }
            NowActions { onFullscreenRequested: root.fullscreenRequested(); Layout.fillWidth: true; Layout.topMargin: 4; visible: root.has }
        }

        LyricsPanel { Layout.fillWidth: true; Layout.fillHeight: true }
    }

    // ══ compact: header (small cover + track + controls) above the lyrics ══
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 18
        visible: root.compact

        RowLayout {
            Layout.fillWidth: true
            spacing: 20
            CrossfadeCover {
                Layout.preferredWidth: 168
                Layout.preferredHeight: 168
                radius: Atelier.radiusLg
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10
                TrackTitle { Layout.fillWidth: true; titleSize: 20 }
                SeekBar { Layout.fillWidth: true; visible: root.has }
                TransportControls { Layout.alignment: Qt.AlignLeft; big: 50; visible: root.has }
            }
        }
        NowActions { onFullscreenRequested: root.fullscreenRequested(); Layout.fillWidth: true; visible: root.has }
        LyricsPanel { Layout.fillWidth: true; Layout.fillHeight: true }
    }

}
