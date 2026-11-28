import QtQuick
import QtQuick.Layouts
import qs.config

// The atelier "chip": tinted pill with a 1px tinted border, optional glyph + label.
// Clickable when `interactive` is set.
ActionSurface {
    id: chip

    property string icon: ""
    property string text: ""
    property color tint: Atelier.accent
    property bool interactive: false
    property string variant: "tinted"   // tinted, secondary, primary
    property bool selected: false

    readonly property color ink: variant === "primary" ? Atelier.onFill
        : variant === "secondary" && !selected ? Atelier.text : tint
    property bool mono: false            // SpaceMono for numbers
    property int pad: 10
    signal clicked()
    accessibleLabel: text
    actionable: interactive
    onActivated: clicked()

    implicitHeight: variant === "tinted" ? 26 : 34
    implicitWidth: row.implicitWidth + 2 * pad
    radius: Math.min(height / 2, Atelier.radiusSm)   // a soft rectangle, not a web pill
    color: variant === "primary" ? Atelier.fill(tint)
        : variant === "secondary" && !selected ? Atelier.containerHigh : Qt.alpha(tint, 0.14)
    border.width: 1
    border.color: variant === "secondary" && !selected ? Atelier.outline : Qt.alpha(tint, 0.45)
    Behavior on color { CAnim {} }
    StateLayer { mouseArea: ma; color: chip.ink; disabled: !chip.interactive }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Text {
            visible: chip.icon !== ""
            text: chip.icon
            font.family: Atelier.font
            font.pixelSize: Atelier.fsMd
            color: chip.ink
        }
        Text {
            visible: chip.text !== ""
            text: chip.text
            font.family: chip.mono ? Atelier.font : Atelier.fontUi
            font.pixelSize: chip.variant === "tinted" ? Atelier.fsSm : Atelier.fsMd
            font.weight: Font.DemiBold
            color: chip.ink
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: chip.interactive
        hoverEnabled: chip.interactive
        cursorShape: chip.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: chip.activated()
    }
}
