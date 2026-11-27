import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// Settings → Appearance.
ColumnLayout {
    required property var win
    Layout.fillWidth: true
    spacing: 20

    // hero: a live miniature of your desktop + the theme
    SettingCard {
        Item {
            Layout.fillWidth: true
            implicitHeight: 196
            RowLayout {
                anchors.fill: parent
                anchors.topMargin: 14
                anchors.bottomMargin: 14
                spacing: 22

                ClippingRectangle {
                    id: mini
                    Layout.preferredWidth: 280
                    Layout.preferredHeight: 166
                    radius: Atelier.radiusSm
                    color: Atelier.base
                    // screen px → preview px, exaggerated a little so thin things stay visible
                    readonly property real k: width / 1920 * 1.7
                    readonly property string edge: Settings.appearance.barPosition
                    readonly property real fr: Math.max(2, Settings.appearance.frame * k)
                    readonly property real bw: Math.max(7, Settings.appearance.barWidth * k)
                    readonly property real gap: Math.max(2, Settings.windows.gapsOut * k)
                    readonly property real inL: (edge === "left" ? bw : fr) + gap
                    readonly property real inR: (edge === "right" ? bw : fr) + gap
                    readonly property real inT: (edge === "top" ? bw : fr) + gap
                    readonly property real inB: (edge === "bottom" ? bw : fr) + gap

                    Image {
                        anchors.fill: parent
                        source: win.visible && Wallpaper.current ? "file://" + Wallpaper.current : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 560
                    }
                    // the frame
                    Rectangle { anchors.fill: parent; color: "transparent"; border.width: mini.fr; border.color: Atelier.surface }
                    // the bar
                    Rectangle {
                        color: Atelier.surface
                        x: mini.edge === "right" ? mini.width - mini.bw : 0
                        y: mini.edge === "bottom" ? mini.height - mini.bw : 0
                        width: mini.edge === "left" || mini.edge === "right" ? mini.bw : mini.width
                        height: mini.edge === "top" || mini.edge === "bottom" ? mini.bw : mini.height
                        Rectangle {   // logo + workspace dots
                            readonly property bool v: mini.edge === "left" || mini.edge === "right"
                            x: v ? (parent.width - width) / 2 : 6
                            y: v ? 6 : (parent.height - height) / 2
                            width: v ? 4 : 16; height: v ? 16 : 4; radius: 2
                            color: Atelier.accent
                        }
                    }
                    // two windows, with your corners and gaps
                    Repeater {
                        model: 2
                        Rectangle {
                            required property int index
                            readonly property real aw: mini.width - mini.inL - mini.inR
                            readonly property real g: Math.max(2, Settings.windows.gapsIn * mini.k)
                            x: mini.inL + (index === 0 ? 0 : aw * 0.58 + g / 2)
                            y: mini.inT
                            width: index === 0 ? aw * 0.58 - g / 2 : aw * 0.42 - g / 2
                            height: mini.height - mini.inT - mini.inB
                            radius: Settings.windowRounding * mini.k
                            color: Qt.alpha(Atelier.base, Settings.windows.activeOpacity)
                            border.width: 1
                            border.color: index === 0 ? Qt.alpha(Atelier.accent, 0.7) : Atelier.outline
                            Column {
                                x: 8; y: 9; spacing: 4
                                Repeater {
                                    model: 4
                                    Rectangle { required property int index; width: [44, 30, 52, 24][index]; height: 3; radius: 1.5; color: Qt.alpha(Atelier.text, 0.25) }
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 6
                    Text { text: Atelier.themeName; font.family: Atelier.fontUi; font.pixelSize: 20; font.weight: Font.Bold; color: Atelier.text }
                    Text {
                        Layout.fillWidth: true
                        text: (Atelier.isLight ? "Light" : "Dark") + " theme · the shell, Hyprland, terminals, VS Code, GTK and Qt apps follow it"
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext; wrapMode: Text.Wrap
                    }
                    Row {
                        Layout.topMargin: 6
                        spacing: 6
                        Repeater {
                            model: ["accent", "red", "peach", "yellow", "green", "teal", "blue", "mauve", "pink"]
                            Rectangle {
                                required property string modelData
                                width: 18; height: 18; radius: 9
                                color: Atelier[modelData]
                                border.width: modelData === "accent" ? 2 : 0
                                border.color: Atelier.text
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        Chip { icon: "󰏘"; text: "Change theme"; tint: Atelier.accent; interactive: true; implicitHeight: 32; onClicked: win.requestOverlay("theme") }
                        Chip { icon: "󰸉"; text: "Wallpaper"; tint: Atelier.accent; interactive: true; implicitHeight: 32; onClicked: win.requestOverlay("wallpaper") }
                        Chip { icon: Atelier.isLight ? "󰖔" : "󰖨"; text: Atelier.isLight ? "Dark" : "Light"; tint: Atelier.accent; interactive: true; implicitHeight: 32; onClicked: SysState.toggleTheme() }
                    }
                }
            }
        }
    }

    SettingCard {
        title: "Wallpaper transition"; icon: "󰸉"; tint: Atelier.blue
        SettingChoice { label: "Style"; description: "How a new wallpaper appears"; tint: Atelier.blue
            options: [{ id: "none", label: "None" }, { id: "fade", label: "Fade" }, { id: "wipe", label: "Wipe" },
                      { id: "slide", label: "Slide" }, { id: "grow", label: "Grow" }, { id: "zoom", label: "Zoom" }, { id: "spread", label: "Spread" }]
            value: Settings.appearance.wallTransition; onPicked: (id) => Settings.appearance.wallTransition = id }
        SettingSwitch { label: "Surprise me"; description: "Pick a different style each time"; tint: Atelier.blue
            checked: Settings.appearance.wallTransition === "random"
            onToggled: (v) => Settings.appearance.wallTransition = v ? "random" : "fade" }
        SettingChoice { label: "Direction"; description: "Where wipe and slide come from"; tint: Atelier.blue
            visible: ["wipe", "slide", "random"].includes(Settings.appearance.wallTransition)
            options: [{ id: "left", label: "Left" }, { id: "right", label: "Right" }, { id: "top", label: "Top" }, { id: "bottom", label: "Bottom" }]
            value: Settings.appearance.wallDirection; onPicked: (id) => Settings.appearance.wallDirection = id }
        SettingSlider { label: "Duration"; tint: Atelier.blue
            visible: Settings.appearance.wallTransition !== "none"
            from: 200; to: 2000; step: 50; suffix: " ms"
            value: Settings.appearance.wallDuration; onMoved: (v) => Settings.appearance.wallDuration = v }
    }

    SettingCard {
        title: "Corners"; icon: "󰝤"; tint: Atelier.accent
        SettingSlider { label: "Corner roundness"; description: "The frame, bar pop-ups and drawers"; from: 0; to: 36; step: 2; suffix: " px"
            value: Settings.appearance.rounding; onMoved: (v) => Settings.appearance.rounding = v }
        SettingSwitch {
            label: "Match window corners"
            description: Settings.appearance.linkRounding
                ? "Windows use " + Settings.windowRounding + " px — concentric with the frame, so the corners line up"
                : "Windows have their own roundness (Windows page)"
            checked: Settings.appearance.linkRounding; onToggled: (v) => Settings.appearance.linkRounding = v }
    }

    SettingCard {
        title: "Shell"; icon: "󰹑"; tint: Atelier.blue
        SettingSlider { label: "Border thickness"; description: "The frame around the screen"; from: 4; to: 20; step: 1; suffix: " px"; tint: Atelier.blue
            value: Settings.appearance.frame; onMoved: (v) => Settings.appearance.frame = v }
        SettingSlider { label: "Shell animation speed"; description: "Drawers, pop-ups and the bar. 1.0 is the default; higher is faster"; from: 0.5; to: 2; step: 0.1; decimals: 1; suffix: "×"
            value: Settings.general.animSpeed; onMoved: (v) => Settings.general.animSpeed = v }
        SettingSwitch { label: "24-hour clock"; description: "Bar, widgets, control center and lock screen"
            checked: Settings.general.clock24; onToggled: (v) => Settings.general.clock24 = v }
    }

    SettingCard {
        id: winLook
        title: "Transparency"; icon: "󰂵"; tint: Atelier.sky
        readonly property var w: Settings.windows
        function resetBlur() {
            const d = { blurSize: 9, blurPasses: 2, blurVibrancy: 0.17, blurNoise: 0.012, blurContrast: 0.95, blurBrightness: 0.90 };
            for (const k in d) Settings.windows[k] = d[k];
        }
        SettingSlider { label: "Focused window opacity"; description: "Applies to every app"; from: 0.6; to: 1; step: 0.01; decimals: 2; tint: Atelier.sky
            value: winLook.w.activeOpacity; onMoved: (v) => Settings.windows.activeOpacity = v }
        SettingSlider { label: "Unfocused window opacity"; from: 0.5; to: 1; step: 0.01; decimals: 2; tint: Atelier.sky
            value: winLook.w.inactiveOpacity; onMoved: (v) => Settings.windows.inactiveOpacity = v }
        SettingSwitch { label: "Shell matches windows"; description: Settings.appearance.glassMatchWindows
                ? "The bar and drawers use the focused window opacity (" + Math.round(Settings.windows.activeOpacity * 100) + "%), so their blur looks the same"
                : "The bar and drawers have their own opacity"
            checked: Settings.appearance.glassMatchWindows; onToggled: (v) => Settings.appearance.glassMatchWindows = v }
        SettingSlider { visible: !Settings.appearance.glassMatchWindows; label: "    Shell glass"; description: "How solid the bar and drawers are"; from: 0.6; to: 1; step: 0.02; decimals: 2
            value: Settings.appearance.glass; onMoved: (v) => Settings.appearance.glass = v }
        SettingChoice { visible: !Atelier.isLight; label: "Shell glass colour"; description: "Deep is the theme's darkest shade; Base is the background most apps use, and lets more blur show"
            options: [{ id: "deep", label: "Deep" }, { id: "base", label: "Base" }]
            value: Settings.appearance.glassTone; onPicked: (id) => Settings.appearance.glassTone = id }
        SettingSwitch { label: "Keep video, games and image apps solid"
            description: "Off: every app is see-through and blurred, including mpv, VLC, image viewers, Steam games, GIMP, Krita, Blender, OBS"
            tint: Atelier.sky; checked: winLook.w.solidApps; onToggled: (v) => Settings.windows.solidApps = v }
        SettingSwitch { label: "Keep fullscreen windows solid"; tint: Atelier.sky
            checked: winLook.w.solidFullscreen; onToggled: (v) => Settings.windows.solidFullscreen = v }
    }

    SettingCard {
        title: "Blur"; icon: "󰂵"; tint: Atelier.sky
        SettingRow { label: "Applies to"; description: "Strength, smoothness and colour are shared by windows, the bar and drawers"
            Chip { icon: "󰑙"; text: "Reset look"; tint: Atelier.subtext; interactive: true; implicitHeight: 28; onClicked: winLook.resetBlur() } }
        SettingSwitch { label: "Behind windows"; description: "Frosted glass behind see-through windows"; tint: Atelier.sky
            checked: winLook.w.blur; onToggled: (v) => Settings.windows.blur = v }
        SettingSwitch { visible: winLook.w.blur; label: "    Blur what's behind"
            description: winLook.w.blurBehind ? "Windows blur the windows under them. Uses noticeably more GPU"
                                              : "Off: windows show the blurred wallpaper only (cheap, looks the same for tiled windows)"
            tint: Atelier.sky; checked: winLook.w.blurBehind; onToggled: (v) => Settings.windows.blurBehind = v }
        SettingSwitch { label: "Behind the shell"; description: "Frosted glass behind the bar and drawers"
            checked: Settings.appearance.shellBlur; onToggled: (v) => Settings.appearance.shellBlur = v }
        SettingSlider { visible: winLook.w.blur || Settings.appearance.shellBlur; label: "    Strength"; description: "How far each pass spreads"; from: 2; to: 16; step: 1; tint: Atelier.sky
            value: winLook.w.blurSize; onMoved: (v) => Settings.windows.blurSize = Math.round(v) }
        SettingSlider { visible: winLook.w.blur || Settings.appearance.shellBlur; label: "    Smoothness"; description: "More passes look softer but cost GPU"; from: 1; to: 4; step: 1; tint: Atelier.sky
            value: winLook.w.blurPasses; onMoved: (v) => Settings.windows.blurPasses = Math.round(v) }
        SettingSlider { visible: winLook.w.blur || Settings.appearance.shellBlur; label: "    Vibrancy"; description: "Colour of what shows through"; from: 0; to: 0.6; step: 0.01; decimals: 2; tint: Atelier.sky
            value: winLook.w.blurVibrancy; onMoved: (v) => Settings.windows.blurVibrancy = v }
        SettingSlider { visible: winLook.w.blur || Settings.appearance.shellBlur; label: "    Brightness"; from: 0.5; to: 1.3; step: 0.01; decimals: 2; tint: Atelier.sky
            value: winLook.w.blurBrightness; onMoved: (v) => Settings.windows.blurBrightness = v }
        SettingSlider { visible: winLook.w.blur || Settings.appearance.shellBlur; label: "    Contrast"; from: 0.5; to: 1.5; step: 0.01; decimals: 2; tint: Atelier.sky
            value: winLook.w.blurContrast; onMoved: (v) => Settings.windows.blurContrast = v }
        SettingSlider { visible: winLook.w.blur || Settings.appearance.shellBlur; label: "    Grain"; description: "A little noise hides colour banding"; from: 0; to: 0.08; step: 0.002; decimals: 3; tint: Atelier.sky
            value: winLook.w.blurNoise; onMoved: (v) => Settings.windows.blurNoise = v }
        SettingSwitch { visible: winLook.w.blur; label: "    Menus and tooltips"; description: "Blur behind app pop-ups too"; tint: Atelier.sky
            checked: winLook.w.blurPopups; onToggled: (v) => Settings.windows.blurPopups = v }
    }

    SettingCard {
        title: "Shadows & dimming"; icon: "󰘵"; tint: Atelier.sky
        SettingSwitch { label: "Window shadows"; tint: Atelier.sky
            checked: winLook.w.shadow; onToggled: (v) => Settings.windows.shadow = v }
        SettingSwitch { label: "Shell shadows"; description: "Under the drawers and along the frame"
            checked: Settings.appearance.shellShadow; onToggled: (v) => Settings.appearance.shellShadow = v }
        SettingSwitch { label: "Edge spectrum"; description: "A soft audio visualizer along the bottom edge while music plays (Normal mode, nothing fullscreen)"
            checked: Settings.appearance.edgeSpectrum; onToggled: (v) => Settings.appearance.edgeSpectrum = v }
        SettingSwitch { label: "Dim unfocused windows"; tint: Atelier.sky
            checked: winLook.w.dimInactive; onToggled: (v) => Settings.windows.dimInactive = v }
        SettingSlider { visible: winLook.w.dimInactive; label: "    Dim amount"; from: 0.02; to: 0.4; step: 0.01; decimals: 2; tint: Atelier.sky
            value: winLook.w.dimStrength; onMoved: (v) => Settings.windows.dimStrength = v }
    }

}
