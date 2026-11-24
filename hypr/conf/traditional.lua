-- Traditional layout (Settings → Bar → Layout): floating windows with title bars, like a classic
-- desktop. The Atelier layout keeps tiling. Applied at config load and live by the Settings app
-- (`hyprctl eval atelier_apply_traditional(t)`), never by a config reload.
--   · every window floats, centred (one window rule, switched on/off)
--   · windows that were tiled when you switched get floated; switching back tiles exactly those
--     and the ones opened meanwhile (picture-in-picture keeps floating). They're marked with the
--     window tag "atelier-floated": tags live on the windows, so they survive config reloads
--   · title bars from the hyprbars plugin (AUR: hyprland-plugin-hyprbars): drag a window by its
--     bar, double-click to maximise, buttons close · maximise · minimise
--   · minimise (the bar's button, or an app's own) parks the window on the hidden named
--     workspace "minimized" (a special workspace would pop up on screen); the dock brings it back
--   · maximise fills the space between the bar and the dock exactly (no gaps); again = restore
local lib = require("conf.lib")

local LIB    = "/usr/lib/libhyprbars.so"
local MIN_WS = "name:minimized"
local BAR_H  = 28                     -- title bar height
local GRAB   = 15                     -- general:extend_border_grab_area outside Traditional

local TAG = "atelier-floated"
atelier_trad = { on = false, buttons = false }   -- buttons: hyprbars drops them on every config reload

local float_rule = hl.window_rule({
    name   = "traditional-float",
    match  = { class = ".*" },
    float  = true,
    center = true,
})

local function addr(w)
    local a = tostring(w.address or "")
    return a:find("^0x") and a or ("0x" .. a)
end
local function keeps_floating(w)   -- these float in the Atelier layout too
    local title = w.title or ""
    return title == "Picture-in-Picture" or title == "Picture in picture"
end
local function present()
    local f = io.open(LIB, "r")
    if f then f:close() return true end
    return false
end

-- ── title bars ───────────────────────────────────────────────────────────────
local function titlebars(want, t)
    -- Hyprland's resize-on-border band is measured from the window's content, so with a title
    -- bar it covers the bar's lower half and a click on a button starts a resize instead. Keep the
    -- band to the border itself while bars show (hyprbars resizes from the edge above the bar).
    hl.config({ general = { extend_border_grab_area = want and 2 or GRAB } })

    if not present() then return end
    if not want then
        -- leaving Traditional: unload the plugin entirely, so the Atelier layout has no trace of it
        if hl.plugin and hl.plugin.hyprbars then hl.exec_cmd("hyprctl plugin unload " .. LIB) end
        return
    end
    if not (hl.plugin and hl.plugin.hyprbars) then
        if not want then return end
        -- hl.plugin.load only works while the config is read: load it from outside, then come back
        hl.exec_cmd("sh -c 'hyprctl plugin load " .. LIB .. " >/dev/null && hyprctl eval \"atelier_apply_traditional()\" >/dev/null'")
        return
    end

    local tb = lib.theme.titlebar or {}
    hl.config({ plugin = { hyprbars = {
        enabled                    = want,
        bar_height                 = BAR_H,
        -- the theme surface; the bar is part of its window, so it takes the window's opacity and
        -- blur from the active mode (glass in Normal, solid in Programming / Game)
        bar_color                  = tb.bg or "rgba(1e1e2eff)",
        ["col.text"]               = tb.text or "rgba(a6adc8ff)",
        bar_text_font              = "Inter",
        bar_text_size              = 10,
        bar_text_weight            = "medium",
        bar_text_align             = "center",
        bar_buttons_alignment      = (t.titlebar_buttons == "left") and "left" or "right",
        bar_padding                = 11,
        bar_button_padding         = 7,
        bar_blur                   = true,
        bar_part_of_window         = true,
        bar_precedence_over_border = true,
        icon_on_hover              = false,
        inactive_button_color      = tb.inactive or "rgba(585b70ff)",
        on_double_click            = "hyprctl eval 'atelier_maximize()'",
    } } })

    -- once per config load (the plugin clears them before a reload)
    if want and not atelier_trad.buttons then
        atelier_trad.buttons = true
        -- plain macOS-style dots, no symbols (tiny glyphs on them read as smudges)
        local function button(color, action)
            hl.plugin.hyprbars.add_button({ bg_color = color, fg_color = color, size = 12, icon = "", action = action })
        end
        -- from the outer edge in: close · minimise · maximise
        button(tb.close or "rgba(f38ba8ff)", [[hyprctl dispatch 'hl.dsp.window.close()']])
        button(tb.min or "rgba(f9e2afff)", "hyprctl eval 'atelier_minimize()'")
        button(tb.max or "rgba(a6e3a1ff)", "hyprctl eval 'atelier_maximize()'")
    end
