-- ==============================================================================
-- 🗂️  Language Registry — Single Source of Truth
-- ==============================================================================
-- Add a new language here and it automatically wires up:
--   • Mason tool installation
--   • LSP server via lspconfig
--   • Formatter via conform.nvim
--   • Linter via nvim-lint
--
-- Keys per language entry:
--   lsp        → lspconfig server name (string)
--   mason      → extra Mason packages beyond the LSP (table of strings)
--   formatters → conform.nvim formatter names (table of strings)
--   linters    → nvim-lint linter names (table of strings)
--   lsp_opts   → extra options passed to lspconfig.setup() (table, optional)
-- ==============================================================================

local M = {}

M.langs = {
  -- ── Web ──────────────────────────────────────────────────────────────────
  html = {
    lsp        = "html",
    mason      = {},
    formatters = { "prettier" },
    linters    = {},
    lsp_opts   = { filetypes = { "html", "htmldjango" } },
  },
  css = {
    lsp        = "cssls",
    mason      = {},
    formatters = { "prettier" },
    linters    = {},   -- stylelint requires project-local config; omit from global
    lsp_opts   = { filetypes = { "css", "scss", "less" } },
  },
  tailwindcss = {
    lsp        = "tailwindcss",
    mason      = { "tailwindcss-language-server", "prettier" },
    formatters = { "prettier" },
    linters    = {},
    lsp_opts   = {
      filetypes = {
        "html", "css", "scss", "javascript", "javascriptreact",
        "typescript", "typescriptreact", "vue", "svelte", "astro", "htmldjango",
      },
    },
  },
  javascript = {
    lsp        = "ts_ls",
    mason      = { "eslint_d", "prettier", "js-debug-adapter" },
    formatters = { "prettier" },
    linters    = { "eslint_d" },
  },
  typescript = {
    lsp        = "ts_ls",
    mason      = { "eslint_d", "prettier", "js-debug-adapter" },
    formatters = { "prettier" },
    linters    = { "eslint_d" },
  },
  javascriptreact = {
    lsp        = "ts_ls",
    mason      = {},
    formatters = { "prettier" },
    linters    = { "eslint_d" },
  },
  typescriptreact = {
    lsp        = "ts_ls",
    mason      = {},
    formatters = { "prettier" },
    linters    = { "eslint_d" },
  },
  json = {
    lsp        = "jsonls",
    mason      = {},
    formatters = { "prettier" },
    linters    = {},
  },
  yaml = {
    lsp        = "yamlls",
    mason      = {},
    formatters = { "prettier" },
    linters    = {},
  },
  vue = {
    lsp        = "volar",
    mason      = { "vue-language-server" },
    formatters = { "prettier" },
    linters    = { "eslint_d" },
  },
  prisma = {
    lsp        = "prismals",
    mason      = { "prettier" },
    formatters = { "prettier" },
    linters    = {},
  },

  -- ── Scripting / Config ───────────────────────────────────────────────────
  -- ── Desktop (quickshell-atelier) ─────────────────────────────────────────
  -- Qt's qmlls (system binary, not from Mason). Quickshell fills `.qmlls.ini` in the shell folder
  -- with its import paths, so Quickshell / qs.* types complete and resolve.
  qml = {
    lsp        = "qmlls",
    mason      = {},
    formatters = {},
    linters    = {},
    lsp_opts   = { cmd = { "/usr/lib/qt6/bin/qmlls" }, filetypes = { "qml", "qmljs" } },
  },
  lua = {
    lsp        = "lua_ls",
    mason      = { "stylua" },
    formatters = { "stylua" },
    linters    = {},   -- luacheck requires luarocks; lua_ls diagnostics cover this
    lsp_opts   = {
      settings = {
        Lua = {
          runtime     = { version = "LuaJIT" },
          diagnostics = { globals = { "vim", "hl" } },   -- hl: Hyprland's Lua config
          workspace   = {
            library         = vim.api.nvim_get_runtime_file("", true),
            checkThirdParty = false,
          },
          telemetry = { enable = false },
        },
      },
    },
  },
  bash = {
    lsp        = "bashls",
    mason      = { "shfmt", "shellcheck" },
    formatters = { "shfmt" },
    linters    = { "shellcheck" },
  },
  toml = {
    lsp        = "taplo",
    mason      = {},
    formatters = {},
    linters    = {},
  },

  -- ── Python ───────────────────────────────────────────────────────────────
  python = {
    lsp        = "pyright",
    mason      = { "black", "ruff" },
    formatters = { "black" },
    linters    = { "ruff" },
    lsp_opts   = {
      filetypes = { "python" },
      settings  = {
        python = {
          analysis = {
            typeCheckingMode       = "basic",
            autoSearchPaths        = true,
            useLibraryCodeForTypes = true,
          },
        },
      },
    },
  },

  -- ── Ruby ─────────────────────────────────────────────────────────────────
  ruby = {
    mason      = { "rubocop" },
    formatters = { "rubocop" },
    linters    = { "rubocop" },
  },

  -- ── Java ─────────────────────────────────────────────────────────────────
  java = {
    lsp        = "jdtls",
    mason      = { "google-java-format" },
    formatters = { "google-java-format" },
    linters    = {},
  },

  -- ── C / C++ ──────────────────────────────────────────────────────────────
  c = {
    lsp        = "clangd",
    mason      = { "clang-format" },
    formatters = { "clang-format" },
    linters    = {},
  },
  cpp = {
    lsp        = "clangd",
    mason      = { "clang-format" },
    formatters = { "clang-format" },
    linters    = {},
  },

  -- ── Go ───────────────────────────────────────────────────────────────────
  go = {
    lsp        = "gopls",
    mason      = { "gofumpt", "goimports-reviser", "golines" },
    formatters = { "gofumpt", "goimports-reviser", "golines" },
    linters    = {},
  },

  -- ── Rust ─────────────────────────────────────────────────────────────────
  rust = {
    lsp        = "rust_analyzer",
    mason      = {},
    formatters = {}, -- Rust-analyzer handles formatting via LSP fallback
    linters    = {},
  },

  -- ── Markup / Docs ────────────────────────────────────────────────────────
  markdown = {
    lsp        = "marksman",
    mason      = { "prettier", "markdownlint-cli2" },
    formatters = { "prettier" },
    -- nvim-lint linter name is "markdownlint" but binary comes from markdownlint-cli2
    linters    = { "markdownlint" },
  },

  -- ── Infrastructure ───────────────────────────────────────────────────────
  dockerfile = {
    lsp        = "dockerls",
    mason      = { "hadolint" },
    formatters = {},
    linters    = { "hadolint" },   -- Mason package name matches nvim-lint name
  },
  docker_compose = {
    lsp        = "docker_compose_language_service",
    mason      = {},
    formatters = {},
    linters    = {},
  },
  emmet = {
    lsp        = "emmet_language_server",
    mason      = {},
    formatters = {},
    linters    = {},
    lsp_opts   = {
      filetypes = {
        "css", "eruby", "html", "javascript", "javascriptreact",
        "less", "sass", "scss", "pug", "typescriptreact", "htmldjango",
      },
      init_options = {
        showAbbreviationSuggestions = true,
        showExpandedAbbreviation    = "always",
        showSuggestionsAsSnippets   = false,
      },
    },
  },
  eslint = {
    lsp        = "eslint",
    mason      = {},
    formatters = {},
    linters    = {},
    -- Tell the ESLint LSP to probe quietly: don't fire a warning when the
    -- eslint library is not found inside node_modules. This happens when
    -- opening JS/TS files in a project that hasn't run `npm install` yet,
    -- or that intentionally doesn't use ESLint.
    opts = {
      settings = {
        eslint = {
          -- "onIgnore" keeps ESLint working but won't error-alert for
          -- files inside .eslintignore. "probe" mode avoids the warning
          -- by simply not activating when no config file is found.
          probe = {
            "javascript", "javascriptreact",
            "typescript", "typescriptreact",
            "vue", "svelte",
          },
          -- Don't warn about missing eslint; just silently do nothing
          onIgnoredFiles        = "off",
          useESLintClass        = false,
          -- experimental: only validate if eslint config is present
          experimental          = { useFlatConfig = false },
          workingDirectory      = { mode = "auto" },
          -- If eslint is not in the project, server stays silent
          nodePath              = "",
          quiet                 = true,
        },
      },
    },
  },
  sql = {
    lsp        = "sqls",
    mason      = {},
    formatters = {},
    linters    = {},
  },
  tex = {
    lsp        = "texlab",
    mason      = {},
    formatters = {},
    linters    = {},
  },
}

