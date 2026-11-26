# Writing a plugin for Quickshell Atelier: the complete reference

This file is written to be handed, whole, to an AI assistant (or a person) who knows nothing about this project.
It contains everything needed to write a working plugin. If you are an AI reading this: build exactly what the user asks,
use only what is listed here, and finish with the checklist in section 14.

---

## 1. What this is

Atelier is a desktop shell written in **QML on Quickshell** (a Wayland shell toolkit, Qt 6) running on Hyprland.
A **plugin** is a folder of QML files plus a `plugin.json`. Dropping it into `~/.config/atelier/plugins/` adds things to the shell
without editing the shell. Plugin code is ordinary QML, loaded at runtime with the shell's own theme and services.

A plugin can add any of six things (called *slots*):

| slot (manifest key) | what it is | needs QML file? |
|---|---|---|
| `lockStyles` | a whole lock-screen look, shown as a card in Settings → Lock screen | yes |
| `desktopWidgets` | a widget on the wallpaper, behind windows | yes |
| `settingsPages` | a page in the Settings app, under the "Plugins" group | yes |
| `barItems` | an item in the top/side bar, just before the power button | yes |
| `launcherActions` | a row in the launcher (search) | no, a manifest entry only |
| `controlTiles` | a button in the control centre's shortcut row | no, a manifest entry only |

A plugin may use any subset. It is not possible (yet) to add new global keybinds, new drawers/overlays, or to change built-in UI.

## 2. Folder layout and install

```
~/.config/atelier/plugins/<id>/        <id> = the folder name: lowercase letters, digits, . _ -   (max 64 chars)
    plugin.json                         required
    LockFace.qml  Widget.qml  Page.qml  BarItem.qml …      any names; referenced from plugin.json
```

Ways to install:
1. Settings → Plugins → "Install a plugin": a git URL, a `.zip` link, or a path to a folder or `.zip`. A repo/zip must have `plugin.json` at its top level (or inside exactly one top-level folder).
2. Copy the folder in by hand, then Settings → Plugins → Reload, or `qs ipc call plugins reload`.
3. `qs ipc call plugins install <source>` (same sources as 1).

**A plugin does not run until it is approved.** New plugins are switched off. The user presses *Approve* in Settings → Plugins
(or `qs ipc call plugins enable <id>`, which also approves). Approval stores a SHA-256 of every file in the folder in `.trusted`.
**If any file changes afterwards, the plugin is no longer approved and stops running** until approved again. So while developing:
edit, then run `qs ipc call plugins enable <id>`.

Other files the shell writes inside a plugin folder: `.disabled` (empty file = switched off), `.trusted` (the hash). Never ship these.

## 3. plugin.json

```json
{
  "name": "My Plugin",
  "version": "1.0",
  "author": "me",
  "description": "One line shown in Settings → Plugins",

  "lockStyles":      [{ "id": "mylock",  "name": "My Lock", "note": "Short subtitle", "file": "LockFace.qml" }],
  "desktopWidgets":  [{ "id": "clock",   "file": "Widget.qml", "hAlign": "right", "vAlign": "top", "margin": 40 }],
  "settingsPages":   [{ "id": "page",    "label": "My Plugin", "icon": "󰋜", "sub": "Subtitle", "file": "Page.qml" }],
  "barItems":        [{ "id": "btn",     "file": "BarItem.qml" }],
  "launcherActions": [{ "id": "say",     "title": "Say hello", "subtitle": "My Plugin", "glyph": "󰋜",
                        "words": "hello greet wave", "cmd": "notify-send hello" }],
  "controlTiles":    [{ "id": "tile",    "label": "Hello", "icon": "󰋜", "cmd": "notify-send hello" }]
}
```

Rules enforced by the scanner (a violation shows as an error on the plugin and **the whole plugin is not loaded**):
- `plugin.json` must be valid JSON. Top-level keys other than the ones above are ignored.
- Every entry is an object with a non-empty string `id`. QML slots also need a string `file`; `launcherActions` need `title`; `controlTiles` need `label`.
- `file` is relative to the plugin folder, must exist, and must stay inside the folder (symlinks pointing out are rejected).
- `launcherActions` and `controlTiles` need a string `cmd` or a string `overlay`.
- Entry `id`s need only be unique within their slot of this plugin. The shell builds a global id `<folder>.<id>`.
- Unknown entry keys are passed through but unused.

