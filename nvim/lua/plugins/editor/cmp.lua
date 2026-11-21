-- nvim-cmp: autocomplete with lspkind icons
return {
  {
    "hrsh7th/nvim-cmp",
    event        = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-nvim-lua",
      {
        "L3MON4D3/LuaSnip",
        version      = "v2.*",
        build        = "make install_jsregexp",
        dependencies = { "rafamadriz/friendly-snippets" },
        config       = function()
          require("luasnip.loaders.from_vscode").lazy_load()
        end,
      },
      "saadparwaiz1/cmp_luasnip",
      "onsails/lspkind.nvim",
      {
        "David-Kunz/cmp-npm",
        dependencies = { "nvim-lua/plenary.nvim" },
        ft = "json",
        config = function()
          require("cmp-npm").setup({})
        end,
      },
    },
    config = function()
      local cmp     = require("cmp")
      local luasnip = require("luasnip")
      local lspkind = require("lspkind")

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        completion = { completeopt = "menu,menuone" },
        window = {
          completion = {
            border = "none",
            winhighlight = "Normal:Pmenu,FloatBorder:PmenuBorder,CursorLine:PmenuSel,Search:None",
            side_padding = 1,
            col_offset = -3,
          },
          documentation = cmp.config.window.bordered({
            border = require("settings").menu_border or "rounded",
            winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:PmenuSel,Search:None",
          }),
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"]     = cmp.mapping.scroll_docs(-4),
          ["<C-f>"]     = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"]     = cmp.mapping.abort(),
          ["<CR>"]      = cmp.mapping.confirm({ select = false }),
          ["<Tab>"]     = cmp.mapping(function(fallback)
            local has_supermaven, supermaven = pcall(require, "supermaven-nvim.completion_preview")
            if has_supermaven and supermaven.has_suggestion() then
              supermaven.on_accept_suggestion()
            elseif cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "lazydev", group_index = 0 }, -- Skip loading LuaLS completions
          { name = "nvim_lsp", priority = 1000 },
          { name = "npm",      priority = 800 },
          { name = "luasnip",  priority = 750 },
          { name = "nvim_lua", priority = 500 },
        }, {
          { name = "buffer", priority = 250 },
          { name = "path",   priority = 100 },
        }),
        sorting = {
          priority_weight = 2,
          comparators = {
            function(entry1, entry2)
              local detail1 = entry1.completion_item.detail or ""
              local detail2 = entry2.completion_item.detail or ""

              local is_rn1 = detail1:find("react%-native") ~= nil
              local is_rn2 = detail2:find("react%-native") ~= nil

              if is_rn1 and not is_rn2 then
                return true
              elseif not is_rn1 and is_rn2 then
                return false
              end
            end,
            cmp.config.compare.offset,
            cmp.config.compare.exact,
            cmp.config.compare.score,
            cmp.config.compare.recently_used,
            cmp.config.compare.locality,
            cmp.config.compare.kind,
            cmp.config.compare.sort_text,
            cmp.config.compare.length,
            cmp.config.compare.order,
          },
        },
        formatting = {
          fields = { "abbr", "kind" },
          format = function(entry, vim_item)
            -- 1. Use manual Nerd Font icons for guaranteed stability
            local icons = {
              Text = "󰉿", Method = "󰆧", Function = "󰊕", Constructor = "",
              Field = "󰜢", Variable = "󰀫", Class = "󰠱", Interface = "",
              Module = "", Property = "󰜢", Unit = "󰑭", Value = "󰎠",
              Enum = "", Keyword = "󰌋", Snippet = "", Color = "󰏘",
              File = "󰈙", Reference = "󰈇", Folder = "󰉋", EnumMember = "",
              Constant = "󰏿", Struct = "󰙅", Event = "", Operator = "󰆕",
              TypeParameter = "󰊄", Supermaven = "",
            }
            local icon = icons[vim_item.kind] or "󰍪"
            vim_item.kind = string.format("%s %s", icon, vim_item.kind)

            -- 2. Clean up the menu text (removes [LSP] etc)
            vim_item.menu = ""

            -- 3. Apply Tailwind colorizer icons if tailwindcss-colorizer-cmp is loaded
            local ok_tw, tw_colorizer = pcall(require, "tailwindcss-colorizer-cmp")
            if ok_tw then
              vim_item = tw_colorizer.formatter(entry, vim_item)
            end

            -- 4. Apply color squares from nvim-highlight-colors if it's a color!
            local colors_ok, highlight_colors = pcall(require, "nvim-highlight-colors")
            if colors_ok then
              -- Pass a dummy item to not mess up our string
              local color_item = highlight_colors.format(entry, { kind = vim_item.kind })
              if color_item and color_item.abbr_hl_group then
                vim_item.kind_hl_group = color_item.abbr_hl_group
                vim_item.kind = color_item.abbr .. " Color"
              end
            end

            return vim_item
          end,
        },
      })
    end,
  },
}
