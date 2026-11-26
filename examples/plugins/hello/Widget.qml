import QtQuick
import qs.config

// A desktop widget: the root Item's implicit size is the window size.
Rectangle {
    implicitWidth: 160; implicitHeight: 56; radius: 16
    color: Qt.alpha(Atelier.base, 0.6)
    Text { anchors.centerIn: parent; text: "Hello 👋"; color: Atelier.text; font.family: Atelier.fontUi; font.pixelSize: 20 }
}
