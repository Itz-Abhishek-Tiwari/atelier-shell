-- plugins/ui/fidget.lua
-- Fidget: LSP progress spinner in the bottom-right corner.
-- Much lighter than Noice's mini view for progress; never steals focus.
return {
  {
    "j-hui/fidget.nvim",
    event = "LspAttach",
    opts = {
      -- ── Progress display ──────────────────────────────────────────────────
      progress = {
        poll_rate         = 0,      -- 0 = use autocmd (reactive, not polling)
        suppress_on_insert = true,  -- don't show while typing
        ignore_done_already = true,
        ignore_empty_message = true,

        -- Spinner shown while task is running
        display = {
          render_limit  = 4,        -- max concurrent tasks shown
          done_ttl      = 1,        -- seconds to show completed tasks
          done_icon     = "✓",
          done_style    = "Constant",
          progress_ttl  = math.huge,
          progress_icon = { pattern = "dots", period = 1 },
          progress_style = "WarningMsg",
          group_style   = "Title",
          icon_style    = "Question",
          priority      = 30,
          skip_history  = true,
          format_message = function(task_progress, task_manager)
            return task_progress.message or ""
          end,
          format_group_name = function(group)
            return tostring(group)
          end,
          overrides = {
            -- Silence rust-analyzer's noisy "Indexing…" messages
            rust_analyzer = { name = "rust-analyzer" },
          },
        },

        ignore = {
          "null-ls",    -- null-ls fires spurious progress events
        },
      },

      -- ── Notification window ───────────────────────────────────────────────
      notification = {
        poll_rate        = 10,
        filter           = vim.log.levels.INFO,
        history_size     = 128,
        override_vim_notify = false,   -- Snacks handles vim.notify

        view = {
          stack_upwards = true,        -- stack grows upward from bottom-right
          icon_separator = " ",
          group_separator = "  ",
          group_separator_hl = "Comment",
          render_message = nil,  -- fidget default
        },

        window = {
          normal_hl   = "Comment",
          winblend    = 60,           -- translucent background
          border      = "none",
          zindex      = 45,
          max_width   = 0,
          max_height  = 0,
          x_padding   = 1,
          y_padding   = 0,
          align       = "bottom",
          relative    = "editor",
        },
      },


      logger = {
        level    = vim.log.levels.WARN,
        max_size = 10000,
        float_precision = 0.01,
        path     = string.format("%s/fidget.nvim.log", vim.fn.stdpath("cache")),
      },
    },
  },
}
