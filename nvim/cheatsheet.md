# 🌊 NamiConfig — Full Documentation & Cheatsheet

Press `<leader>?` or `<leader>ch` anytime to toggle this Cheat Sheet!

---

## ⌨️ Key Definitions & Modifiers
| Key | Description |
| :--- | :--- |
| `<leader>` | Spacebar |
| `<C-...>` | Ctrl + Key |
| `<A-...>` | Option (Mac) / Alt (Linux/Windows) + Key |
| `<S-...>` | Shift + Key |

---

## 🧭 Documentation & Help Shortcuts
| Key | Action | Description |
| :--- | :--- | :--- |
| `<leader>?` | **Open Documentation** | Displays this interactive cheat sheet in a float |
| `<leader>ch` | **Open Documentation** | Displays this interactive cheat sheet in a float |
| `<leader>doc` | **Open Documentation** | Displays this interactive cheat sheet in a float |
| `<leader>ce` | **Edit Documentation** | Opens `cheatsheet.md` in editor mode |
| `<leader>sk` | **Search All Keymaps** | Interactive picker to search every active shortcut |

---

## 🚀 Core Navigation & Editor Options
| Key | Action | Description |
| :--- | :--- | :--- |
| `jk` | **Escape Insert Mode** | Quick exit to Normal mode |
| `;` | **Command Mode** | Enter `:` command mode directly with `;` |
| `<Esc>` | **Clear Highlights** | Clear search highlighting |
| `<C-s>` | **Save File** | Save current buffer |
| `<C-q>` | **Quit** | Close current window / quit |
| `<leader>q` | **Quit Neovim** | Exit Neovim safely |
| `<leader>th` | **Theme Switcher** | Interactive theme picker (persists choice) |
| `<leader>ts` | **Web Settings GUI** | Open interactive browser GUI with Live Preview (`:NamiSettings`) |
| `<leader>tn` | **Toggle Line Numbers** | Toggle absolute line numbers |
| `<leader>tr` | **Toggle Relative Numbers** | Toggle relative line numbers |
| `<leader>tc` | **Toggle Treesitter Context** | Toggle sticky function/class context header |
| `<leader>z` | **Zen Mode** | Toggle distraction-free coding mode |

---

## 📁 File Explorer & Search Pickers
| Key | Action | Description |
| :--- | :--- | :--- |
| `<leader>e` | **Focus File Explorer** | Focus or open file tree (`snacks.explorer`) |
| `<C-n>` | **Toggle File Explorer** | Open/close side file explorer |
| `<leader>ff` | **Find Files** | Fuzzy search files in workspace |
| `<leader>fw` | **Live Grep** | Search string across entire project |
| `<leader>fo` | **Recent Files** | Pick from recently opened files |
| `<leader>fb` | **Find Buffers** | Search active open buffers |
| `<leader>fz` | **Fuzzy Search Buffer** | Search lines in current file |
| `<leader>ma` | **Find Marks** | Pick jump marks |

---

## 🪟 Windows & Buffers
| Key | Action | Description |
| :--- | :--- | :--- |
| `<C-h>` | **Window Left** | Move to left window split |
| `<C-j>` | **Window Down** | Move to lower window split |
| `<C-k>` | **Window Up** | Move to upper window split |
| `<C-l>` | **Window Right** | Move to right window split |
| `<Tab>` | **Next Buffer** | Cycle to next buffer tab |
| `<S-Tab>` | **Prev Buffer** | Cycle to previous buffer tab |
| `<leader>x` | **Close Buffer** | Delete current buffer without messing layout |

---

## ⚡ Code Editing, Formatting & LSP
| Key | Action | Description |
| :--- | :--- | :--- |
| `<leader>/` | **Toggle Comment** | Comment/uncomment lines or visual selection |
| `<A-j>` / `<A-k>` | **Move Lines** | Move line/selection down or up |
| `<leader>fm` / `<leader>cf` | **Format Code** | Format buffer via `conform.nvim` (Prettier/StyLua/Black) |
| `gd` | **Go to Definition** | Jump to symbol definition |
| `gD` | **Go to Declaration** | Jump to symbol declaration |
| `gi` | **Go to Implementation** | Jump to implementation |
| `gr` | **Go to References** | Find all references of symbol |
| `K` | **Hover Documentation** | Show symbol docs/signature in float |
| `<leader>ca` | **Code Action** | Trigger LSP code fixes / refactors |
| `<leader>ra` | **Rename Symbol** | Project-wide symbol rename |
| `[d` / `]d` | **Prev/Next Diagnostic** | Jump between diagnostics/errors |
| `<leader>ds` | **Diagnostics Picker** | Open list of all project errors/warnings |
| `<leader>cl` | **Lint Current File** | Manual async lint check via `nvim-lint` |
| `<leader>tl` | **Toggle Linting** | Enable/disable auto-linting |

---

