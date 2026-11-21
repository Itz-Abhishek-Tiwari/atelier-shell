-- ==============================================================================
-- 󰗃  NamiConfig — YouTube Background Audio Player
-- ==============================================================================
local M = {}

-- ── Resolve settings ──────────────────────────────────────────────────────────
local function get_cfg()
  local ok, s = pcall(require, "core.settings_loader")
  local yt = (ok and s.get and s.get().youtube_player) or {}
  return {
    socket_path    = yt.ipc_socket    or (vim.fn.stdpath("state") .. "/namiconfig_yt_mpv.sock"),
    default_volume = yt.default_volume or 80,
    seek_step      = yt.seek_step      or 10,
    volume_step    = yt.volume_step    or 5,
  }
end

-- Ensure the parent directory of the socket path exists
local function ensure_socket_dir(path)
  local dir = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

-- Helper: is mpv installed?
local function has_mpv()
  return vim.fn.executable("mpv") == 1
end

-- ── Batch IPC over a single Python process ────────────────────────────────────
-- `commands` is a list of lists, e.g. { {"get_property","title"}, {"get_property","pause"} }
-- Returns a list of decoded response objects.
local function send_ipc_batch(socket_path, commands)
  if vim.fn.filereadable(socket_path) == 0 then
    return nil, "IPC socket not found"
  end

  local python_script = [[
import socket, json, sys, time

sock_path = sys.argv[1]
raw_cmds  = json.loads(sys.argv[2])

results = []
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2.0)
    s.connect(sock_path)
    for cmd in raw_cmds:
        payload = json.dumps({"command": cmd}) + "\n"
        s.sendall(payload.encode('utf-8'))
    # Read all responses
    buf = ""
    while len(results) < len(raw_cmds):
        try:
            chunk = s.recv(4096).decode('utf-8', errors='ignore')
            if not chunk:
                break
            buf += chunk
            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                line = line.strip()
                if line:
                    try:
                        results.append(json.loads(line))
                    except Exception:
                        pass
        except socket.timeout:
            break
    s.close()
except Exception as e:
    results.append({"error": str(e)})

print(json.dumps(results))
]]

  local cmd = {
    "python3",
    "-c",
    python_script,
    socket_path,
    vim.json.encode(commands),
  }

  local out = vim.fn.system(cmd)
  if out and #out > 0 then
    local ok, parsed = pcall(vim.json.decode, out)
    if ok and type(parsed) == "table" then
      return parsed
    end
  end
  return nil, "Invalid response"
end

-- Convenience: send a single command, returns a single decoded response
local function send_ipc(socket_path, args)
  local results, err = send_ipc_batch(socket_path, { args })
  if results and results[1] then
    return results[1]
  end
  return nil, err
end

-- ── Ensure mpv daemon is running ──────────────────────────────────────────────
function M.ensure_mpv_running()
  if not has_mpv() then return false end

  local cfg = get_cfg()
  ensure_socket_dir(cfg.socket_path)

  -- Check if socket exists and is responsive
  local res = send_ipc(cfg.socket_path, { "get_property", "idle" })
  if res and (res.error == "success" or res.data ~= nil) then
    return true
  end

  -- Socket dead or missing — clean up stale file
  if vim.fn.filereadable(cfg.socket_path) == 1 then
    vim.fn.delete(cfg.socket_path)
  end

  -- Spawn mpv in idle background mode with IPC socket
  local mpv_cmd = {
    "mpv",
    "--no-video",
    "--idle",
    "--input-ipc-server=" .. cfg.socket_path,
    "--volume=" .. cfg.default_volume,
  }

  vim.fn.jobstart(mpv_cmd, { detach = true })

  -- Wait briefly for socket creation (up to 1 s)
  for _ = 1, 20 do
    if vim.fn.filereadable(cfg.socket_path) == 1 then break end
    vim.cmd("sleep 50m")
  end

  return vim.fn.filereadable(cfg.socket_path) == 1
