-- Appearance: borders, rounding, shadows, and THE one transparency + blur for every app.
--
-- Every window (terminals, Firefox, Spotify, VS Code, …) gets exactly the same opacity and
-- blur from here. No per-app opacity rules, and the apps themselves are kept opaque
-- (kitty: background_opacity 1.0, ghostty: background-opacity = 1) so nothing stacks on top.
-- The only exceptions are in rules.lua: video/games/creative apps and fullscreen stay solid.
--
-- The numbers come from the Settings app (Super+, → Appearance), saved in ../atelier-settings.lua,
-- and are applied live. Defaults are in ../atelier-mode.lua.
local lib   = require("conf.lib")
local win   = lib.win
local theme = lib.theme

hl.config({
    general = {
        -- gaps_out 10 + rounding 14 = window corners concentric with the shell
        -- frame's 24px inner corners (24 - 10 = 14)
        gaps_in          = win.gaps_in,
        gaps_out         = win.gaps_out,
        border_size      = 3,            -- NamiConfig: 3px gradient border
        col = {
            active_border   = { colors = theme.active_border, angle = 45 },
            inactive_border = theme.inactive_border,
        },
        resize_on_border = true,
        allow_tearing    = false,          -- Game mode turns this on (atelier-mode.lua)
    },

    decoration = {
        rounding         = win.rounding,
        rounding_power   = 2,

        -- one opacity for all windows
        active_opacity   = win.active_opacity,
        inactive_opacity = win.inactive_opacity,
        dim_inactive     = win.dim_inactive,   -- gentle focus cue
        dim_strength     = win.dim_strength,

        -- one blur for all windows (and the shell's popups)
        blur = {
            enabled           = win.blur,
            -- size 9 with 3 passes looks the same as size 7 with 4 passes for ~half the GPU
            -- work (measured); each extra pass roughly doubles the cost on this iGPU.
            size              = win.blur_size,
            passes            = win.blur_passes,
            vibrancy          = win.blur_vibrancy,
            new_optimizations = true,
            ignore_opacity    = true,
            -- xray: windows show the cached, pre-blurred wallpaper instead of re-blurring what is
            -- behind them on every redraw. Tiled windows only have the wallpaper behind them, so
            -- they look the same; this is what kept the GPU busy whenever VS Code (or any app)
            -- was redrawing in Normal mode. (Pop-ups still blur real windows: rules.lua.)
            -- (Settings → Appearance → "Blur what's behind" turns it off: real blur, more GPU)
            xray              = win.blur_xray,
            noise             = win.blur_noise,
            contrast          = win.blur_contrast,
            brightness        = win.blur_brightness,
            popups            = win.blur_popups,
        },

        shadow = {
            enabled        = win.shadow,
            range          = 6,          -- tight plain shadow, no glow (colour: theme.lua)
            render_power   = 3,
            color          = theme.shadow,
            color_inactive = theme.shadow_inactive,
        },
    },

    group = {
        col = {
            border_inactive = theme.group_inactive,
            border_active   = { colors = theme.group_active, angle = 45 },
        },
        groupbar = {
            col = {
                active   = theme.groupbar_active,
                inactive = theme.groupbar_inactive,
            },
            font_size  = 10,
            text_color = theme.groupbar_text,
        },
    },
})