Per-slot keys:

| slot | key | meaning / default |
|---|---|---|
| lockStyles | `name`, `note` | card title (default: id) and subtitle (default: "<plugin name> plugin") |
| desktopWidgets | `hAlign` `left\|center\|right` (default `right`), `vAlign` `top\|center\|bottom` (default `top`), `margin` px (default 40) | anchor on the screen; margin is added to the bar/frame inset |
| settingsPages | `label` (default id), `icon` (a glyph, default 󰐱), `sub` (subtitle) | sidebar entry |
| launcherActions | `title`, `subtitle`, `glyph`, `words` (extra search words), `cmd` or `overlay`, `toast` (optional text shown after `cmd` runs) | `cmd` runs via `sh -c`; `overlay` opens a built-in drawer (ids in section 11) |
| controlTiles | `label`, `icon`, `cmd` or `overlay` | tile caption, glyph, action |

**Icons/glyphs** are single characters from the Nerd Font "SpaceMono Nerd Font Propo" (Material Design Icons range, e.g. `󰋜 󰐱 󰂚 󰍛 󰖩`), or an emoji.
Draw them in a `Text` with `font.family: Atelier.font`. Emoji need `font.family: Atelier.fontEmoji`.

## 4. How QML files are loaded (important)

- Each QML file is loaded with a `Loader` from a `file://` URL. **The root of the file must be an `Item`** (or something that inherits it: `Rectangle`, `ColumnLayout`, `SettingCard`, …). Not `Window`, not `QtObject`, not `Scope`, except where a section says otherwise.
- Available imports (anything else will fail): `QtQuick`, `QtQuick.Layouts`, `QtQuick.Controls`, `Quickshell`, `Quickshell.Io`, `Quickshell.Wayland`, `Quickshell.Widgets`, `Quickshell.Services.Mpris`, `Quickshell.Services.Pipewire`, `Quickshell.Services.UPower`, `Quickshell.Bluetooth`, and the shell's own modules:
  - `import qs.config` → `Atelier` (theme tokens, section 6) and `Settings`
  - `import qs.services` → services (section 9)
  - `import qs.components` → shared controls (section 7)
  - `import qs.modules.settings` → `Setting*` controls (section 8), only useful in settings pages
