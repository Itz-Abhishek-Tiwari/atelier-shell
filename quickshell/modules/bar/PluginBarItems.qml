import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

// Bar items from user plugins (docs/plugins.md), placed just before the power button.
// A plugin item sets its own implicit size and can read Atelier.barVertical to lay itself out.
Repeater {
    model: Plugins.barItems
    delegate: Loader {
        id: ld
        required property var modelData
        Layout.alignment: Qt.AlignCenter
        source: "file://" + modelData.file
        onLoaded: Plugins.attach(item, modelData)
        onStatusChanged: if (status === Loader.Error) Plugins.reportError(modelData.plugin, modelData.id + ": could not load " + modelData.file)
    }
}
