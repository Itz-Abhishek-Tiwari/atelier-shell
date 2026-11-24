-- plugins/ui/smear_cursor.lua
-- Animated cursor that "smears" between positions — premium movement feel.
return {
  {
    "sphamba/smear-cursor.nvim",
    event = "VeryLazy",
    opts = {
      -- Smear style: matrix of cells that follow the cursor
      stiffness          = 0.8,   -- 0-1: higher = snappier
      trailing_stiffness = 0.5,   -- tail follows more softly
      distance_stop_animating = 0.5,
      hide_target_hack   = false, -- keep target cell visible

      -- Use the cursor colour from the active theme
      cursor_color         = "none",  -- "none" = inherit from Cursor hl group
      normal_bg            = "none",

      -- Scroll smear (optional — enable if you like it)
      scroll_buffer_space  = true,
      legacy_computing_symbols_support = false,

      -- Filetypes where smear is disabled (avoids conflicts)
      filetypes_disabled   = {
        "noice", "neo-tree", "NvimTree", "lazy", "mason",
        "snacks_picker_list", "snacks_picker_input",
        "snacks_terminal", "toggleterm",
      },
    },
  },
}
