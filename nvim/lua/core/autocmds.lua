local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

-- ── Highlight on Yank ─────────────────────────────────────────────────────────
autocmd("TextYankPost", {
  group = augroup("HighlightYank", { clear = true }),
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 200 })
  end,
})

-- ── Restore cursor position on file open ─────────────────────────────────────
autocmd("BufReadPost", {
  group = augroup("RestoreCursor", { clear = true }),
  callback = function(ev)
    local mark   = vim.api.nvim_buf_get_mark(ev.buf, '"')
    local lcount = vim.api.nvim_buf_line_count(ev.buf)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- ── Auto-create missing parent directories on save ───────────────────────────
autocmd("BufWritePre", {
  group = augroup("AutoCreateDirs", { clear = true }),
  callback = function(ev)
    if ev.match:match("^%w%w+:[\\/][\\/]") then return end
    local file = (vim.uv or vim.loop).fs_realpath(ev.match) or ev.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
  end,
})

-- ── Auto-resize splits when terminal is resized ───────────────────────────────
autocmd("VimResized", {
  group = augroup("ResizeSplits", { clear = true }),
  callback = function()
    vim.cmd("tabdo wincmd =")
  end,
})

-- ── Close auxiliary filetypes with just 'q' ──────────────────────────────────
autocmd("FileType", {
  group   = augroup("QuickClose", { clear = true }),
  pattern = {
    "qf", "help", "man", "notify", "lspinfo",
    "spectre_panel", "startuptime", "tsplayground", "checkhealth",
    "gitsigns-blame", "neotest-output-panel", "neotest-summary",
    "neotest-output", "dbout", "git", "diff", "log",
  },
  callback = function(ev)
    vim.bo[ev.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = ev.buf, silent = true })
  end,
})

-- ── Strip trailing whitespace on save ────────────────────────────────────────
autocmd("BufWritePre", {
  group = augroup("StripTrailingWS", { clear = true }),
  callback = function(ev)
    if not vim.bo[ev.buf].modifiable then return end
    local save = vim.fn.winsaveview()
    vim.cmd([[keeppatterns %s/\s\+$//e]])
    vim.fn.winrestview(save)
  end,
})

-- ── Django HTML filetype detection ───────────────────────────────────────────
-- Evaluated per-buffer (not at startup) so it works even after cwd changes.
autocmd({ "BufNewFile", "BufRead" }, {
  group   = augroup("DjangoFiletype", { clear = true }),
  pattern = "*.html",
  callback = function()
    if vim.fn.filereadable(vim.fn.getcwd() .. "/manage.py") == 1 then
      vim.bo.filetype = "htmldjango"
    end
  end,
})

-- ── Disable Dropbar for Snacks windows ───────────────────────────────────────
autocmd("FileType", {
  group   = augroup("DisableDropbar", { clear = true }),
  pattern = {
    "snacks_picker_list", "snacks_picker_input",
    "snacks_picker_preview", "snacks_layout_box", "snacks_terminal",
  },
  callback = function(ev)
    vim.b[ev.buf].dropbar_enable = false
  end,
})

-- ── Hot Reload Settings ───────────────────────────────────────────────────────
-- Automatically applies setting changes when lua/settings.lua is saved.
autocmd({ "BufWritePost", "FileChangedShellPost" }, {
  group   = augroup("HotReloadSettings", { clear = true }),
  pattern = "*/lua/settings.lua",
  callback = function()
    local ok, err = pcall(function()
      require("core.settings_loader").apply()
    end)
    if not ok then
      vim.notify("Error reloading settings: " .. tostring(err), vim.log.levels.ERROR)
    end
  end,
})

-- ── Large file performance guard ─────────────────────────────────────────────
-- Disables heavy features for files > 500 KB
autocmd("BufReadPre", {
  group = augroup("LargeFile", { clear = true }),
  callback = function(ev)
    local size = vim.fn.getfsize(ev.file)
    if size > 500 * 1024 then
      vim.bo[ev.buf].syntax      = "off"
      vim.wo.foldmethod          = "manual"
      vim.wo.foldexpr            = ""
      vim.b[ev.buf].large_file   = true
      vim.notify(
        "Large file detected — some features disabled for performance.",
        vim.log.levels.WARN
      )
    end
  end,
})

-- ── Auto-stop YouTube Background Audio on Neovim Exit ────────────────────────
-- Only register when a real UI is attached; headless Neovim instances spawned
-- by the web server's /api/youtube/* endpoints must NOT stop the mpv daemon.
if #vim.api.nvim_list_uis() > 0 then
  autocmd("VimLeavePre", {
    group = augroup("YouTubeAutoStopExit", { clear = true }),
    callback = function()
      pcall(function()
        require("core.youtube_player").stop(true)
      end)
    end,
  })
end

