-- Claude Code inside Neovim (coder/claudecode.nvim): runs the `claude` CLI in a split and
-- speaks the same IDE protocol as the VS Code extension, so Claude sees the current file and
-- selection and proposes edits as native diffs (accept / deny below).

-- `claude` from PATH (native installer: ~/.local/bin/claude). Fallback: the binary bundled
-- with the VS Code extension, newest version first, until the CLI is installed.
local function claude_cmd()
  if vim.fn.executable("claude") == 1 then
    return "claude"
  end
  local found = vim.fn.glob(
    vim.fn.expand("~/.vscode/extensions") .. "/anthropic.claude-code-*/resources/native-binary/claude",
    false,
    true
  )
  table.sort(found, function(a, b) return a > b end)
  return found[1] or "claude"
end

return {
  "coder/claudecode.nvim",
  dependencies = { "folke/snacks.nvim" },
  cmd = {
    "ClaudeCode", "ClaudeCodeFocus", "ClaudeCodeSelectModel", "ClaudeCodeAdd",
    "ClaudeCodeSend", "ClaudeCodeTreeAdd", "ClaudeCodeDiffAccept", "ClaudeCodeDiffDeny",
  },
  opts = {
    terminal_cmd = claude_cmd(),
    terminal = {
      split_side = "right",
      split_width_percentage = 0.38,
    },
  },
  keys = {
    { "<leader>a", nil, desc = "AI / Claude Code" },
    { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "Claude: toggle" },
    { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Claude: focus" },
    { "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Claude: resume a session" },
    { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Claude: continue last session" },
    { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Claude: select model" },
    { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Claude: add current buffer" },
    { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Claude: send selection" },
    {
      "<leader>as",
      "<cmd>ClaudeCodeTreeAdd<cr>",
      desc = "Claude: add file",
      ft = { "NvimTree", "neo-tree", "oil", "minifiles", "snacks_picker_list" },
    },
    { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Claude: accept diff" },
    { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Claude: deny diff" },
  },
}
