--------------------------------------------------------------------------------
-- 🌊 NamiConfig - Hyprland Lua Configuration (Hyprland 0.57+)
--
-- This file only loads the pieces, in order. Edit the piece you want:
--
--   conf/monitors.lua     monitors
--   conf/env.lua          environment variables
--   conf/autostart.lua    programs started at login
--   conf/appearance.lua   borders, rounding, shadows, THE one opacity + blur for all apps
--   conf/layouts.lua      dwindle / master / scrolling
--   conf/input.lua        keyboard, touchpad, mice, gestures
--   conf/system.lua       rendering, cursor, VRR, XWayland, misc
--   conf/animations.lua   curves and springs (smooth, no bounce)
--   conf/keybinds.lua     keybindings
--   conf/rules.lua        window and layer rules
--   conf/lib.lua          shared helpers (settings, theme colours)
--
-- Generated / shared files (keep these names, other tools use them):
--   atelier-settings.lua  written by the Settings app (gaps, rounding, opacity, blur, layout)
--   theme.lua             written by `atelier-theme apply <id>` (border/shadow colours)
--   atelier-mode.lua      Normal / Dev / Game modes + the animation set (used by the shell)
--------------------------------------------------------------------------------

local modules = {
    "monitors", "env", "autostart", "appearance", "layouts",
    "input", "system", "animations", "keybinds", "rules",
}

-- A broken module is reported and skipped; the rest still load.
for _, name in ipairs(modules) do
    local ok, err = pcall(require, "conf." .. name)
    if not ok then
        hl.notification.create({ text = "hypr conf/" .. name .. ".lua: " .. tostring(err), timeout = 10000 })
    end
end

--------------------------------------------------------------------------------
-- Performance mode (last, so it wins): applies the animation set, and re-applies Game/Dev
-- mode if the shell has one on, so a config reload doesn't drop you back to Normal.
--------------------------------------------------------------------------------
local mode = require("conf.lib").mode
if mode then
    local ok, err = pcall(function()
        mode.animations(1)                -- always defined, even if a mode then turns them off
        mode.apply(mode.saved_mode())
    end)
    if not ok then
        hl.notification.create({ text = "atelier-mode.lua: " .. tostring(err), timeout = 8000 })
    end
end
