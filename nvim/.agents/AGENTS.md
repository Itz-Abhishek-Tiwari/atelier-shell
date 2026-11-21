# NamiConfig Project Rules for AI Agents

Welcome to **NamiConfig** — a modular, registry-driven Neovim configuration built on `lazy.nvim` and Neovim 0.10+.

When modifying, extending, or debugging this repository, always follow these core architectural rules:

---

## 🏗 Core Architecture & Design Principles

### 1. Single Source of Truth (`lua/core/lang_registry.lua`)
- **NEVER** write ad-hoc, duplicate configurations for LSP servers, Mason tools, formatters, or linters across multiple plugin files.
- All per-language definitions (LSP server name, Mason packages, `conform.nvim` formatters, and `nvim-lint` linters) must be declared in `lua/core/lang_registry.lua` under `M.langs`.
- When adding support for a new language, update `lua/core/lang_registry.lua` first.

### 2. Declarative User Settings (`lua/settings.lua`)
- `lua/settings.lua` is the primary interface for users.
- Keep user options organized into logical tables (`ui`, `editor`, `lsp`, `explorer`, `linting`, `extras`, `custom_tools`).
- When introducing a new configurable feature or setting, add sensible default values in `lua/settings.lua` and retrieve them in plugin specs via `require("core.settings_loader")`.

### 3. Modular Plugin Breakdown (`lua/plugins/`)
Plugins are grouped cleanly by category:
- `lua/plugins/ui/` — Theme, statusline, bufferline, dropbar, noice, snacks UI.
- `lua/plugins/editor/` — Treesitter, cmp completion, autopairs, comment, autosave, etc.
- `lua/plugins/lsp/` — Mason, lspconfig, DAP debugging.
- `lua/plugins/git/` — Gitsigns, diffview.
- `lua/plugins/ai/` — AI integrations (Supermaven, Avante, etc.).
- `lua/plugins/formatting/` — Conform.nvim setup.
- `lua/plugins/linting/` — Nvim-lint setup.
- `lua/plugins/lang/` — Language-specific plugins (e.g. `prisma.lua`, `django.lua`).
- `lua/plugins/extras/` — Opt-in extra language & feature packs (e.g., `extras/lang/go.lua`, `extras/testing/neotest.lua`).

> ⚠️ **IMPORTANT**: When creating a new plugin file under `lua/plugins/`, you **MUST** import it in `lua/plugins/init.lua` (e.g. `{ import = "plugins.editor.myplugin" }`).

### 4. Keymap Conventions
- Leader key is `<leader>` (`Space`).
- Follow standard group prefixes:
  - `<leader>f` — Find / Search (Snacks picker, Telescope)
  - `<leader>c` — Code / LSP (Format, Lint, Code Actions, Rename)
  - `<leader>g` — Git (LazyGit, Diffview, Blame, Hunks)
  - `<leader>d` — Debug (DAP breakpoints, continue, step over/in)
  - `<leader>t` — Toggles & Themes
  - `<leader>a` — AI Assistant (Chat, Refactor, Inline completion)
- Register new key bindings with `which-key.nvim` or include descriptive `desc` fields in `vim.keymap.set`.

### 5. Verification & Testing Rule
- **NEVER** finish a turn without testing your configuration changes.
- Always run headless Neovim syntax verification:
  ```bash
  nvim --headless -c "q"
  ```
- Or run the validation script:
  ```bash
  bash .agents/skills/namiconfig-management/scripts/validate_config.sh
  ```
- Verify that there are zero Lua syntax errors or plugin loading failures.
