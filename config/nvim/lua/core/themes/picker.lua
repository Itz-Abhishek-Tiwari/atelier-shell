local M = {}
local api = vim.api
local fn = vim.fn

-- ── State ─────────────────────────────────────────────────────────────────────
local state = {
  wins = {},
  bufs = {},
  cursor = 1,
  query = "",
  original = nil,
  groups = {},
  filtered = {}
}

local NS = api.nvim_create_namespace("ThemePicker")
local WIN_WIDTH = 60
local WIN_HEIGHT = 15

-- ── Data ──────────────────────────────────────────────────────────────────────
local groups = {
  { name = "Catppuccin", icon = "󰄛", themes = { "catppuccin-mocha", "catppuccin-macchiato", "catppuccin-frappe", "catppuccin-latte" } },
  { name = "TokyoNight", icon = "󰓎", themes = { "tokyonight-night", "tokyonight-storm", "tokyonight-moon", "tokyonight-day" } },
  { name = "Rose Pine",  icon = "󰌹", themes = { "rose-pine-main", "rose-pine-moon", "rose-pine-dawn" } },
  { name = "Kanagawa",   icon = "󰗊", themes = { "kanagawa-wave", "kanagawa-dragon", "kanagawa-lotus" } },
  { name = "Nightfox",   icon = "󰆉", themes = { "nightfox", "duskfox", "nordfox", "terafox", "carbonfox", "dayfox" } },
  { name = "OneDark",    icon = "", themes = { "onedark-dark", "onedark-darker", "onedark-cool", "onedark-deep", "onedark-warm", "onedark-warmer", "onedark-light" } },
  { name = "GitHub",     icon = "", themes = { "github_dark", "github_dark_dimmed", "github_light" } },
  { name = "Material",   icon = "󰔎", themes = { "material-darker", "material-oceanic", "material-lighter" } },
  { name = "Ayu",        icon = "󰆈", themes = { "ayu-dark", "ayu-mirage", "ayu-light" } },
  { name = "Cyberdream", icon = "󰘦", themes = { "cyberdream-dark", "cyberdream-light" } },
  { name = "Gruvbox",    icon = "󰈄", themes = { "gruvbox", "gruvbox-material" } },
  { name = "Others",     icon = "󰍜", themes = { "everforest", "bamboo", "nord", "dracula", "sonokai", "poimandres", "monokai", "nightfly", "moonfly", "oxocarbon", "solarized-osaka", "night-owl", "mellifluous", "vscode-dark", "vscode-light" } },
}

-- ── Helpers ───────────────────────────────────────────────────────────────────
local hex = function(hl_name, prop)
  local hl = vim.api.nvim_get_hl(0, { name = hl_name, link = false })
  local val = hl[prop]
  if not val then return nil end
  return string.format("#%06x", val)
end

local function setup_hls()
  -- Dynamically inherit colors from Telescope highlight groups if they exist in the theme
  local bg = hex("TelescopeNormal", "bg") or hex("NormalFloat", "bg") or hex("Normal", "bg") or "#1e1e2e"
  local fg = hex("TelescopeNormal", "fg") or hex("NormalFloat", "fg") or hex("Normal", "fg") or "#cdd6f4"
  local border = hex("TelescopeBorder", "fg") or hex("FloatBorder", "fg") or "#585b70"
  local accent = hex("TelescopeSelection", "fg") or hex("DiagnosticInfo", "fg") or hex("Function", "fg") or "#89b4fa"
  local muted = hex("Comment", "fg") or "#7f849c"
  local cur_bg = hex("TelescopeSelection", "bg") or hex("CursorLine", "bg") or hex("ColorColumn", "bg") or "#313244"
  local title_fg = hex("Title", "fg") or accent
  
  vim.api.nvim_set_hl(0, "TpBorder", { fg = border, bg = bg })
  vim.api.nvim_set_hl(0, "TpBorderActive", { fg = accent, bg = bg })
  vim.api.nvim_set_hl(0, "TpNormal", { bg = bg, fg = fg })
  vim.api.nvim_set_hl(0, "TpHeader", { fg = title_fg, bold = true })
  vim.api.nvim_set_hl(0, "TpText", { fg = fg })
  vim.api.nvim_set_hl(0, "TpActive", { fg = accent, bg = cur_bg, bold = true })
  vim.api.nvim_set_hl(0, "TpActiveMuted", { fg = accent, bold = false })
  vim.api.nvim_set_hl(0, "TpIndicator", { fg = accent, bg = cur_bg, bold = true })
  vim.api.nvim_set_hl(0, "TpIcon", { fg = accent, bg = cur_bg })
  vim.api.nvim_set_hl(0, "TpMuted", { fg = muted })
