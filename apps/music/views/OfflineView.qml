import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// Offline: every song saved on this computer. Downloads are kept until you remove them; the
// cache holds songs you've played (5 GB by default, least recently played removed first).
// Both play with no internet.
Item {
    id: root
    property string filter: "all"          // all | download | cache
    readonly property var shown: Music.offlineTracks.filter(t => filter === "all" || t.kind === filter)
    readonly property int downloads: Music.offlineTracks.filter(t => t.kind === "download").length

    onVisibleChanged: if (visible) Music.loadOffline()

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        anchors.topMargin: 28
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: "Offline"
                    font.family: Atelier.fontUi; font.pixelSize: 24; font.weight: Font.Bold
                    color: Atelier.text
                }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Music.offlineTracks.length === 0 ? "Songs you play or download play here with no internet"
                        : Music.offlineTracks.length + (Music.offlineTracks.length === 1 ? " song" : " songs") + " saved on this computer"
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg
                    color: Atelier.subtext
                }
            }
            Chip {
                visible: root.shown.length > 0
                icon: "󰒟"; text: "Shuffle"
                tint: Atelier.overlay1
                interactive: true
                implicitHeight: 34
                onClicked: Music.playList(root.shown, 0, true)
            }
            PlayButton {
                visible: root.shown.length > 0
                size: 44
                onClicked: Music.playList(root.shown, 0, false)
            }
        }

        // storage: where it lives and how full the cache is
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: storageCol.implicitHeight + 24
            radius: Atelier.radiusLg
            color: Atelier.container
            border.width: 1
            border.color: Atelier.outline

            ColumnLayout {
                id: storageCol
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 12
                anchors.leftMargin: 16; anchors.rightMargin: 16
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text { text: "󰋊"; font.family: Atelier.font; font.pixelSize: 16; color: Atelier.accent }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: (Music.usage.storage || "") + (Music.usage.fallback ? "  (storage drive not mounted, using home)" : "")
                        font.family: Atelier.font; font.pixelSize: Atelier.fsSm
                        color: Music.usage.fallback ? Atelier.peach : Atelier.subtext
                        Behavior on color { CAnim {} }
                    }
                    Text {
                        text: "Downloads " + Music.bytes(Music.usage.downloadBytes)
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; font.weight: Font.DemiBold
                        color: Atelier.text
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: "Cache"
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; font.weight: Font.DemiBold
                        color: Atelier.text
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 6
                        radius: 3
                        color: Atelier.containerHigh
                        Rectangle {
                            width: parent.width * Math.min(1, (Music.usage.cacheBytes || 0) / Math.max(1, Music.usage.cacheLimit || 1))
                            height: parent.height
                            radius: 3
                            color: Atelier.accent
                        }
                    }
                    Text {
                        text: Music.bytes(Music.usage.cacheBytes) + (Music.usage.cacheLimit ? " of " + Music.bytes(Music.usage.cacheLimit) : "")
                        font.family: Atelier.font; font.pixelSize: Atelier.fsSm
                        color: Atelier.subtext
                    }
                }
            }
        }

        // filter
        Row {
            spacing: 6
            Repeater {
                model: [
                    { id: "all", label: "All", n: Music.offlineTracks.length },
                    { id: "download", label: "Downloaded", n: root.downloads },
                    { id: "cache", label: "Cached", n: Music.offlineTracks.length - root.downloads }
                ]
                Rectangle {
                    required property var modelData
                    readonly property bool on: root.filter === modelData.id
                    implicitWidth: fl.implicitWidth + 28
                    implicitHeight: 32
                    radius: 16
                    color: on ? Atelier.accentFill : Atelier.container
                    Behavior on color { CAnim {} }
                    StateLayer { mouseArea: fma }
                    Text {
                        id: fl
                        anchors.centerIn: parent
                        text: modelData.label + "  " + modelData.n
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold
                        color: parent.on ? Atelier.onFill : Atelier.text
                        Behavior on color { CAnim {} }
                    }
                    MouseArea { id: fma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.filter = modelData.id }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.shown
                SmoothWheel { flickable: list }
                flickDeceleration: 2200
                maximumFlickVelocity: 6000
                // rows slide in, one after another, when the list loads
                populate: Transition {
                    id: pop
                    SequentialAnimation {
                        PauseAnimation { duration: Math.min(pop.ViewTransition.index, 12) * 28 }
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.emphasizedDecel }
                            NumberAnimation { property: "x"; from: 24; to: 0; duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.emphasizedDecel }
                        }
                    }
                }
                add: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 260 }
                        NumberAnimation { property: "x"; from: 24; to: 0; duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.emphasizedDecel }
                    }
                }
                displaced: Transition { NumberAnimation { properties: "x,y"; duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.emphasizedDecel } }
                delegate: TrackRow {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    track: modelData
                    inLibrary: true
                    isCurrent: Music.current !== null && Music.current.id === modelData.id
                    onActivated: Music.playList(root.shown, index, false)
                }
                footer: Item { height: 16 }
            }

            EmptyState {
                anchors.centerIn: parent
                visible: root.shown.length === 0
                icon: "󰇚"
                text: root.filter === "download" ? "Hover a song and press 󰇚 to download it"
                    : "Songs you play are saved here automatically"
            }
        }
    }
}
