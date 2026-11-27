-- Monitors
--
-- Per-output settings come from Settings → Displays (atelier-settings.lua `monitors` list,
-- defaults in atelier-mode.lua, which also applies them: M.apply_monitors). The shell reloads
-- Hyprland after saving display changes, so this file applies them at login and on every reload.
local lib = require("conf.lib")

-- Space the Quickshell frame covers on each screen edge (bar + border), written by the Settings
-- app into atelier-settings.lua. Reserving it here replaces exclusive-zone layer windows.
local reserved = lib.win.reserved or 0

-- Default: any monitor at its preferred mode
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
    reserved = reserved,
})

-- Outputs configured in Settings → Displays
if lib.mode then lib.mode.apply_monitors(lib.win) end
