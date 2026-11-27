-- Atelier performance modes, applied live (no reload, so no cursor hitch):
--
--   hyprctl eval 'dofile(os.getenv("HOME") .. "/.config/hypr/atelier-mode.lua")("game")'
--
--   normal  your own look from Settings (hypr/atelier-settings.lua)
--   dev     programming: opaque windows (crisp text, no blur work behind them), 1-pass blur,
--           shorter, low-travel window animations (M.motion.dev), no dimming
--   game    maximum performance: no blur, no shadows, no animations, opaque windows,
--           tearing allowed for fullscreen games
--   saver   battery saver: the least the compositor can draw: no blur, no shadows, NO
--           animations at all, no dimming, opaque windows (nothing is blended). Kept across logins.
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
    -- blur look (Settings → Appearance → Windows)
    blur_size = 9, blur_vibrancy = 0.17, blur_noise = 0.012, blur_contrast = 0.95, blur_brightness = 0.90,
    blur_xray = true,            -- true: windows blur only the wallpaper (cheap); false: whatever is behind them
    blur_popups = true,          -- menus and tooltips blur too
    dim_inactive = true, dim_strength = 0.06,
    solid_apps = true,           -- video, image viewers, games, creative apps stay opaque (rules.lua)
    solid_fullscreen = true,     -- fullscreen windows stay opaque
    shell_blur = true,           -- blur behind the shell's bar and drawers (rules.lua)
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
    shell_layout = "atelier",    -- Settings → Bar → Layout: "classic" = Traditional (conf/traditional.lua)
    titlebar_buttons = "right",  -- Traditional title bars: left | right
    -- Settings → Keyboard & mouse → Touchpad gestures (registered in conf/input.lua)
    gestures = {
        workspace = true, workspace_fingers = 3,   -- swipe sideways: previous / next workspace
        invert = false, create_new = true, distance = 300,
        overview = true,                           -- the other finger count, up opens / down closes
        launcher = true, pinch_fingers = 4,        -- pinch in opens, pinch out closes
    },
    -- Settings → Modes: what Programming and Game mode change (missing keys: these)
    modes = {
        dev  = { opaque = true, dim = false, blur = "light", shadows = true, animations = true, anim_speed = 0.6 },
        game = { opaque = true, blur = "off", shadows = false, animations = false, tearing = true },
        saver = { opaque = true, dim = false, blur = "off", shadows = false },
    },
    -- Settings → Displays (conf/monitors.lua): one hl.monitor spec per output
    monitors = {},
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

-- The shell persists its mode to ~/.config/atelier/mode (see Perf.qml). Dev and Saver mode are
-- kept across logins; Game mode only within the Hyprland session that set it.
function M.saved_mode()
    local f = io.open(HOME .. "/.config/atelier/mode", "r")
    if not f then return "normal" end
    local raw = f:read("a") or ""
    f:close()
    local mode = raw:match('"mode"%s*:%s*"(%a+)"')
    if mode == "dev" or mode == "saver" then return mode end
    if mode == "game" and raw:match('"session"%s*:%s*"([^"]*)"') == os.getenv("HYPRLAND_INSTANCE_SIGNATURE") then
        return mode
    end
    return "normal"
end

