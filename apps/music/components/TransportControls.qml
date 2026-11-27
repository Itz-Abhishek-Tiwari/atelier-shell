import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

RowLayout {
    property int big: 58
    spacing: Math.max(6, Math.min(16, (width - 260) / 8))
    IconBtn { icon: "shuffle"; size: 40; iconSize: 20; dot: true; active: Music.shuffle; onClicked: Music.setShuffle(!Music.shuffle) }
    IconBtn { icon: "prev"; size: 46; iconSize: 28; onClicked: Music.prev() }
    PlayButton { size: parent.big; playing: Music.playing; busy: Music.loading; onClicked: Music.toggle() }
    IconBtn { icon: "next"; size: 46; iconSize: 28; onClicked: Music.next() }
    IconBtn {
        icon: Music.loop === "track" ? "repeat_one" : "repeat"; size: 40; iconSize: 20; dot: true
        active: Music.loop !== "none"
        onClicked: Music.cycleLoop()
    }
}
