import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config
import qs.services

// Colour picker: a bottom drawer with the chosen colour in HEX / RGB / HSL (click a row to copy it)
// and the last 24 picks. "Pick from screen" lets you click any pixel.
// Open: Super+Shift+X picks at once · IPC `colorpicker pick|toggle|open|close|last|clear`.
Item {
    id: root
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool isLight: Atelier.isLight
    property bool animActive: false
    property string selected: ColorPicker.last
    property string flash: ""            // the row just copied, for a moment
    property double openedAt: 0

    signal closedSignal()

    readonly property var formats: selected ? [
        ["HEX", selected.toUpperCase()],
        ["RGB", ColorPicker.rgbText(selected)],
        ["HSL", ColorPicker.hsl(selected)]
    ] : []
    // ink that reads on the selected colour (for the label printed on the swatch)
    readonly property color swatchInk: selected && Atelier.luminance(Qt.color(selected)) > 0.45 ? "#1b1b1f" : "#f5f5f7"

    function toggle() { if (visible && animActive) close(); else open(); }
    function open() {
        visible = true;
        animActive = true;
        selected = ColorPicker.last;
        openedAt = Date.now();
        focusTimer.restart();
    }
    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }
    // the drawer gets out of the way, then the screen picker starts
    function pickNow() { close(); pickDelay.restart(); }
    function copy(fmt, text) { Quickshell.execDetached(["wl-copy", text]); flash = fmt; flashTimer.restart(); }

    Connections {
        target: ColorPicker
        function onPicked(hex) { root.selected = hex; }
    }
    Timer { id: pickDelay; interval: Atelier.durClose + 80; onTriggered: ColorPicker.pick() }
    Timer { id: focusTimer; interval: 40; onTriggered: keys.forceActiveFocus() }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!root.animActive) root.visible = false }
    Timer { id: flashTimer; interval: 1200; onTriggered: root.flash = "" }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    EdgeDrawer {
        id: drawer
        edge: "bottom"
        open: root.animActive
        bodyWidth: 560
        bodyHeight: 372

        MouseArea { anchors.fill: parent }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: (e) => {
                if (e.isAutoRepeat && Date.now() - root.openedAt < 350) { e.accepted = true; return; }
                if (e.key === Qt.Key_Escape) root.close();
                else if (e.key === Qt.Key_P || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.pickNow();
                else if (e.key === Qt.Key_C && root.selected) root.copy("HEX", root.selected.toUpperCase());
                else return;
                e.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            // ── header: title · pick ───────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                DrawerTitle {
                    Layout.fillWidth: true
                    icon: "󰈊"; tint: Atelier.pink; title: "Colour picker"
                    subtitle: ColorPicker.history.length ? ColorPicker.history.length + " saved colours" : "Nothing picked yet"
                }
                PrimaryButton { icon: "󰈊"; label: "Pick from screen"; onClicked: root.pickNow() }
            }

            // ── the chosen colour ──────────────────────────────────────────────
            Panel {
                Layout.fillWidth: true
                implicitHeight: 132
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 12
                    Rectangle {
                        Layout.preferredWidth: 150
                        Layout.fillHeight: true
                        radius: Atelier.radiusMd
                        color: root.selected || Atelier.containerHigh
                        border.width: 1
                        border.color: Atelier.outline
                        Behavior on color { ColorAnimation { duration: Atelier.durMedium } }
                        EmptyState { anchors.centerIn: parent; visible: !root.selected; icon: "󰈊"; text: "Pick one" }
                        Text {
                            visible: !!root.selected
                            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 10
                            text: root.selected.toUpperCase()
                            font.family: Atelier.font; font.pixelSize: Atelier.fsMd; font.weight: Font.Bold
                            color: root.swatchInk
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 0
                        Repeater {
                            model: root.formats
                            Item {
                                id: fr
                                required property var modelData
                                required property int index
                                readonly property bool copied: root.flash === modelData[0]
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Rectangle { visible: fr.index > 0; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                            anchors.leftMargin: 6; anchors.rightMargin: 6; height: 1; color: Atelier.outline }
                                Rectangle { anchors.fill: parent; anchors.margins: 2; radius: Atelier.radiusSm; color: Atelier.containerHigh
                                            opacity: frMa.containsMouse ? 0.6 : 0; Behavior on opacity { NumberAnimation { duration: Atelier.durFast } } }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10; anchors.rightMargin: 8
                                    spacing: 10
                                    SmallCaps { Layout.preferredWidth: 34; text: fr.modelData[0] }
                                    Text { Layout.fillWidth: true; text: fr.modelData[1]; elide: Text.ElideRight
                                           font.family: Atelier.font; font.pixelSize: Atelier.fsMd; color: Atelier.text }
                                    Text { text: fr.copied ? "Copied" : ""; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.green }
                                    Text { text: fr.copied ? "󰄬" : "󰆏"; font.family: Atelier.font; font.pixelSize: Atelier.fsLg
                                           color: fr.copied ? Atelier.green : (frMa.containsMouse ? Atelier.text : Atelier.subtext) }
                                }
                                MouseArea { id: frMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: root.copy(fr.modelData[0], fr.modelData[1]) }
                            }
                        }
                        EmptyState { visible: !root.selected; Layout.alignment: Qt.AlignCenter; icon: ""; text: "Its HEX, RGB and HSL show up here" }
                    }
                }
            }

            // ── recent picks ───────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                SmallCaps { text: "Recent"; Layout.leftMargin: 4 }
                Item { Layout.fillWidth: true }
                Text {
                    visible: ColorPicker.history.length > 0
                    text: "Clear"
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                    color: clMa.containsMouse ? Atelier.red : Atelier.subtext
                    MouseArea { id: clMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { ColorPicker.clear(); root.selected = ""; } }
                }
            }
            Panel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Text {
                    visible: ColorPicker.history.length === 0
                    anchors.centerIn: parent
                    text: "Colours you pick are kept here"
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext
                }
                Flow {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    Repeater {
                        model: ColorPicker.history
                        Rectangle {
                            id: sw
                            required property string modelData
                            readonly property bool on: root.selected === modelData
                            width: 30; height: 30; radius: Atelier.radiusLg
                            color: modelData
                            border.width: on ? 2 : 1
                            border.color: on ? Atelier.text : Atelier.outline
                            scale: swMa.pressed ? 0.86 : (swMa.containsMouse ? 1.18 : 1)
                            Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                            MouseArea { id: swMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.selected = sw.modelData; root.copy("HEX", sw.modelData.toUpperCase()); } }
                        }
                    }
                }
            }

            HintLine { Layout.fillWidth: true; text: "P or Enter picks from the screen  ·  click a row or a swatch to copy  ·  Esc closes" }
        }
    }
}
