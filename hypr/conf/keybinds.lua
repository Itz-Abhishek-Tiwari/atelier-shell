-- Keybindings
--
-- Every bind meant for people carries a description, "Section · What it does", which the shell's
-- shortcut helper (Super+? or Control center → Shortcuts) reads live from `hyprctl binds -j`.
-- An optional " @ keys" suffix overrides how the keys are shown (one entry for a looped group,
-- e.g. "Workspaces · Go to workspace @ Super + 1 … 0"). Binds without a description are hidden.
--
-- Settings → Shortcuts can give any single-combo described bind new keys (or turn it off) and
-- add your own: `binds.overrides` / `binds.custom` in atelier-settings.lua. Every editable bind
-- is kept in the global `atelier_binds` registry so the shell can rebind live through
-- `atelier_apply_binds(t)` (hyprctl eval) without a config reload; the registry is written to
-- ~/.cache/atelier/keybinds.json for the Settings page.
local lib  = require("conf.lib")
local HOME = lib.HOME
local cfg  = lib.win.binds or {}

-- Super+T / Super+E start whatever Settings → Default apps picked (read at key press, so a
-- change applies without a reload)
local defaults    = HOME .. "/.config/quickshell/scripts/default-apps.py open "
local terminal    = defaults .. "terminal"
local fileManager = defaults .. "files"
local mainMod     = "SUPER"
local qs          = "qs ipc call "

atelier_binds = { list = {}, by_id = {}, custom = {} }

-- hl.bind with a description for the shortcut helper
local function bind(keys, action, desc, opts)
    opts = opts or {}
    if desc then opts.description = desc end
    -- editable: described and a single combo (" @ keys" marks a looped group)
    if desc and not desc:find(" @ ", 1, true) then
        local id, n = desc, 2
        while atelier_binds.by_id[id] do id = desc .. " #" .. n; n = n + 1 end
        local e = { id = id, default = keys, keys = keys, action = action, opts = opts }
        local o = (cfg.overrides or {})[id]
        if type(o) == "string" then e.keys = o end
        atelier_binds.by_id[id] = e
        table.insert(atelier_binds.list, e)
        if e.keys ~= "" then
            local ok, h = pcall(hl.bind, e.keys, action, opts)
            if ok then e.handle = h elseif e.keys ~= keys then
                e.keys = keys                                  -- a bad override: keep the default
                e.handle = hl.bind(keys, action, opts)
            end
        end
        return
    end
    hl.bind(keys, action, opts)
end

-- Apps
bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal),    "Apps · Terminal")
bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager), "Apps · File manager")
bind(mainMod .. " + F", hl.dsp.exec_cmd("firefox"),   "Apps · Browser")
bind(mainMod .. " + A", hl.dsp.exec_cmd("waypaper"),  "Apps · Waypaper")
bind("mouse:275",       hl.dsp.exec_cmd("spotify-launcher"), "Apps · Spotify @ Mouse back button")
bind("mouse:276",       hl.dsp.exec_cmd("vesktop"),          "Apps · Discord @ Mouse forward button")

