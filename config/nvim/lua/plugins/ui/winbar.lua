-- plugins/ui/winbar.lua
-- Per-window winbar: shows navic breadcrumbs OR the file path when LSP
-- breadcrumbs aren't available. Looks exactly like VS Code's path bar.
return {
  {
    -- winbar is built-in — no extra plugin needed.
    -- This spec is a no-op plugin entry that only runs the setup autocmd.
    "nvim-lua/plenary.nvim",  -- always loaded; we piggyback its event
    event = "VeryLazy",
    config = function()
      -- ── Helpers ─────────────────────────────────────────────────────────
      local function is_special(winid)
        local bufid = vim.api.nvim_win_get_buf(winid)
        local ft    = vim.bo[bufid].filetype
        local bt    = vim.bo[bufid].buftype
        local skip  = {
          "dashboard", "alpha", "lazy", "mason", "neo-tree",
          "NvimTree", "noice", "toggleterm", "snacks_terminal",
          "snacks_picker_list", "snacks_picker_input", "snacks_picker_preview",
          "DiffviewFiles", "DiffviewFileHistory", "help", "qf", "startify",
        }
        for _, s in ipairs(skip) do
          if ft == s then return true end
        end
        return bt ~= "" and bt ~= "acwrite"
      end

      local function get_winbar()
        local winid = vim.g.statusline_winid or vim.api.nvim_get_current_win()

        -- Don't render in special windows
        if is_special(winid) then return "" end

        -- Float check
        local cfg = vim.api.nvim_win_get_config(winid)
        if cfg.relative ~= "" then return "" end

        -- Try navic breadcrumbs first
        local ok, navic = pcall(require, "nvim-navic")
        if ok and navic.is_available() then
          local location = navic.get_location()
          if location ~= "" then
            return "%#NavicSeparator#  %#NavicText#" .. location
          end
        end

        -- Fallback: show file path relative to cwd
        local full = vim.fn.expand("%:p")
        if full == "" then return "" end
        local cwd  = vim.fn.getcwd() .. "/"
        local rel  = full:gsub("^" .. vim.pesc(cwd), "")

        -- Split path into parts and join with a separator
        local parts = {}
        for part in rel:gmatch("[^/]+") do
          table.insert(parts, part)
        end
        local sep = " %#WinBarSep#❯%#WinBar# "
        return "%#WinBarPath#  " .. table.concat(parts, sep)
      end

      -- ── Apply winbar to every normal window ─────────────────────────────
      local function set_winbar()
        for _, winid in ipairs(vim.api.nvim_list_wins()) do
          if not is_special(winid) then
            local cfg = vim.api.nvim_win_get_config(winid)
            if cfg.relative == "" then
              vim.wo[winid].winbar = "%{%v:lua.NamiWinbar()%}"
            end
          end
        end
      end

      -- Expose as a global so %{%v:lua...%} can call it
      _G.NamiWinbar = get_winbar

      -- ── Highlight groups ─────────────────────────────────────────────────
      local function set_winbar_hls()
        local function get_fg(name)
          local ok2, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
          return ok2 and hl and hl.fg or nil
        end
        local function get_bg(name)
          local ok2, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
          return ok2 and hl and hl.bg or nil
        end

        local bar_bg   = get_bg("TabLine") or get_bg("StatusLine")
        local muted_fg = get_fg("Comment")
        local sep_fg   = get_fg("NonText") or muted_fg
        local file_fg  = get_fg("Normal")

        vim.api.nvim_set_hl(0, "WinBar",     { bg = bar_bg, fg = file_fg, bold = false })
        vim.api.nvim_set_hl(0, "WinBarNC",   { bg = bar_bg, fg = muted_fg, bold = false })
        vim.api.nvim_set_hl(0, "WinBarPath", { bg = bar_bg, fg = muted_fg })
        vim.api.nvim_set_hl(0, "WinBarSep",  { bg = bar_bg, fg = sep_fg })
      end

      set_winbar_hls()
      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "*", callback = set_winbar_hls,
      })

      -- Set on window enter/file open
      vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "LspAttach" }, {
        callback = set_winbar,
      })
      set_winbar()
    end,
  },
}
