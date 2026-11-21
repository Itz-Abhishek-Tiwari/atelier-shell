-- LSP Configuration — driven by lua/core/lang_registry.lua
return {
  {
    "neovim/nvim-lspconfig",
    event        = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      local settings = require("core.settings_loader").get()

      -- ── Capabilities (boost with cmp-nvim-lsp) ───────────────────────────
      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = require("cmp_nvim_lsp").default_capabilities(capabilities)
      capabilities.textDocument.completion.completionItem = {
        documentationFormat     = { "markdown", "plaintext" },
        snippetSupport          = true,
        preselectSupport        = true,
        insertReplaceSupport    = true,
        labelDetailsSupport     = true,
        deprecatedSupport       = true,
        commitCharactersSupport = true,
        tagSupport              = { valueSet = { 1 } },
        resolveSupport          = {
          properties = { "documentation", "detail", "additionalTextEdits" },
        },
      }

      -- ── on_attach: keymaps set per-buffer when LSP attaches ──────────────
      local on_attach = function(_, bufnr)
        local map = vim.keymap.set
        local bufopts = { buffer = bufnr, silent = true }
        local e = function(tbl, extra)
          return vim.tbl_extend("force", tbl, extra)
        end

        -- Enable inlay hints if requested
        local enable_inlay = settings.enable_inlay_hints
        if enable_inlay == true and vim.lsp.inlay_hint then
          pcall(vim.lsp.inlay_hint.enable, true, { bufnr = bufnr })
        end

        map("n", "gD",         vim.lsp.buf.declaration,     e(bufopts, { desc = "LSP Declaration" }))
        map("n", "gd",         vim.lsp.buf.definition,      e(bufopts, { desc = "LSP Definition" }))
        map("n", "gi",         vim.lsp.buf.implementation,  e(bufopts, { desc = "LSP Implementation" }))
        map("n", "gr",         vim.lsp.buf.references,      e(bufopts, { desc = "LSP References" }))
        map("n", "K",          vim.lsp.buf.hover,           e(bufopts, { desc = "LSP Hover" }))
        map("n", "<leader>ca", vim.lsp.buf.code_action,     e(bufopts, { desc = "LSP Code action" }))
        map("n", "<leader>ra", vim.lsp.buf.rename,          e(bufopts, { desc = "LSP Rename" }))
        map("n", "<leader>fm", function()
          local ok, conform = pcall(require, "conform")
          if ok then
            conform.format({ async = true, lsp_format = "fallback" })
          else
            vim.lsp.buf.format({ async = true })
          end
        end, e(bufopts, { desc = "Format Buffer" }))
        map("n", "[d",  vim.diagnostic.goto_prev, e(bufopts, { desc = "Prev diagnostic" }))
        map("n", "]d",  vim.diagnostic.goto_next, e(bufopts, { desc = "Next diagnostic" }))
      end

      -- ── Diagnostic display ─────────────────────────────────────────────────
      -- Configured globally in lua/core/options.lua (single source of truth).
      -- Nothing to set here.

      local lspconfig = require("lspconfig")
      local registry  = require("core.lang_registry")

      -- ── Boot all servers from the lang registry ───────────────────────────
      for _, srv in ipairs(registry.lsp_servers()) do
        local server_opts = vim.tbl_deep_extend("force", {
          on_attach    = on_attach,
          capabilities = capabilities,
        }, srv.opts or {})
        -- Neovim 0.11+: vim.lsp.config + vim.lsp.enable only. mason-lspconfig v2 also calls
        -- vim.lsp.enable() for installed servers, so the old lspconfig.setup() on top started
        -- every server twice (two pyright / ts_ls per buffer), and servers it auto-enabled ran
        -- with their defaults instead of these options (qmlls from PATH).
        if vim.lsp.config and vim.lsp.enable then
          vim.lsp.config(srv.name, server_opts)
          vim.lsp.enable(srv.name)
        else
          lspconfig[srv.name].setup(server_opts)
        end
      end

      -- ── Boot custom user servers from settings.lua ───────────────────────
      for _, srv_name in ipairs(settings.lsp_servers or {}) do
        local is_in_registry = false
        for _, r_srv in ipairs(registry.lsp_servers()) do
          if r_srv.name == srv_name then is_in_registry = true break end
        end
        if not is_in_registry and lspconfig[srv_name] then
          local o = { on_attach = on_attach, capabilities = capabilities }
          if vim.lsp.config and vim.lsp.enable then
            vim.lsp.config(srv_name, o)
            vim.lsp.enable(srv_name)
          else
            lspconfig[srv_name].setup(o)
          end
        end
      end
    end,
  },
}
