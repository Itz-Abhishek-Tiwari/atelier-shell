---
name: namiconfig-management
description: Manage, extend, configure, and debug NamiConfig (the Neovim configuration). Use when adding new languages to lang_registry, introducing new plugins in lua/plugins/, updating lua/settings.lua, customizing keymaps, or verifying Neovim configuration validity headlessly.
---

# NamiConfig Management Skill

This skill provides step-by-step instructions for AI agents to inspect, extend, modify, and debug **NamiConfig** (a modular, registry-driven Neovim configuration built on `lazy.nvim` and Neovim 0.10+).

---

## 🗺 Architecture Overview

| Layer | File / Directory | Purpose |
|-------|------------------|---------|
| **Entry Point** | `init.lua` | Bootstraps `lazy.nvim` and loads core modules |
| **Language Registry** | `lua/core/lang_registry.lua` | **Single source of truth** for LSP, Mason, formatters, linters |
| **User Settings** | `lua/settings.lua` | Declarative user-facing options (themes, key behavior, extras) |
| **Settings Loader** | `lua/core/settings_loader.lua` | Parses and normalizes `settings.lua` |
| **Global Keymaps** | `lua/core/keymaps.lua` | Global keybindings (`<leader>` maps) |
| **Plugin Specifications** | `lua/plugins/` | Categorized Lazy plugin specs |
| **Plugin Loader Index** | `lua/plugins/init.lua` | Registers all plugin modules to be imported by `lazy.nvim` |

---

## 🛠 Common Workflows

### Workflow 1: Adding a New Language

To add support for a new language (e.g. `elixir`, `zig`, `kotlin`, `gleam`):

1. **Update `lua/core/lang_registry.lua`**:
   Add an entry under `M.langs`:
   ```lua
   elixir = {
     lsp        = "elixirls",
     mason      = { "elixir-ls" },
     formatters = { "mix" },
     linters    = { "credo" },
     lsp_opts   = { ... }, -- (optional custom lspconfig settings)
   },
   ```

2. **Register Treesitter Parsers (if needed)**:
   Check `lua/plugins/editor/treesitter.lua` and ensure the parser is included in `ensure_installed`.

3. **Validate the Configuration**:
   Run the validation script:
   ```bash
   bash .agents/skills/namiconfig-management/scripts/validate_config.sh
   ```

---

### Workflow 2: Adding a New Plugin

1. **Determine the Plugin Category**:
   Choose the appropriate directory under `lua/plugins/`:
   - `ui/` — Visuals, theme, statusline, dropbar, notifications
   - `editor/` — Editing enhancements, completion, motion, refactoring
   - `lsp/` — Language server, mason, DAP tools
   - `git/` — Git utilities, diff tools, PR viewers
   - `ai/` — AI chat/completion assistants
   - `extras/` — Opt-in modular packs (`extras/lang/` or `extras/testing/`)

2. **Create the Plugin File**:
   Example: `lua/plugins/editor/flash.lua`
   ```lua
   return {
     "folke/flash.nvim",
     event = "VeryLazy",
     opts = {},
     keys = {
       { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash Jump" },
     },
   }
   ```

3. **Register in `lua/plugins/init.lua`** (⚠️ **CRITICAL**):
   Add `{ import = "plugins.editor.flash" }` to `lua/plugins/init.lua`.

4. **Verify**:
   Run headless Neovim to verify lazy.nvim parses the plugin spec cleanly:
   ```bash
   nvim --headless -c "q"
   ```

---

### Workflow 3: Adding or Updating User Options

1. **Edit `lua/settings.lua`**:
   Add your new option into the logical table (`ui`, `editor`, `lsp`, etc.).
2. **Consume in Plugin / Core Spec**:
   Retrieve setting values using `settings_loader`:
   ```lua
   local settings = require("core.settings_loader").get()
   if settings.ui.my_new_feature then
     -- apply configuration
   end
   ```

---

### Workflow 4: Adding Keymaps

1. Global keymaps belong in `lua/core/keymaps.lua`.
2. Plugin-specific keymaps belong inside the plugin specification `keys` table (or `config` function).
3. Use `<leader>` (`Space`) as leader key.
4. Always provide a clear `desc` field so `which-key.nvim` formats the popup label nicely.

---

## 🔍 Validation & Testing Checklist

Before finishing any task in NamiConfig:

- [ ] Execute `.agents/skills/namiconfig-management/scripts/validate_config.sh`
- [ ] Ensure all newly created files in `lua/plugins/` are imported in `lua/plugins/init.lua`.
- [ ] Confirm no hardcoded duplicate LSP / formatter configs bypass `lua/core/lang_registry.lua`.
- [ ] Test that user options in `lua/settings.lua` take effect without crashing.

---

## 🐛 Troubleshooting

* **Plugin not loading?** Check if `{ import = "plugins.<category>.<file>" }` is present in `lua/plugins/init.lua`.
* **LSP server not starting?** Verify the LSP server name matches official `nvim-lspconfig` server names in `lua/core/lang_registry.lua`.
* **Mason tool failing to install?** Ensure the Mason package name matches the exact name in Mason's registry.
