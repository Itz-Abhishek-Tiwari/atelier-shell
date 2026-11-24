-- plugins/ui/satellite.lua
-- Satellite: scrollbar on the right edge with diagnostic, search & git markers.
return {
  {
    "lewis6991/satellite.nvim",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      current_only = false,   -- show in all visible windows
      winblend     = 40,      -- semi-transparent track
      zindex       = 40,

      -- ── Handlers ──────────────────────────────────────────────────────────
      handlers = {
        cursor    = { enable = false },
        search    = { enable = true },
        diagnostic = {
          enable  = true,
          signs   = { "-", "=", "≡" },  -- hint, warn, error
          min_severity = vim.diagnostic.severity.HINT,
        },
        gitsigns  = { enable = true, signs = { add = "│", change = "│", delete = "_" } },
        marks     = { enable = true, key = "m", show_builtins = false },
        quickfix  = { enable = true, signs = { "-", "=", "≡" } },
      },

      excluded_filetypes = {
        "prompt", "TelescopePrompt", "noice",
        "lazy", "mason", "lspinfo",
        "NvimTree", "neo-tree",
        "snacks_picker_list", "snacks_picker_input", "snacks_picker_preview",
        "snacks_terminal", "toggleterm",
        "DiffviewFiles", "DiffviewFileHistory",
        "dashboard", "alpha", "startup",
      },
    },
  },
}