end

-- ── Core Logic ────────────────────────────────────────────────────────────────
local function update_filter()
  state.filtered = {}
  local q = state.query:lower()
  
  for _, group in ipairs(groups) do
    local matched_themes = {}
    for _, theme in ipairs(group.themes) do
      if theme:lower():find(q, 1, true) then
        matched_themes[#matched_themes+1] = theme
      end
    end
    
    if #matched_themes > 0 then
      if #state.filtered > 0 then
        state.filtered[#state.filtered+1] = { type = "spacer", label = "" }
      end
      state.filtered[#state.filtered+1] = {
        type = "header",
        label = string.format("%s  %s", group.icon, group.name)
      }
      for _, theme in ipairs(matched_themes) do
        state.filtered[#state.filtered+1] = {
          type = "theme",
          id = theme
        }
      end
    end
  end
  
  if #state.filtered == 0 then
    state.filtered[#state.filtered+1] = { type = "empty", label = " No themes found" }
  end
  
  -- ensure cursor lands on a theme, not a header
  state.cursor = 1
  for i, item in ipairs(state.filtered) do
    if item.type == "theme" then
      state.cursor = i
      break
    end
  end
end

local function render_list()
  local buf = state.bufs.list
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end

  local lines, hi = {}, {}

  for i, item in ipairs(state.filtered) do
    local row = #lines
    local is_cursor = (i == state.cursor)

    if item.type == "header" then
      local line = " " .. item.label
      local len = vim.fn.strdisplaywidth(line)
      if len < WIN_WIDTH then
        line = line .. string.rep(" ", WIN_WIDTH - len)
      end
      lines[#lines+1] = line
      hi[#hi+1] = { row, 0, -1, "TpHeader" }
    elseif item.type == "spacer" then
      lines[#lines+1] = ""
    elseif item.type == "empty" then
      lines[#lines+1] = item.label
      hi[#hi+1] = { row, 0, -1, "TpMuted" }
    else
      local is_active = (state.original and item.id == state.original)
      
      -- Find theme icon in registry
      local icon = "󰏘"
      for _, t in ipairs(require("core.themes.registry")) do
        if t.id == item.id then
          icon = t.icon:gsub("%s+$", "")
          break
        end
      end

      local display_name = item.id
      if is_active then
        display_name = display_name .. " "
      end
      
      local prefix = is_cursor and " ▎  " or "    "
      local spacer = "  "
      local line = prefix .. icon .. spacer .. display_name
      
      -- Pad line to WIN_WIDTH so highlight background is fully colored
      local len = vim.fn.strdisplaywidth(line)
      if len < WIN_WIDTH then
        line = line .. string.rep(" ", WIN_WIDTH - len)
      end
      lines[#lines+1] = line
      
      -- Calculate precise byte offsets for highlight alignment
      local o_prefix = #prefix
      local o_icon   = o_prefix + #icon
      local o_spacer = o_icon + #spacer
      
      local text_hl = is_active and "TpActiveMuted" or "TpText"
      
      if is_cursor then
        hi[#hi+1] = { row, 0,        o_prefix - 1, "TpIndicator" }
        hi[#hi+1] = { row, o_prefix,  o_icon,       "TpIcon" }
        hi[#hi+1] = { row, o_icon,    -1,           "TpActive" }
      else
        hi[#hi+1] = { row, o_prefix,  o_icon,       "TpMuted" }
        hi[#hi+1] = { row, o_icon,    -1,           text_hl }
      end
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for _, h in ipairs(hi) do
    vim.api.nvim_buf_add_highlight(buf, NS, h[4], h[1], h[2], h[3])
  end

  local win = state.wins.list
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_set_cursor, win, { state.cursor, 0 })
  end
end

local function move(dir)
  if #state.filtered == 0 then return end
  local next_cursor = state.cursor
  
  repeat
    next_cursor = next_cursor + dir
    if next_cursor > #state.filtered then
      next_cursor = 1
    elseif next_cursor < 1 then
      next_cursor = #state.filtered
    end
  until state.filtered[next_cursor].type == "theme" or next_cursor == state.cursor
  
  if state.filtered[next_cursor].type == "theme" then
    state.cursor = next_cursor
    render_list()
  end
end

-- ── API ───────────────────────────────────────────────────────────────────────
function M.open()
  if state.wins.list and vim.api.nvim_win_is_valid(state.wins.list) then
    return
  end
  
  setup_hls()
  state.original = vim.g.colors_name
  state.query = ""
  update_filter()
  
  state.bufs.search = api.nvim_create_buf(false, true)
  state.bufs.list = api.nvim_create_buf(false, true)
  
  local ui = api.nvim_list_uis()[1]
  local sw = ui.width
  local sh = ui.height
  
  local r = math.floor((sh - WIN_HEIGHT) / 2)
  local c = math.floor((sw - WIN_WIDTH) / 2)
  
  -- Results Window (List at the top)
  state.wins.list = api.nvim_open_win(state.bufs.list, false, {
    relative = "editor",
    width = WIN_WIDTH,
    height = WIN_HEIGHT,
    row = r,
    col = c,
    style = "minimal",
    border = "rounded",
    title = " Results ",
    title_pos = "left"
  })

  -- Prompt Window (Search input at the bottom)
  state.wins.search = api.nvim_open_win(state.bufs.search, true, {
    relative = "editor",
    width = WIN_WIDTH,
    height = 1,
    row = r + WIN_HEIGHT + 2,
    col = c,
    style = "minimal",
    border = "rounded",
    title = " Prompt ",
    title_pos = "left"
  })
  
  local function set_wo(w, is_search)
    local o = vim.wo[w]
    o.number         = false
    o.relativenumber = false
    o.signcolumn     = is_search and "yes" or "no"
    o.statuscolumn   = ""
    o.cursorline     = false
    o.wrap           = false
    
    local border_hl = is_search and "TpBorderActive" or "TpBorder"
    o.winhighlight   = "Normal:TpNormal,NormalFloat:TpNormal,FloatBorder:" .. border_hl .. ",SignColumn:TpNormal"
  end
  
  set_wo(state.wins.search, true)
  set_wo(state.wins.list, false)
  
  -- Telescope-like Prompt arrow icon
  vim.fn.sign_define("TpSearchIcon", { text = " ❯", texthl = "TpIcon" })
  vim.fn.sign_place(1, "TpSearchGrp", "TpSearchIcon", state.bufs.search, { lnum = 1 })
  
  local opts = { noremap = true, silent = true, buffer = state.bufs.search }
  
  vim.keymap.set({"n", "i"}, "<Esc>", M.close, opts)
  vim.keymap.set({"n", "i"}, "<C-c>", M.close, opts)
  
  vim.keymap.set("i", "<C-n>", function() move(1) end, opts)
  vim.keymap.set("i", "<C-p>", function() move(-1) end, opts)
  vim.keymap.set("i", "<Down>", function() move(1) end, opts)
  vim.keymap.set("i", "<Up>", function() move(-1) end, opts)
  
  vim.keymap.set("n", "j", function() move(1) end, opts)
  vim.keymap.set("n", "k", function() move(-1) end, opts)
  vim.keymap.set("n", "<Down>", function() move(1) end, opts)
  vim.keymap.set("n", "<Up>", function() move(-1) end, opts)
  
  vim.keymap.set({"n", "i"}, "<CR>", function()
    local item = state.filtered[state.cursor]
    if item and item.type == "theme" then
      M.close()
      
      -- Load and apply the theme using the centralized apply module
      require("core.themes.apply").apply(item.id, { save = true, sync_ghostty = true })
      vim.notify(" Theme applied: " .. item.id, vim.log.levels.INFO)
    end
  end, opts)
  
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = state.bufs.search,
    callback = function()
      local lines = api.nvim_buf_get_lines(state.bufs.search, 0, -1, false)
      state.query = lines[1] or ""
      update_filter()
      render_list()
    end
  })
  
  api.nvim_create_autocmd("WinLeave", {
    buffer = state.bufs.search,
    callback = function()
      vim.schedule(function()
        if api.nvim_get_current_win() ~= state.wins.list and api.nvim_get_current_win() ~= state.wins.search then
          M.close()
        end
      end)
    end
  })
  
  vim.cmd("startinsert")
  render_list()
end

function M.close()
  for _, w in pairs(state.wins) do
    if w and api.nvim_win_is_valid(w) then
      api.nvim_win_close(w, true)
    end
  end
  state.wins = {}
  state.bufs = {}
end

return M