import QtQuick
import qs.config

// Text field row; `committed` fires on Enter or when focus leaves the field.
SettingRow {
    id: root

    property string text: ""
    property string placeholder: ""
    property int fieldWidth: 240
    signal committed(string text)

    Rectangle {
        implicitWidth: root.fieldWidth
        implicitHeight: 34
        radius: 17
        color: Atelier.containerHigh
        border.width: 1
        border.color: input.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
        Behavior on border.color { ColorAnimation { duration: Atelier.durFast } }

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            verticalAlignment: Text.AlignVCenter
            font.family: Atelier.fontUi
            font.pixelSize: 12
            color: Atelier.text
            clip: true
            selectByMouse: true
            text: root.text
            onEditingFinished: if (text !== root.text) root.committed(text)
            // follow outside changes unless the user is typing
            Connections { target: root; function onTextChanged() { if (!input.activeFocus) input.text = root.text; } }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !input.text && !input.activeFocus
                text: root.placeholder
                font.family: Atelier.fontUi
                font.pixelSize: 12
                color: Atelier.subtext
                opacity: 0.6
            }
        }
    }
}
