-- Mason: LSP/formatter/linter installer
-- Tools are automatically derived from lua/core/lang_registry.lua
return {
  {
    "williamboman/mason.nvim",
    cmd    = { "Mason", "MasonInstall", "MasonUpdate" },
    config = function()
      require("mason").setup({
        ui = {
          icons = {
            package_installed   = "✓",
            package_pending     = "➜",
            package_uninstalled = "✗",
          },
          border = "rounded",
        },
      })
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    lazy         = true,
    dependencies = { "williamboman/mason.nvim" },
    config       = function()
      local registry = require("core.lang_registry")
      local settings = require("core.settings_loader").get()

      -- Collect only valid LSP server names for mason-lspconfig
      local lsp_servers = {}
      local seen = {}
      local mason_lspconfig = require("mason-lspconfig")
      local available_servers = {}
      if mason_lspconfig.get_available_servers then
        for _, name in ipairs(mason_lspconfig.get_available_servers()) do
          available_servers[name] = true
        end
      end

      local function is_valid(name)
        if not next(available_servers) then return true end
        return available_servers[name] == true
      end

      -- Name alias map for lspconfig server names -> mason-lspconfig names
      local lsp_name_map = {
        volar = "vue_ls",
      }

      for _, srv in ipairs(registry.lsp_servers()) do
        local name = lsp_name_map[srv.name] or srv.name
        -- a server with an absolute cmd is a system binary (e.g. /usr/lib/qt6/bin/qmlls):
        -- Mason's copy would shadow it on PATH (its qmlls needs libodbc and crashes)
        local cmd = srv.opts and srv.opts.cmd
        local system = type(cmd) == "table" and type(cmd[1]) == "string" and cmd[1]:sub(1, 1) == "/"
        if not seen[name] and not system and is_valid(name) then
          seen[name] = true
          table.insert(lsp_servers, name)
        end
      end

      -- Add user's custom LSPs from settings.lua
      for _, raw_name in ipairs(settings.lsp_servers or {}) do
        local name = lsp_name_map[raw_name] or raw_name
        if not seen[name] and is_valid(name) then
          seen[name] = true
          table.insert(lsp_servers, name)
        end
      end

      require("mason-lspconfig").setup({
        ensure_installed   = lsp_servers,
        automatic_installation = true,
      })
    end,
  },

  -- mason-tool-installer: installs formatters/linters that aren't LSP servers
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    cmd   = { "MasonToolsInstall", "MasonToolsUpdate", "MasonToolsClean" },
    event = "VeryLazy",
    dependencies = { "williamboman/mason.nvim" },
    config       = function()
      local registry = require("core.lang_registry")
      local settings = require("core.settings_loader").get()
      
      local tools = registry.mason_tools()
      local seen_tools = {}
      for _, t in ipairs(tools) do seen_tools[t] = true end
      
      -- Add user's custom tools from settings.lua
      for _, name in ipairs(settings.mason_tools or {}) do
        if not seen_tools[name] then
          seen_tools[name] = true
          table.insert(tools, name)
        end
      end

      require("mason-tool-installer").setup({
        ensure_installed = tools,
        auto_update      = false,
        run_on_start     = true,
      })
    end,
  },
}
