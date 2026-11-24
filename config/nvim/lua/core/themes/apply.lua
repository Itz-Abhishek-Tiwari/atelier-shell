-- ─────────────────────────────────────────────────────────────────────────────
-- core/themes/apply.lua
-- Centralized engine for theme loading, setup, and settings synchronization.
-- Handles in-memory setting updates, colorscheme execution, disk saving, and 
-- terminal (Ghostty) theme sync.
-- ─────────────────────────────────────────────────────────────────────────────

local M = {}

M.applying = false

-- ── Sync Ghostty Terminal Theme ───────────────────────────────────────────────
function M.sync_ghostty(ghostty_theme)
  if not ghostty_theme then return end
  local path = vim.fn.expand("~/.config/ghostty/config")
  if vim.fn.filereadable(path) ~= 1 then return end
  
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then return end
  
  local found = false
  for i, l in ipairs(lines) do
    if l:match("^theme%s*=") then
      lines[i] = "theme = " .. ghostty_theme
      found = true
      break
    end
  end
  if not found then
    table.insert(lines, "theme = " .. ghostty_theme)
  end
  
  local f = io.open(path, "w")
  if f then
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
  end
  
  -- Send command+shift+, to Ghostty to reload configuration on macOS
  if vim.fn.has("mac") == 1 then
    os.execute([[osascript -e 'tell application "System Events" to keystroke "," using {command down, shift down}']])
  end
end

-- ── Save Theme & Background to lua/settings.lua ──────────────────────────────
function M.save_to_disk(id, bg_val)
  local p = vim.fn.stdpath("config") .. "/lua/settings.lua"
  if vim.fn.filereadable(p) ~= 1 then return end
  
  local ok, lines = pcall(vim.fn.readfile, p)
  if not ok or not lines then return end

  -- Update theme option
  for i, l in ipairs(lines) do
    local pre, q = l:match("^(%s*theme%s*=%s*)([\"'])")
    if pre and q then
      lines[i] = pre .. q .. id .. q .. ","
      break
    end
  end

  -- Update background option
  for i, l in ipairs(lines) do
    local pre, q = l:match("^(%s*background%s*=%s*)([\"'])")
    if pre and q then
      lines[i] = pre .. q .. bg_val .. q .. ","
      break
    end
  end

  local f = io.open(p, "w")
  if f then
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
  end
end

-- ── Main Apply Function ──────────────────────────────────────────────────────
function M.apply(theme_id, opts)
  if M.applying then return true end
  M.applying = true

  opts = opts or {}
  local reg = require("core.themes.registry")
  
  -- Get the current settings proxy
  local ok_s, settings = pcall(require, "core.settings_loader")
  local s = ok_s and settings.get() or {}

  -- Find the theme entry in the registry
  local entry
  for _, t in ipairs(reg) do
    if t.id == theme_id then
      entry = t
      break
    end
  end

  if not entry then
    vim.notify("Theme not found in registry: " .. tostring(theme_id), vim.log.levels.ERROR)
    M.applying = false
    return false
  end

  -- Eagerly load the theme plugin via lazy.nvim first if it is lazy-loaded
  local has_lazy, lazy = pcall(require, "lazy")
  if has_lazy and entry.plugin then
    local plugin_name = entry.plugin:match("/([^/]+)$") or entry.plugin
    pcall(lazy.load, { plugins = { plugin_name } })
  end

  -- Determine background style
  local light = entry.light
  if type(light) == "function" then light = light() end   -- e.g. "atelier": follows the desktop
  local bg_val = light and "light" or "dark"

  -- Update settings in memory so any concurrent require("settings") gets the new values
  if s.ui then
    s.ui.theme = theme_id
    s.ui.background = bg_val
  else
    s.theme = theme_id
    s.background = bg_val
  end

  -- Run theme setup function if present
  if entry.setup then
    local transparent = false
    if s.ui and s.ui.transparent ~= nil then
      transparent = s.ui.transparent
    elseif s.transparent ~= nil then
      transparent = s.transparent
    end

    local ok_setup, err = pcall(entry.setup, transparent)
    if not ok_setup then
      vim.notify("Error in theme setup: " .. tostring(err), vim.log.levels.WARN)
    end
  end

  -- Load colorscheme
  local colorscheme_name = entry.colorscheme or entry.id
  vim.o.background = bg_val
  
  local ok_color, err_color = pcall(vim.cmd.colorscheme, colorscheme_name)
  if not ok_color then
    vim.notify("Error applying colorscheme '" .. colorscheme_name .. "': " .. tostring(err_color), vim.log.levels.ERROR)
    M.applying = false
    return false
  end

  -- Synchronize with Ghostty if specified
  if opts.sync_ghostty then
    pcall(M.sync_ghostty, entry.ghostty)
  end

  -- Persist settings to disk if specified
  if opts.save then
    pcall(M.save_to_disk, theme_id, bg_val)
  end

  M.applying = false
  return true
end

return M
