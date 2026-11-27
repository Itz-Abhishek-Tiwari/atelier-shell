import QtQuick
import QtQuick.Layouts
import qs.config

// One row of a grouped list (native settings style): label + description on the left, the
// control on the right (put the control inside). Rows after the first get a hairline divider.
Item {
    id: row

    property string label: ""
    property string description: ""
    // a sub-option of the row above (its label starts with spaces): indented, with a guide line
    readonly property bool sub: label.startsWith("  ")
    readonly property int indent: sub ? 22 : 0
    default property alias control: slot.data

    Layout.fillWidth: true
    implicitHeight: Math.max(50, inner.implicitHeight + 22)

    // divider between rows (not above the first one in its group)
    Rectangle {
        visible: row.y > 1
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.leftMargin: row.indent
        anchors.right: parent.right
        height: 1
        color: Atelier.outline
    }

    Rectangle {   // the guide that ties a sub-option to its parent row
        visible: row.sub
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 2; height: Math.min(22, row.height - 20); radius: 1
        color: Qt.alpha(Atelier.accent, 0.45)
    }

    GridLayout {
        id: inner
        readonly property bool stacked: slot.implicitWidth > 0 && width < slot.implicitWidth + 180
        columns: stacked ? 1 : 2
        columnSpacing: 16
        rowSpacing: 8
        anchors.leftMargin: row.indent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: row.label.trim()
                font.family: Atelier.fontUi
                font.pixelSize: Atelier.fsLg
                font.weight: Font.Medium
                color: Atelier.text
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: row.description
                font.family: Atelier.fontUi
                font.pixelSize: Atelier.fsMd
                color: Atelier.subtext
                wrapMode: Text.Wrap
            }
        }

        Item {
            id: slot
            Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
}
