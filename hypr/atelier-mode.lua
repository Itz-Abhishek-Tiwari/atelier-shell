-- Atelier performance modes, applied live (no reload, so no cursor hitch):
--
--   hyprctl eval 'dofile(os.getenv("HOME") .. "/.config/hypr/atelier-mode.lua")("game")'
--
--   normal  your own look from Settings (hypr/atelier-settings.lua)
--   dev     programming: opaque windows (crisp text, no blur work behind them), 1-pass blur,
--           faster window animations, no dimming
--   game    maximum performance: no blur, no shadows, no animations, opaque windows,
--           tearing allowed for fullscreen games
--
-- The shell's own part of each mode (shadows, widgets, DND, power profile) lives in
-- quickshell/services/Perf.qml, which calls this file.
--
-- This file is also the single home of two things hyprland.lua uses at load time:
--   M.settings()    atelier-settings.lua merged over the defaults
--   M.saved_mode()  the mode the shell last set (so a config reload keeps it)

local HOME = os.getenv("HOME")
local M = {}

-- Defaults for anything atelier-settings.lua (written by the Settings app) doesn't set.
M.defaults = {
    gaps_in = 5, gaps_out = 10, rounding = 14, active_opacity = 0.95, inactive_opacity = 0.90,
    blur = true, blur_passes = 2, shadow = true, animations = true,
    layout = "dwindle", dwindle_preserve_split = true, dwindle_smart_split = false,
    master_orientation = "left", master_mfact = 0.55, master_new_on_top = false,
    scroll_column_width = 0.5,
    shell_glass = 0.92,          -- Quickshell surface opacity (Settings → Appearance → Glass)
    reserved = 0,                -- screen edges under the shell frame (written by the shell once it runs)
    -- Settings → Keyboard & mouse (conf/input.lua): Hyprland `input` options, as hl.config takes them
    input = {
        kb_layout = "us", kb_variant = "", kb_options = "",
        repeat_rate = 25, repeat_delay = 600, numlock_by_default = false,
        sensitivity = 0, accel_profile = "adaptive", natural_scroll = false, left_handed = false,
        follow_mouse = 1, scroll_factor = 1.0,
        touchpad = {
            natural_scroll = true, scroll_factor = 0.45, tap_to_click = true,
            clickfinger_behavior = true, disable_while_typing = true, drag_lock = 0,
        },
    },
    mouse_curve = true,          -- macOS-style acceleration curve on the 2.4 GHz mouse
    -- Settings → Modes: what Programming and Game mode change (missing keys: these)
    modes = {
        dev  = { opaque = true, dim = false, blur = "light", shadows = true, animations = true, anim_speed = 0.6 },
        game = { opaque = true, blur = "off", shadows = false, animations = false, tearing = true },
    },
    -- Settings → Displays (conf/monitors.lua): one hl.monitor spec per output
    monitors = {
        { output = "HDMI-A-1", mode = "1366x768@59.79Hz", position = "auto", scale = "auto", transform = 3 },
    },
    -- Settings → Shortcuts (conf/keybinds.lua): new keys for built-in shortcuts ("" = off) + your own
    binds = { overrides = {}, custom = {} },
}

function M.settings()
    local ok, t = pcall(dofile, HOME .. "/.config/hypr/atelier-settings.lua")
    if not ok or type(t) ~= "table" then t = {} end
    for k, v in pairs(M.defaults) do
        if t[k] == nil then t[k] = v end
    end
    return t
end

-- The shell persists its mode to ~/.config/atelier/mode (see Perf.qml). Dev mode is kept
-- across logins; Game mode only within the Hyprland session that set it.
function M.saved_mode()
    local f = io.open(HOME .. "/.config/atelier/mode", "r")
    if not f then return "normal" end
    local raw = f:read("a") or ""
    f:close()
    local mode = raw:match('"mode"%s*:%s*"(%a+)"')
    if mode == "dev" then return "dev" end
    if mode == "game" and raw:match('"session"%s*:%s*"([^"]*)"') == os.getenv("HYPRLAND_INSTANCE_SIGNATURE") then
        return "game"
    end
    return "normal"
end