end

-- ── maximise ─────────────────────────────────────────────────────────────────
-- Hyprland's "maximized" keeps the outer gaps; this fills the work area exactly (inside the bar,
-- the frame and the dock, with the title bar and border on screen). A maximised window clicked
-- again goes back to where it was (or, after a config reload lost that, a centred 70 %).
local function xy(v) if type(v) == "table" then return v.x or v[1] or 0, v.y or v[2] or 0 end return 0, 0 end
atelier_trad_restore = atelier_trad_restore or {}
function atelier_maximize()
    local w = hl.get_active_window()
    if not w then return end
    local sel = "address:" .. addr(w)
    if not w.floating then   -- a tiled window (Atelier layout, or tiled by hand): Hyprland's own
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", window = sel }))
        return
    end
    local m = w.monitor or hl.get_active_monitor()
    if not m then return end
    local r  = type(m.reserved) == "table" and m.reserved or {}
    local bs = tonumber(hl.get_config("general.border_size")) or 0
    local sw, sh = m.width / (m.scale or 1), m.height / (m.scale or 1)
    local tx = m.x + (r.left or 0) + bs
    local ty = m.y + (r.top or 0) + BAR_H + bs
    local tw = math.floor(sw - (r.left or 0) - (r.right or 0) - 2 * bs)
    local th = math.floor(sh - (r.top or 0) - (r.bottom or 0) - BAR_H - 2 * bs)
    local ax, ay = xy(w.at)
    local cw, ch = xy(w.size)
    local a = addr(w)
    if math.abs(ax - tx) <= 2 and math.abs(ay - ty) <= 2 and math.abs(cw - tw) <= 2 and math.abs(ch - th) <= 2 then
        local g = atelier_trad_restore[a] or { w = math.floor(tw * 0.7), h = math.floor(th * 0.7) }
        g.x = g.x or math.floor(tx + (tw - g.w) / 2)
        g.y = g.y or math.floor(ty + (th - g.h) / 2)
        hl.dispatch(hl.dsp.window.resize({ x = g.w, y = g.h, relative = false, window = sel }))
        hl.dispatch(hl.dsp.window.move({ x = g.x, y = g.y, relative = false, window = sel }))
        atelier_trad_restore[a] = nil
    else
        atelier_trad_restore[a] = { x = ax, y = ay, w = cw, h = ch }
        -- resize first: a floating window resizes around its centre, so a move first would be undone
        hl.dispatch(hl.dsp.window.resize({ x = tw, y = th, relative = false, window = sel }))
        hl.dispatch(hl.dsp.window.move({ x = tx, y = ty, relative = false, window = sel }))
    end
end

