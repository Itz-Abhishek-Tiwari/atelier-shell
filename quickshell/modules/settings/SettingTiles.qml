import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config

// Visual choice, system-settings style: a row of tiles, each a small drawn preview with a
// label under it; the picked one gets an accent ring. Sits inside a SettingCard.
//
//   SettingTiles {
//       options: [{ id: "left", label: "Left" }, ...]; value: ...; onPicked: (id) => ...
//       preview: Component { Item { readonly property var option: parent.option ... } }
//   }
// The preview component is loaded once per tile; read `parent.option` (the option object)
// and `parent.selected` from it.
Item {
    id: root

    property string label: ""
    property string description: ""
    property var options: []
    property string value: ""
    property Component preview
    property real tileHeight: 72
    signal picked(string id)

    Layout.fillWidth: true
    implicitHeight: head.implicitHeight + (head.visible ? 12 : 0) + tileHeight + 34 + 22

    // divider like SettingRow (not above the first row)
    Rectangle {
        visible: root.y > 1
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Atelier.outline
    }

    ColumnLayout {
        id: head
        visible: root.label !== ""
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 12
        spacing: 2
        Text { text: root.label; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.Medium; color: Atelier.text }
        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.description
            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
            wrapMode: Text.Wrap
        }
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        spacing: 12

        Repeater {
            model: root.options
            Item {
                id: tile
                required property var modelData
                readonly property bool on: root.value === modelData.id
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: root.tileHeight + 34

                Rectangle {
                    id: frame
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: root.tileHeight
                    radius: Atelier.radiusSm
                    color: Atelier.containerHigh
                    border.width: tile.on ? 2 : 1
                    border.color: tile.on ? Atelier.accent : (ma.containsMouse ? Qt.alpha(Atelier.text, 0.25) : Atelier.outline)
                    Behavior on border.color { CAnim {} }
                    clip: true

                    Loader {
                        anchors.fill: parent
                        anchors.margins: 6
                        readonly property var option: tile.modelData
                        readonly property bool selected: tile.on
                        sourceComponent: root.preview
                    }
                }
                Text {
                    anchors.top: frame.bottom
                    anchors.topMargin: 8
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tile.modelData.label
                    font.family: Atelier.fontUi
                    font.pixelSize: Atelier.fsMd
                    font.weight: tile.on ? Font.DemiBold : Font.Normal
                    color: tile.on ? Atelier.text : Atelier.subtext1
                    Behavior on color { CAnim {} }
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(tile.modelData.id)
                }
            }
        }
    }
}