-- Shell
bind(mainMod .. " + SPACE",         hl.dsp.exec_cmd(qs .. "launcher toggle"),      "Shell · Launcher")
bind(mainMod .. " + D",             hl.dsp.exec_cmd(qs .. "apps toggle"),          "Shell · App grid")
bind(mainMod .. " + C",             hl.dsp.exec_cmd(qs .. "controlcenter toggle"), "Shell · Control center")
bind(mainMod .. " + Shift + slash", hl.dsp.exec_cmd(qs .. "keybinds toggle"),      "Shell · Keyboard shortcuts")
bind(mainMod .. " + comma",         hl.dsp.exec_cmd(qs .. "settings toggle"),      "Shell · Settings")
bind(mainMod .. " + Shift + C",     hl.dsp.exec_cmd(qs .. "camera toggle"),        "Shell · Camera")
bind(mainMod .. " + Tab",           hl.dsp.exec_cmd(qs .. "overview toggle"),      "Shell · Overview")
bind(mainMod .. " + Shift + V",     hl.dsp.exec_cmd(qs .. "clipboard toggle"),     "Shell · Clipboard history")
bind(mainMod .. " + semicolon",       hl.dsp.exec_cmd(qs .. "emoji toggle"),         "Shell · Emoji picker")
bind(mainMod .. " + Shift + semicolon", hl.dsp.exec_cmd(qs .. "emoji gifs"),         "Shell · GIF finder")
bind(mainMod .. " + M",             hl.dsp.exec_cmd(qs .. "media toggle"),         "Shell · Music")
bind(mainMod .. " + G",             hl.dsp.exec_cmd(qs .. "games toggle"),         "Shell · Game library")
bind(mainMod .. " + Alt + W",       hl.dsp.exec_cmd(qs .. "wallpaper toggle"),     "Shell · Wallpapers")
bind(mainMod .. " + slash",         hl.dsp.exec_cmd(qs .. "keyboard toggle"),      "Shell · On-screen keyboard")
bind(mainMod .. " + BackSpace",     hl.dsp.exec_cmd(qs .. "power toggle"),         "Shell · Power menu")
bind(mainMod .. " + Shift + M",     hl.dsp.exec_cmd(qs .. "sysmon toggle"),        "Shell · System monitor")
bind(mainMod .. " + Alt + T",       hl.dsp.exec_cmd(qs .. "timers toggle"),        "Shell · Timers & pomodoro")
bind(mainMod .. " + Shift + X",     hl.dsp.exec_cmd(qs .. "colorpicker pick"),     "Shell · Pick a colour")
-- Alt+Tab window switcher: hold Alt, tap Tab; letting go of Alt focuses the highlighted window
bind("ALT + Tab",                   hl.dsp.exec_cmd(qs .. "switcher next"),        "Windows · Switch window @ Alt + Tab")
bind("ALT + SHIFT + Tab",           hl.dsp.exec_cmd(qs .. "switcher prev"))
hl.bind("Alt_L", hl.dsp.exec_cmd(qs .. "switcher commit"), { release = true, ignore_mods = true })
bind(mainMod .. " + L",             hl.dsp.exec_cmd(qs .. "lock lock || hyprlock"), "Shell · Lock")
bind("Ctrl + Alt + W",              hl.dsp.exec_cmd("killall waybar || waybar"))

-- Modes & look
bind(mainMod .. " + Shift + G", hl.dsp.exec_cmd(qs .. "mode toggleGame"),   "Modes · Game mode")
bind(mainMod .. " + Shift + D", hl.dsp.exec_cmd(qs .. "mode toggleDev"),    "Modes · Programming mode")
bind(mainMod .. " + Shift + T", hl.dsp.exec_cmd(HOME .. "/.local/bin/atelier-theme toggle-mode"), "Modes · Light / dark")
bind(mainMod .. " + Shift + N", hl.dsp.exec_cmd(qs .. "nightlight toggle"), "Modes · Night light")
bind(mainMod .. " + Shift + F", hl.dsp.exec_cmd(HOME .. "/.config/scripts/focus_mode.py"), "Modes · Focus mode")

-- Windows
bind(mainMod .. " + Q",  hl.dsp.window.close(),                    "Windows · Close")
bind(mainMod .. " + W",  hl.dsp.window.float({ action = "toggle" }), "Windows · Float / tile")
bind("Alt + Return",     hl.dsp.window.fullscreen(),               "Windows · Fullscreen")
bind(mainMod .. " + J",  hl.dsp.layout("togglesplit"),             "Windows · Flip split (dwindle)")

-- Focus / resize / move with the arrow keys (one helper entry per group)
local dirs = { left = { -30, 0 }, right = { 30, 0 }, up = { 0, -30 }, down = { 0, 30 } }
for dir, d in pairs(dirs) do
    local first = dir == "left"
    bind(mainMod .. " + " .. dir, hl.dsp.focus({ direction = dir }),
        first and "Windows · Focus @ Super + Arrows" or nil)
    bind(mainMod .. " + Shift + " .. dir, hl.dsp.window.resize({ x = d[1], y = d[2] }),
        first and "Windows · Resize @ Super + Shift + Arrows" or nil, { repeating = true })
    bind(mainMod .. " + Shift + Ctrl + " .. dir, hl.dsp.window.move({ direction = dir }),
        first and "Windows · Move @ Super + Shift + Ctrl + Arrows" or nil)