-- ── minimise / restore, animated ─────────────────────────────────────────────
-- The window glides down into the dock (Hyprland's own move/resize animation), then hides on
-- the "minimized" workspace and gets its size back there, out of sight. Restoring (the dock)
-- does the reverse: it comes back small at the dock and grows to where it was.
local GLIDE_MS = 230
atelier_trad_min = atelier_trad_min or {}
local function dock_point(m)
    local r = type(m.reserved) == "table" and m.reserved or {}
    local sw, sh = m.width / (m.scale or 1), m.height / (m.scale or 1)
    return m.x + ((r.left or 0) + sw - (r.right or 0)) / 2, m.y + sh - (r.bottom or 0) / 2
end
local function tiny(sel, m, cw, ch)
    local dx, dy = dock_point(m)
    local w, h = math.max(60, math.floor(cw * 0.12)), math.max(40, math.floor(ch * 0.12))
    hl.dispatch(hl.dsp.window.resize({ x = w, y = h, relative = false, window = sel }))
    hl.dispatch(hl.dsp.window.move({ x = math.floor(dx - w / 2), y = math.floor(dy - h / 2), relative = false, window = sel }))
end

function atelier_minimize(w)
    w = w or hl.get_active_window()
    if not w then return end
    local a, sel = addr(w), "address:" .. addr(w)
    local m = w.monitor or hl.get_active_monitor()
    local ax, ay = xy(w.at)
    local cw, ch = xy(w.size)
    atelier_trad_min[a] = { x = ax, y = ay, w = cw, h = ch, floating = w.floating }
    if not (m and w.floating) then   -- tiled (or no monitor): just hide it
        hl.dispatch(hl.dsp.window.move({ workspace = MIN_WS, follow = false, window = sel }))
        return
    end
    tiny(sel, m, cw, ch)
    hl.timer(function()
        hl.dispatch(hl.dsp.window.move({ workspace = MIN_WS, follow = false, window = sel }))
        -- back to its real size while hidden, so it reopens as it was
        hl.dispatch(hl.dsp.window.resize({ x = cw, y = ch, relative = false, window = sel }))
        hl.dispatch(hl.dsp.window.move({ x = ax, y = ay, relative = false, window = sel }))
    end, { timeout = GLIDE_MS, type = "oneshot" })
end

-- called by the dock with the window's address ("0x…")
function atelier_unminimize(a)
    local sel = "address:" .. a
    local w = hl.get_window(sel)
    local ws = hl.get_active_workspace()
    if not (w and ws) then return end
    local m = hl.get_active_monitor()
    local g = atelier_trad_min[a]
    if not g then local ax, ay = xy(w.at); local cw, ch = xy(w.size); g = { x = ax, y = ay, w = cw, h = ch } end
    if m and w.floating then tiny(sel, m, g.w, g.h) end
    hl.dispatch(hl.dsp.window.move({ workspace = ws.id, follow = false, window = sel }))
    hl.dispatch(hl.dsp.focus({ window = sel }))
    hl.timer(function()
        hl.dispatch(hl.dsp.window.resize({ x = g.w, y = g.h, relative = false, window = sel }))
        hl.dispatch(hl.dsp.window.move({ x = g.x, y = g.y, relative = false, window = sel }))
    end, { timeout = 30, type = "oneshot" })
    atelier_trad_min[a] = nil
end

-- ── the switch ───────────────────────────────────────────────────────────────
function atelier_apply_traditional(t)
    t = t or (lib.mode and lib.mode.settings()) or lib.win
    local want = (t.shell_layout == "classic")
    pcall(function() float_rule:set_enabled(want) end)

    if want ~= atelier_trad.on then
        if want then
            for _, w in ipairs(hl.get_windows({ mapped = true, floating = false }) or {}) do
                local sel = "address:" .. addr(w)
                hl.dispatch(hl.dsp.window.float({ action = "enable", window = sel }))
                hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TAG, window = sel }))
            end
        else
            -- minimised windows come back to the workspace you're on
            local ws = hl.get_active_workspace()
            for _, w in ipairs(hl.get_windows({ workspace = MIN_WS }) or {}) do
                if ws then hl.dispatch(hl.dsp.window.move({ workspace = ws.id, follow = false, window = "address:" .. addr(w) })) end
            end
            for _, w in ipairs(hl.get_windows({ tag = TAG }) or {}) do
                local sel = "address:" .. addr(w)
                if w.floating and not keeps_floating(w) then
                    hl.dispatch(hl.dsp.window.float({ action = "disable", window = sel }))
                end
                hl.dispatch(hl.dsp.window.tag({ tag = "-" .. TAG, window = sel }))
            end
        end
        atelier_trad.on = want
    end
    titlebars(want, t)
end

-- windows opened while Traditional is on are tiled again when you leave it
hl.on("window.open", function(w)
    if atelier_trad.on and w and not keeps_floating(w) then
        hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TAG, window = "address:" .. addr(w) }))
    end
end)
-- an app's own minimise button: park it like the title bar's button does
hl.on("window.minimize", function(w)
    if atelier_trad.on and w then atelier_minimize(w) end
end)

-- at load the windows are already in the right state (the rule handles new ones), so only sync
-- the flag, the rule and the title bars
atelier_trad.on = (lib.win.shell_layout == "classic")
atelier_apply_traditional(lib.win)
