import QtQuick
import QtQuick.Layouts
import qs.config

// Slider row with a live value label. `moved` fires while dragging (throttled).
SettingRow {
    id: root

    property real from: 0
    property real to: 100
    property real value: 0
    property real step: 1
    property int decimals: 0
    property string suffix: ""
    property color tint: Atelier.accent        // accepted for compatibility; controls use the one system accent
    readonly property color hue: Atelier.accent
    signal moved(real value)

    function snap(v) {
        const n = Math.round((v - from) / step) * step + from;
        return Math.max(from, Math.min(to, Number(n.toFixed(4))));
    }

    RowLayout {
        spacing: 12
        Item {
            id: area
            implicitWidth: 190
            implicitHeight: 28

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: 3
                color: Atelier.containerHigh
                Rectangle {
                    width: Math.max(height, parent.width * ((root.value - root.from) / (root.to - root.from)))
                    height: parent.height
                    radius: 3
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.alpha(root.hue, 0.55) }
                        GradientStop { position: 1; color: root.hue }
                    }
                }
                Rectangle {
                    x: Math.max(0, Math.min(parent.width - width, parent.width * ((root.value - root.from) / (root.to - root.from)) - width / 2))
                    anchors.verticalCenter: parent.verticalCenter
                    width: drag.pressed ? 18 : 16
                    height: width
                    radius: width / 2
                    color: Atelier.onFill            // light ink, like every control on a fill (was text: a dark dot in light themes)
                    border.width: 3
                    border.color: root.hue
                    Behavior on width { NumberAnimation { duration: Atelier.durFast } }
                }
            }
            MouseArea {
                id: drag
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                function apply(x) {
                    const v = root.snap(root.from + (root.to - root.from) * Math.max(0, Math.min(1, x / width)));
                    if (v !== root.value) root.moved(v);
                }
                onPressed: (m) => apply(m.x)
                onPositionChanged: (m) => { if (pressed) apply(m.x); }
                onWheel: (w) => { const v = root.snap(root.value + (w.angleDelta.y > 0 ? root.step : -root.step)); if (v !== root.value) root.moved(v); }
            }
        }
        Text {
            Layout.preferredWidth: 52
            horizontalAlignment: Text.AlignRight
            text: root.value.toFixed(root.decimals) + root.suffix
            font.family: Atelier.font
            font.pixelSize: 12
            color: Atelier.subtext1
        }
    }
}
