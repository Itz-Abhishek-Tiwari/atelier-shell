-- Keyboard, touchpad, mice, gestures
--
-- Layout, repeat, pointer and touchpad options come from Settings → Keyboard & mouse
-- (atelier-settings.lua `input` table, defaults in atelier-mode.lua, which also applies them:
-- M.apply_input). Defaults are macOS-like: natural scrolling on the trackpad, finer/slower scroll
-- steps, two-finger click = right click, three-finger click = middle click, and a custom
-- acceleration curve on the 2.4 GHz mouse.
local lib = require("conf.lib")

if lib.mode then lib.mode.apply_input(lib.win) end

-- 3-finger horizontal swipe switches workspaces
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})
