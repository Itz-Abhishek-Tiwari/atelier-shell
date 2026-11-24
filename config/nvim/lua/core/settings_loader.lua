local M = {}

-- ── Wrap raw settings table with a smart proxy ───────────────────────────────
-- Supports flat key access (settings.theme), nested access (settings.ui.theme),
-- and backwards-compat aliases for renamed keys.
function M.wrap_settings(raw_settings)
  return setmetatable(raw_settings, {
    __index = function(self, key)
      -- 1. Key exists directly on the top-level table
      if rawget(self, key) ~= nil then
        return rawget(self, key)
      end

      -- 2. Backwards-compat aliases for renamed / flattened keys
      local aliases = {
        show_hidden_files      = self.explorer  and self.explorer.show_hidden,
        file_explorer_position = self.explorer  and self.explorer.position,
        enable_linting         = self.linting   and self.linting.enable,
        enable_project_config  = self.project   and self.project.enable_config,
        lsp_servers            = self.custom_tools and self.custom_tools.lsp_servers,
        mason_tools            = self.custom_tools and self.custom_tools.mason_tools,
        picker_layout          = self.ui        and self.ui.picker and self.ui.picker.layout,
        picker_width           = self.ui        and self.ui.picker and self.ui.picker.width,
        picker_height          = self.ui        and self.ui.picker and self.ui.picker.height,
        menu_border            = self.ui        and self.ui.picker and self.ui.picker.border,
        neovide_transparency   = self.ui        and self.ui.neovide and self.ui.neovide.transparency,
        line_height            = self.ui        and self.ui.neovide and self.ui.neovide.line_height,
      }
      if aliases[key] ~= nil then
        return aliases[key]
      end

      -- 3. Walk nested groups to find an identically-named leaf key
      local excluded = { extras = true, lsp_servers = true, mason_tools = true }
      local function find_key(t, k)
        if type(t) ~= "table" then return nil end
        if rawget(t, k) ~= nil then return rawget(t, k) end
        for sub_key, v in pairs(t) do
          if type(v) == "table" and not excluded[sub_key] then
            local res = find_key(v, k)
            if res ~= nil then return res end
          end
        end
      end
      return find_key(self, key)
    end,

    __newindex = function(self, key, value)
      -- Writes to "theme" always update the canonical nested location
      if key == "theme" then
        self.ui.theme = value
      else
        rawset(self, key, value)
      end
    end,
  })
end

-- ── Load (or reload) settings.lua ────────────────────────────────────────────
function M.load()
  package.loaded["settings"] = nil
  local ok, raw = pcall(require, "settings")
  if not ok then raw = {} end
  local wrapped = M.wrap_settings(raw)
  package.loaded["settings"] = wrapped
  return wrapped
end

-- ── Retrieve the already-loaded (or fresh-loaded) settings proxy ─────────────
function M.get()
  return package.loaded["settings"] or M.load()
end

-- ── Apply settings live (called on hot-reload of settings.lua) ───────────────
function M.apply()
  local s = M.load()

  -- 1. Re-apply colorscheme ─────────────────────────────────────────────────
  local theme_id = s.ui and s.ui.theme or s.theme
  if theme_id then
    pcall(function()
      require("core.themes.apply").apply(theme_id)
    end)
  end

  -- 2. Live-update editor options ───────────────────────────────────────────
  if s.show_line_numbers    ~= nil then vim.wo.number         = s.show_line_numbers    end
  if s.relative_line_numbers ~= nil then vim.wo.relativenumber = s.relative_line_numbers end
  if s.wrap_lines            ~= nil then vim.wo.wrap           = s.wrap_lines            end
  if s.color_column               then vim.wo.colorcolumn    = s.color_column            end
  if s.highlight_current_line ~= nil then vim.wo.cursorline   = s.highlight_current_line end
  if s.tab_size and s.tab_size > 0 then
    vim.bo.tabstop     = s.tab_size
    vim.bo.shiftwidth  = s.tab_size
    vim.bo.softtabstop = s.tab_size
  end
  if s.scrolloff  ~= nil then vim.o.scrolloff  = s.scrolloff  end
  if s.mouse_support ~= nil then
    vim.o.mouse = s.mouse_support and "a" or ""
  end
  if s.split_below  ~= nil then vim.o.splitbelow = s.split_below  end
  if s.split_right  ~= nil then vim.o.splitright  = s.split_right  end
  if s.ignore_case_search ~= nil then
    vim.o.ignorecase = s.ignore_case_search
    vim.o.smartcase  = s.ignore_case_search
  end

  local cmdheight = s.ui and s.ui.cmdheight or s.cmdheight
  if cmdheight then vim.o.cmdheight = cmdheight end

  -- 3. Auto-save toggle ─────────────────────────────────────────────────────
  if s.auto_save ~= nil then
    pcall(vim.cmd, s.auto_save and "ASTurnOn" or "ASTurnOff")
  end

  -- 4. LSP settings ─────────────────────────────────────────────────────────
  if vim.lsp.inlay_hint and s.enable_inlay_hints ~= nil then
    pcall(vim.lsp.inlay_hint.enable, s.enable_inlay_hints == true)
  end
  if s.show_inline_errors ~= nil then
    vim.diagnostic.config({
      virtual_text = s.show_inline_errors == true and {
        severity = { min = vim.diagnostic.severity.HINT },
      } or false,
    })
  end

  -- 5. Snacks live-updates ───────────────────────────────────────────────────
  local has_snacks, snacks = pcall(require, "snacks")
  if has_snacks and snacks.config then
    local function toggle_snacks_feature(feature, enabled, enable_fn, disable_fn)
      if not snacks.config[feature] then return end
      snacks.config[feature].enabled = enabled
      if enabled then
        pcall(enable_fn)
      else
        pcall(disable_fn)
      end
    end

    local ui = s.ui or {}
    toggle_snacks_feature("dim",    ui.dim_inactive == true,
      function() if snacks.dim    then snacks.dim.enable()    end end,
      function() if snacks.dim    then snacks.dim.disable()   end end)

    toggle_snacks_feature("indent", ui.show_indent_guides ~= false,
      function() if snacks.indent then snacks.indent.enable()  end end,
      function() if snacks.indent then snacks.indent.disable() end end)

    toggle_snacks_feature("scroll", ui.smooth_scroll ~= false,
      function() if snacks.scroll then snacks.scroll.enable()  end end,
      function() if snacks.scroll then snacks.scroll.disable() end end)

    -- Reload picker config
    if snacks.config.picker then
      package.loaded["core.snacks.picker"] = nil
      local ok_p, new_cfg = pcall(require, "core.snacks.picker")
      if ok_p then
        snacks.config.picker = vim.tbl_deep_extend("force", snacks.config.picker, new_cfg)
      end
    end
  end

  vim.notify("Settings reloaded 🚀", vim.log.levels.INFO, { title = "Config" })
end

return M
