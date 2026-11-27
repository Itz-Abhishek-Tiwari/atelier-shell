import QtQuick
import QtQuick.Controls.Basic as Controls
import qs.config

SettingRow {
    id: choice
    property var options: []
    property string value: ""
    signal picked(string id)

    Controls.ComboBox {
        id: picker
        implicitWidth: Math.min(168, Math.max(104, choice.width * 0.36))
        implicitHeight: 36
        leftPadding: 12
        rightPadding: 30
        model: choice.options
        textRole: "label"
        valueRole: "id"
        currentIndex: indexOfValue(choice.value)
        displayText: currentIndex >= 0 ? currentText : choice.value
        font.family: Atelier.fontUi
        font.pixelSize: Atelier.fsMd
        Accessible.name: choice.label
        onActivated: index => choice.picked(valueAt(index))

        background: Rectangle {
            radius: Atelier.radiusSm
            color: picker.hovered || picker.down ? Atelier.containerHigh : Atelier.container
            border.color: picker.activeFocus || picker.down ? Atelier.accent : Atelier.outline
        }
        contentItem: Text {
            text: picker.displayText
            font: picker.font
            color: Atelier.text
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        indicator: Text {
            x: picker.width - width - 10
            anchors.verticalCenter: parent.verticalCenter
            text: "󰅀"
            font.family: Atelier.font
            font.pixelSize: Atelier.fsMd
            color: Atelier.subtext
        }
        delegate: Controls.ItemDelegate {
            id: option
            required property int index
            required property var modelData
            width: picker.width
            text: modelData.label
            highlighted: picker.highlightedIndex === index
            contentItem: Text {
                text: modelData.label
                font: picker.font
                color: index === picker.currentIndex ? Atelier.accent : Atelier.text
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                color: option.highlighted ? Atelier.containerHigh : "transparent"
                radius: Atelier.radiusSm
            }
        }
        popup.background: Rectangle {
            radius: Atelier.radiusSm
            color: Atelier.base
            border.color: Atelier.outline
        }
    }
}
