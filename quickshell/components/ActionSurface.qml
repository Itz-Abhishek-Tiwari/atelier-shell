import QtQuick
import qs.config

Rectangle {
    id: surface

    property string accessibleLabel: ""
    property bool actionable: true
    property bool checkable: false
    property bool checked: false
    signal activated()

    activeFocusOnTab: actionable
    Accessible.role: !actionable ? Accessible.StaticText : checkable ? Accessible.CheckBox : Accessible.Button
    Accessible.name: accessibleLabel
    Accessible.checkable: actionable && checkable
    Accessible.checked: checked
    Accessible.onPressAction: if (actionable && enabled) activated()
    Accessible.onToggleAction: if (actionable && enabled && checkable) activated()

    Keys.onPressed: event => {
        if (!actionable || (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter))
            return;
        event.accepted = true;
        if (!event.isAutoRepeat) activated();
    }

    Rectangle {
        anchors.fill: parent
        z: 10
        visible: surface.actionable && surface.activeFocus
        radius: surface.radius
        color: "transparent"
        border.width: 2
        border.color: Atelier.text
    }
}
