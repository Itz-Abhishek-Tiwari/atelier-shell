# Quickshell Atelier

Arch Linux + Hyprland (Lua config) desktop built around a custom **Quickshell** shell
(framed side bar with edge drawers, launcher, overview, control center, lock screen, notifications, OSD, settings app),
with one theme engine (`atelier-theme`) that recolours everything.

## Install (one command)

```bash
git clone https://github.com/<your-user>/quickshell-atelier.git ~/quickshell-atelier && ~/quickshell-atelier/install.sh
```

**This folder is the source of truth.** Copy it (or clone it) to a new Arch machine, run
`./install.sh`, reboot, and the machine matches this one: packages, drivers, system files,
every config, themes, the login screen. Keep the folder where it is afterwards: your configs are
**symlinks** into it, so editing either side edits the same file. When copying by hand, include
`hypr/wall/` (the wallpapers; too big for git).

Dotfiles only (no `sudo`, no packages, no `/etc` changes):

```bash
~/quickshell-atelier/install.sh --dotfiles-only
```

Preview without changing anything: `./install.sh --dry-run`. Skip the login screen: `--no-greeter`.

### What the installer does
1. Enables `[multilib]`, installs `yay` if needed, then `packages-pacman.txt` + `packages-aur.txt`,
   headers for every installed kernel (DKMS), and GPU drivers by detected hardware
   (`packages-gpu-nvidia.txt`, `-amd.txt`, `-intel.txt`).
2. Copies `system/etc/*` into `/etc` (iPhone-webcam `v4l2loopback` devices, `ntsync`, zram) and,
   with an NVIDIA GPU, `system/nvidia/etc/*` (DRM modeset + early KMS; rebuilds the initramfs).
   Replaced files are backed up to `~/.config/atelier-backups/system_<timestamp>/`.
3. Enables NetworkManager, bluetooth, power-profiles-daemon, sshd, timesyncd and ufw (deny incoming).
4. Installs the Colloid icons and unpacks the bundled GTK themes (`assets/gtk-themes.tar.xz` → `~/.themes`).
5. Backs up anything it would replace to `~/.config/atelier-backups/backup_<timestamp>/` (nothing is
   deleted), then symlinks the repo into place (safe to re-run).
6. Seeds files that apps rewrite themselves, once: `~/.config/atelier/*`, and `seed/config/*`
   (VS Code settings, Vesktop app settings, default apps, user dirs, Dolphin, Spicetify themes/apps).
   Installs launchers from `applications/`.
7. Builds the qt6ct plugin (`theming/build-qt6ct.sh`), installs `vscode/extensions.txt`, and applies
   the current Atelier theme so every app follows it.
8. Sets zsh as the default shell and installs the login screen (`install-greeter.sh --enable`).

Not covered (do these by hand): the Android SDK/emulator images, the LastWave AppImage
(`~/Applications/LastWave`), browser profiles and app logins.

## What gets linked

| Repo | Target |
|---|---|
| `quickshell/` | `~/.config/quickshell` |
| `hypr/` | `~/.config/hypr` |
| `kitty/`, `ghostty/`, `zed/`, `zellij/`, `fastfetch/`, `qt5ct/`, `qt6ct/`, `Kvantum/`, `gtk-3.0/`, `gtk-4.0/`, `btop/`, `cava/`, `swappy/`, `zathura/`, `environment.d/` | `~/.config/<same>` |
| `vesktop/settings/` | `~/.config/vesktop/settings` (Vencord plugins, quick CSS) |
| `nvim/` (NamiConfig, git submodule) | `~/.config/nvim` |
| `config-scripts/` | `~/.config/scripts` |
| `starship/starship.toml` | `~/.config/starship.toml` |
| `zsh/.zshrc`, `zsh/` | `~/.zshrc`, `~/.config/zsh` |
| `theming/atelier-theme`, `bin/prime-run`, `bin/audiotube`, `config-scripts/adguard-dns.sh` | `~/.local/bin/<name>` |

## Login screen (Quickshell instead of SDDM)

The `greeter/` folder is a Quickshell login screen built on **greetd**. It looks like the lock
screen (one glass panel over your blurred wallpaper: weather and sessions on the left, clock and
password in the middle, system info and users on the right) and uses your theme colours.

```bash
./install-greeter.sh --demo             # preview it fullscreen (password: demo, Esc closes), changes nothing
sudo ./install-greeter.sh               # install greetd + cage + greeter files (login manager unchanged)
sudo ./install-greeter.sh --enable      # switch the login manager from SDDM to greetd
sudo ./install-greeter.sh --refresh     # update the installed greeter after pulling changes
sudo ./install-greeter.sh --quiet-boot  # hide kernel/systemd text at boot (edits /etc/kernel/cmdline)
sudo ./install-greeter.sh --uninstall   # switch back to SDDM and remove the greeter
```

**Settings → Login screen** controls it after installing: layout (panel or minimal), greeting,
which cards show, wallpaper blur and dim, and *Follow theme & wallpaper* (your colours, wallpaper
and `~/.face` are copied over whenever they change). It also has Preview, Install/Update and
Quiet boot buttons. This works without root because the installer gives you
`/var/lib/atelier-greeter`, where the greeter reads its options and pictures.

Whatever the session prints at startup goes to `~/.local/state/atelier-session.log` instead of
the screen.

If a login ever fails: `Ctrl+Alt+F3`, log in, then
`sudo systemctl disable greetd && sudo systemctl enable --force sddm && sudo reboot`.

## Performance modes (Game / Programming)