end

-- Drag and resize windows (mouse, or hold Z/X)
bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   "Windows · Drag @ Super + Left drag",  { mouse = true })
bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), "Windows · Resize @ Super + Right drag", { mouse = true })
bind(mainMod .. " + Z",         hl.dsp.window.drag(),   "Windows · Drag (hold)",   { mouse = true })
bind(mainMod .. " + X",         hl.dsp.window.resize(), "Windows · Resize (hold)", { mouse = true })

-- Layouts. Scrolling is built into Hyprland; its messages are ignored by the other layouts.
-- Super+arrows already focus the next column and scroll the strip to it.
bind(mainMod .. " + Alt + SPACE", hl.dsp.exec_cmd(qs .. "settings cycleLayout"), "Layout · Next layout")
bind(mainMod .. " + Ctrl + left",       hl.dsp.layout("move -col"), "Layout · Scroll columns @ Super + Ctrl + ← →")
bind(mainMod .. " + Ctrl + right",      hl.dsp.layout("move +col"))
bind(mainMod .. " + Ctrl + mouse_up",   hl.dsp.layout("move -col"), "Layout · Scroll columns @ Super + Ctrl + Scroll")
bind(mainMod .. " + Ctrl + mouse_down", hl.dsp.layout("move +col"))
bind(mainMod .. " + R",            hl.dsp.layout("colresize +conf"), "Layout · Wider column")
bind(mainMod .. " + Ctrl + R",     hl.dsp.layout("colresize -conf"), "Layout · Narrower column")
bind(mainMod .. " + bracketleft",  hl.dsp.layout("swapcol l"),       "Layout · Move column left")
bind(mainMod .. " + bracketright", hl.dsp.layout("swapcol r"),       "Layout · Move column right")
bind(mainMod .. " + period",       hl.dsp.layout("fit active"),      "Layout · Fit column on screen")

-- Workspaces 1-10: go / move window / move window silently
for i = 1, 10 do
    local key = i % 10
    local first = i == 1
    bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }),
        first and "Workspaces · Go to workspace @ Super + 1 … 0" or nil)
    bind(mainMod .. " + Shift + " .. key, hl.dsp.window.move({ workspace = i }),
        first and "Workspaces · Move window there @ Super + Shift + 1 … 0" or nil)
    bind(mainMod .. " + Alt + " .. key, hl.dsp.window.move({ workspace = i, silent = true }),
        first and "Workspaces · Send window, stay here @ Super + Alt + 1 … 0" or nil)
end
bind(mainMod .. " + grave",      hl.dsp.focus({ workspace = "previous" }), "Workspaces · Previous workspace")
bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), "Workspaces · Next / previous @ Super + Scroll")
bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Scratchpad (special workspace)
bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"),          "Workspaces · Scratchpad")
bind(mainMod .. " + Shift + S", hl.dsp.window.move({ workspace = "special:magic" }), "Workspaces · Move window to scratchpad")

-- Screenshots & recording (built into the shell: freeze -> pick -> save + copy + preview)
bind("Print",                   hl.dsp.exec_cmd(qs .. "screenshot region"), "Capture · Screenshot an area")
bind(mainMod .. " + P",         hl.dsp.exec_cmd(qs .. "screenshot region"), "Capture · Screenshot an area")
bind(mainMod .. " + Ctrl + P",  hl.dsp.exec_cmd(qs .. "screenshot window"), "Capture · Screenshot a window")
bind("Shift + Print",           hl.dsp.exec_cmd(qs .. "screenshot screen"), "Capture · Screenshot the screen")
bind(mainMod .. " + Alt + P",   hl.dsp.exec_cmd(qs .. "screenshot screen"), "Capture · Screenshot the screen")
bind(mainMod .. " + Shift + R", hl.dsp.exec_cmd(qs .. "record toggle"),     "Capture · Record an area / stop")
bind(mainMod .. " + Alt + R",   hl.dsp.exec_cmd(qs .. "record screen"),     "Capture · Record the screen")