## 🟢 Node.js, Express.js & Web Development
- **LSPs**: `ts_ls` (JS/TS), `jsonls` (JSON / `package.json`), `emmet_language_server`, `tailwindcss`, `html`, `cssls`.
- **Formatting & Linting**: Auto-formats with `prettier` on save. Auto-lints with `eslint_d`.
- **NPM Package Completion**: Editing `package.json` triggers `cmp-npm` for auto-suggesting package names and registry versions.
- **Express / JS Snippets**: Fast insertion of `express.Router()`, `req`, `res`, `next()`, async handlers, and middleware.

---

## 💎 Prisma ORM Integration
- **LSP (`prismals`)**: Auto-loaded for `schema.prisma` files. Provides schema completion, relation validation, model type checks, and inline diagnostics.
- **Formatting**: Auto-formats `.prisma` files on save using Prettier/Prisma formatter.
- **Treesitter**: Full syntax highlighting for models, fields, `@relation`, `@default`, and enums.

---

## 🌐 Express REST API Request Tester (`kulala.nvim`)
Create or open any `.http` or `.rest` file (e.g. `api.http`):
| Key | Action | Description |
| :--- | :--- | :--- |
| `<leader>R` | **Run HTTP Request** | Send API request under cursor |
| `<leader>Rt` | **Toggle View** | Switch between response headers & body |
| `<leader>Rc` | **Copy as cURL** | Copy request as cURL command to clipboard |

---

## 🐛 Node.js & Code Debugging (DAP)
| Key | Action | Description |
| :--- | :--- | :--- |
| `<leader>db` | **Toggle Breakpoint** | Set/remove debug breakpoint on current line |
| `<leader>dc` | **Start / Continue Debug** | Launch Node.js debugger / attach to Express process |
| `<leader>dso` | **Step Over** | Step over current statement |
| `<leader>dsi` | **Step Into** | Step inside function call |
| `<leader>dt` | **Terminate Session** | Stop active debugging session |

*Supported Debuggers*: Node.js (`pwa-node` / `js-debug-adapter`), Python (`debugpy`).

---

## 🏃 Code Runner
| Key | Action | Description |
| :--- | :--- | :--- |
| `<leader>rr` | **Run Current File** | Runs JS/TS via `node`/`tsx` or Python via active virtualenv in a floating terminal |

---

## 🐍 Python Virtual Environment Manager
| Key | Action | Description |
| :--- | :--- | :--- |
| `<leader>vs` | **Select Python Venv** | Interactively pick local `.venv`, `poetry`, or global virtualenv |

---

## 🖥️ Floating & Split Terminals
| Key | Action | Description |
| :--- | :--- | :--- |
| `<C-\`>` | **Toggle Floating Terminal** | Open/hide floating terminal popup |
| `<A-h>` | **Toggle Bottom Terminal** | Open/hide horizontal terminal split at bottom |
| `<A-v>` | **Toggle Right Terminal** | Open/hide vertical terminal split on right |
| `<Esc><Esc>` | **Exit Terminal Mode** | Exit terminal insert mode to navigate windows |

---

## 🐙 Git Integration
| Key | Action | Description |
| :--- | :--- | :--- |
| `<leader>gg` | **Open Lazygit** | Full-screen interactive LazyGit UI |
| `<leader>gf` | **Lazygit Current File** | Open LazyGit for current file history |
| `<leader>gt` | **Git Status** | Picker for git status & changed files |
| `<leader>gc` | **Git Commits** | Search git commit history |
| `<leader>gd` | **Git Diff** | Preview git diffs |
| `<leader>gb` | **Git Branches** | Switch or search git branches |
| `<leader>gB` | **Git Browse** | Open current file/repo in GitHub / GitLab browser |

---

## 🏆 LeetCode Plugin
| Key | Action | Description |
| :--- | :--- | :--- |
| `<leader>lc` | **Open LeetCode** | Open LeetCode dashboard & problem browser |
| `<leader>lr` | **Run Test Cases** | Save & run test cases asynchronously |
| `<leader>ls` | **Submit Solution** | Submit code to LeetCode |
| `<leader>ld` | **Problem Description** | Show problem statement panel |
| `<leader>li` | **Problem Info** | Show problem stats & details |

---

## 󰗃 YouTube Background Audio Player
| Key / Command | Action | Description |
| :--- | :--- | :--- |
| `<leader>yp` / `<leader>yt` | **Play YouTube URL** | Input YouTube link (pre-fills clipboard URL) & stream audio in background |
| `<leader>yc` | **Control Panel HUD** | Open interactive floating HUD window with progress bar & hotkeys |
| `<leader>ys` | **Toggle Pause / Play** | Pause or resume background YouTube playback |
| `<leader>yx` | **Stop Playback** | Stop YouTube audio stream and reset |
| `<leader>y+` / `<leader>y-` | **Volume Up / Down** | Adjust audio volume (+5% / -5%) |
| `<leader>yf` / `<leader>yb` | **Seek Forward / Backward** | Jump audio forward (+10s) or backward (-10s) |
| `<leader>yi` | **Now Playing Info** | Display notification with song title, elapsed time, and volume |
| `:YouTubePlay [url]` | **Command Play** | Stream YouTube audio in background |
| `:YouTubeControls` | **Command HUD** | Open interactive control panel HUD |
| `:YouTubeInstallMpv` | **Install mpv** | Auto-install `mpv` player via Homebrew |

