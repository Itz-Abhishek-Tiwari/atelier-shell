-- Keyboard, touchpad, mice, gestures
--
-- Layout, repeat, pointer and touchpad options come from Settings → Keyboard & mouse
-- (atelier-settings.lua `input` table, defaults in atelier-mode.lua, which also applies them:
-- M.apply_input). Defaults are macOS-like: natural scrolling on the trackpad, finer/slower scroll
-- steps, two-finger click = right click, three-finger click = middle click, and a custom
-- acceleration curve on the 2.4 GHz mouse.
local lib = require("conf.lib")

if lib.mode then lib.mode.apply_input(lib.win) end

-- Touchpad gestures (Settings → Keyboard & mouse). Hyprland can't remove a gesture, so turning one
-- on/off or changing its finger count reloads the config; invert / distance apply live (apply_input).
local g = lib.win.gestures or (lib.mode and lib.mode.defaults.gestures) or {}
local function fingers(n, fallback)
    n = math.floor(tonumber(n) or fallback)
    return (n == 3 or n == 4) and n or fallback
end
local function shell(call) return function() hl.exec_cmd("qs ipc call " .. call) end end
local swipe = fingers(g.workspace_fingers, 3)

if g.workspace ~= false then   -- the workspace follows the fingers, like macOS Spaces
    hl.gesture({ fingers = swipe, direction = "horizontal", action = "workspace" })
end
if g.overview ~= false then    -- the other finger count: up opens the overview, down closes it
    hl.gesture({ fingers = 7 - swipe, direction = "up",   action = shell("overview open") })
    hl.gesture({ fingers = 7 - swipe, direction = "down", action = shell("overview close") })
end
if g.launcher ~= false then    -- like Launchpad: pinch in opens the launcher, pinch out closes it
    local pinch = fingers(g.pinch_fingers, 4)
    hl.gesture({ fingers = pinch, direction = "pinchin",  action = shell("launcher open") })
    hl.gesture({ fingers = pinch, direction = "pinchout", action = shell("launcher close") })
end

hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})