The UI keeps the same look; the work behind it changes. Switch in the control center, in
*Settings → Behavior → Performance modes*, with keys, or over IPC.

| Mode | Key | What it does |
|---|---|---|
| **Normal** | | Your own look and settings. |
| **Programming** | `Super+Shift+D` | Opaque windows (crisp text, no blur work behind them), 1-pass blur, faster window animations, no dimming, performance power profile (balanced on battery), screen kept awake. Remembered across logins. |
| **Game** | `Super+Shift+G` | No blur / shadows / animations, opaque windows and shell glass, tearing allowed, performance power profile, Do Not Disturb, screen kept awake, desktop widgets not drawn. Not remembered across logins. |

**Game library** (`Super+G`): a fullscreen, console-style launcher for every installed game —
Steam (all libraries, including `/mnt/games`), Heroic (Epic, GOG, sideloaded), Lutris, `.desktop`
games and an optional hand-written `~/.config/atelier/games.json`
(`[{"title": "…", "command": "…", "cover": "/path.jpg"}]`). Cover art is downloaded once into
`~/.cache/atelier/game-art`. ←/→ or the wheel to choose, Enter to play, type to search.

*Game mode automatically* (Settings → Behavior, on by default): focusing a game (Steam, gamescope,
Lutris, Heroic, ...) switches to Game mode, and closing it switches back. Leaving any mode restores
your power profile, Do Not Disturb and caffeine exactly as they were.

```bash
qs ipc call mode set game|dev|normal      # also: cycle, toggleGame, toggleDev, get
```

## Daily use

| Action | How |
|---|---|
| Launcher | `SUPER + Space` |
| App grid (also the bar logo) | `SUPER + D` |
| Wallpaper: next / previous / random | `SUPER + ALT + →` / `←` / `I` |
| Control center | `SUPER + C` |
| Keyboard shortcuts (all keys, searchable; also Control center → Shortcuts) | `SUPER + Shift + /` |
| Scrolling layout: scroll / column width / move column / fit | `SUPER + Ctrl + ←→` · `SUPER + R` · `SUPER + [ ]` · `SUPER + .` |
| Settings app | `SUPER + ,` |
| Terminal / file manager (whatever Settings → Default apps picked) | `SUPER + T` / `SUPER + E` |
| Default apps: browser, files, editor, pictures, video, music, PDF, archives, terminal | Settings → Default apps (writes `~/.config/mimeapps.list`; `quickshell/scripts/default-apps.py list\|set`) |
| Power menu | `SUPER + Backspace` |
| Clipboard history | `SUPER + Shift + V` |
| On-screen keyboard | `SUPER + /` |
| Game library (fullscreen) | `SUPER + G` |
| Record screen (pick an area / stop) | `SUPER + Shift + R` (whole screen: `SUPER + Alt + R`, or `R` in the screenshot picker) |
| Night light | `SUPER + Shift + N` (schedule and warmth in Settings → Appearance) |
| Music drawer | hover the middle of the top screen edge, or `SUPER + M` |
| Reload shell | `qs kill; quickshell -d` |
| Reload Hyprland | automatic on save (avoid `hyprctl reload`: it makes the cursor hitch) |
| List / apply theme | `atelier-theme list` / `atelier-theme apply tokyo-night` |
| Light/dark toggle | `atelier-theme toggle-mode` |

Themes (17): Catppuccin (Mocha, Macchiato, Frappé, Latte), Dracula, Everforest, Gruvbox (dark, light), Kanagawa, Nord, One Dark, Ayu Mirage, Rosé Pine (+ Moon, Dawn), Solarized Dark, Tokyo Night.
Add your own as JSON in `theming/themes/` or `~/.config/atelier/themes/`.

## Hardware settings and profiles

The Settings app (`SUPER + ,`, a drawer from the right edge) configures the machine, not just the shell. Everything applies
live and is also written to `hypr/atelier-settings.lua`, so it holds at the next login.

| Page | What it does |
|---|---|
| **Displays** | Resolution, refresh rate, scale, rotation, position, mirroring and VRR for each connector. Every change asks *Keep these settings?* and reverts by itself after 15 s. |
| **Keyboard & mouse** | Layouts and how to switch between them, Caps Lock remap, key repeat, pointer speed and acceleration, natural scrolling, touchpad tap/click/drag options, focus follows mouse. |
| **Sound** | Default output and microphone, their volume and mute, and the volume of each app that is playing or recording. |
| **Shortcuts** | Record new keys for any built-in shortcut or turn it off (conflicts are flagged), and add your own key → command shortcuts. |
| **Profiles** | Save all settings plus the theme and wallpaper under a name, switch between profiles, export or import one as a file, and switch automatically when a display is plugged in (e.g. *Docked* when `HDMI-A-1` connects). |

From scripts: `qs ipc call profiles list|save <name>|apply <name>|active`, and
`qs ipc call settings open displays|input|sound|shortcuts|profiles`.

## Notes
- **Icons:** [Colloid](https://github.com/vinceliuice/Colloid-icon-theme) everywhere (GTK, Qt/qt6ct, KDE, the shell). `install.sh` fetches the variants your themes use, and `atelier-theme apply <id>` switches to the matching one (e.g. Catppuccin → `Colloid-Purple-Catppuccin-Dark`).
- **Wallpapers** live in `hypr/wall/` and are git-ignored (large). Drop your own images there.
- Machine-specific state (`~/.config/atelier/state.json`, etc.) is seeded from `atelier/` but never overwritten.
- `~/.local/bin` must be on your `PATH` for `atelier-theme`.
- Qt theming plugin: run `theming/build-qt6ct.sh` once if you want themed Qt apps.