-- The one animation set: smooth near-critically-damped springs for windows, long ease-out
-- beziers for slides, quiet ease-in for things leaving. Curves and springs are defined in
-- conf/animations.lua. `k` scales every duration: Hyprland "speed" is in 100 ms units, so a
-- smaller number is faster.
local springs = { glide = true, swift = true }
function M.animations(k)
    local function a(leaf, speed, curve, style)
        local spec = { leaf = leaf, enabled = true, speed = speed * k, style = style }
        if springs[curve] then spec.spring = curve else spec.bezier = curve end
        hl.animation(spec)
    end
    a("windowsIn",        4.2, "glide",        "popin 92%")
    a("windowsOut",       1.8, "easeInSoft",   "popin 94%")
    a("windowsMove",      3.8, "swift")
    a("fadeIn",           2.2, "almostLinear")
    a("fadeOut",          1.6, "almostLinear")
    a("fadeSwitch",       3.0, "quick")
    a("fadeShadow",       3.0, "quick")
    a("fadeDim",          3.5, "almostLinear")
    a("border",           4.0, "easeOutQuint")
    a("layersIn",         3.2, "easeOutQuint", "fade")
    a("layersOut",        1.6, "easeInSoft",   "fade")
    a("fadeLayersIn",     2.0, "almostLinear")
    a("fadeLayersOut",    1.4, "almostLinear")
    a("workspaces",       4.2, "easeOutExpo",  "slidefade 12%")
    a("specialWorkspace", 4.0, "easeOutExpo",  "slidefadevert 12%")
    a("zoomFactor",       5.0, "easeOutQuint")
    hl.animation({ leaf = "borderangle", enabled = false })   -- no looping gradient
end

-- one mode's settings from Settings → Modes, filled in from the defaults
local function mode_opts(t, name)
    local o, d = (t.modes or {})[name] or {}, M.defaults.modes[name]
    local r = {}
    for k, v in pairs(d) do r[k] = v end
    for k, v in pairs(o) do r[k] = v end
    return r
end

function M.apply(mode)
    local t = M.settings()
    atelier_mode = mode      -- global: Settings' live apply re-applies the current mode after it
    if mode == "game" or mode == "dev" then
        local o = mode_opts(t, mode)
        local blur = { enabled = o.blur ~= "off" and t.blur }
        if o.blur == "light" then blur.passes = 1 elseif o.blur == "normal" then blur.passes = t.blur_passes end
        hl.config({
            general    = { allow_tearing = mode == "game" and o.tearing == true },
            decoration = {
                active_opacity   = o.opaque and 1.0 or t.active_opacity,
                inactive_opacity = o.opaque and 1.0 or t.inactive_opacity,
                dim_inactive     = o.dim == true,
                blur = blur, shadow = { enabled = o.shadows and t.shadow },
            },
            animations = { enabled = o.animations and t.animations },
        })
        if o.animations and t.animations then M.animations(mode == "dev" and (o.anim_speed or 0.6) or 1) end
    else
        hl.config({
            general    = { allow_tearing = false },
            decoration = {
                active_opacity = t.active_opacity, inactive_opacity = t.inactive_opacity, dim_inactive = true,
                blur = { enabled = t.blur, passes = t.blur_passes }, shadow = { enabled = t.shadow },
            },
            animations = { enabled = t.animations },
        })
        M.animations(1)
    end
end

-- Settings → Keyboard & mouse. Used by conf/input.lua at load and by the shell live:
--   hyprctl eval 'dofile(os.getenv("HOME") .. "/.config/hypr/atelier-mode.lua").apply_input()'
M.MOUSE = "mosart-semi.-2.4g-keyboard-mouse-1"     -- the 2.4 GHz mouse with the macOS-style curve
M.MOUSE_CURVE = "custom 0.25 0.0 0.18 0.417 0.686 0.975 1.278 1.59 1.909 2.233 2.562 2.893 3.227"
function M.apply_input(t)
    t = t or M.settings()
    local input = t.input or M.defaults.input
    hl.config({ input = input })
    hl.device({
        name          = M.MOUSE,
        accel_profile = t.mouse_curve ~= false and M.MOUSE_CURVE or (input.accel_profile or "adaptive"),
    })
end

-- Settings → Displays. `forget` = outputs that lost their saved settings (back to preferred/auto).
function M.apply_monitors(t, forget)
    t = t or M.settings()
    local reserved = t.reserved or 0
    for _, name in ipairs(forget or {}) do
        pcall(hl.monitor, { output = name, mode = "preferred", position = "auto", scale = 1, reserved = reserved })
    end
    for _, m in ipairs(t.monitors or {}) do
        if type(m) == "table" and type(m.output) == "string" and m.output ~= "" then
            local spec = { reserved = reserved }
            for k, v in pairs(m) do spec[k] = v end
            local ok, err = pcall(hl.monitor, spec)
            if not ok then
                hl.notification.create({ text = "Display " .. m.output .. ": " .. tostring(err), timeout = 8000 })
            end
        end
    end
end

-- Callable, so `dofile(".../atelier-mode.lua")("game")` keeps working for Perf.qml.
return setmetatable(M, { __call = function(_, mode) return M.apply(mode) end })