end

-- ── Clipboard YouTube URL helper ──────────────────────────────────────────────
local function get_clipboard_yt_url()
  local clip = (vim.fn.getreg("+") or ""):gsub("^%s*(.-)%s*$", "%1")
  if clip:find("youtube%.com/watch") or clip:find("youtu%.be/")
    or clip:find("youtube%.com/shorts") or clip:find("youtube%.com/playlist") then
    return clip
  end
  return ""
end

-- ── Play ──────────────────────────────────────────────────────────────────────
function M.play(url)
  if not has_mpv() then
    vim.notify("mpv is not installed! Run :YouTubeInstallMpv or 'brew install mpv'.", vim.log.levels.WARN)
    return
  end

  if not url or url:gsub("^%s*(.-)%s*$", "%1") == "" then
    local default_url = get_clipboard_yt_url()
    vim.ui.input({
      prompt  = "󰗃 Enter YouTube URL: ",
      default = default_url,
    }, function(input_url)
      if input_url and input_url:gsub("^%s*(.-)%s*$", "%1") ~= "" then
        M.play(input_url:gsub("^%s*(.-)%s*$", "%1"))
      end
    end)
    return
  end

  url = url:gsub("^%s*(.-)%s*$", "%1")

  if not M.ensure_mpv_running() then
    vim.notify("Failed to start mpv background process.", vim.log.levels.ERROR)
    return
  end

  local cfg = get_cfg()
  vim.notify("󰗃 Loading YouTube audio stream...", vim.log.levels.INFO)
  local res = send_ipc(cfg.socket_path, { "loadfile", url, "replace" })
  if res and res.error == "success" then
    vim.defer_fn(function() M.show_status() end, 1200)
  else
    vim.notify("Failed to load URL into mpv.", vim.log.levels.ERROR)
  end
end

-- ── Toggle pause / resume ─────────────────────────────────────────────────────
function M.toggle_pause()
  local cfg = get_cfg()
  if vim.fn.filereadable(cfg.socket_path) == 0 then
    vim.notify("No active YouTube playback.", vim.log.levels.WARN)
    return
  end

  -- Cycle pause then immediately read state — 2 commands, 1 process
  local results = send_ipc_batch(cfg.socket_path, {
    { "cycle", "pause" },
    { "get_property", "pause" },
  })
  if results and results[2] and results[2].data ~= nil then
    local is_paused = results[2].data
    vim.notify(is_paused and "⏸ Paused YouTube Playback" or "▶ Resumed YouTube Playback", vim.log.levels.INFO)
  end
end

-- ── Stop ─────────────────────────────────────────────────────────────────────
function M.stop(silent)
  local cfg = get_cfg()
  if vim.fn.filereadable(cfg.socket_path) == 1 then
    send_ipc(cfg.socket_path, { "quit" })
    vim.fn.delete(cfg.socket_path)
    if not silent then
      vim.notify("⏹ YouTube Playback Stopped.", vim.log.levels.INFO)
    end
  elseif not silent then
    vim.notify("No active YouTube playback.", vim.log.levels.WARN)
  end
end

-- ── Seek ─────────────────────────────────────────────────────────────────────
function M.seek(seconds)
  local cfg = get_cfg()
  if vim.fn.filereadable(cfg.socket_path) == 0 then
    vim.notify("No active YouTube playback.", vim.log.levels.WARN)
    return
  end
  send_ipc(cfg.socket_path, { "seek", tostring(seconds) })
  local sign = seconds > 0 and "+" or ""
  vim.notify("⏩ Seek " .. sign .. seconds .. "s", vim.log.levels.INFO)
end

