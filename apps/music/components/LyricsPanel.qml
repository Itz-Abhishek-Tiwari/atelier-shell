import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

Rectangle {
    radius: Atelier.radiusLg
    color: Atelier.container
    border.width: 1
    border.color: Atelier.outline
    clip: true

    // visualizer along the bottom, behind the lyrics
    Visualizer {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.margins: 18
        height: Math.min(90, parent.height * 0.22)
        color: Atelier.accent
        opacity: 0.22
        barWidth: 5; gap: 4
    }

    ColumnLayout {
        anchors.centerIn: parent
        visible: Music.lyricsState !== "synced" && Music.lyricsState !== "plain"
        spacing: 10
        SvgIcon {
            id: lyricsIcon
            Layout.alignment: Qt.AlignHCenter
            name: "lyrics"; size: 30
            color: Atelier.overlay1
            SequentialAnimation on opacity {
                running: Music.lyricsState === "loading"
                loops: Animation.Infinite
                onRunningChanged: if (!running) lyricsIcon.opacity = 1
                NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: !(Music.current !== null) ? "Lyrics show up here"
                : Music.lyricsState === "loading" ? "Looking for lyrics…"
                : Music.lyricsState === "instrumental" ? "Instrumental"
                : "No lyrics found for this song"
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg
            color: Atelier.subtext
        }
    }

    ListView {
        id: lyricView
        anchors.fill: parent
        anchors.margins: 8
        visible: Music.lyricsState === "synced"
        clip: true
        model: Music.lyricsState === "synced" ? Music.lyrics : []
        spacing: 6
        // Keep the sung line centred. Done by hand (not highlight-follow): the panel is often
        // created hidden, and highlight-follow never catches up after it becomes visible.
        property bool userScrolled: false
        function targetFor(i) {
            const keep = contentY;
            positionViewAtIndex(Math.max(0, i), ListView.Center);
            const t = contentY;
            contentY = keep;
            return t;
        }
        function follow(animate) {
            if (!visible || Music.lyricIndex < 0 || count === 0) return;
            const t = targetFor(Music.lyricIndex);
            if (animate) { followAnim.to = t; followAnim.restart(); }
            else { followAnim.stop(); contentY = t; }
        }
        Anim { id: followAnim; target: lyricView; property: "contentY"; type: "emphasizedDecel"; duration: 600 }
        Connections {
            target: Music
            function onLyricIndexChanged() { if (!lyricView.moving && !lyricView.userScrolled) lyricView.follow(true); }
        }
        onVisibleChanged: if (visible) { userScrolled = false; Qt.callLater(() => follow(false)); }
        onCountChanged: Qt.callLater(() => follow(false))
        onHeightChanged: Qt.callLater(() => follow(false))
        // scrolling by hand pauses following for a few seconds
        onMovementStarted: { userScrolled = true; resume.restart(); }
        Timer { id: resume; interval: 4000; onTriggered: lyricView.userScrolled = false }
        header: Item { height: lyricView.height / 2 - 30 }
        footer: Item { height: lyricView.height / 2 - 30 }
        SmoothWheel { flickable: lyricView }
        delegate: Item {
            id: ln
            required property var modelData
            required property int index
            readonly property bool current: index === Music.lyricIndex
            readonly property int dist: Math.abs(index - Music.lyricIndex)
            width: lyricView.width
            height: lt.implicitHeight + 12
            Text {
                id: lt
                anchors.verticalCenter: parent.verticalCenter
                x: 24
                width: parent.width - 48
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: ln.modelData[1] === "" ? "♪" : ln.modelData[1]
                font.family: Atelier.fontDisplay
                font.pixelSize: 21
                font.weight: Font.Bold
                color: ln.current ? Atelier.text : (lnMa.containsMouse ? Atelier.subtext1 : Atelier.subtext)
                Behavior on color { CAnim {} }
                opacity: ln.current ? 1 : Math.max(0.28, 0.75 - ln.dist * 0.12)
                scale: ln.current ? 1.06 : 1
                transformOrigin: Item.Center
                Behavior on scale { Anim { type: "spatial" } }
                Behavior on opacity { Anim { type: "slowEffects" } }
            }
            MouseArea {
                id: lnMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Music.seek(ln.modelData[0])
            }
        }
    }

    Flickable {
        id: plainView
        anchors.fill: parent
        anchors.margins: 28
        visible: Music.lyricsState === "plain"
        clip: true
        contentHeight: plainText.implicitHeight
        SmoothWheel { flickable: plainView }
        Text {
            id: plainText
            width: plainView.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: Music.plainLyrics
            lineHeight: 1.35
            font.family: Atelier.fontUi; font.pixelSize: 17
            color: Atelier.text
        }
    }
}
