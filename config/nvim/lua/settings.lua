-- ==============================================================================
-- 🌊  NamiConfig — User Settings (Generated)
-- ==============================================================================
-- Edit this file or use the web GUI to configure your Neovim experience.
-- Hot-reload: changes take effect on :w without restarting Neovim.
-- ==============================================================================

return {
  ui = {
    theme = "atelier", -- follows the desktop theme (quickshell-atelier), live
    background = "dark",
    transparent = true,
    dim_inactive = true,
    show_indent_guides = true,
    smooth_scroll = true,
    cmdheight = 0,
    picker = {
      layout = "telescope",
      border = "rounded",
      width = 0.85,
      height = 0.80,
    },
    neovide = {
      transparency = 0,
      line_height = 0,
    },
    bufferline_style = "nvchad",
  },
  editor = {
    highlight_current_line = true,
    show_line_numbers = true,
    relative_line_numbers = true,
    format_on_save = true,
    tab_size = 0,
    mouse_support = false,
    wrap_lines = true,
    scrolloff = 0,
    auto_save = true,
    color_column = "",
    split_below = true,
    split_right = true,
    ignore_case_search = true,
  },
  lsp = {
    enable_inlay_hints = true,
    show_inline_errors = true,
  },
  explorer = {
    show_hidden = true,
    position = "left",
  },
  linting = {
    enable = true,
  },
  project = {
    enable_config = true,
  },
  extras = {
    "plugins.extras.lang.go",
    "plugins.extras.lang.rust",
    "plugins.extras.lang.sql",
    "plugins.extras.lang.tailwindcss",
    "plugins.extras.testing.neotest",
  },
  custom_tools = {
    lsp_servers = {},
    mason_tools = {},
  },
  youtube_player = {
    ipc_socket = "/tmp/namiconfig_yt_mpv.sock",
    default_volume = 80,
    seek_step = 10,
    volume_step = 5,
  },
}
