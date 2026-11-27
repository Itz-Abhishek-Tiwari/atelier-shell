import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// Queue: what's playing and what's next. Click jumps to a track; × removes one.
// Autoplay keeps the queue going with similar songs when it runs out.
Item {
    id: root

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
                    text: "Queue"
                    font.family: Atelier.fontUi; font.pixelSize: 24; font.weight: Font.Bold
                    color: Atelier.text
                }
                Text {
                    readonly property int remaining: Math.max(0, Music.queue.length - Music.index - 1)
                    text: Music.queue.length === 0 ? "Nothing queued" : remaining + (remaining === 1 ? " song" : " songs") + " up next"
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg
                    color: Atelier.subtext
                }
            }
            Chip {
                icon: "󰑖"
                text: Music.autoplay ? "Autoplay on" : "Autoplay off"
                tint: Music.autoplay ? Atelier.accent : Atelier.overlay1
                interactive: true
                implicitHeight: 32
                onClicked: Music.setAutoplay(!Music.autoplay)
            }
            Chip {
                visible: Music.queue.length > 0
                icon: "󰩺"; text: "Clear"
                tint: Atelier.overlay1
                interactive: true
                implicitHeight: 32
                onClicked: Music.clear()
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
                model: Music.queue
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
                Component.onCompleted: positionViewAtIndex(Math.max(0, Music.index - 1), ListView.Beginning)
                delegate: TrackRow {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    track: modelData
                    number: index
                    inQueue: true
                    isCurrent: index === Music.index
                    opacity: index < Music.index ? 0.55 : 1
                    onActivated: Music.jump(index)
                    onRemoveRequested: Music.remove(index)
                }
                footer: Item { height: 16 }
            }

            EmptyState {
                anchors.centerIn: parent
                visible: Music.queue.length === 0
                icon: "󰲸"
                text: "Play something and it lines up here"
            }
        }
    }
}
