-- Shared values and helpers for the conf/ modules (require("conf.lib")).
local M = {}

M.HOME = os.getenv("HOME")
M.CONF = M.HOME .. "/.config/hypr"

-- Load a Lua file that returns a table; nil if it is missing or broken (never fatal).
function M.load_table(path)
    local ok, t = pcall(dofile, path)
    if ok and type(t) == "table" then return t end
end

-- {"a", "b"} -> "^(a|b)$": one regex per rule instead of one rule per app
function M.any_of(list) return "^(" .. table.concat(list, "|") .. ")$" end

-- Performance modes + Settings-app values (+ their defaults): ../atelier-mode.lua
M.mode = M.load_table(M.CONF .. "/atelier-mode.lua")
M.win  = M.mode and M.mode.settings() or {}

-- Colours, written by `atelier-theme apply <id>`: ../theme.lua
M.theme = M.load_table(M.CONF .. "/theme.lua") or {   -- fallback: Catppuccin Mocha
    active_border     = { "rgba(cba6f7ee)", "rgba(89b4faee)" },
    inactive_border   = "rgba(45475a66)",
    group_active      = { "rgba(cba6f7ee)", "rgba(89b4faee)" },
    group_inactive    = "rgba(45475a80)",
    groupbar_active   = "rgba(cba6f7cc)",
    groupbar_inactive = "rgba(45475a99)",
    groupbar_text     = "rgba(cdd6f4ff)",
    shadow            = 0x6611111b,
    shadow_inactive   = 0x3311111b,
}

return M
