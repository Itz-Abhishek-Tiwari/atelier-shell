-- plugins/ui/statusline.lua

-- ── Color Extraction Helpers ──────────────────────────────────────────────────
local function hex(hl_name, prop)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = hl_name, link = false })
  if not ok or not hl then return nil end
  local val = hl[prop]
  if not val then return nil end
  return string.format("#%06x", val)
end

local function get_lualine_theme()
  local bg = hex("Normal", "bg")
  if not bg or bg == "NONE" then
    bg = hex("NormalFloat", "bg") or hex("StatusLine", "bg") or "#1e1e2e"
  end
  local fg = hex("Normal", "fg") or "#cdd6f4"
  local status_bg = hex("StatusLine", "bg") or hex("CursorLine", "bg") or "#252535"
  local status_fg = hex("StatusLine", "fg") or fg
  local nc_bg = hex("StatusLineNC", "bg") or bg
  local nc_fg = hex("StatusLineNC", "fg") or "#585b70"
  
  -- Accent colors from active theme highlight groups
  local normal_accent  = hex("Function", "fg") or hex("Directory", "fg") or "#89b4fa"
  local insert_accent  = hex("String", "fg") or hex("DiagnosticOk", "fg") or "#a6e3a1"
  local visual_accent  = hex("Statement", "fg") or hex("Constant", "fg") or "#cba6f7"
  local replace_accent = hex("ErrorMsg", "fg") or hex("DiagnosticError", "fg") or "#f38ba8"
  local command_accent = hex("WarningMsg", "fg") or hex("DiagnosticWarn", "fg") or "#fab387"

  return {
    normal = {
      a = { bg = normal_accent, fg = bg, gui = "bold" },
      b = { bg = status_bg, fg = normal_accent },
      c = { bg = status_bg, fg = status_fg },
    },
    insert = {
      a = { bg = insert_accent, fg = bg, gui = "bold" },
      b = { bg = status_bg, fg = insert_accent },
      c = { bg = status_bg, fg = status_fg },
    },
    visual = {
      a = { bg = visual_accent, fg = bg, gui = "bold" },
      b = { bg = status_bg, fg = visual_accent },
      c = { bg = status_bg, fg = status_fg },
    },
    replace = {
      a = { bg = replace_accent, fg = bg, gui = "bold" },
      b = { bg = status_bg, fg = replace_accent },
      c = { bg = status_bg, fg = status_fg },
    },
    command = {
      a = { bg = command_accent, fg = bg, gui = "bold" },
      b = { bg = status_bg, fg = command_accent },
      c = { bg = status_bg, fg = status_fg },
    },
    inactive = {
      a = { bg = nc_bg, fg = nc_fg },
      b = { bg = nc_bg, fg = nc_fg },
      c = { bg = nc_bg, fg = nc_fg },
    },
  }
end

