local map = vim.keymap.set
local opts = { noremap = true, silent = true }

-- ── General ───────────────────────────────────────────────────────────────
map("i", "jk", "<ESC>",            { desc = "Escape insert mode" })
map("n", ";",  ":",                 { desc = "Command mode", noremap = true })
map("n", "<Esc>", "<cmd>nohl<CR>", { desc = "Clear highlights" })
local open_cheatsheet = function()
  local filepath = vim.fn.stdpath("config") .. "/cheatsheet.md"
  Snacks.scratch({ 
    icon = "󱗼", 
    name = "Cheat Sheet & Documentation", 
    file = filepath, 
    wo = { wrap = false, number = false, relativenumber = false, cursorline = false, signcolumn = "no" },
    bo = { modifiable = false, readonly = true }
  })
  vim.schedule(function()
    local buf = vim.fn.bufnr(filepath)
    if buf ~= -1 and vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].modifiable = false
      vim.bo[buf].readonly = true
    end
  end)
end

map("n", "<leader>ch",  open_cheatsheet, { desc = "Open Cheat Sheet & Documentation" })
map("n", "<leader>?",   open_cheatsheet, { desc = "Open Cheat Sheet & Documentation" })
map("n", "<leader>doc", open_cheatsheet, { desc = "Open Cheat Sheet & Documentation" })
map("n", "<leader>ce",  "<cmd>edit " .. vim.fn.stdpath("config") .. "/cheatsheet.md<CR>", { desc = "Edit Cheat Sheet" })
map("n", "<leader>sk",  function() Snacks.picker.keymaps() end, { desc = "Search Keymaps" })

-- Insert Mode Navigation
map("i", "<C-h>", "<Left>",  { desc = "Move left" })
map("i", "<C-l>", "<Right>", { desc = "Move right" })
map("i", "<C-j>", "<Down>",  { desc = "Move down" })
map("i", "<C-k>", "<Up>",    { desc = "Move up" })

-- ── Save / Quit ──────────────────────────────────────────────────────────
map("n", "<C-s>", "<cmd>w<CR>",  { desc = "Save file" })
map("n", "<C-q>", "<cmd>q<CR>",  { desc = "Quit" })
map("n", "<leader>q", "<cmd>qa<CR>", { desc = "Quit Neovim" })
map("n", "ZZ", function()
  if _G.Snacks then
    _G.Snacks.bufdelete()
  else
    require("snacks").bufdelete()
  end
end, { desc = "Close buffer" })

-- ── Move Lines (Alt + j/k) ───────────────────────────────────────────────
map("i", "<A-j>", "<Esc>:m .+1<CR>==gi", { desc = "Move line down" })
map("i", "<A-k>", "<Esc>:m .-2<CR>==gi", { desc = "Move line up" })
map("n", "<A-j>", ":m .+1<CR>==",        { desc = "Move line down" })
map("n", "<A-k>", ":m .-2<CR>==",        { desc = "Move line up" })
map("v", "<A-j>", ":m '>+1<CR>gv=gv",    { desc = "Move selection down" })
map("v", "<A-k>", ":m '<-2<CR>gv=gv",    { desc = "Move selection up" })

-- ── Better Indenting in Visual ────────────────────────────────────────────
map("v", "<", "<gv", { desc = "Indent left" })
map("v", ">", ">gv", { desc = "Indent right" })

