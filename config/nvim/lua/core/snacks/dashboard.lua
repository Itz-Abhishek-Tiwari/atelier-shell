-- Snacks Dashboard — Nami v2: big ASCII art, date line, recent files, startup time
local ok, settings = pcall(require, "settings")
local current_theme = ok and ((settings.ui and settings.ui.theme) or settings.theme) or "catppuccin-mocha"
local nv            = vim.version()
local nvim_ver      = ("%d.%d.%d"):format(nv.major, nv.minor, nv.patch)

local function plugin_count()
  local ok2, lazy = pcall(require, "lazy")
  return ok2 and #vim.tbl_keys(lazy.plugins()) or "?"
end

local function get_greeting()
  local hr = tonumber(os.date("%H"))
  local time_greetings = {
    [5]  = "Good morning, early riser! ☀️",
    [6]  = "Good morning! 🌅",
    [7]  = "Good morning! 🌅",
    [8]  = "Good morning! 🌅",
    [9]  = "Good morning! 🌅",
    [10] = "Have a productive morning! ☕",
    [11] = "Have a productive morning! ☕",
    [12] = "Good afternoon! 🌊",
    [13] = "Good afternoon! 🌊",
    [14] = "Good afternoon! 🌊",
    [15] = "Coding session in progress! 💻",
    [16] = "Coding session in progress! 💻",
    [17] = "Good evening! 🌇",
    [18] = "Good evening! 🌇",
    [19] = "Good evening! 🌇",
    [20] = "Have a relaxing evening! 🌌",
    [21] = "Have a relaxing evening! 🌌",
    [22] = "Night session! 🌙",
    [23] = "Night session! 🌙",
    [0]  = "Burning the midnight oil? 🦉",
    [1]  = "Burning the midnight oil? 🦉",
    [2]  = "Late night coder! 🚀",
    [3]  = "Late night coder! 🚀",
    [4]  = "Late night coder! 🚀",
  }
  return time_greetings[hr] or "Welcome back to NamiConfig! 🌊"
end

local function get_git_info()
  local in_git = vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null"):gsub("%s+", "")
  if in_git ~= "true" then
    return nil
  end

  local branch = vim.fn.system("git branch --show-current 2>/dev/null"):gsub("%s+", "")
  if branch == "" then branch = "detached" end

  local diff = vim.fn.system("git diff --numstat 2>/dev/null")
  local added_lines = 0
  local deleted_lines = 0
  local file_count = 0
  for added, deleted in diff:gmatch("(%d+)%s+(%d+)") do
    added_lines = added_lines + tonumber(added)
    deleted_lines = deleted_lines + tonumber(deleted)
    file_count = file_count + 1
  end

  return {
    branch = branch,
    added = added_lines,
    deleted = deleted_lines,
    files = file_count
  }
end

local function git_status_section()
  local git = get_git_info()
  if not git then
    return {
      { "   󰅚  No Git Repository", hl = "Comment" }
    }
  end

  local line = {}
  table.insert(line, { "    " .. git.branch, hl = "SnacksDashboardKey" })
  if git.files > 0 then
    table.insert(line, { string.format("  ·  %d modified files (", git.files), hl = "SnacksDashboardFooter" })
    if git.added > 0 then
      table.insert(line, { "+" .. git.added, hl = "DiagnosticOk" })
    end
    if git.added > 0 and git.deleted > 0 then
      table.insert(line, { "/", hl = "SnacksDashboardFooter" })
    end
    if git.deleted > 0 then
      table.insert(line, { "-" .. git.deleted, hl = "DiagnosticError" })
    end
    table.insert(line, { ")", hl = "SnacksDashboardFooter" })
  else
    table.insert(line, { "  ·  ✔ Clean working tree", hl = "DiagnosticOk" })
  end
  return line
end

return {
  enabled = true,

  preset = {
    -- ── Compact Double-Line ASCII Logo (Fits small screens perfectly) ──────────
    header = [[

  ╔╗╔ ╔═╗ ╔╦╗ ╦
  ║║║ ╠═╣ ║║║ ║
  ╝╚╝ ╩ ╩ ╩ ╩ ╩
    ]],

    keys = {
      -- ── Navigation ──────────────────────────────────────────────────────
      { icon = " ", key = "f", desc = "Find File",        action = ":lua Snacks.picker.files()" },
      { icon = " ", key = "g", desc = "Live Grep",        action = ":lua Snacks.picker.grep()" },
      { icon = " ", key = "r", desc = "Recent Files",     action = ":lua Snacks.picker.recent()" },
      { icon = " ", key = "n", desc = "New File",         action = ":ene | startinsert" },
      -- ── Sessions ────────────────────────────────────────────────────────
      { icon = " ", key = "p", desc = "Restore Session",  action = ":lua require('persistence').load()" },
      { icon = " ", key = "l", desc = "Last Session",     action = ":lua require('persistence').load({ last = true })" },
      -- ── Config / Quit ────────────────────────────────────────────────────
      { icon = " ", key = "s", desc = "Settings",         action = ":e " .. vim.fn.stdpath("config") .. "/lua/settings.lua" },
      { icon = "💤", key = "z", desc = "Lazy",             action = ":Lazy" },
      { icon = " ", key = "q", desc = "Quit",             action = ":qa" },
    },
  },

  formats = {
    header = { "%s", align = "center" },
    footer = { "%s", align = "center" },
    key    = { "%s", hl = "SnacksDashboardKey" },
  },

  sections = {
    -- ── Header: Nami Art ────────────────────────────────────────────────────
    { section = "header" },

    -- ── Date & Time (Native Lua) ────────────────────────────────────────────
    function()
      return {
        text = {
          { os.date("    %A, %d %B %Y   ·   󱑂  %H:%M"), hl = "SnacksDashboardFooter" }
        },
        align = "center",
      }
    end,

    -- ── Dynamic Greeting ────────────────────────────────────────────────────
    function()
      return {
        text = {
          { "  " .. get_greeting(), hl = "SnacksDashboardHeader", bold = true }
        },
        align = "center",
      }
    end,

    -- ── Git project stats (hidden if screen is very short) ──────────────────
    function()
      if vim.o.lines < 22 then return {} end
      return {
        text = git_status_section(),
        align = "center",
        padding = { 0, 0, 1, 0 }
      }
    end,

    -- ── Navigation keys ─────────────────────────────────────────────────────
    {
      text    = { { "  🚀 Quick Links", hl = "SnacksDashboardHeader" } },
      padding = { 0, 0, 1, 0 },
      indent  = 6,
    },
    { section = "keys", padding = { 0, 0, 1, 0 } },

    -- ── Recent files (only visible on taller screens) ───────────────────────
    function()
      if vim.o.lines < 32 then return {} end
      return {
        text    = { { "    Recent Files", hl = "SnacksDashboardHeader" } },
        padding = { 0, 0, 1, 0 },
        indent  = 6,
      }
    end,
    function()
      if vim.o.lines < 32 then return {} end
      return {
        section = "recent_files",
        limit   = 3,
        indent  = 6,
        padding = { 0, 0, 1, 0 },
      }
    end,

    -- ── Startup time (hidden if screen is very short) ───────────────────────
    function()
      if vim.o.lines < 20 then return {} end
      return { section = "startup" }
    end,

    -- ── Footer (hidden if screen is very short) ─────────────────────────────
    function()
      if vim.o.lines < 18 then return {} end
      return {
        text = {
          { string.format("  Neovim v%s  ·  %s plugins  ·  %s", nvim_ver, plugin_count(), current_theme), hl = "SnacksDashboardFooter" }
        },
        align = "center",
      }
    end,
  },
}