-- ── Volume ───────────────────────────────────────────────────────────────────
function M.adjust_volume(delta)
  local cfg = get_cfg()
  if vim.fn.filereadable(cfg.socket_path) == 0 then
    vim.notify("No active YouTube playback.", vim.log.levels.WARN)
    return
  end

  -- Adjust then read volume — 2 commands, 1 process
  local results = send_ipc_batch(cfg.socket_path, {
    { "add", "volume", tostring(delta) },
    { "get_property", "volume" },
  })
  if results and results[2] and type(results[2].data) == "number" then
    local vol = math.floor(results[2].data)
    local bar_len = 10
    local filled = math.max(0, math.min(bar_len, math.floor((vol / 100) * bar_len)))
    local bar = string.rep("█", filled) .. string.rep("░", bar_len - filled)
    vim.notify("🔊 Volume: " .. vol .. "% [" .. bar .. "]", vim.log.levels.INFO)
  end
end

function M.set_volume(val)
  local cfg = get_cfg()
  if vim.fn.filereadable(cfg.socket_path) == 0 then
    vim.notify("No active YouTube playback.", vim.log.levels.WARN)
    return
  end
  send_ipc(cfg.socket_path, { "set_property", "volume", tostring(val) })
  vim.notify("🔊 Volume set to " .. val .. "%", vim.log.levels.INFO)
end

-- ── Status data ───────────────────────────────────────────────────────────────
function M.get_status_data()
  local cfg = get_cfg()
  if vim.fn.filereadable(cfg.socket_path) == 0 then
    return { active = false }
  end

  -- All 5 properties in a single Python process invocation
  local results = send_ipc_batch(cfg.socket_path, {
    { "get_property", "media-title" },
    { "get_property", "pause" },
    { "get_property", "time-pos" },
    { "get_property", "duration" },
    { "get_property", "volume" },
  })

  if not results then
    return { active = false }
  end

  local function rd(i) return results[i] end

  local title    = (rd(1) and rd(1).data)                                   or "Unknown Title"
  local is_paused = (rd(2) and rd(2).data == true)
  local time_pos  = (rd(3) and type(rd(3).data) == "number") and math.floor(rd(3).data) or 0
  local duration  = (rd(4) and type(rd(4).data) == "number") and math.floor(rd(4).data) or 0
  local volume    = (rd(5) and type(rd(5).data) == "number") and math.floor(rd(5).data) or cfg.default_volume

  return {
    active    = true,
    title     = title,
    is_paused = is_paused,
    time_pos  = time_pos,
    duration  = duration,
    volume    = volume,
  }
end

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function format_time(sec)
  if not sec or sec <= 0 then return "00:00" end
  local m = math.floor(sec / 60)
  local s = sec % 60
  return string.format("%02d:%02d", m, s)
end

function M.show_status()
  local st = M.get_status_data()
  if not st.active then
    vim.notify("No active YouTube background playback.", vim.log.levels.WARN)
    return
  end
  local icon     = st.is_paused and "⏸" or "▶"
  local time_str = format_time(st.time_pos) .. " / " .. format_time(st.duration)
  vim.notify(string.format("󰗃 %s %s\n⏱ %s | 🔊 %d%%", icon, st.title, time_str, st.volume), vim.log.levels.INFO)
end

-- ── Floating HUD Control Panel ────────────────────────────────────────────────
local hud_buf   = nil
local hud_win   = nil
local hud_timer = nil

local function cleanup_hud_timer()
  if hud_timer then
    pcall(function()
      if not hud_timer:is_closing() then
        hud_timer:stop()
        hud_timer:close()
      end
    end)
    hud_timer = nil
  end
end

local function setup_hud_syntax(buf)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd([[
      syntax clear
      syntax match YtHudHeader "NOW PLAYING"
      syntax match YtHudHeader "CONTROLS"
      syntax match YtHudKey "\[[a-zA-Z0-9/+= -]\+\]"
      syntax match YtHudPlaying "▶ Playing"
      syntax match YtHudPaused "⏸ Paused"
      syntax match YtHudStopped "⏹ No playback active"
      syntax match YtHudTime "%d%d:%d%d / %d%d:%d%d"

      highlight default link YtHudHeader Title
      highlight default link YtHudKey Special
      highlight default link YtHudPlaying DiagnosticOk
      highlight default link YtHudPaused DiagnosticWarn
      highlight default link YtHudStopped Comment
      highlight default link YtHudTime Number
    ]])
  end)
