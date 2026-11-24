-- plugins/ui/hlchunk.lua
-- shellRaining/hlchunk.nvim: animated rainbow chunk brackets.
-- Adds ┌─…─► corner+arrow decorations around the current code block
-- while Snacks indent handles the lightweight thin guide lines.
-- The two plugins complement each other: Snacks = always-visible grid,
-- hlchunk = dynamic scope highlight on the current block only.
return {
  {
    "shellRaining/hlchunk.nvim",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      -- ── Chunk (scope bracket around current block) ──────────────────────
      chunk = {
        enable   = true,
        priority = 15,
        style    = {
          { fg = "#806d9e" },   -- default purple when no highlight match
          { fg = "#c21f30" },   -- error/mismatch indicator colour
        },
        use_treesitter = true,  -- use treesitter for accurate block detection
        chars = {
          horizontal_line  = "─",
          vertical_line    = "│",
          left_top         = "╭",
          left_bottom      = "╰",
          right_arrow      = "▶",
        },
        textobject       = "",  -- no text-object key (conflicts with other plugins)
        max_file_size    = 1024 * 1024,   -- 1 MB safety cap
        error_sign       = true,
        -- Animate the chunk appearance for a premium feel
        duration         = 150,
        easing           = "linear",
      },

      -- ── Indent (lightweight guide lines, complement Snacks) ─────────────
      -- We keep this DISABLED: Snacks indent already handles guide lines.
      -- Enabling both causes visual duplication.
      indent = {
        enable = false,
      },

      -- ── Line numbers: highlight the chunk's start/end line numbers ───────
      line_num = {
        enable   = true,
        priority = 10,
        style    = "#806d9e",   -- match chunk colour
        use_treesitter = true,
      },

      -- ── Blank: highlight blank lines inside the chunk ────────────────────
      blank = {
        enable = false,   -- keep clean; too noisy with blank lines highlighted
      },
    },
  },
}
