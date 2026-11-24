-- nvim-lint: asynchronous linting — driven by lua/core/lang_registry.lua
return {
  {
    "mfussenegger/nvim-lint",
    -- The plugin is loaded lazily by the internal autocmd; no event needed here.
    lazy = true,
    config = function()
      local settings = require("core.settings_loader").get()

      -- Respect global toggle
      if settings.enable_linting == false then return end

      local lint     = require("lint")
      local registry = require("core.lang_registry")

      -- ── Wire linters_by_ft from the centralized registry ─────────────────
      lint.linters_by_ft = registry.linters_by_ft()

      -- ── Guard: skip linters whose binary isn't installed yet ─────────────
      local function safe_lint()
        local ft      = vim.bo.filetype
        local linters = lint.linters_by_ft[ft] or {}
        local available = vim.tbl_filter(function(name)
          local linter = lint.linters[name]
          if not linter then return false end
          local cmd = type(linter.cmd) == "function" and linter.cmd() or linter.cmd
          return vim.fn.executable(cmd) == 1
        end, linters)

        if #available > 0 then
          lint.try_lint(available)
        end
      end

      -- ── Auto-lint on relevant events ─────────────────────────────────────
      local lint_augroup = vim.api.nvim_create_augroup("NvimLint", { clear = true })

      local function register_autocmd()
        vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
          group    = lint_augroup,
          callback = function()
            if vim.bo.buftype == "" then safe_lint() end
          end,
        })
      end

      register_autocmd()

      -- ── Manual lint keymap ────────────────────────────────────────────────
      vim.keymap.set("n", "<leader>cl", function()
        safe_lint()
        vim.notify("Linting " .. vim.fn.expand("%:t"), vim.log.levels.INFO)
      end, { desc = "Lint current file" })

      -- ── Toggle linting per-session ────────────────────────────────────────
      local linting_enabled = true
      vim.keymap.set("n", "<leader>tl", function()
        linting_enabled = not linting_enabled
        vim.api.nvim_clear_autocmds({ group = lint_augroup })
        if linting_enabled then
          register_autocmd()
          vim.notify("Linting enabled", vim.log.levels.INFO)
        else
          vim.notify("Linting disabled", vim.log.levels.WARN)
        end
      end, { desc = "Toggle linting" })
    end,
  },
}
