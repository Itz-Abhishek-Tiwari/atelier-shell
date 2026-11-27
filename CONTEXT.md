# Quickshell Atelier project context

Quickshell Atelier is an Arch Linux desktop configuration built around Hyprland and a custom Quickshell interface. The shell is written in Qt Quick/QML, Hyprland is configured in Lua, and Bash and Python scripts connect the UI to system utilities. The desktop shell, greetd login screen, and Atelier Music each have a separate QML entry point.

## Where to start

| Area | Entry point and ownership |
| --- | --- |
| Desktop shell | [quickshell/shell.qml](quickshell/shell.qml) composes per-display surfaces, the bar, drawers, lock screen, and other overlays. It also registers Quickshell IPC handlers. Feature UI lives in [quickshell/modules/](quickshell/modules/), reusable UI in [quickshell/components/](quickshell/components/), and system integrations in [quickshell/services/](quickshell/services/) and [quickshell/scripts/](quickshell/scripts/). |
| Settings | [Settings.qml](quickshell/config/Settings.qml) defines defaults and persists shell preferences. [quickshell/modules/settings/](quickshell/modules/settings/) contains the settings pages. |
| Compositor | [hypr/hyprland.lua](hypr/hyprland.lua) loads [hypr/conf/](hypr/conf/) in order. Start with the relevant module for monitors, input, bindings, rules, or startup. [atelier-mode.lua](hypr/atelier-mode.lua) applies performance modes. |
| Themes | [theming/atelier-theme](theming/atelier-theme) applies palette JSON from [theming/themes/](theming/themes/) and writes colors for the shell, compositor, and supported apps. [Atelier.qml](quickshell/config/Atelier.qml) exposes the shell's theme values. |
| Lock and login | [quickshell/modules/lock/](quickshell/modules/lock/) owns the desktop lock UI. [greeter/shell.qml](greeter/shell.qml) runs the login UI through greetd and reuses lock components through the greeter tree. [greeter-sync.sh](quickshell/scripts/greeter-sync.sh) syncs appearance data for the installed greeter. |
| Music | [apps/music/shell.qml](apps/music/shell.qml) is launched by [atelier-music](local/bin/atelier-music). Its QML client talks to the [ytmd.py](apps/music/backend/ytmd.py) daemon over a newline-delimited JSON Unix socket. The daemon controls mpv, manages playback and offline files, and exports MPRIS. The desktop shell also integrates through [AtelierMusic.qml](quickshell/services/AtelierMusic.qml). |
| Plugins | [Plugins.qml](quickshell/services/Plugins.qml) and [plugins-scan.py](quickshell/scripts/plugins-scan.py) handle discovery and loading. See [plugin authoring](docs/plugin-authoring.md) and [example plugins](examples/plugins/) for the manifest and extension points. |
| Installation | [install.sh](install.sh) ties together package manifests, user config links, and initial state. [setup/](setup/) holds package lists and seeds, [config/](config/) holds app dotfiles, [local/](local/) holds launchers and helpers, and [system/](system/) holds system-level files and boot tooling. |

## Configuration and runtime state

- The installer links the desktop shell and Hyprland trees into `~/.config/quickshell` and `~/.config/hypr`. On an installed machine, editing a linked file can affect the live session, and live settings can update files in the checkout.
- Shell preferences persist in `~/.config/atelier/settings.json`. Settings also writes compositor values to `~/.config/hypr/atelier-settings.lua`, which Hyprland reads at startup. Check both paths when changing a preference that applies to the compositor.
- App-managed files under `setup/seed/config/` are copied only when missing. Seed changes affect initial setup. The installed greeter has its own deployed files and reads synchronized appearance data from `/var/lib/atelier-greeter`.
- Local wallpapers under `hypr/wall/` may be absent from a fresh clone.

## Development and checks

- Follow a desktop feature from its keybinding in [keybinds.lua](hypr/conf/keybinds.lua) or its IPC handler in [shell.qml](quickshell/shell.qml) to the feature QML and any service or script it calls.
- Run `bash setup/check.sh --repo` for repository checks. It checks tracked Bash, Python, and Lua files, validates the example plugin scanner output, checks symlinks, and attempts `git fetch`. Lua checks require `luac`. Run `bash setup/check.sh` in an active desktop session for the additional runtime checks.
- Use `./install.sh --dry-run` to preview the installer and `greeter/install.sh --demo` to preview the login UI. See the [README](README.md) for setup, shortcuts, and greeter deployment commands.
