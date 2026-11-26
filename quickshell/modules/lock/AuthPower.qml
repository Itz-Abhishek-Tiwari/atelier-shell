import QtQuick
import Quickshell
import qs.config

// Sleep / restart / power buttons for a custom password screen (power asks once).
// Each style sets its own colours, corner radius and font.
Row {
    id: row
    required property var ph
    property color ink: Atelier.text
    property color fill: Qt.alpha(Atelier.text, 0.1)
    property real btnRadius: -1            // -1 = round
    property string family: Atelier.fontUi
    property bool upper: false
    property bool confirm: false
    spacing: 30 * ph.u
    visible: opacity > 0
    onVisibleChanged: confirm = false

    Repeater {
        model: row.confirm
            ? [{ id: "sleep", icon: "󰤄", label: "Sleep" }, { id: "reboot", icon: "󰑓", label: "Restart" }, { id: "poweroff", icon: "⏻", label: "Shut down" }]
            : [{ id: "sleep", icon: "󰤄", label: "Sleep" }, { id: "ask", icon: "⏻", label: "Power" }]
        Column {
            id: pw
            required property var modelData
            spacing: 6 * row.ph.u
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 56 * row.ph.u; height: width
                radius: row.btnRadius < 0 ? width / 2 : row.btnRadius
                color: pwMa.containsMouse ? Qt.alpha(row.ink, 0.22) : row.fill
                Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                Text { anchors.centerIn: parent; text: pw.modelData.icon; font.family: Atelier.font; font.pixelSize: Atelier.fsXl * row.ph.ts * 1.3; color: row.ink }
                MouseArea {
                    id: pwMa
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const id = pw.modelData.id;
                        if (id === "ask") row.confirm = true;
                        else if (id === "sleep") Quickshell.execDetached(["systemctl", "suspend"]);
                        else Quickshell.execDetached(["systemctl", id]);
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: row.upper ? pw.modelData.label.toUpperCase() : pw.modelData.label
                font.family: row.family; font.pixelSize: Atelier.fsSm * row.ph.ts
                font.letterSpacing: row.upper ? 2 * row.ph.u : 0
                color: Qt.alpha(row.ink, 0.75)
            }
        }
    }
}