-- ── Window Navigation ────────────────────────────────────────────────────
map("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to below window" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to above window" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- Navigate seamlessly out of terminal mode
map("t", "<C-h>", "<C-\\><C-n><C-w>h", { desc = "Move to left window" })
map("t", "<C-j>", "<C-\\><C-n><C-w>j", { desc = "Move to below window" })
map("t", "<C-k>", "<C-\\><C-n><C-w>k", { desc = "Move to above window" })
map("t", "<C-l>", "<C-\\><C-n><C-w>l", { desc = "Move to right window" })
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
map("t", "<C-x>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- ── Buffer Navigation ────────────────────────────────────────────────────
map("n", "<Tab>",   "<cmd>bnext<CR>",     { desc = "Next buffer" })
map("n", "<S-Tab>", "<cmd>bprevious<CR>", { desc = "Prev buffer" })


-- ── Theme Switcher ──────────────────────────────────────────────────────────
map("n", "<leader>th", function()
  require("core.themes.picker").open()
end, { desc = "Select & Save Theme" })

-- ── Toggles ──────────────────────────────────────────────────────────────
map("n", "<leader>tn", "<cmd>set nu!<CR>",   { desc = "Toggle line number" })
map("n", "<leader>tr", "<cmd>set rnu!<CR>",  { desc = "Toggle relative number" })
map("n", "<leader>tc", "<cmd>TSContextToggle<CR>", { desc = "Toggle Treesitter Context" })
map("n", "<leader>td", function()
  local enabled = vim.diagnostic.is_enabled()
  vim.diagnostic.enable(not enabled)
  vim.notify("Diagnostics " .. (enabled and "disabled" or "enabled"), vim.log.levels.INFO)
end, { desc = "Toggle Diagnostics" })



-- ── Visual Code Screenshot ─────────────────────────────────────────────────
map("v", "<leader>sc", ":Silicon<CR>",                   { desc = "Screenshot code" })

-- ── Python Venv ───────────────────────────────────────────────────────────
map("n", "<leader>vs", function()
  local s = require("settings")
  local paths = {}
  local cwd = vim.fn.getcwd()
  
  -- 1. Check workspace venvs
  local local_venvs = { "/.venv", "/venv" }
  for _, name in ipairs(local_venvs) do
    local p = cwd .. name .. "/bin/python"
    if vim.fn.executable(p) == 1 then
      table.insert(paths, { name = "Local: ." .. name, path = p })
    end
  end
  
  -- 2. Check ~/.virtualenvs
  local home_venv_dir = vim.fn.expand("~/.virtualenvs")
  if vim.fn.isdirectory(home_venv_dir) == 1 then
    local venvs = vim.fn.readdir(home_venv_dir)
    for _, name in ipairs(venvs) do
      local p = home_venv_dir .. "/" .. name .. "/bin/python"
      if vim.fn.executable(p) == 1 then
        table.insert(paths, { name = "Global: " .. name, path = p })
      end
    end
  end

  -- 3. Check poetry venvs
  local poetry_dir = vim.fn.expand("~/.cache/pypoetry/virtualenvs")
  if vim.fn.isdirectory(poetry_dir) == 1 then
    local venvs = vim.fn.readdir(poetry_dir)
    for _, name in ipairs(venvs) do
      local p = poetry_dir .. "/" .. name .. "/bin/python"
      if vim.fn.executable(p) == 1 then
        table.insert(paths, { name = "Poetry: " .. name, path = p })
      end
    end
  end

  if #paths == 0 and vim.env.VIRTUAL_ENV == nil then
    vim.notify("No virtual environments found!", vim.log.levels.WARN)
    return
  end

  local items = {}
  if vim.env.VIRTUAL_ENV ~= nil then
    table.insert(items, {
      text = "Deactivate Current Venv",
      value = "deactivate",
    })
  end
  for _, item in ipairs(paths) do
    table.insert(items, {
      text = item.name,
      value = item.path,
    })
  end

  Snacks.picker.pick({
    source = "venvs",
    items = items,
    prompt = "Select Python Virtual Environment",
    layout = {
      preset = s.picker_layout or "select",
      width = s.picker_width or 0.5,
      height = s.picker_height or 0.8,
    },
    win = {
      input = { border = s.menu_border or "rounded" },
      list = { border = s.menu_border or "rounded" },
      preview = { border = s.menu_border or "rounded" },
    },
    format = function(item)
      local icon = item.value == "deactivate" and "󰅙  " or "  "
      local hl = item.value == "deactivate" and "DiagnosticWarn" or "SnacksPickerText"
      return {
        { icon, "SnacksPickerIcon" },
        { item.text, hl },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if not item then return end
      
      if item.value == "deactivate" then
        vim.env.VIRTUAL_ENV = nil
        local default_py = vim.fn.exepath("python3") or vim.fn.exepath("python") or "python"
        for _, client in ipairs(vim.lsp.get_clients({ name = "pyright" })) do
          client.config.settings.python.pythonPath = default_py
          client.notify("workspace/didChangeConfiguration", { settings = client.config.settings })
        end
        vim.notify("Deactivated Python Virtual Environment", vim.log.levels.WARN)
        return
      end

      local py_path = item.value
      
      -- Set environment variables
      vim.env.VIRTUAL_ENV = py_path:gsub("/bin/python$", "")
      
      -- Update LSP clients
      for _, client in ipairs(vim.lsp.get_clients({ name = "pyright" })) do
        client.config.settings.python.pythonPath = py_path
        client.notify("workspace/didChangeConfiguration", { settings = client.config.settings })
      end
      
      vim.notify("Activated Venv: " .. item.text, vim.log.levels.INFO)
    end,
  })
end, { desc = "Select Python venv" })


-- ── Code Runner ───────────────────────────────────────────────────────────
map("n", "<leader>rr", function()
  local ft = vim.bo.filetype
  local file = vim.fn.expand("%:p")

  if file == "" then
    vim.notify("No file to run!", vim.log.levels.WARN)
    return
  end

  -- Save buffer first
  vim.cmd("silent! write")

  local cmd

  if ft == "python" then
    -- Use venv python if active, else python3/python
    local py = (vim.env.VIRTUAL_ENV and vim.env.VIRTUAL_ENV .. "/bin/python")
      or vim.fn.exepath("python3")
      or vim.fn.exepath("python")
      or "python3"
    cmd = py .. " " .. vim.fn.shellescape(file)

  elseif ft == "javascript" or ft == "javascriptreact" then
    cmd = "node " .. vim.fn.shellescape(file)

  elseif ft == "typescript" or ft == "typescriptreact" then
    -- Prefer tsx (bun), ts-node, or npx ts-node
    if vim.fn.executable("tsx") == 1 then
      cmd = "tsx " .. vim.fn.shellescape(file)
    elseif vim.fn.executable("ts-node") == 1 then
      cmd = "ts-node " .. vim.fn.shellescape(file)
    else
      cmd = "npx --yes ts-node " .. vim.fn.shellescape(file)
    end

  elseif ft == "sh" or ft == "bash" then
    cmd = "bash " .. vim.fn.shellescape(file)

  elseif ft == "go" then
    cmd = "go run " .. vim.fn.shellescape(file)

  elseif ft == "rust" then
    local root = vim.fs.find({ "Cargo.toml" }, { path = file, upward = true })[1]
    if root then
      cmd = "cargo run"
    else
      local bin = vim.fn.fnamemodify(file, ":r")
      cmd = "rustc " .. vim.fn.shellescape(file) .. " -o " .. vim.fn.shellescape(bin) .. " && " .. vim.fn.shellescape(bin) .. " && rm " .. vim.fn.shellescape(bin)
    end

  elseif ft == "c" then
    local bin = vim.fn.fnamemodify(file, ":r")
    cmd = "gcc -O2 " .. vim.fn.shellescape(file) .. " -o " .. vim.fn.shellescape(bin) .. " && " .. vim.fn.shellescape(bin) .. " && rm " .. vim.fn.shellescape(bin)

  elseif ft == "cpp" then
    local bin = vim.fn.fnamemodify(file, ":r")
    cmd = "g++ -std=c++17 -O2 " .. vim.fn.shellescape(file) .. " -o " .. vim.fn.shellescape(bin) .. " && " .. vim.fn.shellescape(bin) .. " && rm " .. vim.fn.shellescape(bin)

  elseif ft == "java" then
    cmd = "java " .. vim.fn.shellescape(file)

  elseif ft == "ruby" then
    cmd = "ruby " .. vim.fn.shellescape(file)

  else
    vim.notify("No runner configured for filetype: " .. ft, vim.log.levels.WARN)
    return
  end

  local fname = vim.fn.expand("%:t")

  -- Pass file path via env var to avoid all single-quote / shellescape issues
  -- inside the bash -c '...' wrapper.
  local env_vars = {
    RUNNER_FILE = file,
    RUNNER_NAME = fname,
    RUNNER_CMD  = cmd,        -- e.g. "node" / "python3" / "tsx"
  }

  -- Pretty ANSI wrapper ────────────────────────────────────────────────────
  --   • dynamic-width separator using tput cols
  --   • header: file icon + name + timestamp
  --   • green ✓ / red ✗ footer with exit code
  --   • silent read -n1 so the pressed key isn't echoed
  local script = [[
clear
_w=$(tput cols 2>/dev/null || echo 72)
_sep=$(printf '%*s' "$_w" '' | tr ' ' '─')
_ts=$(date '+%H:%M:%S')

# ── header ────────────────────────────────────────────────────────────
printf '\033[38;5;239m%s\033[0m\n' "$_sep"
printf '  \033[1;38;5;75m▶  %s\033[0m   \033[38;5;240m%s\033[0m\n' "$RUNNER_NAME" "$_ts"
printf '\033[38;5;239m%s\033[0m\n\n' "$_sep"

# ── run ───────────────────────────────────────────────────────────────
eval "$RUNNER_CMD \"$RUNNER_FILE\""
_x=$?

# ── footer ────────────────────────────────────────────────────────────
printf '\n\033[38;5;239m%s\033[0m\n' "$_sep"
if [ "$_x" -eq 0 ]; then
  printf '  \033[1;32m✓  Done\033[0m  \033[38;5;240m(exit 0)\033[0m   \033[38;5;245m· press any key to close\033[0m\n'
else
  printf '  \033[1;31m✗  Exited with error\033[0m  \033[38;5;240m(exit %s)\033[0m   \033[38;5;245m· press any key to close\033[0m\n' "$_x"
fi
read -n1 -s
]]

  local term = Snacks.terminal("bash -c " .. vim.fn.shellescape(script), {
    env = env_vars,
    win = {
      position    = "bottom",
      height      = 0.35,
      border      = require("settings").menu_border or "rounded",
      title       = " ▶ " .. fname .. " ",
      title_pos   = "center",
    },
    bo = { filetype = "snacks_terminal" },
  })
end, { desc = "Run current file (Node / Python)" })

-- ── Web Documentation & Settings Server ───────────────────────────────────
map("n", "<leader>ws", function()
  local docs_path = vim.fn.stdpath("config") .. "/docs"
  local server_js = docs_path .. "/server.js"
  if vim.fn.filereadable(server_js) == 0 then
    vim.notify("Server script not found at: " .. server_js, vim.log.levels.ERROR)
    return
  end

  local cmd = "node " .. vim.fn.shellescape(server_js)
  local script = [[
clear
printf '\033[1;38;5;75m⚡ Launching NamiConfig Unified Server...\033[0m\n'
printf '\033[38;5;240mURL: http://localhost:8085\033[0m\n\n'
export NVIM_SERVER=]] .. vim.fn.shellescape(vim.v.servername) .. [[

eval "]] .. cmd .. [["
]]

  Snacks.terminal("bash -c " .. vim.fn.shellescape(script), {
    win = {
      position  = "bottom",
      height    = 0.35,
      border    = require("settings").menu_border or "rounded",
      title     = " ⚡ NamiConfig Server ",
      title_pos = "center",
    },
    bo = { filetype = "snacks_terminal" },
  })
end, { desc = "Start Web Docs & Settings Server" })

map("n", "<leader>wd", function()
  require("core.settings_gui").open("home")
end, { desc = "Open Web Docs in Browser" })

map("n", "<leader>ts", function()
  require("core.settings_gui").open("settings")
end, { desc = "Open Settings GUI (Web)" })

-- ── 󰗃 YouTube Background Audio Player ─────────────────────────────────────
local yt = require("core.youtube_player")

vim.api.nvim_create_user_command("YouTubePlay", function(opts) yt.play(opts.args) end, { nargs = "?", desc = "Play YouTube URL audio" })
vim.api.nvim_create_user_command("YouTubePause", function() yt.toggle_pause() end, { desc = "Pause/Resume YouTube audio" })
vim.api.nvim_create_user_command("YouTubeToggle", function() yt.toggle_pause() end, { desc = "Pause/Resume YouTube audio" })
vim.api.nvim_create_user_command("YouTubeStop", function() yt.stop() end, { desc = "Stop YouTube audio playback" })
vim.api.nvim_create_user_command("YouTubeControls", function() yt.open_control_panel() end, { desc = "Open YouTube Player HUD panel" })
vim.api.nvim_create_user_command("YouTubeVolume", function(opts) yt.set_volume(tonumber(opts.args) or 80) end, { nargs = 1, desc = "Set YouTube volume (0-100)" })
vim.api.nvim_create_user_command("YouTubeSeek", function(opts) yt.seek(tonumber(opts.args) or 10) end, { nargs = 1, desc = "Seek YouTube audio by seconds (+/-)" })
vim.api.nvim_create_user_command("YouTubeStatus", function() yt.show_status() end, { desc = "Show YouTube player status" })
vim.api.nvim_create_user_command("YouTubeInstallMpv", function() yt.install_mpv() end, { desc = "Install mpv via Homebrew" })

map("n", "<leader>yp", function() yt.play() end,               { desc = "Play YouTube URL audio" })
map("n", "<leader>yt", function() yt.play() end,               { desc = "Play YouTube URL audio" })
map("n", "<leader>ys", function() yt.toggle_pause() end,       { desc = "Toggle Pause / Resume YouTube" })
map("n", "<leader>yx", function() yt.stop() end,               { desc = "Stop YouTube Playback" })
map("n", "<leader>yc", function() yt.open_control_panel() end, { desc = "Open YouTube Control Panel HUD" })
map("n", "<leader>y+", function() yt.adjust_volume(5) end,     { desc = "Increase YouTube Volume (+5%)" })
map("n", "<leader>y-", function() yt.adjust_volume(-5) end,    { desc = "Decrease YouTube Volume (-5%)" })
map("n", "<leader>yf", function() yt.seek(10) end,             { desc = "Seek YouTube Forward (+10s)" })
map("n", "<leader>yb", function() yt.seek(-10) end,            { desc = "Seek YouTube Backward (-10s)" })
map("n", "<leader>yi", function() yt.show_status() end,        { desc = "Show YouTube Playing Info" })


-- ── Hard Mode: Disable Arrow Keys ─────────────────────────────────────────
local disabled = [[<cmd>echohl Error | echo "KEY DISABLED" | echohl None<CR>]]
map("i", "<Up>",    "<C-o>" .. disabled, { noremap = true })
map("i", "<Down>",  "<C-o>" .. disabled, { noremap = true })
map("i", "<Left>",  "<C-o>" .. disabled, { noremap = true })
map("i", "<Right>", "<C-o>" .. disabled, { noremap = true })
map("n", "<Up>",    disabled,            { noremap = true })
map("n", "<Down>",  disabled,            { noremap = true })
map("n", "<Left>",  disabled,            { noremap = true })
map("n", "<Right>", disabled,            { noremap = true })
