-- Environment variables
local HOME = require("conf.lib").HOME

-- Wayland first, with X11 fallbacks so apps/games without a Wayland backend still start
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("SDL_VIDEODRIVER", "wayland,x11")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")

-- GPU: the laptop panel is driven by the AMD iGPU, so apps render there too
-- (forcing NVIDIA PRIME offload made every frame cross the PCIe bus → stutter,
-- extra latency, and a dGPU that never sleeps). Use `prime-run <app>` for games/3D.
hl.env("LIBVA_DRIVER_NAME", "radeonsi")

-- Cursor
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "macOS")

-- Qt/KDE apps: qt6ct platform theme, built into ~/.local (theming/build-qt6ct.sh). The palette comes from
-- the active theme (atelier-theme) and changes live. Qt just ignores it if the plugin is missing.
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_PLUGIN_PATH", HOME .. "/.local/lib/qt6/plugins")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
-- Dolphin/KDE apps outside Plasma: find the app menu (archlinux-xdg-menu) for "Open With" and service menus
hl.env("XDG_MENU_PREFIX", "arch-")
