import QtQuick
import qs.components
import qs.config

// A little screen of nine spots: click where something should sit.
// h: left | center | right    v: top | middle | bottom    (an unset value highlights nothing)
Rectangle {
    id: pad
    property string h: ""
    property string v: ""
    signal picked(string h, string v)

    implicitWidth: 168; implicitHeight: 100
    radius: Atelier.radiusSm
    color: Atelier.containerHigh
    border.width: 1; border.color: Atelier.outline
    readonly property var hs: ["left", "center", "right"]
    readonly property var vs: ["top", "middle", "bottom"]
    readonly property string vNorm: v === "center" ? "middle" : v

    Grid {
        anchors.fill: parent; anchors.margins: 6
        columns: 3; spacing: 4
        Repeater {
            model: 9
            Rectangle {
                required property int index
                readonly property string ch: pad.hs[index % 3]
                readonly property string cv: pad.vs[Math.floor(index / 3)]
                readonly property bool on: pad.h === ch && pad.vNorm === cv
                width: (pad.width - 12 - 8) / 3; height: (pad.height - 12 - 8) / 3
                radius: 4
                color: on ? Atelier.fill(Atelier.accent) : (cellMa.containsMouse ? Qt.alpha(Atelier.text, 0.10) : "transparent")
                Behavior on color { CAnim {} }
                Rectangle { visible: !parent.on; anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: Qt.alpha(Atelier.text, 0.3) }
                Column {   // the widget, as two lines
                    visible: parent.on
                    anchors.centerIn: parent; spacing: 2
                    Rectangle { width: 22; height: 5; radius: 2; color: Atelier.onFill }
                    Rectangle { width: 14; height: 2; radius: 1; color: Qt.alpha(Atelier.onFill, 0.7) }
                }
                MouseArea { id: cellMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: pad.picked(parent.ch, parent.cv) }
            }
        }
    }
}
