-- ─────────────────────────────────────────────────────────────────────────────
-- core/themes/atelier.lua
-- The "atelier" theme: follows the desktop theme (quickshell-atelier's `atelier-theme`).
--
-- atelier-theme writes the active palette to ~/.config/atelier/theme.json on every switch:
-- 22 Catppuccin role names (base, mantle, …, mauve, pink) plus `accent`, and `variant`
-- (dark | light). The registry entry feeds that palette to catppuccin.nvim as colour overrides,
-- so every catppuccin integration (cmp, snacks, telescope, gitsigns, …) uses the desktop colours.
-- watch() re-applies the theme live in every running Neovim when the file changes.
-- ─────────────────────────────────────────────────────────────────────────────

local M = {}

M.path = vim.fn.expand("~/.config/atelier/theme.json")

local ROLES = {
  "rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach", "yellow", "green", "teal",
  "sky", "sapphire", "blue", "lavender", "text", "subtext1", "subtext0", "overlay2", "overlay1",
  "overlay0", "surface2", "surface1", "surface0", "base", "mantle", "crust",
}

-- The active desktop theme as { colors = {...}, light = bool, accent = "#rrggbb" }, or nil.
function M.read()
  local ok, lines = pcall(vim.fn.readfile, M.path)
  if not ok or not lines or #lines == 0 then return nil end
  local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok2 or type(data) ~= "table" or type(data.colors) ~= "table" then return nil end
  local c = data.colors
  local colors = {}
  for _, role in ipairs(ROLES) do
    if type(c[role]) == "string" then colors[role] = c[role] end
  end
  -- roles the desktop palette doesn't have: derive them from its neighbours
  colors.rosewater = colors.rosewater or c.pink
  colors.flamingo  = colors.flamingo or c.pink
  colors.maroon    = colors.maroon or c.red
  colors.overlay2  = colors.overlay2 or c.overlay1
  -- catppuccin's highlights use lavender as their accent: make it the desktop accent
  if type(c.accent) == "string" then colors.lavender = c.accent end
  return { colors = colors, light = data.variant == "light", accent = c.accent }
end

function M.is_light()
  local t = M.read()
  return t ~= nil and t.light
end

-- Re-apply on every desktop theme switch while "atelier" is the active Neovim theme.
local watcher, timer
function M.watch()
  if watcher then return end
  local dir = vim.fn.fnamemodify(M.path, ":h")
  if vim.fn.isdirectory(dir) == 0 then return end
  timer = vim.uv.new_timer()
  watcher = vim.uv.new_fs_event()
  -- watch the folder, not the file: atelier-theme replaces theme.json atomically (rename)
  watcher:start(dir, {}, function(err, fname)
    if err or fname ~= "theme.json" then return end
    timer:stop()
    timer:start(150, 0, vim.schedule_wrap(function()
      local ok, s = pcall(require, "core.settings_loader")
      local cur = ok and s.get() or {}
      local id = (cur.ui and cur.ui.theme) or cur.theme
      if id == "atelier" then
        require("core.themes.apply").apply("atelier")
      end
    end))
  end)
end

return M