- **Declare `property var plugin` on the root item** and the shell fills it with `{ id, name, dir }` (the plugin's folder id, display name, absolute folder path). It is set right after load, so it is `undefined` for the first moment: guard with `plugin ? … : …`. Use `plugin.dir` for paths to your own files (e.g. images: `"file://" + plugin.dir + "/icon.png"`).
- A file that fails to load (syntax error, missing import, wrong root) is skipped, the shell keeps running, and the reason appears on the plugin's row in Settings → Plugins. A QML *warning* goes to `qs log`.
- QML tip: do not name a property `on<Capital>…` unless you mean a signal handler.
- Sizes: do not hardcode pixel sizes for text if you can use `Atelier.fs*` tokens (section 6); the user's UI scale/type settings follow them.
- Do not run busy timers or animations when invisible. The shell has a Battery-saver and Game mode and users are performance-sensitive. Prefer `Timer { running: visible }`.

## 5. The five QML slots in detail

### 5.1 barItems
- Placed in a row (top/bottom bar) or column (left/right bar), right before the power button, in **both** bar layouts.
- Set `implicitWidth` and `implicitHeight` on the root. Keep the bar's thickness direction ≤ ~34 px (`Atelier.barWidth` is the actual bar thickness).
- `Atelier.barVertical` is `true` when the bar is on the left/right: lay out text/icons for a narrow column.
- Receives mouse input normally (use `MouseArea`).
- To open a built-in drawer from a click, run the IPC command: `Plugins.run(["qs", "ipc", "call", "…"])` (section 12).

### 5.2 desktopWidgets
- Each widget becomes its own layer window on the **Bottom** layer (above the wallpaper, below normal windows), anchored by `hAlign`/`vAlign` with `margin`.
- The window size is the root item's `implicitWidth`/`implicitHeight` (minimum 1×1). Set them. Do not rely on `anchors.fill` of the window.
- `hAlign`/`vAlign`/`margin` are only the *default* place. The user can override position, edge distance and an X/Y nudge per widget in Settings → Plugins → Desktop widgets, so do not assume where you sit.
- Hidden when the user turned off desktop widgets, or in Game/Battery-saver mode if they chose to hide widgets.
- Use a translucent background such as `Qt.alpha(Atelier.base, 0.6)`, matching the shell's look.

### 5.3 settingsPages
- The root is placed in a `ColumnLayout` with `Layout.fillWidth: true`. Use `SettingCard` (a titled group) containing `SettingRow`/`SettingSwitch`/… rows, or a `ColumnLayout` of several cards with `spacing: 20`.
- The page is only instantiated while it is the visible page.
- Persist user choices with `Plugins.set` / `Plugins.get` (section 10).

### 5.4 lockStyles
- The user picks it in Settings → Lock screen; the shell shows your file as the full-screen lock face. A live miniature is also rendered in the card (see "preview" below).
- Root item gets a property **`ph`** assigned after load. Declare `property var ph`. It is the shell's lock object. Guard: `ph ? … : …`.
- Your item fills the whole screen. **Draw your own background.** The shell's password field is drawn over your face when the user starts typing (`ph.auth` becomes true); keep the centre-bottom region reasonably free or fade your face when `ph.auth`.
- **Size everything relative to `ph.u`** (a scale unit = screen height ÷ 1000 × the user's lock-size setting, which defaults to 0.72; so on a 1080 px tall screen `ph.u` is about 0.78). e.g. a font of 200 design-units is `200 * ph.u` pixels. Never use fixed pixel sizes for big things: the same file is rendered small in the Settings preview card and at full size on the lock screen.
- Properties available on `ph` (all read-only):

| `ph.…` | type | meaning |
|---|---|---|
| `hh` `mm` | string | hour (12/24h per user setting, zero-padded) and minutes, e.g. "09" "45" |
| `h1` | string | hour without a leading zero |
| `ampm` | string | "AM"/"PM", or "" in 24-hour mode |
| `now` | date | current time, ticks every second |
| `u` | real | scale unit, see above |
| `ts` | real | multiply type tokens by this (`Atelier.fsMd * ph.ts`) |
| `wide` | bool | screen wider than 1.3:1 |
| `auth` | bool | password prompt is showing |
| `leaving` | bool | unlock animation is playing |
| `thumb` | bool | true when rendered as the tiny preview in Settings (no real input, don't start work) |
| `hasBattery` `batPct` `charging` | bool / int 0-100 / bool | battery |
| `weather` `temp` `condition` | string | e.g. "☀ +18°C Clear", "18°C", "Clear" |
| `notifs` | list | notifications (objects with `summary`, `body`, `appName`); may be empty. Respects the user's "show on lock" setting |
| `player` | Mpris player or null | the playing media player; `player.trackTitle`, `player.trackArtist`, `player.isPlaying` |
| `display` | string | display font family name ("Inter Display") |

- Login screen: lock styles from plugins are **not** available at the login screen (greetd). That screen uses the default style. Nothing to do.
- Never accept input yourself for passwords. The shell handles authentication. Do not attempt PAM, `Process` calls to read passwords, or similar.

### 5.5 launcherActions and 5.6 controlTiles
Pure manifest. No QML. `cmd` is a shell string run with `sh -c`; to open a built-in drawer use `overlay` instead (ids in section 11). For both, `cmd` XOR `overlay`.

## 6. Theme tokens: `Atelier` (from `import qs.config`)

Always use tokens so the plugin follows the user's theme (29 themes, light and dark). **Never hardcode colours** except in deliberate art.

Colours: `base mantle crust` (backgrounds, `crust` darkest), `surface0 surface1 surface2 overlay0 overlay1` (greys, rising), `text` (main ink), `subtext1 subtext` (secondary ink),
hues `red peach yellow green teal sky sapphire blue lavender mauve pink`, and `accent` (the user's accent; use for coloured text/icons/borders).
Fills: `accentFill` (an accent suitable as a **background**), `onFill` (text colour to put on `accentFill`).
Glass surfaces: `container` (subtle card fill, 6% ink), `containerHigh` (hover/selected, 11%), `outline` (hairline border), `hover`, `pressed`, `scrim`, `shadow`, `surface` (the shell's frosted panel colour).
Booleans: `isLight`, `mode` (`"light"`/`"dark"`).

Typography: `Atelier.font` ("SpaceMono Nerd Font Propo": glyphs, numbers, clocks), `Atelier.fontUi` ("Inter": labels, body), `Atelier.fontDisplay` ("Inter Display": big clocks/headings), `Atelier.fontEmoji`.
Sizes (px): `fsMicro 10`, `fsSm 11` (captions), `fsMd 12` (body), `fsLg 13` (buttons), `fsXl 15` (titles), `fsTitle 22`.
Radii: `radiusSm 10`, `radiusMd 14`, `radiusLg 18`.
Motion: `durFast` (hover/colour), `durMedium` (small moves), `durOpen`, `durClose`, `curveOpen`, `curveStandard`, `curveSmooth` (use with `easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard`). Durations are 0 in Battery-saver mode; always use them instead of fixed ms.
Misc: `Atelier.userName`, `Atelier.hour12(date)` (zero-padded hour per the user's clock setting), `Atelier.ampm(date)`, `Atelier.clock24`, `Atelier.barVertical`, `Atelier.barWidth`.
`Qt.alpha(color, a)` is the idiom for translucent versions: `Qt.alpha(Atelier.accent, 0.15)`.

The shell look: rounded, quiet, translucent surfaces; cards `Atelier.container` with radius `radiusMd`; one accent; small Inter text; Nerd-Font glyph icons; hover = `containerHigh`. Match it.

## 7. Shared components (`import qs.components`)

| type | properties / signals | use |
|---|---|---|
| `Chip` | `icon text tint interactive mono pad`, `clicked()` | tinted pill with 1px tinted border; set `interactive: true` to make it a button; `implicitHeight: 30` is the usual size |
| `IconButton` | `icon size glyphSize hoverTint active`, `clicked()` | round glyph button |
| `PrimaryButton` | `icon label size fill`, `clicked()` | the one filled action |
| `ToggleSwitch` | `on`, `toggled()` (does NOT flip itself: set `on` yourself), `implicitWidth/Height` (44×26) | on/off pill |
| `Segmented` | `model [{id, icon, label}] current segmentWidth`, `picked(id)` | tab bar |
| `ChoicePill` | `icon label on mono`, `clicked()` | selectable pill |
| `LevelBar` | `value 0..1`, `tint` | slim progress bar |
| `Panel` | default content | card surface with hairline border, radius 18 |
| `EmptyState` | `icon text` | quiet "nothing here" |
| `SmallCaps` | text | tiny spaced uppercase section label |

## 8. Settings controls (`import qs.modules.settings`, plus `qs.components`)

These stack inside a `SettingCard`. Each is a labelled row.

- `SettingCard { title; icon; tint }`: group container. Children go in as rows.
- `SettingRow { label; description }`: a row; put any control inside it (it is placed on the right). A label starting with two spaces renders as an indented sub-option.
- `SettingSwitch { label; description; checked; onToggled: (value) => … }`: `toggled(bool value)` passes the **new** value (the opposite of the current `checked`). The switch does not flip itself: `checked` must come from your stored state, which `Plugins.set` updates.
- `SettingChoice { label; description; options: [{id, label}]; value; onPicked: (id) => … }`
- `SettingSlider { label; description; from; to; value; step; decimals; suffix; zeroText; onMoved: (v) => … }`
- `SettingField { label; description; text; placeholder; fieldWidth; onCommitted: (text) => … }`: fires on Enter or focus loss.
- `SettingSwatches { label; description; value; allowColourful; onPicked: (id) => … }`: colour picker (theme roles or `#rrggbb`).
- `SettingTiles { label; description; options; value; preview: Component; tileHeight; onPicked }`

Typical persisted setting (the pattern to copy):

```qml
SettingSwitch {
    label: "Show seconds"
    description: "Adds seconds to the clock"
    checked: plugin ? Plugins.get(plugin.id, "seconds", false) : false
    onToggled: (v) => Plugins.set(plugin.id, "seconds", v)
}
```

## 9. Shell services (`import qs.services`) you may read

Read-only data is safest. Calling functions on services you don't own can change the user's system; do it only if the user asked for that behaviour.

| singleton | useful members |
|---|---|
| `Plugins` | the plugin API, section 10 |
| `Notifs` | `count`, `list` (newest first), `dnd` (bool, writable), `dismissGroup(n)` |
| `Weather` | `ok`, `line` ("☀ 18°C Clear"), `w` (`{temp, unit, desc, …}`), `refresh()` |
| `Battery` | `present`, `pct` (0-100, -1 if none), `onBattery`, `timeLeft()` |
| `SysState` | `wifiConnected`, `ssid`, `wifiSignal`, `wifiIcon`, `brightness` (0-1), `setBrightness(v)` |
| `SysMon` | CPU/RAM/etc. in `d` (only while `active`), `cpuHist`, `netHist`, `fmtBytes(b)`, `fmtRate(b)` |
| `Perf` | `mode` (`normal\|dev\|game\|saver\|showcase`), `game`, `saver`, `hideWidgets` |
| `Wallpaper` | `current` (path), `next()`, `prev()`, `random()`, `set(path)` |
| `Profile` | `login`, `realName`, `host`, `faceUrl` |
| `NightLight` | `active`, `toggle()` |
| `Recorder` | `recording`, `elapsedText` |
| `Timers` | timers/stopwatch/pomodoro state |
| `Updates` | `count`, `repo`, `aur`, `check()` |
| `Settings` (from `qs.config`) | the user's settings tree, e.g. `Settings.general.clock24`. Read only; do not write the user's settings from a plugin |

Also usable directly: `Quickshell.Services.Mpris` (`Mpris.players.values`), `Quickshell.Services.UPower`, `Quickshell.Services.Pipewire` (volume), `Quickshell.Io` (`Process`, `FileView`, `StdioCollector`).
Anything not listed here may exist but is not part of the plugin contract and can change.

## 10. The plugin API: `Plugins` (from `import qs.services`)

| call | does |
|---|---|
| `Plugins.get(pluginId, key, fallback)` | read a saved value. **Binding-friendly**: re-evaluates when any value changes. `pluginId` = `plugin.id` |
| `Plugins.set(pluginId, key, value)` | save a JSON-serialisable value (string, number, bool, array, object) to `~/.config/atelier/plugin-data.json` |
| `Plugins.run(["cmd", "arg", …])` | run a command, detached, no output captured (array, not a string; no shell) |
| `Plugins.notify(title, body)` | desktop notification (runs `notify-send`) |
| `Plugins.dir` | the plugins directory |

Saved values survive reloads, updates and reinstalls of the plugin. Use your own `key` names; they are namespaced by `pluginId`.
For commands whose output you need, use a `Process` from `Quickshell.Io` in your own QML:

```qml
import Quickshell.Io
Process {
    id: p
    command: ["sh", "-c", "uptime -p"]
    running: true
    stdout: StdioCollector { onStreamFinished: label.text = text.trim() }
}
```

## 11. Built-in drawer ids (for `overlay` in launcherActions / controlTiles)

`wallpaper wifi bluetooth games theme keyboard settings settings:modes clipboard emoji gifs sysmon timers ports colors calendar power notifications media screenshot screenshot-window screenshot-screen`

## 12. IPC (talking to the shell from commands)

The shell is controlled with `qs ipc call <target> <function> [args]`. A plugin can call these via `Plugins.run(["qs","ipc","call",…])` or in `cmd`.
Always available: `plugins` (`reload`, `list`, `enable <id>`, `disable <id>`, `install <source>`, `remove <id>`), `lock` (`lock`), `profiles` (`list`, `save <name>`, `apply <name>`, `active`), `settings` (`open <page>`).
`qs ipc show` prints every target and function the running shell has.
A plugin may declare its own handler in a QML file loaded by the shell (e.g. in a bar item):

```qml
import Quickshell
IpcHandler { target: "myplugin"; function ping(): void { /* … */ } }   // qs ipc call myplugin ping
```

Handler functions must declare their types (`: void`, `: string`, `id: string`). Use a unique `target` name prefixed with your plugin id.

## 13. Complete working templates

### 13.1 Bar item with a saved counter
`plugin.json`: `{ "name": "Counter", "barItems": [{ "id": "c", "file": "Bar.qml" }] }`

```qml
// Bar.qml
import QtQuick
import qs.config
import qs.services

Item {
    id: root
    property var plugin
    readonly property int count: plugin ? Plugins.get(plugin.id, "count", 0) : 0
    implicitWidth: Atelier.barVertical ? 30 : label.implicitWidth + 16
    implicitHeight: 30

    Rectangle {
        anchors.fill: parent; radius: Atelier.radiusSm
        color: ma.containsMouse ? Atelier.containerHigh : Atelier.container
        Behavior on color { ColorAnimation { duration: Atelier.durFast } }
    }
    Text {
        id: label
        anchors.centerIn: parent
        text: root.count
        color: Atelier.accent; font.family: Atelier.font; font.pixelSize: Atelier.fsMd; font.bold: true
    }
    MouseArea {
        id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: Plugins.set(root.plugin.id, "count", root.count + 1)
    }
}
```

### 13.2 Desktop widget with a live clock
```qml
// Widget.qml   ("desktopWidgets": [{ "id": "clock", "file": "Widget.qml", "hAlign": "left", "vAlign": "bottom", "margin": 48 }])
import QtQuick
import qs.config

Rectangle {
    implicitWidth: col.implicitWidth + 40; implicitHeight: col.implicitHeight + 28
    radius: Atelier.radiusLg
    color: Qt.alpha(Atelier.base, 0.55); border.width: 1; border.color: Atelier.outline
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: parent.now = new Date() }
    Column {
        id: col; anchors.centerIn: parent; spacing: 2
        Text { text: Atelier.hour12(now) + ":" + Qt.formatTime(now, "mm"); color: Atelier.text
               font.family: Atelier.fontDisplay; font.pixelSize: 56; font.weight: Font.Light }
        Text { text: Qt.formatDate(now, "dddd d MMMM"); color: Atelier.subtext
               font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd }
    }
}
```

### 13.3 Settings page
```qml
// Page.qml
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services
import qs.modules.settings

ColumnLayout {
    property var plugin
    spacing: 20
    SettingCard {
        title: "My plugin"; icon: "󰐱"
        SettingSwitch {
            label: "Enabled feature"; description: "What it does"
            checked: plugin ? Plugins.get(plugin.id, "on", true) : true
            onToggled: (v) => Plugins.set(plugin.id, "on", v)
        }
        SettingSlider {
            label: "Amount"; from: 0; to: 10; step: 1; value: plugin ? Plugins.get(plugin.id, "amount", 3) : 3
            onMoved: (v) => Plugins.set(plugin.id, "amount", v)
        }
        SettingField {
            label: "Name"; placeholder: "type here"; text: plugin ? Plugins.get(plugin.id, "name", "") : ""
            onCommitted: (t) => Plugins.set(plugin.id, "name", t)
        }
    }
}
```

### 13.4 Lock face
```qml
// LockFace.qml   ("lockStyles": [{ "id": "big", "name": "Big", "note": "Huge clock", "file": "LockFace.qml" }])
import QtQuick
import qs.config

Item {
    id: root
    property var ph
    opacity: ph && ph.auth ? 0.25 : 1                       // step back when the password prompt is up
    Behavior on opacity { NumberAnimation { duration: Atelier.durMedium } }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Atelier.crust }
            GradientStop { position: 1; color: Qt.tint(Atelier.crust, Qt.alpha(Atelier.accent, 0.25)) }
        }
    }
    Column {
        anchors.centerIn: parent; spacing: root.ph ? 10 * root.ph.u : 0
        Text { anchors.horizontalCenter: parent.horizontalCenter
               text: root.ph ? root.ph.hh + ":" + root.ph.mm : ""
               color: Atelier.text; font.family: Atelier.fontDisplay; font.weight: Font.Light
               font.pixelSize: root.ph ? 260 * root.ph.u : 10 }
        Text { anchors.horizontalCenter: parent.horizontalCenter
               text: root.ph ? Qt.formatDate(root.ph.now, "dddd d MMMM") : ""
               color: Atelier.accent; font.family: Atelier.fontUi
               font.pixelSize: root.ph ? 36 * root.ph.u : 10 }
    }
}
```

### 13.5 Manifest-only plugin (no QML)
```json
{
  "name": "Quick links",
  "launcherActions": [
    { "id": "gh", "title": "GitHub", "subtitle": "Open github.com", "glyph": "󰊤", "words": "git code repo", "cmd": "xdg-open https://github.com" }
  ],
  "controlTiles": [
    { "id": "term", "label": "Term", "icon": "󰆍", "cmd": "kitty" }
  ]
}
```

## 14. Do / don't, and the finish checklist

Do:
- Root of every QML file is an `Item`-derived type; declare `property var plugin` (and `ph` for lock faces).
- Guard `plugin` and `ph` for `undefined` at first.
- Use `Atelier` colour/size/duration tokens; use `ph.u` for lock-face sizes.
- Keep `plugin.json` valid JSON with only the documented keys.
- Keep work cheap: no polling faster than needed, stop timers when not visible, no per-frame JS loops.
- Use `Plugins.get/set` for persistence.

Don't:
- Don't hardcode colours, fonts or pixel text sizes (except deliberate art).
- Don't edit, read or depend on files outside your plugin folder, except `~` data the user explicitly asked for.
- Don't read passwords or handle authentication on lock faces. Don't spawn background daemons. Don't use network calls unless the user asked, and say so in `description`.
- Don't write the user's `Settings`, don't call `qs ipc call plugins …` from a plugin to change other plugins.
- Don't use `Window`/`PanelWindow` yourself for bar items/pages (the shell owns windows); desktop widgets get their window from the shell.
- Don't commit `.trusted` or `.disabled`.

Finish checklist (do all, in order):
1. `python3 -c 'import json; json.load(open("plugin.json"))'` succeeds; every `file` exists.
2. Copy/clone the folder into `~/.config/atelier/plugins/<id>/` (id: lowercase letters, digits, `.`, `_`, `-`).
3. `qs ipc call plugins reload` then `qs ipc call plugins list`. The plugin should be listed as `off <id>  (not approved)` with no `!` error.
4. Approve and run it: `qs ipc call plugins enable <id>`; `list` should now say `on  <id>`.
5. Look for errors: `qs log | grep -v DEBUG | tail -30`. Fix any `Type … unavailable`, `ReferenceError`, `TypeError`, or `… is not defined`. Also read Settings → Plugins: a row says "Problem: …" if a file failed to load.
6. Test each slot by eye: bar item appears (both orientations if you can), widget on the desktop, Settings page in the sidebar under "Plugins", lock card in Settings → Lock screen (use its Preview), launcher entry (open launcher, type the title), control tile.
7. After every edit to any file, the plugin loses approval: run `qs ipc call plugins enable <id>` again. If a changed QML file still shows the old version, restart Quickshell (changes to cached QML are not always picked up by a reload; this behaviour has not been verified).
8. Check both a dark and a light theme if you used custom colours.

## 15. Troubleshooting

| symptom | cause / fix |
|---|---|
| listed with `! bad entry in <slot>` | an entry is missing `id`/`file`/`title`/`label`, or a launcher action/tile lacks `cmd`/`overlay` |
| `! <file> not found` | wrong relative path, or path escapes the folder |
| `! plugin.json: …` | invalid JSON (trailing commas, comments) |
| listed `(not approved)` and nothing shows | press Approve, or `qs ipc call plugins enable <id>` |
| worked, then stopped after editing | files changed → approval hash mismatch → approve again |
| Settings shows "Problem: x: could not load f.qml" | QML error in that file; see `qs log` for the line |
| bar item invisible | root has no `implicitWidth/implicitHeight` |
| widget invisible | no implicit size, or the user hides widgets / is in Game or Battery-saver mode |
| lock face blank in preview | drawn with fixed pixels instead of `ph.u`, or `ph` used before it is set |
| `ReferenceError: Plugins is not defined` | missing `import qs.services` |
| `ReferenceError: Atelier is not defined` | missing `import qs.config` |
| `Type SettingCard unavailable` | missing `import qs.modules.settings` |

## 16. A ready prompt for another AI

> You are writing a plugin for Quickshell Atelier. Read the attached `plugin-authoring.md` fully first; it is the only spec. Produce a folder
> `<id>/` containing `plugin.json` and the QML files, following its rules and templates, using only the APIs it lists. Output every file in full
> as separate code blocks with its path. Then give the exact commands from section 14 for me to install and test it.
> What I want: *(describe the plugin here)*

---

Security reminder for users: **a plugin is code that runs inside your shell with your permissions.** Read every file before approving it.
