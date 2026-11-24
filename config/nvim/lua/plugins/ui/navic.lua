-- plugins/ui/navic.lua
-- nvim-navic: LSP-powered breadcrumb location context.
-- Hooks into every LSP client's on_attach so the statusline can
-- show  File › Class › function  in the centre section.
return {
  {
    "SmiteshP/nvim-navic",
    lazy = true,  -- loaded on demand by lualine + lspconfig on_attach
    opts = {
      lsp = {
        auto_attach = true,   -- automatically hooks into every LSP client
        preference  = nil,    -- use whichever client attaches first
      },
      highlight   = true,     -- use LSP semantic token colours for breadcrumb segments
      separator   = "  ❯  ", -- same separator as dropbar for visual consistency
      depth_limit = 5,        -- max depth to show before truncating
      depth_limit_indicator = "…",
      safe_output = true,     -- don't error if navic can't get location
      icons = {
        File          = "󰈙 ",
        Module        = " ",
        Namespace     = "󰌗 ",
        Package       = " ",
        Class         = "󰌗 ",
        Method        = "󰆧 ",
        Property      = " ",
        Field         = " ",
        Constructor   = " ",
        Enum          = "󰕘 ",
        Interface     = "󰕘 ",
        Function      = "󰊕 ",
        Variable      = "󰆧 ",
        Constant      = "󰏿 ",
        String        = "󰀬 ",
        Number        = "󰎠 ",
        Boolean       = "◩ ",
        Array         = "󰅪 ",
        Object        = "󰅩 ",
        Key           = "󰌋 ",
        Null          = "󰟢 ",
        EnumMember    = " ",
        Struct        = "󰌗 ",
        Event         = " ",
        Operator      = "󰆕 ",
        TypeParameter = "󰊄 ",
      },
    },
  },
}
