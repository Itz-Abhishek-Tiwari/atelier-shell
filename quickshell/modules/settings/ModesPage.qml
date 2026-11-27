import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// Settings → Modes.
ColumnLayout {
    required property var win
    id: modesPage
    Layout.fillWidth: true
    spacing: 20

    // which mode's options are shown below the cards (follows the active mode, Normal has none)
    property string editing: Perf.mode !== "normal" ? Perf.mode : "dev"
    Connections { target: Perf; function onModeChanged() { if (Perf.mode !== "normal") modesPage.editing = Perf.mode; } }

    readonly property var blurOpts: [{ id: "off", label: "Off" }, { id: "light", label: "Light" }, { id: "normal", label: "Your usual" }]
    readonly property var powerOpts: [{ id: "performance", label: "Performance" }, { id: "balanced", label: "Balanced" },
                                      { id: "power-saver", label: "Power saver" }, { id: "unchanged", label: "Don't change" }]
    // must match the defaults in config/Settings.qml (modes)
    readonly property var defaults: ({
        dev:  { Opaque: true, Dim: false, Blur: "light", Shadows: true, Animations: true, AnimSpeed: 0.6,
                Power: "performance", Caffeine: true, Dnd: false },
        game: { Opaque: true, Blur: "off", Shadows: false, Animations: false, Tearing: true,
                Power: "performance", Caffeine: true, Dnd: true, HideWidgets: true, LeanShell: true },
        saver: { Opaque: true, Dim: false, Blur: "off", Shadows: false,
                 Power: "power-saver", Caffeine: false, Dnd: false, HideWidgets: true, LeanShell: true }
    })
    function reset(m) { const d = defaults[m]; for (const k in d) Settings.modes[m + k] = d[k]; }
    function isDefault(m) { const d = defaults[m]; for (const k in d) if (Settings.modes[m + k] !== d[k]) return false; return true; }

    // ── the modes: one card each, click to switch ─────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Repeater {
            model: Perf.info
            Rectangle {
                id: card
                required property var modelData
                readonly property bool on: Perf.mode === modelData.id
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 128
                radius: Atelier.radiusLg
                color: on ? Qt.alpha(modelData.tint, Atelier.isLight ? 0.16 : 0.20) : Atelier.container
                StateLayer { mouseArea: cardMa }
                border.width: on ? 2 : 1
                border.color: on ? Qt.alpha(modelData.tint, 0.65) : Atelier.outline
                scale: cardMa.pressed ? 0.97 : 1
                Behavior on color { CAnim {} }
                Behavior on scale { Anim { type: "fastSpatial" } }

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6
                    Rectangle {
                        width: 38; height: 38; radius: Atelier.radiusMd
                        color: Qt.alpha(card.modelData.tint, card.on ? 0.30 : 0.16)
                        Text { anchors.centerIn: parent; text: card.modelData.icon; font.family: Atelier.font; font.pixelSize: 20; color: card.modelData.tint }
                    }
                    Text { text: card.modelData.label; width: parent.width; elide: Text.ElideRight
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; font.weight: Font.DemiBold; color: Atelier.text }
                    Text { text: card.modelData.blurb; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                }
                // GPU cost: five small pips along the bottom edge
                Row {
                    anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 2
                    Repeater {
                        model: 5
                        Rectangle { required property int index
                            width: 4; height: 10; radius: 2
                            color: index < card.modelData.cost ? card.modelData.tint : Qt.alpha(Atelier.subtext, 0.25) }
                    }
                }
                MouseArea { id: cardMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: Perf.set(card.modelData.id) }
            }
        }
    }
    Text {
        Layout.leftMargin: 4
        text: "The bars on each card show how hard the mode works the GPU. Normal is your own look from Appearance and Windows."
        font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext
        wrapMode: Text.Wrap; Layout.fillWidth: true
    }

    // ── which mode to customise ───────────────────────────────────────────────
    SettingCard {
        title: "Customise"
        SettingChoice { label: "Mode"; description: "Everything below applies to the mode you pick here"
            options: [{ id: "dev", label: "Programming" }, { id: "game", label: "Game" }, { id: "saver", label: "Saver" }]
            value: modesPage.editing; onPicked: (id) => modesPage.editing = id }
    }

    SettingCard {
        visible: modesPage.editing === "dev"
        title: "Programming mode"; icon: "󰅩"; tint: Atelier.teal
        SettingSwitch { label: "Opaque windows"; description: "Crisp text, nothing blurred behind windows"; tint: Atelier.teal
            checked: Settings.modes.devOpaque; onToggled: (v) => Settings.modes.devOpaque = v }
        SettingSwitch { label: "Dim unfocused windows"; tint: Atelier.teal
            checked: Settings.modes.devDim; onToggled: (v) => Settings.modes.devDim = v }
        SettingChoice { label: "Blur"; description: "Light = one pass, cheaper"; tint: Atelier.teal
            options: modesPage.blurOpts; value: Settings.modes.devBlur; onPicked: (id) => Settings.modes.devBlur = id }
        SettingSwitch { label: "Window shadows"; tint: Atelier.teal
            checked: Settings.modes.devShadows; onToggled: (v) => Settings.modes.devShadows = v }
        SettingSwitch { label: "Animations"; tint: Atelier.teal
            checked: Settings.modes.devAnimations; onToggled: (v) => Settings.modes.devAnimations = v }
        SettingSlider { visible: Settings.modes.devAnimations; label: "Animation length"; description: "100% = like Normal mode; smaller is snappier"
            from: 30; to: 100; step: 5; decimals: 0; suffix: "%"; tint: Atelier.teal
            value: Settings.modes.devAnimSpeed * 100; onMoved: (v) => Settings.modes.devAnimSpeed = v / 100 }
        SettingChoice { label: "Power profile"; description: "Performance drops to Balanced on battery"; tint: Atelier.teal
            options: modesPage.powerOpts; value: Settings.modes.devPower; onPicked: (id) => Settings.modes.devPower = id }
        SettingSwitch { label: "Keep the screen awake"; tint: Atelier.teal
            checked: Settings.modes.devCaffeine; onToggled: (v) => Settings.modes.devCaffeine = v }
        SettingSwitch { label: "Do Not Disturb"; description: "Silence notification pop-ups"; tint: Atelier.teal
            checked: Settings.modes.devDnd; onToggled: (v) => Settings.modes.devDnd = v }
        SettingRow {
            visible: !modesPage.isDefault("dev")
            label: "Back to the defaults"
            Chip { icon: "󰑓"; text: "Reset"; tint: Atelier.teal; interactive: true; implicitHeight: 30; onClicked: modesPage.reset("dev") }
        }
    }

    SettingCard {
        visible: modesPage.editing === "game"
        title: "Game mode"; icon: "󰊴"; tint: Atelier.red
        SettingSwitch { label: "Opaque windows"; tint: Atelier.red
            checked: Settings.modes.gameOpaque; onToggled: (v) => Settings.modes.gameOpaque = v }
        SettingChoice { label: "Blur"; tint: Atelier.red
            options: modesPage.blurOpts; value: Settings.modes.gameBlur; onPicked: (id) => Settings.modes.gameBlur = id }
        SettingSwitch { label: "Window shadows"; tint: Atelier.red
            checked: Settings.modes.gameShadows; onToggled: (v) => Settings.modes.gameShadows = v }
        SettingSwitch { label: "Animations"; tint: Atelier.red
            checked: Settings.modes.gameAnimations; onToggled: (v) => Settings.modes.gameAnimations = v }
        SettingSwitch { label: "Allow tearing"; description: "Lowest latency for fullscreen games"; tint: Atelier.red
            checked: Settings.modes.gameTearing; onToggled: (v) => Settings.modes.gameTearing = v }
        SettingChoice { label: "Power profile"; tint: Atelier.red
            options: modesPage.powerOpts; value: Settings.modes.gamePower; onPicked: (id) => Settings.modes.gamePower = id }
        SettingSwitch { label: "Keep the screen awake"; tint: Atelier.red
            checked: Settings.modes.gameCaffeine; onToggled: (v) => Settings.modes.gameCaffeine = v }
        SettingSwitch { label: "Do Not Disturb"; tint: Atelier.red
            checked: Settings.modes.gameDnd; onToggled: (v) => Settings.modes.gameDnd = v }
        SettingSwitch { label: "Hide the desktop widget"; tint: Atelier.red
            checked: Settings.modes.gameHideWidgets; onToggled: (v) => Settings.modes.gameHideWidgets = v }
        SettingSwitch { label: "Lighter shell"; description: "No shadows on the bar and drawers, solid instead of glass"; tint: Atelier.red
            checked: Settings.modes.gameLeanShell; onToggled: (v) => Settings.modes.gameLeanShell = v }
        SettingRow {
            visible: !modesPage.isDefault("game")
            label: "Back to the defaults"
            Chip { icon: "󰑓"; text: "Reset"; tint: Atelier.red; interactive: true; implicitHeight: 30; onClicked: modesPage.reset("game") }
        }
    }

    SettingCard {
        visible: modesPage.editing === "saver"
        title: "Battery saver"; icon: "󰌪"; tint: Atelier.yellow
        SettingRow { label: "Best battery life"; description: "Opaque windows, no blur, shadows, animations or dimming, the power-saver profile, and no desktop widget. Nothing is blended or animated, so the GPU can rest." }
        SettingSwitch { label: "Opaque windows"; description: "Nothing is blended"; tint: Atelier.yellow
            checked: Settings.modes.saverOpaque; onToggled: (v) => Settings.modes.saverOpaque = v }
        SettingSwitch { label: "Dim unfocused windows"; tint: Atelier.yellow
            checked: Settings.modes.saverDim; onToggled: (v) => Settings.modes.saverDim = v }
        SettingChoice { label: "Blur"; tint: Atelier.yellow
            options: modesPage.blurOpts; value: Settings.modes.saverBlur; onPicked: (id) => Settings.modes.saverBlur = id }
        SettingSwitch { label: "Window shadows"; tint: Atelier.yellow
            checked: Settings.modes.saverShadows; onToggled: (v) => Settings.modes.saverShadows = v }
        SettingRow { label: "Animations"; description: "Always off in this mode: windows, the shell and wallpaper changes are instant" }
        SettingChoice { label: "Power profile"; tint: Atelier.yellow
            options: modesPage.powerOpts; value: Settings.modes.saverPower; onPicked: (id) => Settings.modes.saverPower = id }
        SettingSwitch { label: "Keep the screen awake"; description: "Off saves battery"; tint: Atelier.yellow
            checked: Settings.modes.saverCaffeine; onToggled: (v) => Settings.modes.saverCaffeine = v }
        SettingSwitch { label: "Do Not Disturb"; tint: Atelier.yellow
            checked: Settings.modes.saverDnd; onToggled: (v) => Settings.modes.saverDnd = v }
        SettingSwitch { label: "Hide the desktop widget"; description: "It is not drawn or refreshed"; tint: Atelier.yellow
            checked: Settings.modes.saverHideWidgets; onToggled: (v) => Settings.modes.saverHideWidgets = v }
        SettingSwitch { label: "Lighter shell"; description: "No shadows on the bar and drawers, solid instead of glass"; tint: Atelier.yellow
            checked: Settings.modes.saverLeanShell; onToggled: (v) => Settings.modes.saverLeanShell = v }
        SettingRow {
            visible: !modesPage.isDefault("saver")
            label: "Back to the defaults"
            Chip { icon: "󰑓"; text: "Reset"; tint: Atelier.yellow; interactive: true; implicitHeight: 30; onClicked: modesPage.reset("saver") }
        }
    }

    SettingCard {
        title: "Game mode automatically"; icon: "󰐊"; tint: Atelier.peach
        SettingSwitch { label: "Switch on for games"; description: "On when a game (Steam, gamescope, Lutris, Heroic…) is focused, back off when it closes"; tint: Atelier.peach
            checked: Settings.behavior.autoGameMode; onToggled: (v) => Settings.behavior.autoGameMode = v }
        SettingField { visible: Settings.behavior.autoGameMode; label: "Also counts as a game"
            description: "Window classes, comma-separated (hyprctl activewindow shows a window's class)"
            placeholder: "e.g. osu!, retroarch"; fieldWidth: 220
            text: Settings.modes.gameApps; onCommitted: (t) => Settings.modes.gameApps = t.trim() }
    }
}
