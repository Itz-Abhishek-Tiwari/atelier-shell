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

    readonly property var blurOpts: [{ id: "off", label: "Off" }, { id: "light", label: "Light" }, { id: "normal", label: "Your usual" }]
    readonly property var powerOpts: [{ id: "performance", label: "Performance" }, { id: "balanced", label: "Balanced" },
                                      { id: "power-saver", label: "Power saver" }, { id: "unchanged", label: "Don't change" }]
    // must match the defaults in config/Settings.qml (modes)
    readonly property var defaults: ({
        dev:  { Opaque: true, Dim: false, Blur: "light", Shadows: true, Animations: true, AnimSpeed: 0.6,
                Power: "performance", Caffeine: true, Dnd: false },
        game: { Opaque: true, Blur: "off", Shadows: false, Animations: false, Tearing: true,
                Power: "performance", Caffeine: true, Dnd: true, HideWidgets: true, LeanShell: true }
    })
    function reset(m) { const d = defaults[m]; for (const k in d) Settings.modes[m + k] = d[k]; }
    function isDefault(m) { const d = defaults[m]; for (const k in d) if (Settings.modes[m + k] !== d[k]) return false; return true; }

    SettingCard {
        title: "Current mode"; icon: "󰊗"; tint: Atelier.sapphire
        SettingChoice { label: "Mode"; tint: Atelier.sapphire
            description: "Normal is your own look from Appearance and Windows"
            options: [{ id: "normal", label: "Normal" }, { id: "dev", label: "Programming" }, { id: "game", label: "Game" }]
            value: Perf.mode; onPicked: (id) => Perf.set(id) }
    }

    SettingCard {
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
        title: "Game mode automatically"; icon: "󰐊"; tint: Atelier.peach
        SettingSwitch { label: "Switch on for games"; description: "On when a game (Steam, gamescope, Lutris, Heroic…) is focused, back off when it closes"; tint: Atelier.peach
            checked: Settings.behavior.autoGameMode; onToggled: (v) => Settings.behavior.autoGameMode = v }
        SettingField { visible: Settings.behavior.autoGameMode; label: "Also counts as a game"
            description: "Window classes, comma-separated (hyprctl activewindow shows a window's class)"
            placeholder: "e.g. osu!, retroarch"; fieldWidth: 220
            text: Settings.modes.gameApps; onCommitted: (t) => Settings.modes.gameApps = t.trim() }
    }
}
