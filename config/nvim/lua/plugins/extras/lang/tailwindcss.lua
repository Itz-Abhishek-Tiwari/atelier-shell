-- Extra: Tailwind CSS & Modern Frontend Tooling
-- Enable in settings.lua → extras = { "plugins.extras.lang.tailwindcss" }

return {
  -- Tailwind tools (sorting, concealing, LSP integration)
  {
    "luckasRanarison/tailwind-tools.nvim",
    name = "tailwind-tools",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    ft = {
      "html", "css", "scss", "javascript", "javascriptreact",
      "typescript", "typescriptreact", "vue", "svelte", "astro",
    },
    opts = {
      document_color = {
        enabled = true,
        kind = "inline", -- "inline", "foreground", or "background"
        inline_symbol = "󰝤 ",
        debounce = 200,
      },
      conceal = {
        enabled = false,
        min_length = 10,
        symbol = "…",
      },
      custom_filetypes = { "htmldjango" },
    },
    config = function(_, opts)
      require("tailwind-tools").setup(opts)

      -- Keybindings for Tailwind Tools (using non-conflicting keymaps)
      vim.api.nvim_create_autocmd("FileType", {
        pattern = {
          "html", "css", "scss", "javascript", "javascriptreact",
          "typescript", "typescriptreact", "vue", "svelte", "astro",
        },
        callback = function(args)
          local bopts = { buffer = args.buf, silent = true }
          vim.keymap.set("n", "<leader>tC", "<cmd>TailwindConcealToggle<CR>", vim.tbl_extend("force", bopts, { desc = "Tailwind: Toggle Conceal" }))
          vim.keymap.set("n", "<leader>tS", "<cmd>TailwindSort<CR>",          vim.tbl_extend("force", bopts, { desc = "Tailwind: Sort Classes" }))
          vim.keymap.set("n", "<leader>tq", "<cmd>TailwindSortSelection<CR>", vim.tbl_extend("force", bopts, { desc = "Tailwind: Sort Selection" }))
        end,
      })
    end,
  },

  -- Tailwind Colorizer for nvim-cmp completion menu
  {
    "roobert/tailwindcss-colorizer-cmp.nvim",
    event = "InsertEnter",
    config = function()
      require("tailwindcss-colorizer-cmp").setup({
        color_square_width = 2,
      })
    end,
  },

  -- Ensure Treesitter CSS & HTML parsers are installed
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "css", "html", "tsx", "vue", "svelte" })
    end,
  },
}
