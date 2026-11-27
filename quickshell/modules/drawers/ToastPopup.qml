import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.config

// Toast that drops out of the top border at the top centre. Click-through;
// disappears on its own.
Item {
    id: toastRoot
    readonly property bool requested: toastTimer.running
    visible: requested || toastDrawer.visible

    // a click-through strip along the top of the shared DrawerHost window
    anchors { top: parent.top; left: parent.left; right: parent.right }
    height: 100 + Atelier.maxInset

    property string message: ""
    property string iconText: "✓"
    property color iconColor: Atelier.green

    function showToast(msg, icon, color) {
        toastRoot.message = msg;
        toastRoot.iconText = icon || "✓";
        toastRoot.iconColor = color || Atelier.green;
        toastTimer.restart();
    }

    Timer {
        id: toastTimer
        interval: 2200
        repeat: false
    }

    EdgeDrawer {
        id: toastDrawer
        edge: "top"
        open: toastTimer.running
        bodyWidth: Math.max(180, row.implicitWidth + 36)
        bodyHeight: 50
        cornerRadius: 22
        anchorPos: -1   // top centre (top-right belongs to notifications)

        Behavior on bodyWidth { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard } }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 10

            // Circular Icon Halo
            Rectangle {
                implicitWidth: 26
                implicitHeight: 26
                radius: 13
                color: Qt.rgba(toastRoot.iconColor.r, toastRoot.iconColor.g, toastRoot.iconColor.b, 0.16)

                Text {
                    anchors.centerIn: parent
                    text: toastRoot.iconText
                    font.family: Atelier.font
                    font.pixelSize: Atelier.fsMd
                    font.bold: true
                    color: toastRoot.iconColor
                }
            }

            Text {
                text: toastRoot.message
                font.family: Atelier.font
                font.pixelSize: Atelier.fsMd
                font.bold: true
                color: Atelier.text
            }
        }
    }
}
