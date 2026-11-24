-- ─────────────────────────────────────────────────────────────────────────────
-- 🌊 NamiConfig Plugin Index
-- All plugin modules imported by lazy.nvim on startup
-- ─────────────────────────────────────────────────────────────────────────────

return {
  -- ── UI & Aesthetics ────────────────────────────────────────────────────────
  { import = "plugins.ui.theme" },
  { import = "plugins.ui.bufferline" },
  { import = "plugins.ui.statusline" },
  { import = "plugins.ui.noice" },
  { import = "plugins.ui.dropbar" },
  { import = "plugins.ui.snacks" },
  { import = "plugins.ui.treesitter-context" },
  { import = "plugins.ui.glow" },
  { import = "plugins.ui.misc" },
  { import = "plugins.ui.navic" },       -- LSP breadcrumbs for statusline
  { import = "plugins.ui.illuminate" },  -- word-under-cursor highlights
  { import = "plugins.ui.hlchunk" },     -- animated scope-bracket decorations
  { import = "plugins.ui.smear_cursor" }, -- animated cursor movement
  { import = "plugins.ui.satellite" },   -- scrollbar with diagnostic/git markers
  { import = "plugins.ui.tint" },        -- dim inactive splits
  { import = "plugins.ui.ufo" },         -- modern LSP/treesitter code folding
  { import = "plugins.ui.winbar" },      -- per-window path/breadcrumb bar
  { import = "plugins.ui.fidget" },      -- LSP progress corner spinner

  -- ── Core Editor Enhancements ───────────────────────────────────────────────
  { import = "plugins.editor.treesitter" },
  { import = "plugins.editor.cmp" },
  { import = "plugins.editor.autopairs" },
  { import = "plugins.editor.comment" },
  { import = "plugins.editor.autosave" },
  { import = "plugins.editor.persistence" },
  { import = "plugins.editor.flash" },      -- instant jump anywhere in buffer

  -- ── Language Server, Formatting, Linting & Debugging ──────────────────────
  { import = "plugins.lsp.mason" },
  { import = "plugins.lsp.lspconfig" },
  { import = "plugins.lsp.dap" },
  { import = "plugins.lsp.neoconf" },
  { import = "plugins.lsp.conform" },
  { import = "plugins.lsp.lint" },

  -- ── Standalone Tools ───────────────────────────────────────────────────────
  { import = "plugins.tools.kulala" },
  { import = "plugins.tools.leetcode" },
  { import = "plugins.tools.syntax" },
  { import = "plugins.tools.sqlite" },

  -- ── Git Integration ───────────────────────────────────────────────────────
  { import = "plugins.git.gitsigns" },
  { import = "plugins.git.diffview" },

  -- ── AI Assistants ─────────────────────────────────────────────────────────
  { import = "plugins.ai.supermaven" },
  { import = "plugins.ai.claudecode" },

  -- ── Language-Specific Plugins ─────────────────────────────────────────────
  { import = "plugins.lang.django" },
  { import = "plugins.lang.lazydev" },
  { import = "plugins.lang.prisma" },
}
