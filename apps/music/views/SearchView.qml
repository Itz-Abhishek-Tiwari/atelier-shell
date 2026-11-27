import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// Search: songs on YouTube Music. Enter searches; ↑/↓ pick a result, Enter plays it
// (as a radio: the song, then similar ones), Shift+Enter adds it to the queue.
Item {
    id: root
    function focusInput() { input.forceActiveFocus(); input.selectAll(); }
    // a search started elsewhere (IPC) fills the box, so Enter then plays instead of re-searching
    Connections {
        target: Music
        function onLastQueryChanged() { if (input.text.trim() !== Music.lastQuery) input.text = Music.lastQuery; }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        anchors.topMargin: 28
        spacing: 18

        Text {
            text: "Search"
            font.family: Atelier.fontUi; font.pixelSize: 24; font.weight: Font.Bold
            color: Atelier.text
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: Atelier.radiusMd
            color: Atelier.container
            border.width: 1
            border.color: input.activeFocus ? Qt.alpha(Atelier.accent, 0.7) : Atelier.outline
            Behavior on border.color { CAnim {} }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 8
                spacing: 12
                SvgIcon {
                    id: searchIcon
                    name: "search"; size: 20
                    color: input.activeFocus || Music.searching ? Atelier.accent : Atelier.subtext
                    Behavior on color { CAnim {} }
                    // searching: the icon breathes
                    SequentialAnimation on opacity {
                        running: Music.searching
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) searchIcon.opacity = 1
                        NumberAnimation { to: 0.3; duration: 450; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutSine }
                    }
                }
                TextInput {
                    id: input
                    Layout.fillWidth: true
                    font.family: Atelier.fontUi
                    font.pixelSize: 15
                    color: Atelier.text
                    selectionColor: Qt.alpha(Atelier.accent, 0.4)
                    selectedTextColor: Atelier.text
                    clip: true
                    selectByMouse: true
                    Keys.onPressed: (e) => {
                        if (e.key === Qt.Key_Down) { list.incrementCurrentIndex(); e.accepted = true; }
                        else if (e.key === Qt.Key_Up) { list.decrementCurrentIndex(); e.accepted = true; }
                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            const t = Music.results[list.currentIndex];
                            if (input.text.trim() !== Music.lastQuery || !t) { Music.search(input.text); list.currentIndex = 0; }
                            else if (e.modifiers & Qt.ShiftModifier) Music.add(t);
                            else Music.radio(t);
                            e.accepted = true;
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !input.text
                        text: "What do you want to listen to?"
                        font: input.font
                        color: Atelier.subtext
                        opacity: 0.7
                    }
                }
                IconButton {
                    visible: input.text !== ""
                    icon: "󰅖"; size: 32; glyphSize: 13
                    onClicked: { input.text = ""; input.forceActiveFocus(); }
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
                model: Music.results
                currentIndex: 0
                highlightMoveDuration: 0
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
                header: Text {
                    visible: Music.results.length > 0
                    height: visible ? 30 : 0
                    text: "Songs"
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.Bold
                    color: Atelier.subtext
                }
                delegate: TrackRow {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    track: modelData
                    isCurrent: Music.current !== null && Music.current.id === modelData.id
                    border.width: ListView.isCurrentItem && input.activeFocus ? 1 : 0
                    border.color: Qt.alpha(Atelier.accent, 0.5)
                    onActivated: { list.currentIndex = index; Music.radio(modelData); }
                }
                footer: Item { height: 16 }
            }

            EmptyState {
                anchors.centerIn: parent
                visible: list.count === 0 && !Music.searching
                icon: Music.lastQuery ? "󰍉" : "󰝚"
                text: Music.lastQuery ? "No songs found for “" + Music.lastQuery + "”" : "Search for a song, artist or album"
            }
        }
    }
}
