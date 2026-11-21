-- plugins/ui/ufo.lua
-- nvim-ufo: modern code folding with fold-count virtual text.
-- Shows "▶ 12 lines" instead of the usual ---- fold indicator.
return {
  {
    "kevinhwang91/nvim-ufo",
    event        = { "BufReadPost", "BufNewFile" },
    dependencies = { "kevinhwang91/promise-async" },

    init = function()
      -- Neovim requires these opt values BEFORE the plugin loads
      vim.o.foldcolumn    = "0"   -- small left gutter column shows fold markers
      vim.o.foldlevel     = 99    -- start with all folds open
      vim.o.foldlevelstart = 99
      vim.o.foldenable    = true
    end,

    opts = {
      provider_selector = function(bufnr, filetype, buftype)
        -- Use indent-based folding for certain filetypes
        local indent_fts = { "markdown", "txt", "yaml", "toml", "ini" }
        for _, ft in ipairs(indent_fts) do
          if filetype == ft then return "indent" end
        end
        if buftype ~= "" then return "" end  -- skip non-file buffers

        local function handleFallbackException(err, providerName)
          if type(err) == "string" and err:match("UfoFallbackException") then
            return require("ufo").getFolds(bufnr, providerName)
          else
            return require("promise").reject(err)
          end
        end

        return function()
          return require("ufo").getFolds(bufnr, "lsp")
            :catch(function(err)
              return handleFallbackException(err, "treesitter")
            end)
            :catch(function(err)
              return handleFallbackException(err, "indent")
            end)
        end
      end,

      -- ── Virtual text on fold line ──────────────────────────────────────────
      fold_virt_text_handler = function(virtText, lnum, endLnum, width, truncate)
        local newVirtText = {}
        local totalLines  = endLnum - lnum
        local suffix      = ("  ▶ %d lines "):format(totalLines)
        local sufWidth    = vim.fn.strdisplaywidth(suffix)
        local targetWidth = width - sufWidth
        local curWidth    = 0

        for _, chunk in ipairs(virtText) do
          local chunkText  = chunk[1]
          local chunkWidth = vim.fn.strdisplaywidth(chunkText)
          if targetWidth > curWidth + chunkWidth then
            table.insert(newVirtText, chunk)
          else
            chunkText = truncate(chunkText, targetWidth - curWidth)
            table.insert(newVirtText, { chunkText, chunk[2] })
            chunkWidth = vim.fn.strdisplaywidth(chunkText)
            if curWidth + chunkWidth < targetWidth then
              suffix = suffix .. (" "):rep(targetWidth - curWidth - chunkWidth)
            end
            break
          end
          curWidth = curWidth + chunkWidth
        end

        table.insert(newVirtText, { suffix, "MoreMsg" })
        return newVirtText
      end,
    },

    config = function(_, opts)
      require("ufo").setup(opts)

      -- ── Keybindings ────────────────────────────────────────────────────────
      vim.keymap.set("n", "zR", require("ufo").openAllFolds,        { desc = "Open all folds" })
      vim.keymap.set("n", "zM", require("ufo").closeAllFolds,       { desc = "Close all folds" })
      vim.keymap.set("n", "zr", require("ufo").openFoldsExceptKinds, { desc = "Open folds except kinds" })
      vim.keymap.set("n", "zm", require("ufo").closeFoldsWith,      { desc = "Close folds with" })

      -- Peek inside a fold without opening it
      vim.keymap.set("n", "K", function()
        local winid = require("ufo").peekFoldedLinesUnderCursor()
        if not winid then
          vim.lsp.buf.hover()
        end
      end, { desc = "Peek fold / LSP hover" })
    end,
  },
}
