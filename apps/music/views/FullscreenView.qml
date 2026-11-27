import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// Fullscreen player: only the music, Apple Music style.
//  - backdrop: the cover, heavily blurred, a bit more saturated, scaled past the screen edges
//    (a blur fades at its own edges) and drifting very slowly; crossfades per track;
//  - the cover with a soft shadow, shown at once from the local / small copy and sharpened
//    when the 1200 px version arrives;
//  - lyrics: the sung line bright white, the rest dimmed white; click a line to jump there.
// Controls fade out after a few seconds without the mouse moving. F11 / Esc / ⤡ leave.
Item {
    id: root
    signal exitRequested()
    readonly property bool has: Music.current !== null
    property bool chrome: true

    function poke() { chrome = true; hideTimer.restart(); }
    onVisibleChanged: if (visible) poke()
    Timer { id: hideTimer; interval: 3500; onTriggered: if (Music.playing) root.chrome = false }

    readonly property string lowArt: Music.currentArt          // local file or 544 px: instant
    readonly property string highArt: Music.artAt(1200)

    Rectangle { anchors.fill: parent; color: "black" }

    // ══ backdrop ══
    Item {
        id: backdrop
        anchors.fill: parent
        property bool flip: false
        property string shown: ""
        readonly property string want: root.lowArt
        onWantChanged: {
            if (want === shown) return;
            shown = want;
            flip = !flip;
            if (flip) bgB.source = want;
            else bgA.source = want;
        }
        Component.onCompleted: { bgA.source = want; shown = want; }

        Image { id: bgA; visible: false; anchors.fill: parent; sourceSize: Qt.size(192, 192); fillMode: Image.PreserveAspectCrop; asynchronous: true }
        Image { id: bgB; visible: false; anchors.fill: parent; sourceSize: Qt.size(192, 192); fillMode: Image.PreserveAspectCrop; asynchronous: true }

        Item {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            scale: 1.45            // past the screen edges: the blur's soft border never shows
            // drifts only while it's worth a redraw: shown, playing, on screen, Normal mode
            SequentialAnimation on rotation {
                running: root.visible && Music.playing && Music.uiVisible && !Atelier.opaque
                loops: Animation.Infinite
                NumberAnimation { from: -4; to: 4; duration: 26000; easing.type: Easing.InOutSine }
                NumberAnimation { from: 4; to: -4; duration: 26000; easing.type: Easing.InOutSine }
            }
            MultiEffect {
                anchors.fill: parent
                source: bgA
                autoPaddingEnabled: false
                blurEnabled: true; blur: 1.0; blurMax: 64; blurMultiplier: 1.4
                saturation: 0.45
                brightness: -0.08
                opacity: (backdrop.flip ? 0 : 1) * (bgA.status === Image.Ready ? 1 : 0)
                Behavior on opacity { Anim { type: "slowEffects"; duration: 900 } }
            }
            MultiEffect {
                anchors.fill: parent
                source: bgB
                autoPaddingEnabled: false
                blurEnabled: true; blur: 1.0; blurMax: 64; blurMultiplier: 1.4
                saturation: 0.45
                brightness: -0.08
                opacity: (backdrop.flip ? 1 : 0) * (bgB.status === Image.Ready ? 1 : 0)
                Behavior on opacity { Anim { type: "slowEffects"; duration: 900 } }
            }
        }
        // a soft vignette keeps white text readable on any cover
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.42) }
                GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.22) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.38) }
            }
        }
    }

    // visualizer across the bottom of the screen
    Visualizer {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: 24; anchors.rightMargin: 24; anchors.bottomMargin: 18
        height: root.height * 0.16
        color: "white"
        opacity: 0.16
        barWidth: 10; gap: 7
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.chrome ? Qt.ArrowCursor : Qt.BlankCursor
        onPositionChanged: root.poke()
        onClicked: root.poke()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Math.max(64, root.width * 0.07)
        anchors.rightMargin: Math.max(48, root.width * 0.05)
        spacing: Math.max(48, root.width * 0.06)

        // ══ cover + track + controls ══
        ColumnLayout {
            id: side
            Layout.alignment: Qt.AlignVCenter
            readonly property real w: Math.min(root.height * 0.5, root.width * 0.32)
            Layout.preferredWidth: w
            Layout.maximumWidth: w
            spacing: 26

            Item {
                Layout.preferredWidth: side.w
                Layout.preferredHeight: side.w
                scale: Music.playing ? 1 : 0.94
                Behavior on scale { Anim { type: "slowSpatial" } }
                // soft shadow under the cover (an analytic rounded-rect shadow, no offscreen pass)
                RectangularShadow {
                    anchors.fill: parent
                    radius: 22
                    offset.y: 22
                    blur: 60
                    spread: -6
                    color: Qt.rgba(0, 0, 0, 0.55)
                    visible: root.has
                }
                // instant: the local / small cover; the sharp one fades in over it
                Cover { anchors.fill: parent; radius: 22; source: root.lowArt }
                Cover {
                    anchors.fill: parent
                    radius: 22
                    source: root.highArt !== root.lowArt ? root.highArt : ""
                    tile: "transparent"
                    placeholder: ""
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    text: root.has ? Music.current.title : "Nothing playing"
                    elide: Text.ElideRight
                    font.family: Atelier.fontDisplay; font.pixelSize: Math.round(root.height * 0.032); font.weight: Font.Bold
                    color: "white"
                }
                Text {
                    Layout.fillWidth: true
                    text: root.has ? (Music.current.artist || "") : ""
                    elide: Text.ElideRight
                    font.family: Atelier.fontUi; font.pixelSize: Math.round(root.height * 0.019); font.weight: Font.Medium
                    color: Qt.rgba(1, 1, 1, 0.65)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 20
                opacity: root.chrome ? 1 : 0
                Behavior on opacity { Anim { type: "slowEffects"; duration: 500 } }

                // seek, in white
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Item {
                        id: seek
                        Layout.fillWidth: true
                        implicitHeight: 14
                        property real dragFrac: -1
                        readonly property real frac: dragFrac >= 0 ? dragFrac : (Music.dur > 0 ? Math.min(1, Music.pos / Music.dur) : 0)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: sMa.containsMouse || seek.dragFrac >= 0 ? 8 : 5
                            radius: height / 2
                            color: Qt.rgba(1, 1, 1, 0.22)
                            Behavior on height { Anim { type: "fastSpatial" } }
                            Rectangle { width: Math.max(height, parent.width * seek.frac); height: parent.height; radius: parent.radius; color: Qt.rgba(1, 1, 1, 0.92) }
                        }
                        MouseArea {
                            id: sMa
                            anchors.fill: parent
                            anchors.margins: -8
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            function at(x) { return Math.max(0, Math.min(1, (x - 8) / seek.width)); }
                            onPressed: (m) => seek.dragFrac = at(m.x)
                            onPositionChanged: (m) => { if (pressed) seek.dragFrac = at(m.x); }
                            onReleased: { Music.seek(seek.dragFrac * Music.dur); seek.dragFrac = -1; }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: Music.clock(seek.frac * Music.dur); font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: Qt.rgba(1, 1, 1, 0.6) }
                        Item { Layout.fillWidth: true }
                        Text { text: "-" + Music.clock(Math.max(0, Music.dur - seek.frac * Music.dur)); font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: Qt.rgba(1, 1, 1, 0.6) }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Math.max(14, side.w * 0.05)
                    IconBtn { icon: "shuffle"; size: 48; iconSize: 22; tint: "white"; dot: true; active: Music.shuffle; onClicked: Music.setShuffle(!Music.shuffle) }
                    IconBtn { icon: "prev"; size: 60; iconSize: 38; tint: "white"; onClicked: Music.prev() }
                    // white play button: an accent fill looks muddy over a coloured backdrop
                    Rectangle {
                        implicitWidth: 76; implicitHeight: 76; radius: 38
                        color: "white"
                        scale: playMa.pressed ? 0.92 : playMa.containsMouse ? 1.05 : 1
                        Behavior on scale { Anim { type: "fastSpatial" } }
                        SvgIcon {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: Music.playing ? 0 : 2
                            name: Music.playing ? "pause" : "play"
                            size: 38
                            color: "#111111"
                        }
                        MouseArea { id: playMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Music.toggle() }
                    }
                    IconBtn { icon: "next"; size: 60; iconSize: 38; tint: "white"; onClicked: Music.next() }
                    IconBtn {
                        icon: Music.loop === "track" ? "repeat_one" : "repeat"; size: 48; iconSize: 22; tint: "white"; dot: true
                        active: Music.loop !== "none"
                        onClicked: Music.cycleLoop()
                    }
                }
            }
        }

        // ══ lyrics ══
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.centerIn: parent
                visible: Music.lyricsState !== "synced" && Music.lyricsState !== "plain"
                text: Music.lyricsState === "loading" ? "Looking for lyrics…"
                    : Music.lyricsState === "instrumental" ? "♪  Instrumental  ♪" : ""
                font.family: Atelier.fontDisplay; font.pixelSize: Math.round(root.height * 0.03); font.weight: Font.Bold
                color: Qt.rgba(1, 1, 1, 0.5)
            }

            ListView {
                id: lyricView
                anchors.fill: parent
                anchors.topMargin: root.height * 0.08
                anchors.bottomMargin: root.height * 0.08
                visible: Music.lyricsState === "synced"
                clip: true
                interactive: false
                model: Music.lyricsState === "synced" ? Music.lyrics : []
                currentIndex: Music.lyricIndex
                highlightRangeMode: ListView.ApplyRange
                preferredHighlightBegin: height * 0.36
                preferredHighlightEnd: height * 0.36 + 90
                highlightMoveDuration: 650
                highlightMoveVelocity: -1
                highlight: Item {}
                spacing: Math.round(root.height * 0.022)
                header: Item { height: lyricView.height * 0.36 }
                footer: Item { height: lyricView.height * 0.64 }
                delegate: Text {
                    id: line
                    required property var modelData
                    required property int index
                    readonly property bool current: index === Music.lyricIndex
                    readonly property bool past: index < Music.lyricIndex
                    width: lyricView.width
                    wrapMode: Text.WordWrap
                    text: modelData[1] === "" ? "♪" : modelData[1]
                    font.family: Atelier.fontDisplay
                    font.pixelSize: Math.round(root.height * 0.04)
                    font.weight: Font.ExtraBold
                    color: "white"
                    opacity: current ? 1 : past ? 0.28 : 0.4
                    scale: current ? 1 : 0.97
                    transformOrigin: Item.Left
                    Behavior on opacity { Anim { type: "slowEffects"; duration: 500 } }
                    Behavior on scale { Anim { type: "spatial" } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Music.seek(line.modelData[0]) }
                }
            }
            Flickable {
                anchors.fill: parent
                anchors.topMargin: root.height * 0.08
                visible: Music.lyricsState === "plain"
                clip: true
                contentHeight: plain.implicitHeight
                Text {
                    id: plain
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Music.plainLyrics
                    lineHeight: 1.3
                    font.family: Atelier.fontDisplay; font.pixelSize: Math.round(root.height * 0.03); font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.85)
                }
            }
        }
    }

    // leave fullscreen
    IconBtn {
        anchors.top: parent.top; anchors.right: parent.right
        anchors.margins: 28
        icon: "fullscreen_exit"; size: 46; iconSize: 24; tint: "white"
        opacity: root.chrome ? 1 : 0
        Behavior on opacity { Anim { type: "slowEffects"; duration: 500 } }
        onClicked: root.exitRequested()
    }
}