-- Motion, one profile per mode. Curves and springs are defined in conf/animations.lua.
-- Each leaf is { speed, curve, style }; Hyprland "speed" is in 100 ms units (smaller = faster),
-- `false` turns that leaf off. Springs (glide, swift) are near-critically damped: no wobble.
--
--   normal  Caelestia / Material 3: windows decelerate in (emphasizedDecel), accelerate out
--           (emphasizedAccel), moves, fades and workspaces on the standard curve
--   dev     crisp: the same timing scaled by Settings → Modes → "Animation length", but with
--           less travel (windows barely scale, workspaces slide 5 %) and no soft tails, so
--           motion never pulls your eye off the code
--   game    still: only used when Game mode keeps animations on. Fades only, nothing moves or
--           scales (a moving window makes the compositor redraw the whole game every frame)
local springs = { glide = true, swift = true }
M.motion = {
    -- normal: Caelestia's Hyprland motion (Material 3), matched to the shell's Anim tokens.
    -- Layers fade rather than slide: the shell re-maps its own frame / drawer surfaces (glass
    -- changes), and a slide would make the bar visibly move on those re-maps.
    normal = {
        windowsIn        = { 5.0, "emphasizedDecel", "popin 92%" },
        windowsOut       = { 3.0, "emphasizedAccel", "popin 94%" },
        windowsMove      = { 6.0, "standard" },
        fadeIn           = { 6.0, "standard" },
        fadeOut          = { 6.0, "standard" },
        fadeSwitch       = { 6.0, "standard" },
        fadeShadow       = { 6.0, "standard" },
        fadeDim          = { 6.0, "standard" },
        border           = { 6.0, "standard" },
        layersIn         = { 5.0, "emphasizedDecel", "fade" },
        layersOut        = { 4.0, "emphasizedAccel", "fade" },
        fadeLayersIn     = { 5.0, "standard" },
        fadeLayersOut    = { 4.0, "standard" },
        workspaces       = { 5.0, "standard", "slide" },
        specialWorkspace = { 4.0, "specialWorkSwitch", "slidefadevert 15%" },
        zoomFactor       = { 5.0, "emphasizedDecel" },
    },
    dev = {
        windowsIn        = { 3.0, "swift",        "popin 97%" },
        windowsOut       = { 1.4, "easeInSoft",   "popin 98%" },
        windowsMove      = { 3.2, "swift" },
        fadeIn           = { 1.8, "almostLinear" },
        fadeOut          = { 1.2, "almostLinear" },
        fadeSwitch       = { 2.2, "quick" },
        fadeShadow       = { 2.2, "quick" },
        fadeDim          = { 2.5, "almostLinear" },
        border           = { 2.5, "quick" },
        layersIn         = { 2.4, "easeOutQuint", "fade" },
        layersOut        = { 1.2, "easeInSoft",   "fade" },
        fadeLayersIn     = { 1.6, "almostLinear" },
        fadeLayersOut    = { 1.0, "almostLinear" },
        workspaces       = { 3.4, "easeOutQuint", "slidefade 5%" },
        specialWorkspace = { 3.2, "easeOutQuint", "slidefadevert 5%" },
        zoomFactor       = { 3.0, "easeOutQuint" },
    },
    game = {
        windowsIn        = { 1.6, "almostLinear", "popin 100%" },
        windowsOut       = { 1.0, "almostLinear", "popin 100%" },
        windowsMove      = false,
        fadeIn           = { 1.6, "almostLinear" },
        fadeOut          = { 1.0, "almostLinear" },
        fadeSwitch       = false,
        fadeShadow       = false,
        fadeDim          = false,
        border           = false,
        layersIn         = { 1.4, "almostLinear", "fade" },
        layersOut        = { 1.0, "almostLinear", "fade" },
        fadeLayersIn     = { 1.4, "almostLinear" },
        fadeLayersOut    = { 1.0, "almostLinear" },
        workspaces       = { 1.6, "almostLinear", "fade" },
        specialWorkspace = { 1.6, "almostLinear", "fade" },
        zoomFactor       = false,
    },
}

-- Apply a mode's motion profile; `k` scales every duration (Programming mode's slider).
function M.animations(mode, k)
    if type(mode) == "number" then mode, k = "normal", mode end   -- old call style: M.animations(k)
    local set = M.motion[mode] or M.motion.normal
    k = k or 1
    for leaf, a in pairs(set) do
        if a == false then
            hl.animation({ leaf = leaf, enabled = false })
        else
            local spec = { leaf = leaf, enabled = true, speed = a[1] * k, style = a[3] }
            if springs[a[2]] then spec.spring = a[2] else spec.bezier = a[2] end
            hl.animation(spec)
        end
    end
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
    if mode == "game" or mode == "dev" or mode == "saver" then
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
            animations = { enabled = mode ~= "saver" and o.animations and t.animations },   -- Saver never animates
        })
        if mode ~= "saver" and o.animations and t.animations then M.animations(mode, mode == "dev" and (o.anim_speed or 0.6) or 1) end
    else
        hl.config({
            general    = { allow_tearing = false },
            decoration = {
                active_opacity = t.active_opacity, inactive_opacity = t.inactive_opacity, dim_inactive = t.dim_inactive,
                blur = { enabled = t.blur, passes = t.blur_passes }, shadow = { enabled = t.shadow },
            },
            animations = { enabled = t.animations },
        })
        M.animations("normal", 1)
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
    local g = t.gestures or M.defaults.gestures
    hl.config({ gestures = {
        workspace_swipe_invert     = g.invert == true,
        workspace_swipe_create_new = g.create_new ~= false,
        workspace_swipe_distance   = math.floor(tonumber(g.distance) or 300),
    } })
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
