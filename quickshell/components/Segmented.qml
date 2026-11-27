import QtQuick
import qs.config

// A segmented tab bar (the music drawer's tabs): equal segments in a rounded container,
// the current one filled. model: [{ id, icon, label }]
Rectangle {
    id: sg
    property var model: []
    property string current: ""
    property int segmentWidth: 104
    signal picked(string id)

    implicitWidth: model.length * segmentWidth + 6 + (model.length - 1) * 2
    implicitHeight: 36
    radius: Atelier.radiusLg
    color: Atelier.container

    Row {
        id: segRow
        anchors.fill: parent
        anchors.margins: 3
        spacing: 2
        Repeater {
            model: sg.model
            Rectangle {
                id: seg
                required property var modelData
                readonly property bool on: sg.current === modelData.id
                width: sg.segmentWidth
                height: segRow.height
                radius: height / 2
                color: on ? Atelier.accentFill : "transparent"
                Behavior on color { CAnim {} }
                StateLayer { mouseArea: segMa; color: parent.on ? Atelier.onFill : Atelier.text }
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: !!seg.modelData.icon
                           text: seg.modelData.icon || ""; font.family: Atelier.font; font.pixelSize: Atelier.fsLg
                           color: seg.on ? Atelier.onFill : Atelier.subtext }
                    Text { anchors.verticalCenter: parent.verticalCenter
                           text: seg.modelData.label; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold
                           color: seg.on ? Atelier.onFill : Atelier.text }
                }
                MouseArea { id: segMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sg.picked(seg.modelData.id) }
            }
        }
    }
}
