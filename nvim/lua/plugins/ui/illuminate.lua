-- plugins/ui/illuminate.lua
-- RRethy/vim-illuminate: Highlights all occurrences of the symbol
-- under the cursor across the buffer using a subtle background tint.
-- Much more visible than the stock `*` highlight with zero overhead.
return {
  {
    "RRethy/vim-illuminate",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      -- Priority: LSP > treesitter > regex (best accuracy first)
      providers = { "lsp", "treesitter", "regex" },

      delay = 120,              -- ms before highlighting kicks in (feels snappy)
      large_file_cutoff = 2000, -- disable for huge files to stay performant
      large_file_overrides = {
        providers = { "regex" },
      },

      -- Filetypes to skip entirely
      filetypes_denylist = {
        "dirbuf", "dirvish", "fugitive", "alpha", "NvimTree",
        "lazy", "mason", "lspinfo", "help", "startify", "dashboard",
        "neo-tree", "snacks_picker_list", "snacks_picker_input",
        "snacks_picker_preview", "snacks_terminal", "toggleterm",
      },

      -- Under-cursor word: highlight all matches
      under_cursor = true,

      -- Visual mode: don't highlight in visual (uses its own selection hl)
      modes_denylist = { "v", "vs", "V", "Vs", "\22", "\22s" },
    },
    config = function(_, opts)
      require("illuminate").configure(opts)

      -- ── Subtle highlight styling ────────────────────────────────────────
      -- Applied on every colourscheme change so it adapts to the active theme
      local function set_illuminate_hls()
        local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = "CursorLine", link = false })
        local bg = ok and hl and hl.bg

        -- IlluminatedWordText: plain word match (regex / no semantic info)
        vim.api.nvim_set_hl(0, "IlluminatedWordText",  { bg = bg, underline = false })
        -- IlluminatedWordRead: reading the value
        vim.api.nvim_set_hl(0, "IlluminatedWordRead",  { bg = bg, underline = false })
        -- IlluminatedWordWrite: assignment / mutation
        vim.api.nvim_set_hl(0, "IlluminatedWordWrite", {
          bg        = bg,
          underline = true,
          sp        = vim.api.nvim_get_hl(0, { name = "DiagnosticWarn", link = false }).fg,
        })
      end

      set_illuminate_hls()
      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern  = "*",
        callback = set_illuminate_hls,
      })

      -- ── Keybindings ─────────────────────────────────────────────────────
      -- Jump to next / previous reference under cursor
      vim.keymap.set("n", "]]", function()
        require("illuminate").goto_next_reference(false)
      end, { desc = "Next reference (illuminate)" })

      vim.keymap.set("n", "[[", function()
        require("illuminate").goto_prev_reference(false)
      end, { desc = "Prev reference (illuminate)" })
    end,
  },
}
