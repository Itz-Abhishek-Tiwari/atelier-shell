-- plugins/ui/tint.lua
-- Tint: dim inactive splits so the active window always pops visually.
-- Uses a subtle desaturation + darkening — never jarring, always readable.
return {
  {
    "levouh/tint.nvim",
    event = "WinNew",
    opts = {
      tint         = -25,      -- darken inactive windows by 25 (negative = darker)
      saturation   = 0.75,     -- desaturate to 75%
      tint_background_colors = true,   -- also tint background groups

      -- Windows that should NEVER be dimmed
      highlight_ignore_patterns = {
        "WinSeparator", "Status.*", "NormalNC",
      },

      window_ignore_function = function(winid)
        local bufid = vim.api.nvim_win_get_buf(winid)
        local ft    = vim.bo[bufid].filetype
        local bt    = vim.bo[bufid].buftype

        -- Skip special windows
        local skip_fts = {
          "dashboard", "alpha", "startup", "lazy", "mason",
          "neo-tree", "NvimTree", "TelescopePrompt",
          "snacks_picker_list", "snacks_picker_input", "snacks_picker_preview",
          "snacks_terminal", "toggleterm", "noice", "notify",
          "DiffviewFiles", "DiffviewFileHistory",
        }
        for _, s in ipairs(skip_fts) do
          if ft == s then return true end
        end

        -- Skip floating windows (floats have their own focus behaviour)
        local config = vim.api.nvim_win_get_config(winid)
        if config.relative ~= "" then return true end

        -- Skip non-file buffers
        return bt ~= "" and bt ~= "acwrite"
      end,
    },
  },
}
