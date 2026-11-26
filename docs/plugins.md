# Plugins

Writing one with an AI? Hand it [plugin-authoring.md](plugin-authoring.md): the complete, self-contained reference (every slot, token, component, API, templates, checklist).

Add your own bits to the shell without editing it. A plugin is a folder in `~/.config/atelier/plugins/<id>/`
with a `plugin.json` and the files it points at. See `examples/plugins/hello/` (one of everything).

**Install:** Settings → Plugins → *Install a plugin* (git URL, `.zip` link, or a folder), or copy a folder in and press
Reload (`qs ipc call plugins reload`). From a script: `qs ipc call plugins install <source>`.
**Approve:** a new plugin is off until you press *Approve* (Review opens its folder). The shell remembers a hash of the
plugin's files in `.trusted`; if any file changes later, the plugin stops and asks again.
**Switch off / remove:** Settings → Plugins, or `qs ipc call plugins disable|enable|remove <id>` (`list` shows all).
A plugin with an error is listed with the reason and not loaded.

```
~/.config/atelier/plugins/<id>/
    plugin.json
    LockFace.qml  Widget.qml  Page.qml  BarItem.qml …
```

## plugin.json

`name`, `version`, `author`, `description` are shown in Settings. Every list below is optional; `file` is relative to the plugin folder.

| key               | each entry                                              | what you get |
|-------------------|---------------------------------------------------------|--------------|
| `lockStyles`      | `id, name, note, file`                                  | a card in Settings → Lock screen and a full-screen face. The root Item gets a `ph` property (the lock: `ph.hh`, `ph.mm`, `ph.auth`, `ph.u` …, as in the built-in faces) |
| `desktopWidgets`  | `id, file, hAlign, vAlign, margin`                      | an Item on the wallpaper (behind windows), sized by its implicit size. `hAlign`/`vAlign`/`margin` are only the default: the user can move it in Settings → Plugins → Desktop widgets |
| `settingsPages`   | `id, label, icon, sub, file`                            | a page in Settings under "Plugins"; any `Setting*` control works |
| `barItems`        | `id, file`                                              | an Item in the bar, just before the power button. Set `implicitWidth/Height`; read `Atelier.barVertical` for a side bar |
| `launcherActions` | `id, title, subtitle, glyph, words, cmd` or `overlay`   | a row in the launcher (search it by `title` or `words`). `cmd` runs through `sh -c`; `overlay` opens a shell drawer |
| `controlTiles`    | `id, label, icon, cmd` or `overlay`                     | a tile in the control centre's shortcut row |

## What your QML can use

Files can `import qs.config`, `qs.services`, `qs.components` and read the theme tokens (`Atelier.accent` …), so they follow the desktop theme.
Declare `property var plugin` on the root Item and the shell fills it with `{id, name, dir}`. From `qs.services`:

| call | does |
|------|------|
| `Plugins.get(plugin.id, "key", fallback)` / `Plugins.set(plugin.id, "key", value)` | your own saved values (`~/.config/atelier/plugin-data.json`); they survive updating the plugin, and bindings update when they change |
| `Plugins.run(["cmd", "arg"])` | run a command, detached |
| `Plugins.notify("title", "body")` | a desktop notification |

A plugin can also declare its own `IpcHandler { target: "myplugin" … }` for `qs ipc call`.

## Limits and safety

- **Plugins are code that runs inside your shell, with your permissions. Only install ones you trust, and read them first.**
- A QML file that fails to load is skipped and the reason is shown on its row in Settings → Plugins.
- Lock styles are not available on the login screen (it cannot read your home folder); it uses the Atelier style instead.
- Settings → Plugins looks for new or removed folders each time you open it; elsewhere use Reload.
