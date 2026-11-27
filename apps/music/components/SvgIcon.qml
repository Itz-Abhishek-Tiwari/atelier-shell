import QtQuick
import qs.config

// The app's icons, drawn with the shell's own icon font (Atelier.font, a Nerd Font with the
// Material Design Icons set), so they match the bar, drawers and Settings glyph for glyph.
// Use `name` from the table below (each was checked against the font: none are missing).
// (Kept the old SvgIcon name so every caller works unchanged.)
Item {
    id: ic
    property string name: "play"
    property color color: Atelier.text
    property real size: 20

    implicitWidth: size
    implicitHeight: size

    readonly property var glyphs: ({
        "play": "󰐊", "pause": "󰏤", "next": "󰒭", "prev": "󰒮",
        "shuffle": "󰒝", "repeat": "󰑖", "repeat_one": "󰑘", "download": "󰇚",
        "downloaded": "󰗠", "fullscreen": "󰊓", "fullscreen_exit": "󰊔", "queue": "󰲸",
        "lyrics": "󰍡", "radio": "󰐹", "autoplay": "󰛤", "menu": "󰍜",
        "menu_open": "󰮫", "home": "󰋜", "search": "󰍉", "offline": "󰇚",
        "now": "󰝚", "close": "󰅖", "add": "󰐕", "play_next": "󰐑",
        "delete": "󰆴", "refresh": "󰑐", "heart": "󰋕", "heart_fill": "󰋑",
        "more": "󰇙", "volume_up": "󰕾", "volume_down": "󰖀", "volume_off": "󰖁",
        "sleep": "󰒲", "playlist_add": "󰐒", "library": "󰌳", "history": "󰋚",
        "edit": "󰏫", "check": "󰄬", "back": "󰁍", "chevron": "󰅂"
    })

    Text {
        anchors.centerIn: parent
        text: ic.glyphs[ic.name] || ""
        font.family: Atelier.font
        font.pixelSize: Math.round(ic.size)
        color: ic.color
    }
}
