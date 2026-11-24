import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.modules.bar
import qs.services

// Settings → Tools.
ColumnLayout {
    required property var win
    Layout.fillWidth: true
    spacing: 20

    SettingCard {
        title: "Screen recording"; icon: "󰑋"; tint: Atelier.red
        SettingRow { label: Recorder.available ? "Start / stop" : "Needs wf-recorder"
            description: Recorder.available ? "Super+Shift+R picks an area · Super+Alt+R records the whole screen · R in the screenshot picker"
                                            : "sudo pacman -S wf-recorder" }
        SettingChoice { label: "Sound"; tint: Atelier.red
            options: [{ id: "none", label: "None" }, { id: "system", label: "System" }, { id: "mic", label: "Microphone" }]
            value: Settings.recorder.audio; onPicked: (id) => Settings.recorder.audio = id }
        SettingChoice { label: "Frame rate"; tint: Atelier.red
            options: [{ id: "30", label: "30 fps" }, { id: "60", label: "60 fps" }]
            value: String(Settings.recorder.fps); onPicked: (id) => Settings.recorder.fps = Number(id) }
        SettingField { label: "Save to"; placeholder: "~/Videos/Recordings"; fieldWidth: 260
            text: Settings.recorder.folder; onCommitted: (t) => Settings.recorder.folder = t.trim() || "~/Videos/Recordings" }
    }

    SettingCard {
        title: "Emoji & GIFs"; icon: "󰞅"; tint: Atelier.yellow
        SettingRow { label: "Open"
            description: "Super+; for emoji · Super+Shift+; for GIFs · Tab switches between them"
            Chip { icon: "󰞅"; text: "Emoji"; tint: Atelier.yellow; interactive: true; implicitHeight: 32
                onClicked: win.requestOverlay("emoji") } }
        SettingSwitch { label: "Type the emoji for me"
            description: "Also types it into the window you were in (needs wtype). Off: only copies it"
            checked: Settings.emoji.typeOnPick; onToggled: (v) => Settings.emoji.typeOnPick = v }
        SettingChoice { label: "Skin tone"; description: "For emoji that have one"
            options: [{ id: "0", label: "✋" }, { id: "1", label: "✋🏻" }, { id: "2", label: "✋🏼" },
                      { id: "3", label: "✋🏽" }, { id: "4", label: "✋🏾" }, { id: "5", label: "✋🏿" }]
            value: String(Settings.emoji.tone); onPicked: (id) => Settings.emoji.tone = Number(id) }
        SettingChoice { label: "GIF service"; description: "Both are free with a key; safe search is always on"
            options: [{ id: "giphy", label: "GIPHY" }, { id: "tenor", label: "Tenor" }]
            value: Settings.emoji.gifProvider; onPicked: (id) => Settings.emoji.gifProvider = id }
        SettingField { label: "API key"; fieldWidth: 280
            description: Settings.emoji.gifProvider === "tenor" ? "console.cloud.google.com → enable the Tenor API → create a key"
                                                               : "developers.giphy.com → Create an app → API key"
            placeholder: "Paste your key"
            text: Settings.emoji.gifKey; onCommitted: (t) => Settings.emoji.gifKey = t.trim() }
    }

    SettingCard {
        title: "Focus timer"; icon: "󰔟"; tint: Atelier.accent
        SettingRow { label: "Open"; description: "Super+Alt+T · timers, stopwatch and pomodoro"
            Chip { icon: "󱎫"; text: "Timers"; tint: Atelier.accent; interactive: true; implicitHeight: 32; onClicked: win.requestOverlay("timers") } }
        SettingSlider { label: "Focus length"; from: 5; to: 90; step: 5; suffix: " min"
            value: Settings.behavior.pomoFocus; onMoved: (v) => Settings.behavior.pomoFocus = Math.round(v) }
        SettingSlider { label: "Short break"; from: 1; to: 30; step: 1; suffix: " min"
            value: Settings.behavior.pomoShort; onMoved: (v) => Settings.behavior.pomoShort = Math.round(v) }
        SettingSlider { label: "Long break"; from: 5; to: 60; step: 5; suffix: " min"
            value: Settings.behavior.pomoLong; onMoved: (v) => Settings.behavior.pomoLong = Math.round(v) }
        SettingSlider { label: "Long break after"; from: 2; to: 8; step: 1; suffix: " rounds"
            value: Settings.behavior.pomoEvery; onMoved: (v) => Settings.behavior.pomoEvery = Math.round(v) }
    }
}