-- ── Derived helpers (used by mason / conform / nvim-lint configs) ─────────────

--- Returns a deduplicated list of Mason packages to auto-install.
-- NOTE: This returns ONLY the extra tools (formatters, linters) from the
-- `mason` field. LSP servers are handled separately by mason-lspconfig,
-- which performs the lspconfig-name → mason-package-name translation.
function M.mason_tools()
  local seen = {}
  local tools = {}
  for _, def in pairs(M.langs) do
    for _, pkg in ipairs(def.mason or {}) do
      if not seen[pkg] then
        seen[pkg] = true
        table.insert(tools, pkg)
      end
    end
  end
  return tools
end

--- Returns conform.nvim formatters_by_ft table.
function M.formatters_by_ft()
  local result = {}
  for ft, def in pairs(M.langs) do
    if def.formatters and #def.formatters > 0 then
      result[ft] = def.formatters
    end
  end
  return result
end

--- Returns nvim-lint linters_by_ft table.
function M.linters_by_ft()
  local result = {}
  for ft, def in pairs(M.langs) do
    if def.linters and #def.linters > 0 then
      result[ft] = def.linters
    end
  end
  return result
end

--- Returns a list of { lsp_name, lsp_opts } for lspconfig setup.
function M.lsp_servers()
  local seen = {}
  local servers = {}
  for _, def in pairs(M.langs) do
    if def.lsp and not seen[def.lsp] then
      seen[def.lsp] = true
      table.insert(servers, { name = def.lsp, opts = def.lsp_opts or {} })
    end
  end
  return servers
end

return M
