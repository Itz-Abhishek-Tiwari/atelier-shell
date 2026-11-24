-- Misc UI: icons, devicons, inline colors, markdown render, discord, code screenshot
return {
  -- Core icon sets
  {
    "nvim-tree/nvim-web-devicons",
    lazy = false,
    opts = {
      override_by_filename = {
        ["tailwind.config.js"]  = { icon = "󱏿", color = "#38bdf8", name = "Tailwind" },
        ["tailwind.config.ts"]  = { icon = "󱏿", color = "#38bdf8", name = "Tailwind" },
        ["tailwind.config.cjs"] = { icon = "󱏿", color = "#38bdf8", name = "Tailwind" },
        ["tailwind.config.mjs"] = { icon = "󱏿", color = "#38bdf8", name = "Tailwind" },
        ["postcss.config.js"]  = { icon = "󰌞", color = "#dd3a0a", name = "PostCSS" },
        ["postcss.config.cjs"] = { icon = "󰌞", color = "#dd3a0a", name = "PostCSS" },
      },
      override_by_extension = {
        ["astro"]  = { icon = "󱓞", color = "#ff5d01", name = "Astro" },
        ["svelte"] = { icon = "b", color = "#ff3e00", name = "Svelte" },
        ["prisma"] = { icon = "amp", color = "#5a67d8", name = "Prisma" },
      },
      default = true,
    },
  },
  { "echasnovski/mini.icons", version = false, lazy = false },


  -- Inline color highlighting
  {
    "brenoprata10/nvim-highlight-colors",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("nvim-highlight-colors").setup({
        render = "virtual",
        virtual_symbol = "▨",
        virtual_symbol_position = "inline",
        enable_tailwind = true, -- Also enables UnoCSS LSP color support
        enable_short_hex = true,
      })
    end,
  },

  -- Markdown rendering inside Neovim
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft           = { "markdown", "norg", "rmd", "org" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    opts         = {},
  },

  -- Code screenshot
  {
    "michaelrommel/nvim-silicon",
    lazy = true,
    cmd  = "Silicon",
    config = function()
      require("silicon").setup({
        font          = "JetBrainsMono NFM=15;Apple Color Emoji=15",
        theme         = "gruvbox-dark",
        to_clipboard  = true,
        background    = "#8D6479",
        output        = "~/Pictures/Screenshots/code.png",
        window_title  = function()
          return vim.fn.fnamemodify(
            vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()), ":t"
          )
        end,
      })
    end,
  },

  -- Discord rich presence
  {
    "IogaMaster/neocord",
    event = "VeryLazy",
    opts  = {
      logo            = "auto",
      main_image      = "language",
      show_time       = true,
      global_timer    = false,
      editing_text    = "Editing %s",
      file_explorer_text = "Browsing %s",
      workspace_text  = "Working on %s",
    },
  },

  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts  = {
      preset = "modern",
      plugins = { spelling = { enabled = true, suggestions = 20 } },
      win  = { border = "rounded" },
    },
    config = function(_, opts)
      local wk = require("which-key")
      wk.setup(opts)

      -- ── Register ALL <leader> group prefixes ──────────────────────────────
      wk.add({
        -- Top-level navigation / editor
        { "<leader>e",  group = "\u{f0645} Explorer" },
        { "<leader>x",  group = "\u{f05ad} Close Buffer" },
        { "<leader>n",  group = "\u{f03a6} Numbers / Notifications" },
        { "<leader>nh", desc = "Noice message history" },
        { "<leader>nd", desc = "Dismiss Noice messages" },
        { "<leader>nl", desc = "Show last message" },

        -- Find / Files / Telescope
        { "<leader>f",  group = "\u{f0349} Find" },
        { "<leader>ff", desc = "Find files" },
        { "<leader>fw", desc = "Live grep" },
        { "<leader>fb", desc = "Find buffers" },
        { "<leader>fh", desc = "Help tags" },
        { "<leader>fo", desc = "Recent files" },
        { "<leader>fz", desc = "Fuzzy in buffer" },

        -- Git
        { "<leader>g",  group = "\u{f02a2} Git" },
        { "<leader>gg", desc = "LazyGit" },
        { "<leader>gd", desc = "Diffview toggle" },
        { "<leader>gt", desc = "Git status" },
        { "<leader>gc", desc = "Git commits" },
        { "<leader>gT", desc = "Go: Test (Go files only)" },

        -- Code / LSP
        { "<leader>c",  group = "\u{f0171} Code / LSP" },
        { "<leader>ca", desc = "Code action" },
        { "<leader>cf", desc = "Format buffer" },
        { "<leader>cl", desc = "Lint file" },
        { "<leader>cn", desc = "Dismiss notification" },

        -- Rename / Refactor
        { "<leader>r",  group = "\u{f0455} Rename / Refactor" },
        { "<leader>ra", desc = "LSP rename" },

        -- Diagnostics
        { "<leader>d",  group = "\u{f00e4} Diagnostics / Debug" },
        { "<leader>ds", desc = "Diagnostics list" },
        { "<leader>db", desc = "DAP: Toggle breakpoint" },
        { "<leader>dc", desc = "DAP: Continue" },
        { "<leader>dso",desc = "DAP: Step over" },
        { "<leader>dsi",desc = "DAP: Step in" },
        { "<leader>dt", desc = "DAP: Terminate" },

        -- Format
        { "<leader>fm", desc = "LSP format" },

        -- Toggle / UI
        { "<leader>t",  group = "\u{f0521} Toggles" },
        { "<leader>tl", desc = "Toggle linting" },
        { "<leader>th", desc = "Select theme" },
        { "<leader>tn", desc = "Toggle line numbers" },
        { "<leader>tr", desc = "Toggle relative numbers" },
        { "<leader>tc", desc = "Toggle Treesitter context" },
        { "<leader>td", desc = "Toggle diagnostics" },

        -- Testing (neotest extra)
        { "<leader>T",  group = "\u{f0668} Tests" },
        { "<leader>Tr", desc = "Run nearest test" },
        { "<leader>Tf", desc = "Run file tests" },
        { "<leader>Ta", desc = "Run all tests" },
        { "<leader>Td", desc = "Debug nearest test" },
        { "<leader>Ts", desc = "Stop tests" },
        { "<leader>To", desc = "Test output" },
        { "<leader>TS", desc = "Test summary" },
        { "<leader>Tw", desc = "Watch file tests" },

        -- Database (sql extra)
        { "<leader>D",  group = "\u{f01bc} Database" },
        { "<leader>Du", desc = "DB: Toggle UI" },
        { "<leader>Da", desc = "DB: Add connection" },
        { "<leader>Df", desc = "DB: Find buffer" },

        -- SQLite Browser (nvim-dbee — always available)
        { "<leader>S",  group = "\u{f1c0} SQLite / DB" },
        { "<leader>So", desc = "DB: Open browser" },
        { "<leader>Sc", desc = "DB: Close browser" },
        { "<leader>St", desc = "DB: Toggle browser" },

        -- Session
        { "<leader>q",  group = "\u{f04ce} Session" },

        -- Zen Mode
        { "<leader>z",  desc = "Toggle Zen Mode" },

        -- Misc
        { "<leader>ma", desc = "Find marks" },
        { "<leader>op", desc = "Toggle Glow HUD Preview" },
        { "<leader>of", desc = "Toggle Glow Fullscreen" },
        { "<leader>sc", desc = "Screenshot code" },
        { "<leader>vs", desc = "Select Python venv" },
        { "<leader>/",  desc = "Toggle comment" },
      })
    end,
  },
}

