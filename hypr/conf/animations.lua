-- Animation curves and springs.
-- The animation set itself (which leaf uses which curve) is in ../atelier-mode.lua, one copy
-- shared by every performance mode; hyprland.lua applies it last.
--
-- Feel: smooth glide, no wobble. Things arrive fast and settle softly (long ease-out tail),
-- things leave quickly and quietly. Springs are close to critically damped so they never bounce.

hl.config({
    animations = {
        enabled = require("conf.lib").win.animations,
        workspace_wraparound = false,
    },
})

-- Ease-out: quick start, long soft landing (arrivals, slides, borders)
hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1},   {0.32, 1}   } })
hl.curve("easeOutExpo",  { type = "bezier", points = { {0.16, 1},   {0.3,  1}   } })
-- Ease-in: gentle start, then gone (things leaving)
hl.curve("easeInSoft",   { type = "bezier", points = { {0.4,  0},   {0.7,  0.2} } })
-- Fades: nearly linear reads smoothest for opacity
hl.curve("almostLinear", { type = "bezier", points = { {0.5,  0.5}, {0.75, 1}   } })
hl.curve("quick",        { type = "bezier", points = { {0.15, 0},   {0.1,  1}   } })

-- Material 3 (Caelestia's set; the same curves the shell's Anim tokens use, so windows and
-- panels move as one system): arrivals decelerate, departures accelerate, the rest is standard.
hl.curve("emphasizedDecel",   { type = "bezier", points = { {0.05, 0.7}, {0.1, 1}    } })
hl.curve("emphasizedAccel",   { type = "bezier", points = { {0.3,  0},   {0.8, 0.15} } })
hl.curve("standard",          { type = "bezier", points = { {0.2,  0},   {0,   1}    } })
hl.curve("specialWorkSwitch", { type = "bezier", points = { {0.05, 0.7}, {0.1, 1}    } })

-- Springs. Damping ratio ζ = damping / (2·√(stiffness·mass)); ζ = 1 is no overshoot.
--   glide  ζ ≈ 0.92: soft, settles without a visible bounce (windows opening, moving, resizing)
--   swift  ζ ≈ 0.95: stiffer and faster, for tiling reflows that should feel snappy
hl.curve("glide", { type = "spring", mass = 1, stiffness = 210, damping = 26.5 })
hl.curve("swift", { type = "spring", mass = 1, stiffness = 340, damping = 35 })
