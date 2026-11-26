import QtQuick
import qs.config
import qs.services

// A bar item: set an implicit size; Atelier.barVertical says whether the bar is a side bar.
// `plugin` ({id, name, dir}) is filled in by the shell if you declare it. Plugins.get/set keep your settings.
Item {
    property var plugin
    readonly property int clicks: plugin ? Plugins.get(plugin.id, "clicks", 0) : 0
    implicitWidth: 34; implicitHeight: 34
    Rectangle {
        anchors.centerIn: parent; width: 26; height: 26; radius: 13
        color: ma.containsMouse ? Atelier.containerHigh : Atelier.container
        Text { anchors.centerIn: parent; text: "👋"; font.pixelSize: 14 }
    }
    MouseArea {
        id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: { Plugins.set(plugin.id, "clicks", clicks + 1); Plugins.notify("Hello", "Clicked " + (clicks + 1) + " times"); }
    }
}
