import QtQuick
import Quickshell.Widgets
import qs.components
import qs.config

// One OSD slider: a tall pill. The fill rises from the bottom (true to scale),
// the value sits at the top, the icon at the bottom. Drag/click to set, scroll to
// nudge, click the icon to mute. The active slider is a little wider.
Item {
    id: lvl

    property real value: 0                 // 0..1
    property bool dimmed: false            // muted
    property bool focused: false           // the one that just changed
    property bool hovered: false           // pointer is over the OSD
    property color tint: Atelier.accent
    property string icon
    property string valueText: Math.round(value * 100)
    signal moved(real v)
    signal iconClicked()

    implicitWidth: focused ? 46 : 38
    implicitHeight: 210
    opacity: focused || hovered ? 1 : 0.6
    Behavior on implicitWidth { Anim { type: "spatial" } }
    Behavior on opacity { Anim { type: "effects" } }

    readonly property real shown: Math.max(0, Math.min(1, value))
    readonly property color fillColor: dimmed ? Atelier.overlay0 : Atelier.fill(tint)

    ClippingRectangle {
        id: track
        anchors.fill: parent
        radius: width / 2
        color: Atelier.container

        // fill
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height * lvl.shown
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(lvl.fillColor, 1.12) }
                GradientStop { position: 1; color: lvl.fillColor }
            }
            Behavior on height { enabled: !input.pressed; NumberAnimation { duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.m3.emphasizedDecel } }
        }
    }

    // value (top) — dark on the fill, normal text on the track
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 12
        text: lvl.dimmed ? "off" : lvl.valueText
        font.family: Atelier.font
        font.pixelSize: Atelier.fsSm
        font.bold: true
        color: lvl.shown > 0.92 ? Atelier.onFill : Atelier.text
        Behavior on color { CAnim {} }
    }

    // icon (bottom) — sits inside the fill once there is any
    Text {
        id: iconText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        text: lvl.icon
        font.family: Atelier.font
        font.pixelSize: 18
        color: lvl.dimmed ? Atelier.red : (lvl.shown > 0.1 ? Atelier.onFill : Atelier.text)
        Behavior on color { CAnim {} }
    }

    // Input lives on top of everything (outside the clipping effect)
    MouseArea {
        id: input
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        property bool onIcon: false
        function apply(my) { lvl.moved(Math.max(0, Math.min(1, 1 - my / height))); }
        onPressed: (m) => {
            onIcon = m.y > height - 44;
            if (!onIcon) apply(m.y);
        }
        onPositionChanged: (m) => { if (pressed && !onIcon) apply(m.y); }
        onReleased: (m) => { if (onIcon && m.y > height - 44) lvl.iconClicked(); onIcon = false; }
        onWheel: (w) => lvl.moved(Math.max(0, Math.min(1, lvl.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
