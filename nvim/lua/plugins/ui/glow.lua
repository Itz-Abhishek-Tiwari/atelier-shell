-- Premium Floating Glow Markdown Previewer with real-time autoupdates and fullscreen support
return {
  {
    dir = vim.fn.stdpath("config"),
    name = "glow-preview",
    ft = "markdown",
    config = function()
      local previews = {} -- active previews indexed by buffer number: { win = win, buf = buf, augroup = augroup, toggle_fs = function }

      local function toggle_glow()
        local src_buf = vim.api.nvim_get_current_buf()
        local file = vim.api.nvim_buf_get_name(src_buf)

        if file == "" or vim.bo[src_buf].filetype ~= "markdown" then
          vim.notify("GlowPreview: Not a markdown file", vim.log.levels.WARN, { title = "Glow" })
          return
        end

        -- If already open, close it
        if previews[src_buf] then
          local p = previews[src_buf]
          if p.win and vim.api.nvim_win_is_valid(p.win) then
            pcall(vim.api.nvim_win_close, p.win, true)
          end
          pcall(vim.api.nvim_del_augroup_by_id, p.augroup)
          previews[src_buf] = nil
          vim.notify("Glow Preview closed", vim.log.levels.INFO, { title = "Glow" })
          return
        end

        local src_win = vim.api.nvim_get_current_win()

        -- Geometry for right-side floating HUD panel
        local columns = vim.o.columns
        local lines = vim.o.lines
        local width = math.floor(columns * 0.45)
        local height = math.floor(lines * 0.82)
        local row = math.floor((lines - height) / 2) - 1
        local col = columns - width - 4

        -- Unique preview window
        local glow_win = vim.api.nvim_open_win(0, false, {
          relative  = "editor",
          style     = "minimal",
          border    = "rounded",
          width     = width,
          height    = height,
          row       = row,
          col       = col,
          title     = " 📝 Glow Preview [q: Close] ",
          title_pos = "center",
        })

        local glow_buf = nil
        local ag = vim.api.nvim_create_augroup("GlowPreview_" .. src_buf, { clear = true })

        local function cleanup()
          if previews[src_buf] then
            local p = previews[src_buf]
            pcall(vim.api.nvim_del_augroup_by_id, p.augroup)
            if p.win and vim.api.nvim_win_is_valid(p.win) then
              pcall(vim.api.nvim_win_close, p.win, true)
            end
            if glow_buf and vim.api.nvim_buf_is_valid(glow_buf) then
              pcall(vim.api.nvim_buf_delete, glow_buf, { force = true })
            end
            previews[src_buf] = nil
          end
        end

        local function render()
          if not vim.api.nvim_win_is_valid(glow_win) then
            return
          end

          local old_buf = glow_buf
          glow_buf = vim.api.nvim_create_buf(false, true)
          vim.bo[glow_buf].buflisted = false
          vim.api.nvim_win_set_buf(glow_win, glow_buf)

          if old_buf and vim.api.nvim_buf_is_valid(old_buf) then
            pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
          end

          local term_width = vim.api.nvim_win_get_width(glow_win) - 4
          vim.api.nvim_buf_call(glow_buf, function()
            vim.fn.termopen(string.format(
              "glow --style dark --width %d %s",
              term_width, vim.fn.shellescape(file)
            ))
          end)

          local wo = vim.wo[glow_win]
          wo.number         = false
          wo.relativenumber = false
          wo.signcolumn     = "no"
          wo.statuscolumn   = ""
          wo.foldcolumn     = "0"
          wo.winhighlight   = "Normal:NormalFloat,FloatBorder:FloatBorder"
          wo.winfixwidth    = true

          -- Bind local keymaps inside the new terminal scratch buffer
          local key_opts = { buffer = glow_buf, silent = true, nowait = true }
          vim.keymap.set("n", "f", function()
            if previews[src_buf] and previews[src_buf].toggle_fs then
              previews[src_buf].toggle_fs()
            end
          end, key_opts)
          vim.keymap.set("n", "<C-f>", function()
            if previews[src_buf] and previews[src_buf].toggle_fs then
              previews[src_buf].toggle_fs()
            end
          end, key_opts)

          -- Fast close keys
          vim.keymap.set("n", "q", cleanup, key_opts)
          vim.keymap.set("t", "q", cleanup, key_opts)
          vim.keymap.set("t", "<Esc>", cleanup, key_opts)
        end

        -- Initial render
        render()

        -- Focus back to code window
        vim.cmd("stopinsert")
        if vim.api.nvim_win_is_valid(src_win) then
          vim.api.nvim_set_current_win(src_win)
        end

        -- Dynamic fullscreen toggler (truly covers the whole editor window)
        local is_fullscreen = false
        local function toggle_fs()
          if not previews[src_buf] or not vim.api.nvim_win_is_valid(glow_win) then
            return
          end

          local term_cols = vim.o.columns
          local term_lines = vim.o.lines

          if not is_fullscreen then
            vim.api.nvim_win_set_config(glow_win, {
              relative = "editor",
              width    = term_cols,
              height   = term_lines,
              row      = 0,
              col      = 0,
              title    = " 🖥️ Fullscreen Preview [q: Close] ",
              title_pos = "center",
            })
            is_fullscreen = true
            vim.notify("Glow Preview: Fullscreen Mode 🖥️", vim.log.levels.INFO, { title = "Glow" })
          else
            local s_width = math.floor(term_cols * 0.45)
            local s_height = math.floor(term_lines * 0.82)
            local s_row = math.floor((term_lines - s_height) / 2) - 1
            local s_col = term_cols - s_width - 4

            vim.api.nvim_win_set_config(glow_win, {
              relative = "editor",
              width    = s_width,
              height   = s_height,
              row      = s_row,
              col      = s_col,
              title    = " 📝 Glow Preview [q: Close] ",
              title_pos = "center",
            })
            is_fullscreen = false
            vim.notify("Glow Preview: Sidebar Mode 📋", vim.log.levels.INFO, { title = "Glow" })
          end

          render()
        end

        vim.api.nvim_create_autocmd("BufWritePost", {
          group    = ag,
          buffer   = src_buf,
          callback = render,
        })

        vim.api.nvim_create_autocmd({ "BufUnload", "VimLeave" }, {
          group    = ag,
          buffer   = src_buf,
          callback = cleanup,
        })

        vim.api.nvim_create_autocmd("WinClosed", {
          group    = ag,
          pattern  = tostring(glow_win),
          callback = cleanup,
        })

        previews[src_buf] = { win = glow_win, buf = glow_buf, augroup = ag, toggle_fs = toggle_fs }
        vim.notify("Glow HUD Preview launched 🚀", vim.log.levels.INFO, { title = "Glow" })
      end

      -- Expose a global user command for fullscreen toggle
      vim.api.nvim_create_user_command("GlowPreviewFullscreen", function()
        local buf = vim.api.nvim_get_current_buf()
        if previews[buf] and previews[buf].toggle_fs then
          previews[buf].toggle_fs()
        else
          toggle_glow()
          vim.defer_fn(function()
            if previews[buf] and previews[buf].toggle_fs then
              previews[buf].toggle_fs()
            end
          end, 200)
        end
      end, {})

      vim.api.nvim_create_user_command("GlowPreview", toggle_glow, {})

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "markdown",
        callback = function()
          vim.keymap.set("n", "<leader>op", toggle_glow, {
            buffer = true,
            silent = true,
            desc   = "Toggle Glow HUD Preview",
          })
          vim.keymap.set("n", "<leader>of", "<cmd>GlowPreviewFullscreen<cr>", {
            buffer = true,
            silent = true,
            desc   = "Toggle Glow Fullscreen",
          })
        end,
      })
    end,
  },
}
