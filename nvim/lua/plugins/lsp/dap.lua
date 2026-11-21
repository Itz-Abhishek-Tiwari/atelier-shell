-- DAP: Debug Adapter Protocol (Python + Node.js/TypeScript)
return {
  -- ── Core DAP engine ───────────────────────────────────────────────────────
  {
    "mfussenegger/nvim-dap",
    lazy = true,
    keys = {
      { "<leader>db",  "<cmd>DapToggleBreakpoint<CR>", desc = "DAP: Toggle breakpoint" },
      { "<leader>dc",  "<cmd>DapContinue<CR>",          desc = "DAP: Continue"          },
      { "<leader>dso", "<cmd>DapStepOver<CR>",           desc = "DAP: Step over"         },
      { "<leader>dsi", "<cmd>DapStepIn<CR>",             desc = "DAP: Step in"           },
      { "<leader>dt",  "<cmd>DapTerminate<CR>",          desc = "DAP: Terminate"         },
    },
    config = function()
      local dap = require("dap")

      -- ── Node.js / TypeScript adapter (js-debug-adapter via Mason) ─────────
      if not dap.adapters["pwa-node"] then
        dap.adapters["pwa-node"] = {
          type = "server",
          host = "localhost",
          port = "${port}",
          executable = {
            command = "node",
            args = {
              vim.fn.stdpath("data") .. "/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js",
              "${port}",
            },
          },
        }
      end

      for _, language in ipairs({ "typescript", "javascript", "typescriptreact", "javascriptreact" }) do
        if not dap.configurations[language] then
          dap.configurations[language] = {
            {
              type    = "pwa-node",
              request = "launch",
              name    = "Launch Current File (Node.js)",
              program = "${file}",
              cwd     = "${workspaceFolder}",
            },
            {
              type      = "pwa-node",
              request   = "attach",
              name      = "Attach to Node Process",
              processId = require("dap.utils").pick_process,
              cwd       = "${workspaceFolder}",
            },
            {
              type                   = "pwa-node",
              request                = "launch",
              name                   = "Debug Express App (npm run dev)",
              runtimeExecutable      = "npm",
              runtimeArgs            = { "run", "dev" },
              rootPath               = "${workspaceFolder}",
              cwd                    = "${workspaceFolder}",
              console                = "integratedTerminal",
              internalConsoleOptions = "neverOpen",
            },
          }
        end
      end
    end,
  },

  -- ── DAP UI ────────────────────────────────────────────────────────────────
  { "nvim-neotest/nvim-nio", lazy = true },
  {
    "rcarriga/nvim-dap-ui",
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    config = function()
      local dap   = require("dap")
      local dapui = require("dapui")
      dapui.setup()
      dap.listeners.after.event_initialized["dapui_config"]  = function() dapui.open()  end
      dap.listeners.before.event_terminated["dapui_config"]  = function() dapui.close() end
      dap.listeners.before.event_exited["dapui_config"]      = function() dapui.close() end
    end,
  },

  -- ── Python DAP (debugpy) ──────────────────────────────────────────────────
  {
    "mfussenegger/nvim-dap-python",
    ft           = "python",
    dependencies = { "mfussenegger/nvim-dap", "rcarriga/nvim-dap-ui" },
    config       = function()
      local debugpy = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"
      require("dap-python").setup(debugpy)
    end,
  },
}
