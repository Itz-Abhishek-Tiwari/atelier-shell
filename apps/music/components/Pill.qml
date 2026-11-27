import QtQuick
import qs.config

// A pill button with a vector icon and a label; `on` tints it with the accent.
Rectangle {
    id: pill
    property string icon
    property string label
    property bool on: false
    property bool compact: false          // icon only (round), the label becomes a tooltip
    signal clicked()
    implicitWidth: compact ? 36 : pr.implicitWidth + 26
    implicitHeight: compact ? 36 : 32
    radius: height / 2
    Behavior on implicitWidth { Anim { type: "fastSpatial" } }
    color: on ? Qt.alpha(Atelier.accent, 0.16) : Atelier.container
    StateLayer { mouseArea: pma }
    border.width: 1
    border.color: on ? Qt.alpha(Atelier.accent, 0.4) : Atelier.outline
    Behavior on color { CAnim {} }
    Row {
        id: pr
        anchors.centerIn: parent
        spacing: 7
        SvgIcon { anchors.verticalCenter: parent.verticalCenter; name: pill.icon; size: pill.compact ? 17 : 15; color: pill.on ? Atelier.accent : Atelier.subtext1 }
        Text {
            visible: !pill.compact
            anchors.verticalCenter: parent.verticalCenter
            text: pill.label
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold
            color: pill.on ? Atelier.accent : Atelier.text
            Behavior on color { CAnim {} }
        }
    }
    MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pill.clicked() }

    // compact: the label as a small tooltip above
    Rectangle {
        visible: pill.compact && pma.containsMouse
        anchors.bottom: parent.top; anchors.bottomMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: tip.implicitWidth + 18; height: 26; radius: 13
        color: Atelier.surface0
        border.width: 1; border.color: Atelier.outline
        z: 10
        Text { id: tip; anchors.centerIn: parent; text: pill.label; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; font.weight: Font.DemiBold; color: Atelier.text }
    }
}