end

function M.open_control_panel()
  if not has_mpv() then
    vim.notify("mpv is not installed! Run :YouTubeInstallMpv or 'brew install mpv'.", vim.log.levels.WARN)
    return
  end

  if hud_win and vim.api.nvim_win_is_valid(hud_win) then
    vim.api.nvim_set_current_win(hud_win)
    return
  end

  -- Clean up any leftover timer before creating a new HUD
  cleanup_hud_timer()

  hud_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[hud_buf].bufhidden = "wipe"
  vim.bo[hud_buf].filetype  = "youtube_player_hud"

  local width  = 74
  local height = 12
  local row    = math.floor((vim.o.lines   - height) / 2)
  local col    = math.floor((vim.o.columns - width)  / 2)

  hud_win = vim.api.nvim_open_win(hud_buf, true, {
    relative  = "editor",
    width     = width,
    height    = height,
    row       = row,
    col       = col,
    style     = "minimal",
    border    = "rounded",
    title     = " 󰗃 YouTube Background Player ",
    title_pos = "center",
  })

  vim.wo[hud_win].wrap         = false
  vim.wo[hud_win].number       = false
  vim.wo[hud_win].relativenumber = false
  vim.wo[hud_win].cursorline   = false
  vim.wo[hud_win].signcolumn   = "no"

  setup_hud_syntax(hud_buf)

  -- Refresh HUD content
  local function refresh_hud()
    if not (hud_buf and vim.api.nvim_buf_is_valid(hud_buf)) then return end

    local st    = M.get_status_data()
    local lines = {}
    table.insert(lines, "  󰗃 NOW PLAYING ──────────────────────────────────────────────────")

    if not st.active then
      table.insert(lines, "   Status   : ⏹ No playback active")
      table.insert(lines, "   Title    : -")
      table.insert(lines, "   Progress : [░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░]  00:00 / 00:00")
      table.insert(lines, "   Volume   : 🔊 -")
    else
      local status_str  = st.is_paused and "⏸ Paused" or "▶ Playing"
      local progress_len = 30
      local pct         = st.duration > 0 and (st.time_pos / st.duration) or 0
      local filled      = math.max(0, math.min(progress_len, math.floor(pct * progress_len)))
      local pbar        = string.rep("█", filled) .. string.rep("░", progress_len - filled)
      local tstr        = format_time(st.time_pos) .. " / " .. format_time(st.duration)

      local title_str   = st.title
      if #title_str > 48 then title_str = title_str:sub(1, 45) .. "..." end

      local vol_bar_len = 10
      local vol_filled  = math.max(0, math.min(vol_bar_len, math.floor((st.volume / 100) * vol_bar_len)))
      local vbar        = string.rep("█", vol_filled) .. string.rep("░", vol_bar_len - vol_filled)

      table.insert(lines, "   Status   : " .. status_str)
      table.insert(lines, "   Title    : " .. title_str)
      table.insert(lines, string.format("   Progress : [%s]  %s", pbar, tstr))
      table.insert(lines, string.format("   Volume   : 🔊 %d%%  [%s]", st.volume, vbar))
    end

    table.insert(lines, "")
    table.insert(lines, "  󰘵 CONTROLS ─────────────────────────────────────────────────────")
    table.insert(lines, "   [p/Space] Play/Pause    [+] Vol +5%    [f] Seek +10s   [u] New URL")
    table.insert(lines, "   [s]       Stop          [-] Vol -5%    [b] Seek -10s   [q/Esc] Close")
    table.insert(lines, "   [i]       Install mpv")

    vim.bo[hud_buf].modifiable = true
    vim.api.nvim_buf_set_lines(hud_buf, 0, -1, false, lines)
    vim.bo[hud_buf].modifiable = false
  end

  refresh_hud()

  -- Keybindings inside HUD
  local map_opts = { buffer = hud_buf, silent = true, noremap = true }
  vim.keymap.set("n", "p",       function() M.toggle_pause()    refresh_hud() end, map_opts)
  vim.keymap.set("n", "<space>", function() M.toggle_pause()    refresh_hud() end, map_opts)
  vim.keymap.set("n", "s",       function() M.stop()            refresh_hud() end, map_opts)
  vim.keymap.set("n", "+",       function() M.adjust_volume(5)  refresh_hud() end, map_opts)
  vim.keymap.set("n", "=",       function() M.adjust_volume(5)  refresh_hud() end, map_opts)
  vim.keymap.set("n", "-",       function() M.adjust_volume(-5) refresh_hud() end, map_opts)
  vim.keymap.set("n", "f",       function() M.seek(10)          refresh_hud() end, map_opts)
  vim.keymap.set("n", "<Right>", function() M.seek(10)          refresh_hud() end, map_opts)
  vim.keymap.set("n", "l",       function() M.seek(10)          refresh_hud() end, map_opts)
  vim.keymap.set("n", "b",       function() M.seek(-10)         refresh_hud() end, map_opts)
  vim.keymap.set("n", "<Left>",  function() M.seek(-10)         refresh_hud() end, map_opts)
  vim.keymap.set("n", "h",       function() M.seek(-10)         refresh_hud() end, map_opts)
  vim.keymap.set("n", "u", function()
    if hud_win and vim.api.nvim_win_is_valid(hud_win) then
      vim.api.nvim_win_close(hud_win, true)
    end
    M.play()
  end, map_opts)
  vim.keymap.set("n", "i", function() M.install_mpv() end, map_opts)
  local function close_hud()
    if hud_win and vim.api.nvim_win_is_valid(hud_win) then
      vim.api.nvim_win_close(hud_win, true)
    end
  end
  vim.keymap.set("n", "q",     close_hud, map_opts)
  vim.keymap.set("n", "<Esc>", close_hud, map_opts)

  -- Clean up timer when the HUD buffer is wiped (closed by any means)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer   = hud_buf,
    once     = true,
    callback = cleanup_hud_timer,
  })

  -- Periodic 1-second refresh while the HUD window is open
  hud_timer = vim.uv.new_timer()
  hud_timer:start(1000, 1000, vim.schedule_wrap(function()
    if hud_win and vim.api.nvim_win_is_valid(hud_win) then
      refresh_hud()
    else
      cleanup_hud_timer()
    end
  end))
end

-- ── Install mpv helper ────────────────────────────────────────────────────────
function M.install_mpv()
  if has_mpv() then
    vim.notify("mpv is already installed!", vim.log.levels.INFO)
    return
  end
  local script = [[
clear
printf '\033[1;38;5;75m⚡ Installing mpv via Homebrew...\033[0m\n\n'
brew install mpv
_x=$?
if [ "$_x" -eq 0 ]; then
  printf '\n\033[1;32m✓ mpv installed successfully!\033[0m press any key to close\n'
else
  printf '\n\033[1;31m✗ Installation failed (exit %s)\033[0m press any key to close\n' "$_x"
fi
read -n1 -s
]]
  if _G.Snacks then
    _G.Snacks.terminal("bash -c " .. vim.fn.shellescape(script), {
      win = {
        position  = "bottom",
        height    = 0.35,
        border    = "rounded",
        title     = " ⚡ Install mpv ",
        title_pos = "center",
      },
    })
  else
    vim.fn.system("brew install mpv")
    vim.notify("mpv installation complete!", vim.log.levels.INFO)
  end
end

return M
