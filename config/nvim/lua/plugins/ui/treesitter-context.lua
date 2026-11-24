-- Treesitter Context: Sticky headers for functions and classes
return {
  {
    "nvim-treesitter/nvim-treesitter-context",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      enable = true,
      max_lines = 3,            -- How many lines the window should span. Values <= 0 mean no limit.
      min_window_height = 0,    -- Minimum editor window height to enable context. Values <= 0 mean no limit.
      line_numbers = true,
      multiline_threshold = 20, -- Maximum number of lines to show for a single context
      trim_scope = "outer",     -- Which context lines to discard if `max_lines` is exceeded. Choices: 'inner', 'outer'
      mode = "cursor",          -- Line used to calculate context. Choices: 'cursor', 'topline'
      separator = nil,          -- No separator rule — blends as an elevated panel
      zindex = 20,              -- The Z-index of the context window
      on_attach = nil,          -- (fun(buf: integer): boolean) return false to disable attaching
    },
    config = function(_, opts)
      require("treesitter-context").setup(opts)

      -- Derive a slightly elevated bg from the float/pmenu background
      local function apply_context_hls()
        local function get_bg(name)
          local ok2, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
          return ok2 and hl and hl.bg or nil
        end
        -- Prefer Pmenu bg (panel feel), fall back to CursorLine, then Normal
        local ctx_bg = get_bg("Pmenu") or get_bg("CursorLine") or get_bg("Normal")
        local num_fg = (function()
          local ok2, hl = pcall(vim.api.nvim_get_hl, 0, { name = "CursorLineNr", link = false })
          return ok2 and hl and hl.fg or nil
        end)()

        if ctx_bg then
          vim.api.nvim_set_hl(0, "TreesitterContext",           { bg = ctx_bg })
          vim.api.nvim_set_hl(0, "TreesitterContextLineNumber", { bg = ctx_bg, fg = num_fg, bold = true })
        else
          vim.api.nvim_set_hl(0, "TreesitterContext",           { link = "CursorLine" })
          vim.api.nvim_set_hl(0, "TreesitterContextLineNumber", { link = "CursorLineNr" })
        end
        -- Separator invisible (separator = nil disables it anyway)
        vim.api.nvim_set_hl(0, "TreesitterContextSeparator", { link = "WinSeparator" })
        -- The bottom line of the context block
        vim.api.nvim_set_hl(0, "TreesitterContextBottom",    { underline = false })
      end

      apply_context_hls()
      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern  = "*",
        callback = apply_context_hls,
      })
    end,
  },
}
