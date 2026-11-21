-- plugins/editor/flash.lua
-- flash.nvim: jump anywhere in the visible buffer with 1-2 keystrokes.
-- Replaces hop.nvim / leap.nvim with a single, zero-config plugin.
return {
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {
      -- ── Core behaviour ────────────────────────────────────────────────────
      labels = "asdfghjklqwertyuiopzxcvbnm",
      search = {
        multi_window = true,   -- search across all visible windows
        forward      = true,
        wrap         = true,
        mode         = "exact",   -- "exact" | "search" | "fuzzy"
        incremental   = false,
      },

      jump = {
        jumplist = true,   -- push to jumplist so <C-o> goes back
        pos      = "start",
        history  = false,
        register = false,
        nohlsearch = true,  -- clear search highlight after jumping
        autojump   = false, -- don't auto-jump when only one match
      },

      label = {
        uppercase    = false,
        exclude      = "",
        current      = true,
        after        = true,
        before       = false,
        style        = "overlay",
        reuse        = "lowercase",
        distance     = true,
        min_pattern_length = 0,
        rainbow      = { enabled = true, shade = 5 },  -- rainbow label colours
        format       = function(opts)
          return { { opts.match.label, opts.hl_group } }
        end,
      },

      highlight = {
        backdrop   = true,   -- dim everything except matches (very premium)
        matches    = true,
        priority   = 5000,
        groups = {
          match       = "FlashMatch",
          current     = "FlashCurrent",
          backdrop    = "FlashBackdrop",
          label       = "FlashLabel",
        },
      },

      -- ── Modes ─────────────────────────────────────────────────────────────
      modes = {
        -- f/F/t/T: enhanced native motions with flash labels
        char = {
          enabled   = true,
          config    = function(opts)
            opts.autojump = #require("flash").pattern() == 1
          end,
          highlight = { backdrop = false },
          jump      = { register = false },
          keys = { "f", "F", "t", "T", ";", "," },
          char_actions = function(motion)
            return {
              [";"] = "next",
              [","] = "prev",
            }
          end,
          search = { wrap = false },
          label = { exclude = "hjkliardc" },
        },
        -- search: auto-label / show labels while in / or ?
        search = { enabled = true },
        -- treesitter: select a treesitter node
        treesitter = { labels = "abcdefghijklmnopqrstuvwxyz" },
        treesitter_search = {
          jump = { pos = "range", autojump = false },
          search = { multi_window = true, wrap = true, incremental = false },
          remote_op = { restore = true, motion = true },
          label = { before = true, after = true, style = "inline" },
        },
        remote = {
          remote_op = { restore = true, motion = true },
        },
      },

      prompt = {
        enabled = true,
        prefix  = { { "⚡", "FlashPromptIcon" } },
        win_config = {
          relative = "editor",
          width    = 1,          -- 1 column full-width
          height   = 1,
          row      = -1,
          col      = 0,
          zindex   = 1000,
        },
      },
    },

    keys = {
      -- s: flash jump (forward/back)
      { "s",     mode = { "n", "x", "o" }, function() require("flash").jump() end,              desc = "Flash Jump" },
      -- S: treesitter select
      { "S",     mode = { "n", "x", "o" }, function() require("flash").treesitter() end,        desc = "Flash Treesitter" },
      -- r: remote flash (operator pending)
      { "r",     mode = "o",               function() require("flash").remote() end,             desc = "Flash Remote" },
      -- R: treesitter search (operator pending)
      { "R",     mode = { "o", "x" },      function() require("flash").treesitter_search() end, desc = "Flash Treesitter Search" },
      -- <C-s>: toggle flash in search (/)
      { "<c-s>", mode = "c",               function() require("flash").toggle() end,             desc = "Toggle Flash Search" },
    },
  },
}
