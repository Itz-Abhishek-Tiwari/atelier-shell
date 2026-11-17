-- Tiling layouts (chosen/tuned in the Settings app → Windows; Super+Alt+Space cycles them)
local win = require("conf.lib").win

hl.config({
    general = {
        layout = win.layout or "dwindle",
    },

    dwindle = {
        preserve_split = win.dwindle_preserve_split,
        smart_split    = win.dwindle_smart_split,
    },

    master = {
        new_status  = "master",
        orientation = win.master_orientation,
        mfact       = win.master_mfact,
        new_on_top  = win.master_new_on_top,
    },

    scrolling = {
        column_width           = win.scroll_column_width,
        explicit_column_widths = "0.333, 0.5, 0.667, 1.0",   -- Super+R / Super+Ctrl+R cycle these
    },
})