local function get_opts()
  local function is_wide() return vim.o.columns > 100 end

  -- ── LSP cache ─────────────────────────────────────────────────────────
  local lsp_cache = {}
  vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach", "BufEnter" }, {
    callback = function(ev) lsp_cache[ev.buf] = nil end,
  })
  local function lsp_clients()
    local buf = vim.api.nvim_get_current_buf()
    if lsp_cache[buf] then return lsp_cache[buf] end
    local clients = (vim.lsp.get_clients or vim.lsp.get_active_clients)({ bufnr = buf })
    if #clients == 0 then lsp_cache[buf] = ""; return "" end
    local names = {}
    local seen = {}
    for _, c in ipairs(clients) do
      if c.name ~= "null-ls" and c.name ~= "none-ls" then
        if not seen[c.name] then
          seen[c.name] = true
          table.insert(names, c.name)
        end
      end
    end
    local r = table.concat(names, " · ")
    lsp_cache[buf] = r
    return r
  end

  -- ── Mode with icon ────────────────────────────────────────────────────
  local mode_map = {
    n  = { "NORMAL",    "󰋜" },
    i  = { "INSERT",    "󰏫" },
    v  = { "VISUAL",    "󰒉" },
    V  = { "V-LINE",    "󰒉" },
    ["\22"] = { "V-BLOCK", "󰒊" },
    c  = { "COMMAND",   "󰘳" },
    R  = { "REPLACE",   "󰬮" },
    s  = { "SELECT",    "󰒉" },
    t  = { "TERMINAL",  "" },
    no = { "O-PENDING", "󰏗" },
  }
  local function mode_label()
    local m = mode_map[vim.fn.mode()] or { "NORMAL", "󰋜" }
    return is_wide() and (m[2] .. "  " .. m[1]) or m[2]
  end

  -- ── Macro recording ───────────────────────────────────────────────────
  local function macro_rec()
    local r = vim.fn.reg_recording()
    return r ~= "" and ("󰻃 @" .. r) or ""
  end

  -- ── Navic breadcrumbs ─────────────────────────────────────────────────
  local function navic_location()
    local ok, navic = pcall(require, "nvim-navic")
    if not ok or not navic.is_available() then return "" end
    local loc = navic.get_location()
    return loc ~= "" and ("  " .. loc) or ""
  end

  -- ── Git blame (current line) ───────────────────────────────────────────
  local blame_cache = {}
  vim.api.nvim_create_autocmd({ "CursorHold", "BufEnter" }, {
    callback = function()
      blame_cache = {}
    end,
  })
  local function git_blame()
    if not is_wide() then return "" end
    local buf = vim.api.nvim_get_current_buf()
    local line = vim.fn.line(".")
    local key = buf .. ":" .. line
    if blame_cache[key] ~= nil then return blame_cache[key] end

    local ok, gitsigns = pcall(require, "gitsigns")
    if not ok then blame_cache[key] = ""; return "" end

    local blame = vim.b.gitsigns_blame_line_dict
    if not blame or blame.summary == "Not Committed Yet" or not blame.author then
      blame_cache[key] = ""; return ""
    end

    -- Shorten author first name only
    local author = blame.author:match("^(%S+)") or blame.author
    local date_relative = blame.date_relative or ""
    local result = " " .. author .. ", " .. date_relative
    blame_cache[key] = result
    return result
  end

  -- ── Formatters (conform) ──────────────────────────────────────────────
  local function formatters()
    if not is_wide() then return "" end
    local ok, conform = pcall(require, "conform")
    if not ok then return "" end
    local fmts = conform.list_formatters(0)
    if #fmts == 0 then return "" end
    return "󰛗 " .. table.concat(vim.tbl_map(function(f) return f.name end, fmts), " · ")
  end

  -- ── Python venv ───────────────────────────────────────────────────────
  local function python_env()
    if vim.bo.filetype ~= "python" then return "" end
    local v = vim.env.VIRTUAL_ENV or vim.env.CONDA_DEFAULT_ENV
    return v and ("󰌠 " .. vim.fn.fnamemodify(v, ":t")) or ""
  end

  -- ── Word count ────────────────────────────────────────────────────────
  local prose = { markdown = true, text = true, rst = true, org = true }
  local function word_count()
    return prose[vim.bo.filetype] and ("󰈙 " .. vim.fn.wordcount().words .. "w") or ""
  end

  -- ── Kulala HTTP env ───────────────────────────────────────────────────
  local function kulala_indicator()
    if vim.bo.filetype ~= "http" then return "" end
    local ok, env = pcall(function()
      return require("kulala.config").get_selected_env()
    end)
    return (ok and env) and ("󰖟 " .. env) or "󰖟 HTTP"
  end

  -- ── Cursor location ───────────────────────────────────────────────────
  local function location()
    return string.format("󰆏 %d:%d", vim.fn.line("."), vim.fn.col("."))
  end

  -- ── Terminal name formatter ────────────────────────────────────────────
  local function format_filename(name)
    local bufname = vim.api.nvim_buf_get_name(0)
    if bufname:match("^term://") then
      local dir, shell = bufname:match("^term://(.-)//%d+:(.*)$")
      if not dir then
        dir, shell = bufname:match("^term://(.-):(.*)$")
      end
      if dir and shell then
        local home = vim.env.HOME
        if home then
          dir = dir:gsub("^" .. vim.pesc(home), "~")
        end
        local dir_tail = vim.fn.fnamemodify(dir, ":t")
        local shell_name = vim.fn.fnamemodify(shell, ":t")
        return string.format("Terminal: %s (%s)", shell_name, dir_tail)
      end
      return "Terminal"
    end
    return name
  end

  -- ── Right-side info block (LSP + fmt + env + ft) ─────────────────────
  local function right_block()
    local parts = {}

    -- LSP
    local lsp = lsp_clients()
    if lsp ~= "" then table.insert(parts, " " .. lsp) end

    -- Formatters
    local fmt = formatters()
    if fmt ~= "" then table.insert(parts, fmt) end

    -- Python venv
    local py = python_env()
    if py ~= "" then table.insert(parts, py) end

    -- Word count
    local wc = word_count()
    if wc ~= "" then table.insert(parts, wc) end

    -- Kulala
    local ku = kulala_indicator()
    if ku ~= "" then table.insert(parts, ku) end

    -- Encoding (only non-utf8)
    local enc = vim.opt.fileencoding:get()
    if enc ~= "" and enc ~= "utf-8" then
      table.insert(parts, "󰉿 " .. enc)
    end

    -- File format (only non-unix)
    local ff_icons = { unix = "", dos = "", mac = "" }
    local ff = vim.bo.fileformat
    if ff ~= "unix" then
      table.insert(parts, (ff_icons[ff] or ff))
    end

    -- Filetype (always shown)
    local ft = vim.bo.filetype
    if ft ~= "" then
      local ok, devicons = pcall(require, "nvim-web-devicons")
      local icon = ok and devicons.get_icon_by_filetype(ft, { default = true }) or ""
      table.insert(parts, (icon ~= "" and icon .. " " or "") .. ft)
    end

    return table.concat(parts, " · ")
  end

  return {
    options = {
      theme = get_lualine_theme(),
      component_separators = { left = "", right = "" },
      section_separators   = { left = "", right = "" },
      globalstatus = true,
      refresh = { statusline = 1000 },
      disabled_filetypes = {
        statusline = { "dashboard", "alpha", "starter", "snacks_dashboard" },
      },
    },

    sections = {
      lualine_a = {
        {
          mode_label,
          padding = { left = 1, right = 1 },
        },
      },

      lualine_b = {
        { "branch", icon = "" },
        {
          "diff",
          symbols = { added = " ", modified = " ", removed = " " },
          source = function()
            local gitsigns = vim.b.gitsigns_status_dict
            if gitsigns then
              return {
                added = gitsigns.added,
                modified = gitsigns.changed,
                removed = gitsigns.removed
              }
            end
          end
        }
      },

      lualine_c = {
        { macro_rec, color = { fg = "#e06c75", gui = "bold" } },
        {
          "filename",
          path           = 1,
          newfile_status = true,
          symbols = {
            modified = "  ",
            readonly = "  ",
            unnamed  = " [No Name]",
            newfile  = " 󰝒 ",
          },
          fmt = format_filename,
        },
        {
          navic_location,
          color = { fg = "#7f849c" },
        },
        {
          git_blame,
          color = { fg = "#585b70", italic = true },
        },
      },

      lualine_x = {
        {
          "diagnostics",
          sources = { "nvim_diagnostic" },
          symbols = { error = " ", warn = " ", info = " ", hint = " " },
        },
        {
          right_block,
        },
      },

      lualine_y = {
        { "progress", icon = "", padding = { left = 1, right = 1 } },
        { location,              padding = { left = 0, right = 1 } },
      },

      lualine_z = {},
    },

    inactive_sections = {
      lualine_c = {
        {
          "filename",
          path    = 1,
          symbols = { modified = "  ", readonly = "  " },
          fmt     = format_filename,
        },
      },
      lualine_x = { location },
    },

    extensions = { "lazy", "mason", "quickfix", "man", "fzf" },
  }
end

return {
  {
    "nvim-lualine/lualine.nvim",
    lazy = false,
    enabled = true,
    dependencies = {
      "nvim-tree/nvim-web-devicons",
      "SmiteshP/nvim-navic",
    },
    opts = get_opts,
    config = function(_, opts)
      require("lualine").setup(opts)

      -- Dynamic theme reloading on colorscheme change
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("LualineThemeReload", { clear = true }),
        callback = function()
          package.loaded["lualine"] = nil
          require("lualine").setup(get_opts())
        end,
      })
    end,
  },
}