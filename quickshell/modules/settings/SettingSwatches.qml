import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// Colour row: label on top, then a line of swatches: Text · Automatic · Accent · every theme
// colour · (optionally) Colourful, plus a custom hex field and "pick from screen".
// value is "text" | "auto" | "accent" | a palette role | "#rrggbb" | "colourful".
Item {
    id: root

    property string label: ""
    property string description: ""
    property string value: "text"
    property bool allowColourful: false
    signal picked(string id)

    readonly property var specials: [
        { id: "text", label: "Text (follows the wallpaper's brightness)" },
        { id: "auto", label: "Automatic: the theme colour that stands out most here" },
        { id: "accent", label: "Accent" }
    ]
    readonly property var roles: ["blue", "sapphire", "sky", "teal", "green", "yellow", "peach", "red", "pink", "mauve", "lavender"]
    readonly property var options: (allowColourful ? [{ id: "colourful", label: "Colourful: each line keeps its own hue" }] : [])
        .concat(specials)
        .concat(roles.map(r => ({ id: r, label: r.charAt(0).toUpperCase() + r.slice(1) })))
    property string hovered: ""
    readonly property string currentLabel: {
        const id = hovered || value;
        if (id.startsWith("#")) return "Custom " + id.toUpperCase();
        const o = options.find(x => x.id === id);
        return o ? o.label : id;
    }
    property bool awaitingPick: false

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 24

    Rectangle {   // divider like SettingRow
        visible: root.y > 1
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: 1; color: Atelier.outline
    }

    Connections {
        target: ColorPicker
        enabled: root.awaitingPick
        function onPicked(hex) { root.awaitingPick = false; root.picked(hex); }
    }
    Connections {
        target: ColorPicker
        enabled: root.awaitingPick
        function onPickingChanged() { if (!ColorPicker.picking) pickReset.restart(); }
    }
    Timer { id: pickReset; interval: 300; onTriggered: root.awaitingPick = false }

    ColumnLayout {
        id: col
        anchors.left: parent.left; anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { Layout.fillWidth: true; text: root.label; elide: Text.ElideRight
                       font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.Medium; color: Atelier.text }
                Text { Layout.fillWidth: true; text: root.hovered ? root.currentLabel : (root.description || root.currentLabel)
                       wrapMode: Text.Wrap; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
            }
            // custom hex
            Rectangle {
                implicitWidth: 92; implicitHeight: 30; radius: Atelier.radiusLg
                color: Atelier.containerHigh
                border.width: 1
                border.color: hex.activeFocus || root.value.startsWith("#") ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6
                                color: root.value.startsWith("#") ? root.value : "transparent"
                                border.width: 1; border.color: Atelier.outline }
                    TextInput {
                        id: hex
                        anchors.verticalCenter: parent.verticalCenter
                        width: 58
                        font.family: Atelier.font; font.pixelSize: Atelier.fsSm; color: Atelier.text
                        maximumLength: 7
                        selectByMouse: true
                        text: root.value.startsWith("#") ? root.value.toUpperCase() : ""
                        onEditingFinished: {
                            let t = text.trim().toLowerCase();
                            if (t && !t.startsWith("#")) t = "#" + t;
                            if (/^#[0-9a-f]{6}$/.test(t)) root.picked(t);
                        }
                        Text { visible: !hex.text && !hex.activeFocus; anchors.verticalCenter: parent.verticalCenter
                               text: "#hex"; font: hex.font; color: Atelier.subtext; opacity: 0.7 }
                    }
                }
            }
            // pick from the screen
            Rectangle {
                implicitWidth: 30; implicitHeight: 30; radius: Atelier.radiusLg
                color: root.awaitingPick ? Qt.alpha(Atelier.accent, 0.16) : "transparent"
                StateLayer { mouseArea: pkMa }
                Text { anchors.centerIn: parent; text: "󰈊"; font.family: Atelier.font; font.pixelSize: Atelier.iconSm
                       color: root.awaitingPick ? Atelier.accent : (pkMa.containsMouse ? Atelier.text : Atelier.subtext) }
                MouseArea { id: pkMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onEntered: root.hovered = ""; onClicked: { root.awaitingPick = true; ColorPicker.pick(); } }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 7
            Repeater {
                model: root.options
                Item {
                    id: sw
                    required property var modelData
                    readonly property bool on: root.value === modelData.id
                    readonly property string id_: modelData.id
                    width: 28; height: 28
                    // selection ring
                    Rectangle {
                        anchors.fill: parent; radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: sw.on ? Atelier.text : "transparent"
                    }
                    Rectangle {
                        id: dot
                        anchors.centerIn: parent
                        width: 20; height: 20; radius: Atelier.radiusSm
                        scale: swMa.containsMouse && !sw.on ? 1.15 : 1
                        Behavior on scale { Anim { type: "fastSpatial" } }
                        border.width: 1
                        border.color: Atelier.outline
                        color: sw.id_ === "text" ? Atelier.text
                             : sw.id_ === "auto" || sw.id_ === "colourful" ? Atelier.containerHigh
                             : Atelier[sw.id_]
                        gradient: sw.id_ === "colourful" ? rainbow : null
                        Text {
                            anchors.centerIn: parent
                            visible: sw.id_ === "auto" || sw.id_ === "text"
                            text: sw.id_ === "auto" ? "A" : "T"
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMicro; font.weight: Font.Bold
                            color: sw.id_ === "text" ? Atelier.base : Atelier.text
                            Behavior on color { CAnim {} }
                        }
                    }
                    MouseArea {
                        id: swMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.hovered = sw.id_
                        onExited: if (root.hovered === sw.id_) root.hovered = ""
                        onClicked: root.picked(sw.id_)
                    }
                }
            }
        }
    }

    Gradient {
        id: rainbow
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Atelier.peach }
        GradientStop { position: 0.5; color: Atelier.pink }
        GradientStop { position: 1; color: Atelier.sapphire }
    }
}
