import QtQuick
import qs.config

// The one on/off pill switch (control center, settings rows, drawers). Size it with
// implicitWidth/implicitHeight; the knob follows the height. It does not flip itself: bind `on` to
// your state and change that state in onToggled.
// Off: a faint track with a quiet knob. On: the accent fill with a bright knob. Pressing stretches the knob.
ActionSurface {
    id: ts
    property bool on: false
    signal toggled()
    checkable: true
    checked: on
    onActivated: toggled()
    implicitWidth: 40
    implicitHeight: 22
    radius: height / 2
    opacity: enabled ? 1 : 0.45
    color: on ? Atelier.accentFill : Qt.alpha(Atelier.text, 0.16)
    border.width: 1
    border.color: on ? Qt.alpha(Atelier.accent, 0.55) : Qt.alpha(Atelier.text, 0.14)
    Behavior on color { CAnim {} }
    Behavior on border.color { CAnim {} }

    readonly property real inset: 4                   // knob to track edge, all round
    Rectangle {
        id: knob
        readonly property real d: ts.height - 2 * ts.inset
        width: d + (ma.pressed ? Math.round(d * 0.28) : 0)
        height: d
        radius: height / 2
        anchors.verticalCenter: parent.verticalCenter
        x: ts.on ? ts.width - width - ts.inset : ts.inset
        color: ts.on ? Atelier.onFill : Qt.alpha(Atelier.text, 0.78)
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.12)
        Behavior on x { Anim { type: "fastSpatial" } }
        Behavior on width { Anim { type: "fastSpatial" } }
        Behavior on color { CAnim {} }
    }
    MouseArea { id: ma; anchors.fill: parent; enabled: ts.enabled; cursorShape: Qt.PointingHandCursor; onClicked: ts.activated() }
}