-- Media
bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       "Media · Next track",     { locked = true })
bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), nil,                      { locked = true })
bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), "Media · Play / pause",   { locked = true })
bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   "Media · Previous track", { locked = true })

-- Volume & brightness: hardware keys and the bare F-keys do the same thing, through the
-- shell's OSD (no notify-send popups). Work on the lock screen too.
local media_keys = {
    { { "XF86AudioRaiseVolume",  "F12" }, qs .. "osd volumeUp",       true,  "Media · Volume up" },
    { { "XF86AudioLowerVolume",  "F11" }, qs .. "osd volumeDown",     true,  "Media · Volume down" },
    { { "XF86AudioMute",         "F10" }, qs .. "osd mute",           false, "Media · Mute" },
    { { "XF86MonBrightnessUp",   "F3"  }, qs .. "osd brightnessUp",   true,  "Media · Brightness up" },
    { { "XF86MonBrightnessDown", "F1"  }, qs .. "osd brightnessDown", true,  "Media · Brightness down" },
}
for _, m in ipairs(media_keys) do
    for i, key in ipairs(m[1]) do
        -- describe the F-key (the hardware key shows the same action next to it)
        bind(key, hl.dsp.exec_cmd(m[2]), i == 2 and m[4] or nil, { locked = true, repeating = m[3] })
    end
end
bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), "Media · Mute microphone", { locked = true })

-- Wallpapers
-- the shell draws the wallpaper (with the transition from Settings), no picker needed
bind(mainMod .. " + Alt + Left",  hl.dsp.exec_cmd(qs .. "wallpaper prev"),   "Wallpaper · Previous")
bind(mainMod .. " + Alt + Right", hl.dsp.exec_cmd(qs .. "wallpaper next"),   "Wallpaper · Next")
bind(mainMod .. " + Alt + I",     hl.dsp.exec_cmd(qs .. "wallpaper random"), "Wallpaper · Random")

--------------------------------------------------------------------------------
-- Settings → Shortcuts: your own shortcuts, live rebinding, and the registry dump
--------------------------------------------------------------------------------
local function json_str(s)
    return '"' .. tostring(s):gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
        return string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function dump()
    local rows = {}
    for _, e in ipairs(atelier_binds.list) do
        rows[#rows + 1] = "{\"id\":" .. json_str(e.id) .. ",\"keys\":" .. json_str(e.keys)
            .. ",\"default\":" .. json_str(e.default) .. "}"
    end
    local f = io.open(HOME .. "/.cache/atelier/keybinds.json", "w")
    if f then f:write("[" .. table.concat(rows, ",\n") .. "]\n"); f:close() end
end

local function bind_custom(list)
    for _, h in ipairs(atelier_binds.custom) do pcall(function() h:remove() end) end
    atelier_binds.custom = {}
    for _, c in ipairs(list or {}) do
        if type(c) == "table" and (c.keys or "") ~= "" and (c.cmd or "") ~= "" then
            local label = (c.label or "") ~= "" and c.label or c.cmd
            local ok, h = pcall(hl.bind, c.keys, hl.dsp.exec_cmd(c.cmd), { description = "Custom · " .. label })
            if ok then table.insert(atelier_binds.custom, h) end
        end
    end
end

-- t = the `binds` table of atelier-settings.lua. Rebinds only what changed.
function atelier_apply_binds(t)
    t = t or {}
    local ov = t.overrides or {}
    for _, e in ipairs(atelier_binds.list) do
        local want = ov[e.id]
        if type(want) ~= "string" then want = e.default end
        if want ~= e.keys then
            if e.handle then pcall(function() e.handle:remove() end); e.handle = nil end
            if want ~= "" then
                local ok, h = pcall(hl.bind, want, e.action, e.opts)
                if ok then e.handle = h; e.keys = want
                else e.handle = hl.bind(e.default, e.action, e.opts); e.keys = e.default end
            else
                e.keys = ""
            end
        end
    end
    bind_custom(t.custom)
    dump()
end

bind_custom(cfg.custom)
dump()
