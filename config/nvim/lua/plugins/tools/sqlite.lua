-- ─────────────────────────────────────────────────────────────────────────────
-- 🗄️  nvim-dbee — VSCode-style SQLite / Database Browser
--
-- Click any .db / .sqlite / .sqlite3 file in nvim-tree and it opens
-- automatically as a formatted table grid — no prompts, no manual steps.
--
-- Layout:
--   Left   → Drawer  : connection tree + table list + call log
--   Center → Editor  : SQL scratch pad
--   Bottom → Result  : formatted table grid with column headers & rows
--
-- Keymaps:
--   <leader>So  → Open  DB browser
--   <leader>Sc  → Close DB browser
--   <leader>St  → Toggle DB browser
--
-- Inside the Drawer:
--   o / <CR>    expand node / load table data into result grid
--   r           refresh connection
--   A           add a connection manually
--   dd          remove connection
-- Inside the Result grid:
--   <C-n>       next page of rows
--   <C-p>       previous page of rows
--   yy          yank current row
-- Inside the Editor:
--   BB          run query in current buffer
-- ─────────────────────────────────────────────────────────────────────────────

return {
  {
    "kndndrj/nvim-dbee",
    dependencies = { "MunifTanjim/nui.nvim" },

    -- Build / download the Go backend binary on install or update
    build = function()
      require("dbee").install()
    end,

    cmd  = { "Dbee" },
    keys = {
      { "<leader>So", function() require("dbee").open()   end, desc = "DB: Open browser"   },
      { "<leader>Sc", function() require("dbee").close()  end, desc = "DB: Close browser"  },
      { "<leader>St", function() require("dbee").toggle() end, desc = "DB: Toggle browser" },
    },

    -- ── init: runs at Neovim startup (even though the plugin is lazy) ─────────
    -- We register the BufReadPost autocmd here so it fires the moment a .db
    -- file is opened — before Neovim renders any binary garbage.
    init = function()
      -- Persistent connections file — FileSource reads/writes JSON here
      local conn_file = vim.fn.stdpath("data") .. "/dbee/connections.json"
      vim.fn.mkdir(vim.fn.fnamemodify(conn_file, ":h"), "p")

      -- Store for config() to reference
      vim.g._dbee_conn_file = conn_file

      vim.api.nvim_create_autocmd("BufReadPost", {
        pattern = { "*.db", "*.sqlite", "*.sqlite3" },
        group   = vim.api.nvim_create_augroup("NamiDbeeAutoOpen", { clear = true }),
        callback = function(ev)
          local buf     = ev.buf
          local db_path = vim.fn.fnamemodify(ev.file, ":p")
          local db_name = vim.fn.fnamemodify(db_path, ":t:r")

          -- ── Step 1: write the connection to the JSON file BEFORE loading dbee
          -- This way FileSource picks it up on first load without any API calls.
          local existing = {}
          local fh = io.open(conn_file, "r")
          if fh then
            local ok, decoded = pcall(vim.fn.json_decode, fh:read("*all"))
            fh:close()
            if ok and type(decoded) == "table" then existing = decoded end
          end

          local found = false
          for _, c in ipairs(existing) do
            if c.url == db_path then found = true; break end
          end

          if not found then
            table.insert(existing, {
              -- dbee uses "type" not "driver"; SQLite URL is the raw file path
              id   = "sqlite_" .. db_name .. "_" .. vim.fn.sha256(db_path):sub(1, 8),
              name = db_name,
              type = "sqlite",
              url  = db_path,
            })
            local fw = io.open(conn_file, "w")
            if fw then
              local ok2, json = pcall(vim.fn.json_encode, existing)
              if ok2 then fw:write(json) end
              fw:close()
            end
          end

          vim.schedule(function()
            -- ── Step 2: wipe the binary buffer; open blank screen first
            vim.cmd("enew")
            if vim.api.nvim_buf_is_valid(buf) then
              vim.api.nvim_buf_delete(buf, { force = true })
            end

            -- ── Step 3: force-load the lazy plugin
            vim.cmd("Lazy load nvim-dbee")

            -- ── Step 4: if plugin is already initialised, reload the source
            --            so the newly written connection appears without restart
            local ok, dbee = pcall(require, "dbee")
            if ok and dbee.is_core_loaded and dbee.is_core_loaded() then
              local source_name = vim.fs.basename(conn_file) -- "connections.json"
              pcall(function()
                dbee.handler():source_reload(source_name)
              end)
            end

            -- ── Step 5: open the browser
            if ok then dbee.open() end
          end)
        end,
      })
    end,

    -- ── config: runs when the plugin is first loaded (lazy trigger) ──────────
    config = function()
      local conn_file = vim.g._dbee_conn_file
                     or (vim.fn.stdpath("data") .. "/dbee/connections.json")

      require("dbee").setup({
        -- FileSource: persistent JSON file; supports create/delete/update from UI
        sources = {
          require("dbee.sources").FileSource:new(conn_file),
        },

        -- Result grid
        result = {
          page_size = 100,
          mappings  = {
            { key = "<C-n>", mode = "n", action = "page_next"       },
            { key = "<C-p>", mode = "n", action = "page_prev"       },
            { key = "yy",    mode = "n", action = "yank_current_row" },
          },
        },

        -- SQL Editor
        editor = {
          mappings = {
            { key = "BB",         mode = "n", action = "run_file" },
            { key = "<C-Return>", mode = "n", action = "run_file" },
          },
        },

        -- Drawer (connection tree)
        drawer = {
          disable_candies = false,
          mappings = {
            { key = "o",    mode = "n", action = "toggle_node"    },
            { key = "<CR>", mode = "n", action = "action_1"       },
            { key = "r",    mode = "n", action = "refresh"        },
            { key = "dd",   mode = "n", action = "remove"         },
            { key = "A",    mode = "n", action = "add"            },
            { key = "q",    mode = "n", action = "close"          },
          },
        },
      })
    end,
  },
}
