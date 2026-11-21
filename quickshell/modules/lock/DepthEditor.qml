import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.config

// Lock screen editor for the Depth lock (One UI style "customise lock screen"): shown over the
// live preview (qs ipc call lock edit, Settings → Lock screen → Depth → Customise). Every
// choice is written to Settings.lock right away, so the clock behind it updates as you pick;
// Cancel puts back what was there when the editor opened, Done/Esc keeps it.
Item {
    id: ed
    required property var lockRoot
    anchors.fill: parent

    readonly property var keys: ["depthPos", "depthX", "depthY", "depthEffect", "depthStyle", "depthColor", "depthLayout", "depthClockSize", "depthFont", "depthWeight", "depthShadow"]
    readonly property var defaults: ({ depthPos: "auto", depthX: 0.5, depthY: 0.1, depthEffect: true, depthStyle: "solid", depthColor: "auto", depthLayout: "horizontal", depthClockSize: 0.22,
                                       depthFont: "display", depthWeight: "bold", depthShadow: true })
    property var snapshot: ({})
    property string tab: "style"
    property real shown: 0

    Component.onCompleted: {
        const s = {};
        for (const k of keys) s[k] = Settings.lock[k];
        snapshot = s;
        shown = 1;
    }
    Behavior on shown { NumberAnimation { duration: Atelier.durOpen; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveOpen } }

    function set(k, v) { Settings.lock[k] = v; }
    function cancel() {
        for (const k of keys) Settings.lock[k] = snapshot[k];
        lockRoot.stopPreview();
    }
    function done() { lockRoot.stopPreview(); }
    function reset() { for (const k of keys) Settings.lock[k] = defaults[k]; }

    // ── the sheet ──
    Item {
        id: sheetWrap
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24 - (1 - ed.shown) * (sheet.height + 40)
        width: Math.min(860, parent.width - 48)
        height: sheet.height

        RectangularShadow {
            anchors.fill: sheet
            radius: sheet.radius
            blur: 40
            offset.y: 8
            color: Qt.alpha(Atelier.crust, 0.5)
        }
        Rectangle {
            id: sheet
            width: parent.width
            height: col.implicitHeight + 36
            radius: Math.max(22, Atelier.rounding)
            color: Atelier.surface
            border.width: 1
            border.color: Atelier.outline

            // swallow clicks so they don't reach the lock behind
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: col
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 18
                spacing: 14

                // header
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: col.width
                    spacing: 8
                    ColumnLayout {
                        spacing: 1
                        Text { text: "Customise lock screen"; font.family: Atelier.fontUi; font.pixelSize: 16; font.weight: Font.DemiBold; color: Atelier.text }
                        Text { text: "Changes show on the clock as you pick"; font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext }
                    }
                    Item { Layout.fillWidth: true }
                    Btn { label: "Reset"; onClicked: ed.reset() }
                    Btn { label: "Cancel"; onClicked: ed.cancel() }
                    Btn { label: "Done"; primary: true; onClicked: ed.done() }
                }

                // tabs
                Row {
                    spacing: 6
                    Repeater {
                        model: [{ id: "style", label: "Style", icon: "󰏘" }, { id: "colour", label: "Colour", icon: "󰉦" },
                                { id: "font", label: "Font", icon: "󰛖" }, { id: "size", label: "Layout & size", icon: "󰩨" }]
                        Rectangle {
                            required property var modelData
                            readonly property bool on: ed.tab === modelData.id
                            width: tabRow.implicitWidth + 24; height: 32; radius: 16
                            color: on ? Atelier.accentFill : (tabMa.containsMouse ? Atelier.container : "transparent")
                            Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                            Row {
                                id: tabRow
                                anchors.centerIn: parent
                                spacing: 7
                                Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData.icon; font.family: Atelier.font; font.pixelSize: 13
                                    color: parent.parent.on ? Atelier.onFill : Atelier.subtext1 }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData.label; font.family: Atelier.fontUi; font.pixelSize: 12
                                    font.weight: parent.parent.on ? Font.DemiBold : Font.Normal
                                    color: parent.parent.on ? Atelier.onFill : Atelier.subtext1 }
                            }
                            MouseArea { id: tabMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ed.tab = parent.modelData.id }
                        }
                    }
                }

                // ── Style: solid / glass (big preview tiles) + shadow ──
                RowLayout {
                    visible: ed.tab === "style"
                    Layout.fillWidth: true
                    spacing: 12
                    StyleTile { kind: "solid"; label: "Solid"; sub: "A clean, coloured clock" }
                    StyleTile { kind: "glass"; label: "Glass"; sub: "Frosted digits, the wallpaper shows through" }
                    ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 8
                    Opt {
                        label: Settings.lock.depthEffect ? "Depth effect on" : "Depth effect off"
                        icon: "󰽙"
                        on: Settings.lock.depthEffect
                        onClicked: ed.set("depthEffect", !Settings.lock.depthEffect)
                    }
                    Opt {
                        label: Settings.lock.depthShadow ? "Shadow on" : "Shadow off"
                        icon: "󰘷"
                        on: Settings.lock.depthShadow
                        onClicked: ed.set("depthShadow", !Settings.lock.depthShadow)
                    }
                    }
                    Item { Layout.fillWidth: true }
                }

                // ── Colour: swatches + custom hex ──
                ColumnLayout {
                    visible: ed.tab === "colour"
                    Layout.fillWidth: true
                    spacing: 10
                    Flow {
                        Layout.fillWidth: true
                        spacing: 10
                        Repeater {
                            model: [
                                { id: "auto",     label: "Auto",   c: "transparent" },
                                { id: "theme",    label: "Theme",  c: Atelier.text },
                                { id: "white",    label: "White",  c: "#ffffff" },
                                { id: "black",    label: "Black",  c: "#161616" },
                                { id: "accent",   label: "Accent", c: Atelier.accent },
                                { id: "pink",     label: "",       c: Atelier.pink },
                                { id: "red",      label: "",       c: Atelier.red },
                                { id: "peach",    label: "",       c: Atelier.peach },
                                { id: "yellow",   label: "",       c: Atelier.yellow },
                                { id: "green",    label: "",       c: Atelier.green },
                                { id: "teal",     label: "",       c: Atelier.teal },
                                { id: "sky",      label: "",       c: Atelier.sky },
                                { id: "blue",     label: "",       c: Atelier.blue },
                                { id: "lavender", label: "",       c: Atelier.lavender },
                                { id: "mauve",    label: "",       c: Atelier.mauve }
                            ]
                            Column {
                                required property var modelData
                                readonly property bool on: Settings.lock.depthColor === modelData.id
                                spacing: 4
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 38; height: 38; radius: 19
                                    color: parent.modelData.c
                                    border.width: parent.on ? 3 : 1
                                    border.color: parent.on ? Atelier.accent : Atelier.outline
                                    // auto: a little rainbow so it reads as "from the picture"
                                    Rectangle {
                                        visible: parent.parent.modelData.id === "auto"
                                        anchors.fill: parent; anchors.margins: 4; radius: width / 2
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0; color: Atelier.peach }
                                            GradientStop { position: 0.5; color: Atelier.green }
                                            GradientStop { position: 1; color: Atelier.blue }
                                        }
                                    }
                                    scale: swMa.containsMouse ? 1.1 : 1
                                    Behavior on scale { NumberAnimation { duration: 140 } }
                                    MouseArea { id: swMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: ed.set("depthColor", parent.parent.modelData.id) }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: parent.modelData.label !== ""
                                    text: parent.modelData.label
                                    font.family: Atelier.fontUi; font.pixelSize: 10
                                    color: parent.on ? Atelier.text : Atelier.subtext
                                }
                            }
                        }
                    }
                    RowLayout {
                        spacing: 8
                        Text { text: "Custom"; font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.subtext1 }
                        Rectangle {
                            implicitWidth: 130; implicitHeight: 32; radius: 16
                            color: Atelier.container
                            border.width: 1
                            border.color: hexIn.activeFocus ? Qt.alpha(Atelier.accent, 0.7) : Atelier.outline
                            Rectangle {
                                anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                width: 16; height: 16; radius: 8
                                color: /^#[0-9a-fA-F]{6}$/.test(hexIn.text) ? hexIn.text : "transparent"
                                border.width: 1; border.color: Atelier.outline
                            }
                            TextInput {
                                id: hexIn
                                anchors.fill: parent; anchors.leftMargin: 32; anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                text: Settings.lock.depthColor.startsWith("#") ? Settings.lock.depthColor : ""
                                font.family: Atelier.font; font.pixelSize: 12
                                color: Atelier.text
                                maximumLength: 7
                                selectByMouse: true
                                onAccepted: {
                                    let v = text.trim();
                                    if (v && !v.startsWith("#")) v = "#" + v;
                                    if (/^#[0-9a-fA-F]{6}$/.test(v)) ed.set("depthColor", v.toLowerCase());
                                }
                                Text { anchors.verticalCenter: parent.verticalCenter; visible: !parent.text && !parent.activeFocus; text: "#rrggbb"
                                    font: parent.font; color: Atelier.subtext }
                            }
                        }
                        Text { text: "Enter to apply"; font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext }
                    }
                }

                // ── Font: family + weight, each label drawn in its own font ──
                ColumnLayout {
                    visible: ed.tab === "font"
                    Layout.fillWidth: true
                    spacing: 10
                    Row {
                        spacing: 10
                        Repeater {
                            model: [{ id: "display", label: "Display", fam: "Inter Display" }, { id: "mono", label: "Mono", fam: Atelier.font },
                                    { id: "serif", label: "Serif", fam: "Noto Serif" }]
                            FontTile {
                                required property var modelData
                                fam: modelData.fam; label: modelData.label
                                weight: ({ light: Font.Light, regular: Font.Normal, bold: Font.Bold, black: Font.Black })[Settings.lock.depthWeight] ?? Font.Bold
                                on: Settings.lock.depthFont === modelData.id
                                onClicked: ed.set("depthFont", modelData.id)
                            }
                        }
                    }
                    Row {
                        spacing: 6
                        Repeater {
                            model: [{ id: "light", label: "Light" }, { id: "regular", label: "Regular" }, { id: "bold", label: "Bold" }, { id: "black", label: "Black" }]
                            Opt {
                                required property var modelData
                                label: modelData.label
                                on: Settings.lock.depthWeight === modelData.id
                                onClicked: ed.set("depthWeight", modelData.id)
                            }
                        }
                    }
                }

                // ── Layout & size ──
                ColumnLayout {
                    visible: ed.tab === "size"
                    Layout.fillWidth: true
                    spacing: 12
                    RowLayout {
                        spacing: 6
                        Text { text: "Position"; font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.subtext1; Layout.rightMargin: 6 }
                        Opt { label: "Auto"; icon: "󰚩"; on: Settings.lock.depthPos !== "custom"; onClicked: ed.set("depthPos", "auto") }
                        Opt { label: "Custom"; icon: "󰆾"; on: Settings.lock.depthPos === "custom"; onClicked: ed.set("depthPos", "custom") }
                        Text {
                            Layout.leftMargin: 8
                            text: Settings.lock.depthPos === "custom" ? "Drag the clock on the screen above to move it"
                                                                       : "Placed around your wallpaper's subject, different on every picture"
                            font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext
                        }
                    }
                    Row {
                        spacing: 6
                        Opt { label: "One line  12:45"; on: Settings.lock.depthLayout !== "stacked"; onClicked: ed.set("depthLayout", "horizontal") }
                        Opt { label: "Stacked  12 / 45"; on: Settings.lock.depthLayout === "stacked"; onClicked: ed.set("depthLayout", "stacked") }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Text { text: "Size"; font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.subtext1 }
                        Text { text: "A"; font.family: "Inter Display"; font.pixelSize: 12; font.weight: Font.Bold; color: Atelier.subtext }
                        // slider
                        Item {
                            id: slider
                            Layout.fillWidth: true
                            implicitHeight: 28
                            readonly property real from: 0.12
                            readonly property real to: 0.34
                            readonly property real frac: (Settings.lock.depthClockSize - from) / (to - from)
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width; height: 6; radius: 3
                                color: Qt.alpha(Atelier.accent, 0.18)
                                Rectangle { width: parent.width * slider.frac; height: parent.height; radius: 3; color: Atelier.accentFill }
                            }
                            Rectangle {
                                x: slider.frac * (slider.width - width)
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20; radius: 10
                                color: Atelier.text
                                border.width: 3; border.color: Atelier.accentFill
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                function pick(x) {
                                    const f = Math.max(0, Math.min(1, x / width));
                                    ed.set("depthClockSize", Math.round((slider.from + f * (slider.to - slider.from)) * 100) / 100);
                                }
                                onPressed: (m) => pick(m.x)
                                onPositionChanged: (m) => { if (pressed) pick(m.x); }
                            }
                        }
                        Text { text: "A"; font.family: "Inter Display"; font.pixelSize: 22; font.weight: Font.Bold; color: Atelier.subtext }
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Stacked turns into one line by itself on pictures where the subject would hide the minutes."
                        font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext
                    }
                }
            }
        }
    }

    // ── pieces ──
    component Btn: Rectangle {
        id: b
        property string label
        property bool primary: false
        signal clicked()
        implicitWidth: bt.implicitWidth + 28; implicitHeight: 34; radius: 17
        color: primary ? (bMa.containsMouse ? Qt.lighter(Atelier.accentFill, 1.1) : Atelier.accentFill)
                       : (bMa.containsMouse ? Atelier.containerHigh : Atelier.container)
        border.width: primary ? 0 : 1; border.color: Atelier.outline
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Text { id: bt; anchors.centerIn: parent; text: b.label; font.family: Atelier.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold
            color: b.primary ? Atelier.onFill : Atelier.text }
        MouseArea { id: bMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }

    component Opt: Rectangle {
        id: o
        property string label
        property string icon: ""
        property bool on: false
        signal clicked()
        implicitWidth: oRow.implicitWidth + 26; implicitHeight: 34; radius: 17
        color: on ? Qt.alpha(Atelier.accent, 0.18) : (oMa.containsMouse ? Atelier.container : "transparent")
        border.width: 1
        border.color: on ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Row {
            id: oRow
            anchors.centerIn: parent
            spacing: 7
            Text { visible: o.icon !== ""; anchors.verticalCenter: parent.verticalCenter; text: o.icon; font.family: Atelier.font; font.pixelSize: 13
                color: o.on ? Atelier.accent : Atelier.subtext1 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: o.label; font.family: Atelier.fontUi; font.pixelSize: 12
                font.weight: o.on ? Font.DemiBold : Font.Normal; color: o.on ? Atelier.text : Atelier.subtext1 }
        }
        MouseArea { id: oMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: o.clicked() }
    }

    component FontTile: Rectangle {
        id: ft
        property string fam
        property string label
        property int weight: Font.Bold
        property bool on: false
        signal clicked()
        width: 132; height: 84; radius: 16
        color: on ? Qt.alpha(Atelier.accent, 0.14) : (ftMa.containsMouse ? Atelier.containerHigh : Atelier.container)
        border.width: on ? 2 : 1
        border.color: on ? Atelier.accent : Atelier.outline
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 8; text: "12:45"; font.family: ft.fam; font.pixelSize: 34; font.weight: ft.weight
            font.features: { "tnum": 1 }; color: Atelier.text }
        Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 8; text: ft.label
            font.family: Atelier.fontUi; font.pixelSize: 11; color: ft.on ? Atelier.text : Atelier.subtext }
        MouseArea { id: ftMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ft.clicked() }
    }

    component StyleTile: Rectangle {
        id: st
        property string kind
        property string label
        property string sub
        readonly property bool on: Settings.lock.depthStyle === kind
        Layout.preferredWidth: 230
        implicitHeight: 96
        radius: 16
        color: on ? Qt.alpha(Atelier.accent, 0.14) : (stMa.containsMouse ? Atelier.containerHigh : Atelier.container)
        border.width: on ? 2 : 1
        border.color: on ? Atelier.accent : Atelier.outline
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        // mini sample: solid = filled digits, glass = outlined, frosted-looking digits
        Rectangle {
            id: sample
            anchors.left: parent.left; anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 92; height: 72; radius: 12
            gradient: Gradient {
                GradientStop { position: 0; color: Atelier.blue }
                GradientStop { position: 1; color: Atelier.mauve }
            }
            Text {
                anchors.centerIn: parent
                text: "12"
                font.family: "Inter Display"; font.pixelSize: 40; font.weight: Font.Black
                color: st.kind === "glass" ? Qt.rgba(1, 1, 1, 0.38) : Atelier.crust
                style: st.kind === "glass" ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(1, 1, 1, 0.85)
            }
        }
        Column {
            anchors.left: sample.right; anchors.leftMargin: 12
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Text { text: st.label; font.family: Atelier.fontUi; font.pixelSize: 14; font.weight: Font.DemiBold; color: Atelier.text }
            Text { width: parent.width; text: st.sub; wrapMode: Text.WordWrap; font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext }
        }
        MouseArea { id: stMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ed.set("depthStyle", st.kind) }
    }
}
