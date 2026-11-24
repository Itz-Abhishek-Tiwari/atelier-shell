-- Treesitter: syntax highlighting and indentation parser configuration
return {
  {
    "nvim-treesitter/nvim-treesitter",
    event  = { "BufReadPost", "BufNewFile", "VeryLazy" },
    build  = ":TSUpdate",
    config = function(_, opts)
      -- Old `master` branch API
      local ok, configs = pcall(require, "nvim-treesitter.configs")
      if ok then
        configs.setup(opts)
        return
      end

      -- `main` branch (what lazy-lock pins): no configs module. Parsers are built with the
      -- `tree-sitter` CLI into stdpath("data")/site, and highlighting is started per buffer.
      local ts = require("nvim-treesitter")
      ts.setup({ install_dir = vim.fn.stdpath("data") .. "/site" })
      if vim.fn.executable("tree-sitter") == 1 then
        -- Neovim 0.12 bundles c, lua, markdown, query, vim, vimdoc (with matching queries):
        -- never build our own copies of those, they would shadow the bundled ones.
        local bundled = { c = true, lua = true, markdown = true, markdown_inline = true,
                          query = true, vim = true, vimdoc = true }
        local want = vim.tbl_filter(function(l) return not bundled[l] end, opts.ensure_installed)
        local installed = {}
        for _, l in ipairs(ts.get_installed and ts.get_installed() or {}) do installed[l] = true end
        local missing = vim.tbl_filter(function(l) return not installed[l] end, want)
        if #missing > 0 then pcall(ts.install, missing) end
      else
        vim.schedule(function()
          vim.notify("nvim-treesitter: install the `tree-sitter` CLI (pacman -S tree-sitter-cli) "
            .. "to build parsers", vim.log.levels.WARN, { title = "Treesitter" })
        end)
      end

      local regex_too = {}
      for _, l in ipairs(opts.highlight.additional_vim_regex_highlighting or {}) do regex_too[l] = true end
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("NamiTreesitter", { clear = true }),
        callback = function(ev)
          if not pcall(vim.treesitter.start, ev.buf) then return end   -- no parser for this filetype
          if regex_too[vim.bo[ev.buf].filetype] then vim.bo[ev.buf].syntax = "on" end
          if opts.indent.enable then
            vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
    opts = {
      ensure_installed = {
        "vim", "lua", "vimdoc",
        "html", "css", "scss",
        "javascript", "typescript", "tsx", "jsdoc",
        "json", "jsonc", "json5",
        "prisma", "sql", "http",
        "python",
        "htmldjango",
        "markdown", "markdown_inline",
        "regex",
        "bash",
        "yaml", "toml",
        "dockerfile",
        "vue", "svelte",
        "latex", "norg", "typst",
        "qmljs", "hyprlang", "ini",   -- desktop: Quickshell QML, Hyprland, misc configs
      },
      highlight = {
        enable                            = true,
        additional_vim_regex_highlighting = { "html" },
      },
      indent = { enable = true },
    },
  },
}
