import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.components
import qs.config

// Lock screen editor for the Depth lock (One UI style "customise lock screen"): shown over the
// live preview (qs ipc call lock edit, Settings → Lock screen → Depth → Customise). Every
// choice is written to Settings.lock right away, so the clock behind it updates as you pick;
// Cancel puts back what was there when the editor opened, Done/Esc keeps it.
//
// Built from the shell's shared pieces (Segmented tabs, ToggleSwitch, ChoicePill,
// PrimaryButton) so it looks like the rest of Atelier. Five tabs:
//   Style    solid / glass, depth effect, shadow, glass frost + tint
//   Colour   auto, theme, white, black, every theme colour, any hex
//   Font     typeface + weight
//   Layout   position (auto / drag), one line / stacked, size
//   Details  date (long / short / off), weather, AM/PM, 12 / 24-hour
Item {
    id: ed
    required property var lockRoot
    anchors.fill: parent

    readonly property var defaults: ({
        depthPos: "auto", depthX: 0.5, depthY: 0.1, depthEffect: true, depthStyle: "solid", depthColor: "auto",
        depthLayout: "horizontal", depthClockSize: 0.22, depthFont: "display", depthWeight: "bold", depthShadow: true,
        depthGlassTint: 0.2, depthGlassFrost: 0.9, depthDate: "long", depthWeather: true, depthAmPm: true, clock: "system"
    })
    readonly property var keys: Object.keys(defaults)
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
        for (const k of keys) if (snapshot[k] !== undefined) Settings.lock[k] = snapshot[k];
        lockRoot.stopPreview();
    }
    function done() { lockRoot.stopPreview(); }
    function reset() { for (const k of keys) Settings.lock[k] = defaults[k]; }

    // the theme colours, without repeats (some themes use one colour for several roles)
    readonly property var swatches: {
        const seen = {};
        return allSwatches.filter(x => {
            if (x.label) return true;
            const k = String(x.c);
            if (seen[k]) return false;
            seen[k] = true;
            return true;
        });
    }
    readonly property var allSwatches: [
        { id: "auto", label: "Auto" }, { id: "theme", label: "Theme", c: Atelier.text },
        { id: "white", label: "White", c: "#ffffff" }, { id: "black", label: "Black", c: "#161616" },
        { id: "accent", label: "Accent", c: Atelier.accent }, { id: "pink", c: Atelier.pink }, { id: "red", c: Atelier.red },
        { id: "peach", c: Atelier.peach }, { id: "yellow", c: Atelier.yellow }, { id: "green", c: Atelier.green },
        { id: "teal", c: Atelier.teal }, { id: "sky", c: Atelier.sky }, { id: "blue", c: Atelier.blue },
        { id: "lavender", c: Atelier.lavender }, { id: "mauve", c: Atelier.mauve }
    ]

    // ── the sheet ──
    Item {
        id: sheetWrap
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24 - (1 - ed.shown) * (sheet.height + 40)
        width: Math.min(940, parent.width - 48)
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
            height: col.implicitHeight + 40
            radius: Math.max(22, Atelier.rounding)
            color: Atelier.surface
            border.width: 1
            border.color: Atelier.outline

            // swallow clicks so they don't reach the lock behind
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: col
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 20
                spacing: 16

                // ── header: title · tabs · actions ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        implicitWidth: 36; implicitHeight: 36; radius: 12
                        color: Qt.alpha(Atelier.accent, 0.14)
                        border.width: 1; border.color: Qt.alpha(Atelier.accent, 0.35)
                        Text { anchors.centerIn: parent; text: "󰌾"; font.family: Atelier.font; font.pixelSize: 17; color: Atelier.accent }
                    }
                    ColumnLayout {
                        spacing: 0
                        Text { text: "Customise the lock screen"; font.family: Atelier.fontUi; font.pixelSize: 15; font.weight: Font.DemiBold; color: Atelier.text }
                        Text { text: "Changes show on the clock as you pick"; font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext }
                    }
                    Item { Layout.fillWidth: true }
                    ChoicePill { label: "Reset"; icon: "󰑙"; onClicked: ed.reset() }
                    ChoicePill { label: "Cancel"; onClicked: ed.cancel() }
                    PrimaryButton { label: "Done"; icon: "󰄬"; onClicked: ed.done() }
                }

                Segmented {
                    Layout.fillWidth: true
                    segmentWidth: (col.width - 6 - 4 * 2) / 5
                    model: [{ id: "style", label: "Style", icon: "󰏘" }, { id: "colour", label: "Colour", icon: "󰉦" },
                            { id: "font", label: "Font", icon: "󰛖" }, { id: "layout", label: "Layout", icon: "󰩨" },
                            { id: "details", label: "Details", icon: "󰃭" }]
                    current: ed.tab
                    onPicked: (id) => ed.tab = id
                }

                // ── Style ─────────────────────────────────────────────────────
                RowLayout {
                    visible: ed.tab === "style"
                    Layout.fillWidth: true
                    spacing: 16
                    StyleTile { kind: "solid"; label: "Solid"; sub: "A clean, coloured clock" }
                    StyleTile { kind: "glass"; label: "Glass"; sub: "Frosted digits; the picture shows through" }
                    Panel {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: styleRows.implicitHeight + 6
                        ColumnLayout {
                            id: styleRows
                            x: 0; y: 3; width: parent.width
                            spacing: 0
                            OptRow { first: true; label: "Depth effect"; sub: "The clock goes behind the subject"
                                ToggleSwitch { on: Settings.lock.depthEffect; onToggled: ed.set("depthEffect", !Settings.lock.depthEffect) } }
                            OptRow { label: "Shadow"; sub: "Lifts the clock off busy pictures"
                                ToggleSwitch { on: Settings.lock.depthShadow; onToggled: ed.set("depthShadow", !Settings.lock.depthShadow) } }
                            OptRow { visible: Settings.lock.depthStyle === "glass"; label: "Frost"; sub: "Blur inside the digits"
                                Slide { from: 0.2; to: 1; key: "depthGlassFrost"; fallback: 0.9; percent: true } }
                            OptRow { visible: Settings.lock.depthStyle === "glass"; label: "Tint"; sub: "Clock colour in the glass"
                                Slide { from: 0; to: 0.7; key: "depthGlassTint"; fallback: 0.2; percent: true } }
                        }
                    }
                }

                // ── Colour ────────────────────────────────────────────────────
                ColumnLayout {
                    visible: ed.tab === "colour"
                    Layout.fillWidth: true
                    spacing: 12
                    Flow {
                        Layout.fillWidth: true
                        spacing: 10
                        Repeater {
                            model: ed.swatches
                            Item {
                                id: sw
                                required property var modelData
                                readonly property bool on: Settings.lock.depthColor === modelData.id
                                width: modelData.label ? swLabel.implicitWidth + 50 : 38
                                height: 38
                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: sw.modelData.label ? (sw.on ? Atelier.containerHigh : Atelier.container) : "transparent"
                                    border.width: sw.on ? 2 : (sw.modelData.label ? 1 : 0)
                                    border.color: sw.on ? Atelier.accent : Atelier.outline
                                }
                                Rectangle {
                                    id: dot
                                    x: sw.modelData.label ? 6 : 3; anchors.verticalCenter: parent.verticalCenter
                                    width: sw.modelData.label ? 26 : 32; height: width; radius: width / 2
                                    color: sw.modelData.c || "transparent"
                                    border.width: 1; border.color: Qt.alpha(Atelier.text, 0.25)
                                    // Auto: half light, half dark (it picks from the picture)
                                    Rectangle {
                                        visible: sw.modelData.id === "auto"
                                        anchors.fill: parent; radius: parent.radius
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: "#f2f2f2" }
                                            GradientStop { position: 0.499; color: "#f2f2f2" }
                                            GradientStop { position: 0.5; color: "#1e1e1e" }
                                            GradientStop { position: 1.0; color: "#1e1e1e" }
                                        }
                                    }
                                    // ring for the round, unlabelled swatches
                                    Rectangle {
                                        visible: !sw.modelData.label && sw.on
                                        anchors.centerIn: parent
                                        width: parent.width + 8; height: width; radius: width / 2
                                        color: "transparent"; border.width: 2; border.color: Atelier.text
                                    }
                                    scale: swMa.containsMouse && !sw.on ? 1.12 : 1
                                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                                }
                                Text { id: swLabel; visible: !!sw.modelData.label; anchors.left: dot.right; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                       text: sw.modelData.label || ""; font.family: Atelier.fontUi; font.pixelSize: 12; font.weight: Font.Medium
                                       color: sw.on ? Atelier.text : Atelier.subtext1 }
                                MouseArea { id: swMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: ed.set("depthColor", sw.modelData.id) }
                            }
                        }
                    }
                    RowLayout {
                        spacing: 10
                        Text { text: "Your own"; font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.subtext1 }
                        Rectangle {
                            implicitWidth: 150; implicitHeight: 34; radius: 17
                            color: Atelier.container
                            border.width: 1
                            border.color: hexIn.activeFocus || Settings.lock.depthColor.startsWith("#") ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                            Row {
                                anchors.fill: parent; anchors.leftMargin: 10
                                spacing: 8
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8
                                            color: Settings.lock.depthColor.startsWith("#") ? Settings.lock.depthColor : "transparent"
                                            border.width: 1; border.color: Atelier.outline }
                                TextInput {
                                    id: hexIn
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 100
                                    text: Settings.lock.depthColor.startsWith("#") ? Settings.lock.depthColor : ""
                                    font.family: Atelier.font; font.pixelSize: 12; color: Atelier.text
                                    maximumLength: 7; selectByMouse: true
                                    onAccepted: {
                                        let v = text.trim();
                                        if (v && !v.startsWith("#")) v = "#" + v;
                                        if (/^#[0-9a-fA-F]{6}$/.test(v)) ed.set("depthColor", v.toLowerCase());
                                    }
                                    Text { visible: !parent.text && !parent.activeFocus; anchors.verticalCenter: parent.verticalCenter
                                           text: "#rrggbb"; font: parent.font; color: Atelier.subtext; opacity: 0.7 }
                                }
                            }
                        }
                        Text { text: "Enter applies · Auto picks a tone from the picture that reads on it"
                               font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext }
                    }
                }

                // ── Font ──────────────────────────────────────────────────────
                ColumnLayout {
                    visible: ed.tab === "font"
                    Layout.fillWidth: true
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: [{ id: "display", label: "Display", fam: "Inter Display" }, { id: "mono", label: "Mono", fam: Atelier.font },
                                    { id: "serif", label: "Serif", fam: "Noto Serif" }]
                            FontTile {
                                required property var modelData
                                Layout.fillWidth: true
                                fam: modelData.fam; label: modelData.label
                                weight: ({ light: Font.Light, regular: Font.Normal, bold: Font.Bold, black: Font.Black })[Settings.lock.depthWeight] ?? Font.Bold
                                on: Settings.lock.depthFont === modelData.id
                                onClicked: ed.set("depthFont", modelData.id)
                            }
                        }
                    }
                    RowLayout {
                        spacing: 8
                        Text { text: "Weight"; font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.subtext1; Layout.rightMargin: 6 }
                        Repeater {
                            model: [{ id: "light", label: "Light" }, { id: "regular", label: "Regular" }, { id: "bold", label: "Bold" }, { id: "black", label: "Black" }]
                            ChoicePill {
                                required property var modelData
                                label: modelData.label
                                on: Settings.lock.depthWeight === modelData.id
                                onClicked: ed.set("depthWeight", modelData.id)
                            }
                        }
                    }
                }

                // ── Layout ────────────────────────────────────────────────────
                Panel {
                    visible: ed.tab === "layout"
                    Layout.fillWidth: true
                    implicitHeight: layoutRows.implicitHeight + 6
                    ColumnLayout {
                        id: layoutRows
                        x: 0; y: 3; width: parent.width
                        spacing: 0
                        OptRow { first: true; label: "Position"
                            sub: Settings.lock.depthPos === "custom" ? "Drag the clock on the screen above · double-click it to centre"
                                                                     : "Placed around the subject of each picture"
                            Row { spacing: 6
                                ChoicePill { label: "Automatic"; on: Settings.lock.depthPos !== "custom"; onClicked: ed.set("depthPos", "auto") }
                                ChoicePill { label: "Where I put it"; on: Settings.lock.depthPos === "custom"; onClicked: ed.set("depthPos", "custom") } } }
                        OptRow { label: "Arrangement"; sub: "Stacked turns into one line by itself where the subject would hide the minutes"
                            Row { spacing: 6
                                ChoicePill { label: "12:45"; mono: true; on: Settings.lock.depthLayout !== "stacked"; onClicked: ed.set("depthLayout", "horizontal") }
                                ChoicePill { label: "12 / 45"; mono: true; on: Settings.lock.depthLayout === "stacked"; onClicked: ed.set("depthLayout", "stacked") } } }
                        OptRow { label: "Size"; sub: "Automatic position may shrink it a little to fit above the subject"
                            Slide { from: 0.12; to: 0.34; key: "depthClockSize"; fallback: 0.22; percent: false; suffix: "%"; scaleShown: 100 / 0.22 } }
                    }
                }

                // ── Details ───────────────────────────────────────────────────
                Panel {
                    visible: ed.tab === "details"
                    Layout.fillWidth: true
                    implicitHeight: detailRows.implicitHeight + 6
                    ColumnLayout {
                        id: detailRows
                        x: 0; y: 3; width: parent.width
                        spacing: 0
                        OptRow { first: true; label: "Date"
                            Row { spacing: 6
                                ChoicePill { label: "Monday, 23 November"; on: (Settings.lock.depthDate || "long") === "long"; onClicked: ed.set("depthDate", "long") }
                                ChoicePill { label: "Mon 23 Nov"; on: Settings.lock.depthDate === "short"; onClicked: ed.set("depthDate", "short") }
                                ChoicePill { label: "Off"; on: Settings.lock.depthDate === "off"; onClicked: ed.set("depthDate", "off") } } }
                        OptRow { label: "Weather"; sub: "The temperature after the date"
                            ToggleSwitch { on: Settings.lock.depthWeather ?? true; onToggled: ed.set("depthWeather", !(Settings.lock.depthWeather ?? true)) } }
                        OptRow { label: "Clock"
                            sub: Settings.lock.clock === "system" ? "Follows Appearance → 24-hour clock" : "Only the lock screen"
                            Row { spacing: 6
                                ChoicePill { label: "System"; on: Settings.lock.clock === "system"; onClicked: ed.set("clock", "system") }
                                ChoicePill { label: "12-hour"; on: Settings.lock.clock === "12"; onClicked: ed.set("clock", "12") }
                                ChoicePill { label: "24-hour"; on: Settings.lock.clock === "24"; onClicked: ed.set("clock", "24") } } }
                        OptRow { visible: !Atelier.lockClock24; label: "AM / PM"; sub: "Small, beside the digits"
                            ToggleSwitch { on: Settings.lock.depthAmPm ?? true; onToggled: ed.set("depthAmPm", !(Settings.lock.depthAmPm ?? true)) } }
                    }
                }
            }
        }
    }

    // ── pieces ──
    // one option row in a Panel: label (+ quiet line) on the left, the control on the right
    component OptRow: Item {
        id: orow
        property bool first: false
        property string label
        property string sub: ""
        default property alias control: oSlot.data
        Layout.fillWidth: true
        implicitHeight: Math.max(52, oText.implicitHeight + 22)
        Rectangle { visible: !orow.first; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 14; anchors.rightMargin: 14; height: 1; color: Atelier.outline }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16; anchors.rightMargin: 14
            spacing: 16
            ColumnLayout {
                id: oText
                Layout.fillWidth: true
                spacing: 1
                Text { Layout.fillWidth: true; text: orow.label; font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: Font.Medium; color: Atelier.text; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; visible: orow.sub !== ""; text: orow.sub; font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext; wrapMode: Text.WordWrap }
            }
            Item { id: oSlot; implicitWidth: childrenRect.width; implicitHeight: childrenRect.height }
        }
    }

    // a slider bound to Settings.lock[key], with its value shown
    component Slide: RowLayout {
        id: sl
        property real from: 0
        property real to: 1
        property string key
        property real fallback: 0
        property bool percent: true
        property string suffix: "%"
        property real scaleShown: 100
        readonly property real value: Settings.lock[key] ?? fallback
        readonly property real frac: Math.max(0, Math.min(1, (value - from) / (to - from)))
        spacing: 12
        Item {
            id: track
            implicitWidth: 180; implicitHeight: 26
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 6; radius: 3
                color: Atelier.containerHigh
                Rectangle { width: Math.max(6, parent.width * sl.frac); height: parent.height; radius: 3; color: Atelier.accentFill }
            }
            Rectangle {
                x: sl.frac * (track.width - width)
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18; radius: 9
                color: Atelier.onFill
                border.width: 3; border.color: Atelier.accentFill
                scale: slMa.pressed ? 1.15 : 1
                Behavior on scale { NumberAnimation { duration: 120 } }
            }
            MouseArea {
                id: slMa
                anchors.fill: parent
                anchors.topMargin: -6; anchors.bottomMargin: -6
                cursorShape: Qt.PointingHandCursor
                function pick(x) {
                    const f = Math.max(0, Math.min(1, x / width));
                    ed.set(sl.key, Math.round((sl.from + f * (sl.to - sl.from)) * 100) / 100);
                }
                onPressed: (m) => pick(m.x)
                onPositionChanged: (m) => { if (pressed) pick(m.x); }
            }
        }
        Text {
            Layout.preferredWidth: 44
            horizontalAlignment: Text.AlignRight
            text: Math.round(sl.value * sl.scaleShown) + sl.suffix
            font.family: Atelier.font; font.pixelSize: 11; color: Atelier.subtext1
        }
    }

    component FontTile: Rectangle {
        id: ft
        property string fam
        property string label
        property int weight: Font.Bold
        property bool on: false
        signal clicked()
        implicitHeight: 96; radius: 16
        color: on ? Qt.alpha(Atelier.accent, 0.12) : (ftMa.containsMouse ? Atelier.containerHigh : Atelier.container)
        border.width: on ? 2 : 1
        border.color: on ? Atelier.accent : Atelier.outline
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 10; text: "12:45"; font.family: ft.fam; font.pixelSize: 38; font.weight: ft.weight
            font.features: { "tnum": 1 }; color: Atelier.text }
        Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 10; text: ft.label
            font.family: Atelier.fontUi; font.pixelSize: 11; font.weight: ft.on ? Font.DemiBold : Font.Normal; color: ft.on ? Atelier.text : Atelier.subtext }
        MouseArea { id: ftMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ft.clicked() }
    }

    component StyleTile: Rectangle {
        id: st
        property string kind
        property string label
        property string sub
        readonly property bool on: Settings.lock.depthStyle === kind
        Layout.preferredWidth: 220
        Layout.alignment: Qt.AlignTop
        implicitHeight: 172
        radius: 18
        color: on ? Qt.alpha(Atelier.accent, 0.12) : (stMa.containsMouse ? Atelier.containerHigh : Atelier.container)
        border.width: on ? 2 : 1
        border.color: on ? Atelier.accent : Atelier.outline
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
        // a small picture of each look: solid digits / frosted digits with a rim
        Rectangle {
            id: sample
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 10
            height: 96; radius: 12
            gradient: Gradient {
                GradientStop { position: 0; color: Atelier.sapphire }
                GradientStop { position: 1; color: Atelier.mauve }
            }
            Text {
                anchors.centerIn: parent
                text: "12:45"
                font.family: "Inter Display"; font.pixelSize: 44; font.weight: Font.Bold
                font.features: { "tnum": 1 }
                color: st.kind === "glass" ? Qt.rgba(1, 1, 1, 0.3) : "white"
                style: st.kind === "glass" ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(1, 1, 1, 0.85)
            }
        }
        Column {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: sample.bottom
            anchors.margins: 12; anchors.topMargin: 10
            spacing: 2
            Text { text: st.label; font.family: Atelier.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold; color: Atelier.text }
            Text { width: parent.width; text: st.sub; wrapMode: Text.WordWrap; font.family: Atelier.fontUi; font.pixelSize: 11; color: Atelier.subtext }
        }
        MouseArea { id: stMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ed.set("depthStyle", st.kind) }
    }
}
