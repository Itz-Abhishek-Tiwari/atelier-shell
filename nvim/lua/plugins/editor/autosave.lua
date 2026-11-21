-- Auto-Save plugin configuration
return {
  "okuuva/auto-save.nvim",
  cmd   = "ASToggle",
  event = { "InsertLeave", "TextChanged" },
  opts  = function()
    local settings = require("core.settings_loader").get()
    local enabled  = settings.auto_save

    return {
      enabled = enabled == true,
      trigger_events = {
        immediate_save       = { "BufLeave", "FocusLost" },
        defer_save           = { "InsertLeave", "TextChanged" },
        cancel_deferred_save = { "InsertEnter" },
      },
      condition = function(buf)
        local fn = vim.fn
        local utils = require("auto-save.utils.data")

        if fn.getbufvar(buf, "&modifiable") == 1 and
          utils.not_in(fn.getbufvar(buf, "&filetype"), { "snacks_picker_list", "snacks_picker_input", "harpoon", "gitcommit" }) then
          return true
        end
        return false
      end,
      write_all_buffers = false,
      debounce_delay    = 1000,
    }
  end,
}
