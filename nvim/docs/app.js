/* ============================================================
   NamiConfig Docs — App Logic v2
   ============================================================ */

// ── Theme Simulator Data ────────────────────────────────────
const THEMES = {
  kanagawa:    { bg:'#1f1f28', surface:'#2a2a37', kw:'#957fb8', fn:'#7e9cd8', str:'#98bb6c', num:'#d27e99', comment:'#727169', field:'#7aa89f' },
  catppuccin:  { bg:'#1e1e2e', surface:'#313244', kw:'#cba6f7', fn:'#89b4fa', str:'#a6e3a1', num:'#fab387', comment:'#6c7086', field:'#94e2d5' },
  'rose-pine': { bg:'#191724', surface:'#26233a', kw:'#c4a7e7', fn:'#9ccfd8', str:'#f6c177', num:'#eb6f92', comment:'#6e6a86', field:'#ebbcba' },
  tokyonight:  { bg:'#1a1b26', surface:'#24283b', kw:'#bb9af7', fn:'#7aa2f7', str:'#9ece6a', num:'#ff9e64', comment:'#565f89', field:'#73daca' },
  gruvbox:     { bg:'#282828', surface:'#3c3836', kw:'#fb4934', fn:'#8ec07c', str:'#b8bb26', num:'#d3869b', comment:'#928374', field:'#83a598' },
  nord:        { bg:'#2e3440', surface:'#3b4252', kw:'#81a1c1', fn:'#88c0d0', str:'#a3be8c', num:'#b48ead', comment:'#4c566a', field:'#8fbcbb' },
};

function applyTheme(name) {
  const t = THEMES[name];
  if (!t) return;
  const ed = document.getElementById('sim-editor');
  if (!ed) return;

  // Dynamic header background sync to avoid color split mismatch
  const head = ed.parentElement ? ed.parentElement.querySelector('.ink-panel-head') : null;
  if (head) {
    head.style.backgroundColor = t.surface;
    head.style.transition = 'background .35s ease';
  }

  ed.style.backgroundColor  = t.bg;
  ed.style.color             = t.field;
  ed.style.transition        = 'background .35s ease, color .35s ease';
  ed.querySelectorAll('.kw').forEach(el      => { el.style.color = t.kw;      el.style.transition = 'color .3s'; });
  ed.querySelectorAll('.fn').forEach(el      => { el.style.color = t.fn;      el.style.transition = 'color .3s'; });
  ed.querySelectorAll('.str').forEach(el     => { el.style.color = t.str;     el.style.transition = 'color .3s'; });
  ed.querySelectorAll('.num').forEach(el     => { el.style.color = t.num;     el.style.transition = 'color .3s'; });
  ed.querySelectorAll('.cmt').forEach(el     => { el.style.color = t.comment; el.style.transition = 'color .3s'; });
  ed.querySelectorAll('.field').forEach(el   => { el.style.color = t.field;   el.style.transition = 'color .3s'; });
  ed.querySelectorAll('.ln').forEach(el          => { el.style.color = t.comment; });
}



// ── Copy to clipboard ────────────────────────────────────────
function initCopy() {
  document.querySelectorAll('[data-copy]').forEach(btn => {
    btn.addEventListener('click', e => {
      e.stopPropagation();
      const text = btn.dataset.copy;
      navigator.clipboard.writeText(text)
        .then(() => {
          const origHTML = btn.innerHTML;
          // Temporarily show success state
          if (origHTML.includes('Copy setup')) {
            btn.innerHTML = '<iconify-icon icon="tabler:check" width="15"></iconify-icon> Copied!';
          } else if (origHTML.includes('Copy')) {
            btn.innerHTML = '<iconify-icon icon="tabler:check" width="14"></iconify-icon> Copied';
          } else {
            btn.innerHTML = '<iconify-icon icon="tabler:check" width="14"></iconify-icon>';
          }
          btn.style.borderColor = '#3F5D4A';
          btn.style.color = '#3F5D4A';
          setTimeout(() => {
            btn.innerHTML = origHTML;
            btn.style.borderColor = '';
            btn.style.color = '';
          }, 1500);
        })
        .catch(() => {});
    });
  });
}

// ── Tab navigation ───────────────────────────────────────────
function initTabs() {
  const links = document.querySelectorAll('.chapter-link');
  const panes = document.querySelectorAll('.chapter-pane');
  const crumb = document.getElementById('crumb');

  const chapterNames = {
    home: 'Ch. 01 · Home',
    start: 'Ch. 02 · Get Started',
    docs: 'Ch. 03 · Architecture',
    keymaps: 'Ch. 04 · Keymaps',
    langs: 'Ch. 05 · Languages',
    settings: 'Ch. 06 · Settings GUI'
  };

  function go(id) {
    if (!id) id = 'home';
    links.forEach(l => {
      const active = l.dataset.chapter === id;
      l.classList.toggle('bg-ink/5', active);
      l.classList.toggle('dark:bg-white/5', active);
      l.classList.toggle('text-moss', active);
      l.classList.toggle('dark:text-brass', active);
    });
    
    panes.forEach(p => p.classList.toggle('active', p.id === id));
    
    if (crumb && chapterNames[id]) {
      crumb.innerHTML = chapterNames[id];
    }
    
    window.scrollTo({ top: 0, behavior: 'smooth' });
    history.replaceState(null, '', '#' + id);
  }

  links.forEach(l => {
    l.addEventListener('click', () => go(l.dataset.chapter));
  });

  // data-nav buttons inside content
  document.querySelectorAll('[data-nav]').forEach(el => {
    el.addEventListener('click', () => go(el.dataset.nav));
  });

  // Restore from URL hash
  const hash = location.hash.slice(1);
  if (hash && document.getElementById(hash)) {
    go(hash);
  } else {
    go('home');
  }
}

// ── Theme switcher ───────────────────────────────────────────
function initTheme() {
  const pills = document.querySelectorAll('.t-pill');
  // Apply default
  applyTheme('kanagawa');
  pills.forEach(p => {
    p.addEventListener('click', () => {
      pills.forEach(pp => pp.classList.remove('active'));
      p.classList.add('active');
      applyTheme(p.dataset.theme);
    });
  });
}

// ── Keymap search & filter ───────────────────────────────────
function initKeymaps() {
  const search = document.getElementById('km-search');
  const rows   = document.querySelectorAll('#km-body tr');
  const pills  = document.querySelectorAll('.f-pill');

  let activecat = 'all';

  function filter() {
    const q = search.value.toLowerCase().trim();
    rows.forEach(row => {
      const matchCat   = activecat === 'all' || row.dataset.cat === activecat;
      const matchQuery = !q || row.textContent.toLowerCase().includes(q);
      row.style.display = (matchCat && matchQuery) ? '' : 'none';
    });
  }

  if (search) search.addEventListener('input', filter);

  pills.forEach(p => {
    p.addEventListener('click', () => {
      pills.forEach(pp => pp.classList.remove('active'));
      p.classList.add('active');
      activecat = p.dataset.cat;
      filter();
    });
  });
}

// ── Language search ──────────────────────────────────────────
function initLangs() {
  const search = document.getElementById('lang-search');
  const rows   = document.querySelectorAll('#lang-body tr');
  if (!search) return;
  search.addEventListener('input', () => {
    const q = search.value.toLowerCase().trim();
    rows.forEach(row => {
      row.style.display = (!q || row.textContent.toLowerCase().includes(q)) ? '' : 'none';
    });
  });
}

// ── Intersection observer — stagger stat cards ───────────────
function initObserver() {
  if (!window.IntersectionObserver) return;
  const obs = new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (e.isIntersecting) {
        e.target.style.animationPlayState = 'running';
        obs.unobserve(e.target);
      }
    });
  }, { threshold: .15 });
  document.querySelectorAll('.stat-card, .feature-card, .step-item').forEach(el => {
    el.style.animationPlayState = 'paused';
    obs.observe(el);
  });
}

// ── Theme Toggle Controls ────────────────────────────────────
function initThemeToggle() {
  const toggle = document.getElementById('theme-toggle');
  if (!toggle) return;
  
  const icon = document.getElementById('theme-icon');
  const label = document.getElementById('theme-label');
  
  function updateUI(isDark) {
    if (isDark) {
      document.documentElement.classList.add('dark');
      if (icon) icon.setAttribute('icon', 'tabler:sun');
      if (label) label.textContent = 'Light mode';
      localStorage.setItem('nami-theme', 'dark');
    } else {
      document.documentElement.classList.remove('dark');
      if (icon) icon.setAttribute('icon', 'tabler:moon');
      if (label) label.textContent = 'Dark mode';
      localStorage.setItem('nami-theme', 'light');
    }
  }

  // Initial update based on document state
  updateUI(document.documentElement.classList.contains('dark'));

  toggle.addEventListener('click', () => {
    const isDark = document.documentElement.classList.contains('dark');
    updateUI(!isDark);
  });
}

// ── Sidebar Controls ─────────────────────────────────────────
window.toggleSidebar = function() {
  const sidebar = document.getElementById('sidebar');
  const backdrop = document.getElementById('sidebar-backdrop');
  if (window.innerWidth < 1024) {
    sidebar.classList.toggle('open');
    if (sidebar.classList.contains('open')) {
      backdrop.classList.remove('opacity-0', 'pointer-events-none');
    } else {
      backdrop.classList.add('opacity-0', 'pointer-events-none');
    }
  } else {
    sidebar.classList.toggle('collapsed');
  }
};

window.closeSidebar = function() {
  const sidebar = document.getElementById('sidebar');
  const backdrop = document.getElementById('sidebar-backdrop');
  sidebar.classList.remove('open');
  backdrop.classList.add('opacity-0', 'pointer-events-none');
};

window.openSidebar = function() {
  const sidebar = document.getElementById('sidebar');
  const backdrop = document.getElementById('sidebar-backdrop');
  sidebar.classList.add('open');
  backdrop.classList.remove('opacity-0', 'pointer-events-none');
};

// ── Toast Notification System ────────────────────────────────
function showToast(message, type = 'info') {
  const container = document.getElementById('toasts');
  if (!container) return;
  const t = document.createElement('div');
  t.className = `px-4 py-3 rounded-lg shadow-lg text-sm transition-all duration-300 transform translate-y-2 opacity-0 flex items-center gap-2 border text-[#EDE7DA] bg-panel border-white/10 z-50`;
  
  let icon = 'tabler:info-circle';
  if (type === 'success') {
    icon = 'tabler:circle-check';
    t.style.borderColor = '#3F5D4A';
  } else if (type === 'error') {
    icon = 'tabler:alert-triangle';
    t.style.borderColor = '#A34A2E';
  }
  
  t.innerHTML = `<iconify-icon icon="${icon}" width="16"></iconify-icon><span>${message}</span>`;
  container.appendChild(t);
  
  // Fade in
  setTimeout(() => {
    t.classList.remove('opacity-0', 'translate-y-2');
  }, 10);

  // Fade out
  setTimeout(() => {
    t.classList.add('opacity-0', 'translate-y-2');
    setTimeout(() => t.remove(), 300);
  }, 3000);
}

// ── Settings GUI Logic ───────────────────────────────────────
let currentSettings = null;

let isReadOnly = false;

async function initSettings() {
  const settingsSection = document.getElementById('settings');
  if (!settingsSection) return;

  // Let's first try to fetch the settings from Neovim
  try {
    const res = await fetch('/api/settings');
    if (!res.ok) throw new Error('API not available');
    currentSettings = await res.json();
  } catch (err) {
    console.warn('API not available, settings GUI running in read-only preview mode.');
    isReadOnly = true;
    
    // Show a warning inside the settings tab
    const warning = document.createElement('div');
    warning.className = 'p-4 mb-6 rounded-lg bg-rust/10 border border-rust text-sm text-rust flex items-center gap-3';
    warning.innerHTML = `<iconify-icon icon="tabler:alert-triangle" width="18"></iconify-icon>
      <div><strong>Read-Only Mode:</strong> The local Neovim server is not running. To enable saving configuration changes, run Neovim and start the server using <code class="bg-black/10 dark:bg-black/30 px-1 py-0.5 rounded font-mono">:NamiSettings</code> or <code class="bg-black/10 dark:bg-black/30 px-1 py-0.5 rounded font-mono">&lt;leader&gt;ts</code>.</div>`;
    
    if (settingsSection.firstElementChild) {
      settingsSection.insertBefore(warning, settingsSection.firstElementChild);
    }
    
    convertSelectsToCustom();
    updateCustomTags('setting-custom_tools-lsp_servers', 'custom-lsp-tags');
    updateCustomTags('setting-custom_tools-mason_tools', 'custom-mason-tags');
    return;
  }

  // Populate UI form with settings values
  populateForm(currentSettings);
  convertSelectsToCustom();
  updateCustomTags('setting-custom_tools-lsp_servers', 'custom-lsp-tags');
  updateCustomTags('setting-custom_tools-mason_tools', 'custom-mason-tags');
  updateLivePreview(currentSettings);

  // Sync background dropdown automatically when theme changes
  const themeSelect = document.getElementById('setting-ui-theme');
  const bgSelect = document.getElementById('setting-ui-background');
  if (themeSelect && bgSelect) {
    const LIGHT_THEMES = [
      'kanagawa-lotus',
      'catppuccin-latte',
      'tokyonight-day',
      'rose-pine-dawn',
      'github_light',
      'onedark-light'
    ];
    themeSelect.addEventListener('change', (e) => {
      const theme = e.target.value;
      const newBg = LIGHT_THEMES.includes(theme) ? 'light' : 'dark';
      if (bgSelect.value !== newBg) {
        bgSelect.value = newBg;
        bgSelect.dispatchEvent(new Event('change', { bubbles: true }));
      }
    });
  }

  // Set up auto-save handlers
  let autoSaveTimeout = null;

  const triggerAutoSave = async () => {
    const updated = collectFormSettings();
    updateLivePreview(updated);
    if (isReadOnly) return;
    try {
      const urlParams = new URLSearchParams(window.location.search);
      const serverAddr = urlParams.get('server') || '';
      
      const saveRes = await fetch(`/api/settings${serverAddr ? '?server=' + encodeURIComponent(serverAddr) : ''}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updated)
      });
      if (saveRes.ok) {
        showToast('Configuration updated! ⚡', 'success');
      }
    } catch (e) {
      showToast('Sync failed: ' + e.message, 'error');
    }
  };

  // Immediate save for toggles (checkboxes) and dropdowns (selects)
  settingsSection.addEventListener('change', (e) => {
    if (e.target.type === 'checkbox' || e.target.tagName === 'SELECT') {
      triggerAutoSave();
    }
  });

  // Debounced save for text/number fields to avoid incomplete writes while typing
  settingsSection.addEventListener('input', (e) => {
    if (e.target.type === 'text' || e.target.type === 'number') {
      clearTimeout(autoSaveTimeout);
      autoSaveTimeout = setTimeout(triggerAutoSave, 600);
    }
  });

  // Start auto-reload SSE listener
  setupSSE();
}

function setupSSE() {
  try {
    const source = new EventSource('/api/events');
    source.onmessage = async (event) => {
      if (event.data === 'reload') {
        try {
          const res = await fetch('/api/settings');
          if (res.ok) {
            currentSettings = await res.json();
            populateForm(currentSettings);
            showToast('Settings synced from Neovim 🔄', 'info');
          }
        } catch (e) {
          console.error('Failed to sync settings:', e);
        }
      }
    };
    source.onerror = () => {
      // EventSource automatically handles reconnect attempts
    };
  } catch (err) {
    console.warn('SSE auto-reload is not supported or failed to initialize:', err);
  }
}

function populateForm(settings) {
  // Helper to set checkbox checked state
  const setCheck = (id, val) => {
    const el = document.getElementById(id);
    if (el && document.activeElement !== el) el.checked = !!val;
  };
  
  // Helper to set select/input value
  const setVal = (id, val) => {
    const el = document.getElementById(id);
    if (el && document.activeElement !== el) {
      const newVal = val !== undefined && val !== null ? val : '';
      if (el.value !== newVal) {
        el.value = newVal;
        el.dispatchEvent(new Event('change', { bubbles: true }));
      }
    }
  };

  // UI Settings
  const ui = settings.ui || {};
  setVal('setting-ui-theme', ui.theme);
  setVal('setting-ui-background', ui.background);
  setCheck('setting-ui-transparent', ui.transparent);
  setCheck('setting-ui-dim_inactive', ui.dim_inactive);
  setCheck('setting-ui-show_indent_guides', ui.show_indent_guides);
  setCheck('setting-ui-smooth_scroll', ui.smooth_scroll);
  setVal('setting-ui-cmdheight', ui.cmdheight);
  setVal('setting-ui-bufferline_style', ui.bufferline_style);

  const picker = ui.picker || {};
  setVal('setting-ui-picker-layout', picker.layout);
  setVal('setting-ui-picker-border', picker.border);
  setVal('setting-ui-picker-width', picker.width);
  setVal('setting-ui-picker-height', picker.height);

  const neovide = ui.neovide || {};
  setVal('setting-ui-neovide-transparency', neovide.transparency);
  setVal('setting-ui-neovide-line_height', neovide.line_height);

  // Editor Settings
  const ed = settings.editor || {};
  setCheck('setting-editor-highlight_current_line', ed.highlight_current_line);
  setCheck('setting-editor-show_line_numbers', ed.show_line_numbers);
  setCheck('setting-editor-relative_line_numbers', ed.relative_line_numbers);
  setCheck('setting-editor-format_on_save', ed.format_on_save);
  setCheck('setting-editor-auto_save', ed.auto_save);
  setCheck('setting-editor-mouse_support', ed.mouse_support);
  setCheck('setting-editor-wrap_lines', ed.wrap_lines);
  setCheck('setting-editor-split_below', ed.split_below);
  setCheck('setting-editor-split_right', ed.split_right);
  setCheck('setting-editor-ignore_case_search', ed.ignore_case_search);
  setVal('setting-editor-tab_size', ed.tab_size);
  setVal('setting-editor-scrolloff', ed.scrolloff);
  setVal('setting-editor-color_column', ed.color_column);

  // LSP Settings
  const lsp = settings.lsp || {};
  setCheck('setting-lsp-enable_inlay_hints', lsp.enable_inlay_hints);
  setCheck('setting-lsp-show_inline_errors', lsp.show_inline_errors);

  // Linting Settings
  const lint = settings.linting || {};
  setCheck('setting-linting-enable', lint.enable);

  // Project Settings
  const proj = settings.project || {};
  setCheck('setting-project-enable_config', proj.enable_config);

  // Explorer Settings
  const exp = settings.explorer || {};
  setCheck('setting-explorer-show_hidden', exp.show_hidden);
  setVal('setting-explorer-position', exp.position);

  // Extras Settings
  const extras = settings.extras || [];
  document.querySelectorAll('.setting-extra-checkbox').forEach(cb => {
    cb.checked = extras.includes(cb.dataset.extra);
  });

  // Custom Tools Settings
  const ct = settings.custom_tools || {};
  const lspServers = ct.lsp_servers || [];
  const masonTools = ct.mason_tools || [];
  setVal('setting-custom_tools-lsp_servers', lspServers.join(', '));
  setVal('setting-custom_tools-mason_tools', masonTools.join(', '));
}

function collectFormSettings() {
  const getCheck = (id) => {
    const el = document.getElementById(id);
    return el ? el.checked : false;
  };

  const getVal = (id) => {
    const el = document.getElementById(id);
    return el ? el.value : '';
  };

  const getNum = (id) => {
    const val = getVal(id);
    return val !== '' ? parseFloat(val) : 0;
  };

  const getInt = (id) => {
    const val = getVal(id);
    return val !== '' ? parseInt(val, 10) : 0;
  };

  // Collect extras
  const extras = [];
  document.querySelectorAll('.setting-extra-checkbox').forEach(cb => {
    if (cb.checked) {
      extras.push(cb.dataset.extra);
    }
  });

  // Parse custom tools inputs
  const parseCommaList = (id) => {
    const text = getVal(id);
    return text.split(',')
      .map(s => s.trim())
      .filter(s => s.length > 0);
  };

  const formValues = {
    ui: {
      theme: getVal('setting-ui-theme'),
      background: getVal('setting-ui-background'),
      transparent: getCheck('setting-ui-transparent'),
      dim_inactive: getCheck('setting-ui-dim_inactive'),
      show_indent_guides: getCheck('setting-ui-show_indent_guides'),
      smooth_scroll: getCheck('setting-ui-smooth_scroll'),
      cmdheight: getInt('setting-ui-cmdheight'),
      picker: {
        layout: getVal('setting-ui-picker-layout'),
        border: getVal('setting-ui-picker-border'),
        width: getNum('setting-ui-picker-width'),
        height: getNum('setting-ui-picker-height')
      },
      neovide: {
        transparency: getNum('setting-ui-neovide-transparency'),
        line_height: getNum('setting-ui-neovide-line_height')
      },
      bufferline_style: getVal('setting-ui-bufferline_style')
    },
    editor: {
      highlight_current_line: getCheck('setting-editor-highlight_current_line'),
      show_line_numbers: getCheck('setting-editor-show_line_numbers'),
      relative_line_numbers: getCheck('setting-editor-relative_line_numbers'),
      format_on_save: getCheck('setting-editor-format_on_save'),
      tab_size: getInt('setting-editor-tab_size'),
      mouse_support: getCheck('setting-editor-mouse_support'),
      wrap_lines: getCheck('setting-editor-wrap_lines'),
      scrolloff: getInt('setting-editor-scrolloff'),
      auto_save: getCheck('setting-editor-auto_save'),
      color_column: getVal('setting-editor-color_column'),
      split_below: getCheck('setting-editor-split_below'),
      split_right: getCheck('setting-editor-split_right'),
      ignore_case_search: getCheck('setting-editor-ignore_case_search')
    },
    lsp: {
      enable_inlay_hints: getCheck('setting-lsp-enable_inlay_hints'),
      show_inline_errors: getCheck('setting-lsp-show_inline_errors')
    },
    explorer: {
      show_hidden: getCheck('setting-explorer-show_hidden'),
      position: getVal('setting-explorer-position')
    },
    linting: {
      enable: getCheck('setting-linting-enable')
    },
    project: {
      enable_config: getCheck('setting-project-enable_config')
    },
    extras: extras,
    custom_tools: {
      lsp_servers: parseCommaList('setting-custom_tools-lsp_servers'),
      mason_tools: parseCommaList('setting-custom_tools-mason_tools')
    }
  };

  // Deep-merge form values into the last-known settings object so that keys
  // not exposed in the GUI (e.g. youtube_player) are never silently dropped.
  if (currentSettings && typeof currentSettings === 'object') {
    const base = JSON.parse(JSON.stringify(currentSettings));
    const deepMerge = (target, source) => {
      for (const key of Object.keys(source)) {
        if (source[key] !== null && typeof source[key] === 'object' && !Array.isArray(source[key])) {
          target[key] = target[key] || {};
          deepMerge(target[key], source[key]);
        } else {
          target[key] = source[key];
        }
      }
      return target;
    };
    return deepMerge(base, formValues);
  }

  return formValues;
}


function convertSelectsToCustom() {
  const settingsSection = document.getElementById('settings');
  if (!settingsSection) return;

  const selects = settingsSection.querySelectorAll('select');
  selects.forEach(select => {
    // Check if already converted
    if (select.nextElementSibling && select.nextElementSibling.classList.contains('custom-select-container')) {
      return;
    }

    // Hide original select
    select.style.display = 'none';

    // Create wrapper
    const container = document.createElement('div');
    container.className = 'custom-select-container relative w-full';

    // Create trigger button
    const trigger = document.createElement('button');
    trigger.type = 'button';
    trigger.className = 'custom-select-trigger w-full flex items-center justify-between px-3 py-2 rounded border border-ink/10 dark:border-white/10 bg-paper dark:bg-inkdark text-left text-sm outline-none focus:ring-2 focus:ring-moss/20 dark:focus:ring-brass/20 focus:border-moss dark:focus:border-brass transition-all duration-200';
    trigger.innerHTML = `
      <span class="custom-select-label"></span>
      <iconify-icon icon="tabler:chevron-down" class="custom-select-chevron text-ink/40 dark:text-[#A79C87] transition-transform duration-200" width="16"></iconify-icon>
    `;

    // Create options dropdown
    const optionsMenu = document.createElement('div');
    optionsMenu.className = 'custom-select-options absolute left-0 right-0 mt-1 max-h-60 overflow-y-auto rounded border border-ink/10 dark:border-white/10 bg-paper dark:bg-inkdark z-50 hidden shadow-lg py-1';

    container.appendChild(trigger);
    container.appendChild(optionsMenu);
    select.parentNode.insertBefore(container, select.nextSibling);

    const updateLabel = () => {
      const selectedOpt = select.options[select.selectedIndex];
      const label = container.querySelector('.custom-select-label');
      if (label && selectedOpt) {
        label.textContent = selectedOpt.textContent;
      }
      
      // Update active option styling in dropdown
      optionsMenu.querySelectorAll('.custom-select-option').forEach(opt => {
        if (opt.dataset.value === select.value) {
          opt.classList.add('bg-moss/5', 'dark:bg-brass/5', 'text-moss', 'dark:text-brass', 'font-medium');
        } else {
          opt.classList.remove('bg-moss/5', 'dark:bg-brass/5', 'text-moss', 'dark:text-brass', 'font-medium');
        }
      });
    };

    // Rebuild options menu based on original select structure
    const rebuildOptions = () => {
      optionsMenu.innerHTML = '';
      
      const processOption = (opt) => {
        const item = document.createElement('div');
        item.className = 'custom-select-option px-3 py-1.5 text-sm text-ink/80 dark:text-[#A79C87] hover:bg-moss/10 dark:hover:bg-brass/10 hover:text-moss dark:hover:text-brass cursor-pointer transition-colors duration-150';
        item.textContent = opt.textContent;
        item.dataset.value = opt.value;
        item.addEventListener('click', (e) => {
          e.stopPropagation();
          select.value = opt.value;
          select.dispatchEvent(new Event('change', { bubbles: true }));
          optionsMenu.classList.add('hidden');
          trigger.querySelector('.custom-select-chevron').style.transform = '';
          trigger.classList.remove('border-moss', 'dark:border-brass', 'ring-2', 'ring-moss/20', 'dark:ring-brass/20');
        });
        optionsMenu.appendChild(item);
      };

      // Handle optgroups or direct children
      Array.from(select.children).forEach(child => {
        if (child.tagName === 'OPTGROUP') {
          const header = document.createElement('div');
          header.className = 'px-3 py-1 text-[10px] uppercase tracking-wider text-ink/40 dark:text-[#A79C87]/40 font-bold select-none cursor-default';
          header.textContent = child.label;
          optionsMenu.appendChild(header);

          Array.from(child.children).forEach(opt => {
            processOption(opt);
          });
        } else if (child.tagName === 'OPTION') {
          processOption(child);
        }
      });
    };

    rebuildOptions();
    updateLabel();

    // Toggle dropdown
    trigger.addEventListener('click', (e) => {
      e.stopPropagation();
      
      // Close all other custom dropdowns first
      document.querySelectorAll('.custom-select-options').forEach(menu => {
        if (menu !== optionsMenu) {
          menu.classList.add('hidden');
          const siblingTrigger = menu.previousElementSibling;
          if (siblingTrigger) {
            siblingTrigger.querySelector('.custom-select-chevron').style.transform = '';
            siblingTrigger.classList.remove('border-moss', 'dark:border-brass', 'ring-2', 'ring-moss/20', 'dark:ring-brass/20');
          }
        }
      });

      const isHidden = optionsMenu.classList.contains('hidden');
      if (isHidden) {
        optionsMenu.classList.remove('hidden');
        trigger.querySelector('.custom-select-chevron').style.transform = 'rotate(180deg)';
        trigger.classList.add('border-moss', 'dark:border-brass', 'ring-2', 'ring-moss/20', 'dark:ring-brass/20');
        
        // Scroll active item into view inside dropdown
        const activeItem = optionsMenu.querySelector('.font-medium');
        if (activeItem) {
          optionsMenu.scrollTop = activeItem.offsetTop - 40;
        }
      } else {
        optionsMenu.classList.add('hidden');
        trigger.querySelector('.custom-select-chevron').style.transform = '';
        trigger.classList.remove('border-moss', 'dark:border-brass', 'ring-2', 'ring-moss/20', 'dark:ring-brass/20');
      }
    });

    // Listen to changes on original select to keep custom elements in sync
    select.addEventListener('change', updateLabel);
  });
}

// Global click listener to close custom dropdowns on clicking outside
document.addEventListener('click', () => {
  document.querySelectorAll('.custom-select-options').forEach(menu => {
    menu.classList.add('hidden');
    const trigger = menu.previousElementSibling;
    if (trigger) {
      const chevron = trigger.querySelector('.custom-select-chevron');
      if (chevron) chevron.style.transform = '';
      trigger.classList.remove('border-moss', 'dark:border-brass', 'ring-2', 'ring-moss/20', 'dark:ring-brass/20');
    }
  });
});

function updateCustomTags(inputId, tagsContainerId) {
  const input = document.getElementById(inputId);
  const container = document.getElementById(tagsContainerId);
  if (!input || !container) return;

  const render = () => {
    container.innerHTML = '';
    const val = input.value.trim();
    if (val === '') return;

    const items = val.split(',')
      .map(s => s.trim())
      .filter(s => s.length > 0);

    items.forEach(item => {
      const tag = document.createElement('span');
      tag.className = 'px-2 py-0.5 text-[10px] rounded bg-moss/10 dark:bg-brass/10 text-moss dark:text-brass font-mono font-medium flex items-center gap-1 hover:bg-rust/10 hover:text-rust dark:hover:bg-rust/15 cursor-pointer transition-colors';
      tag.innerHTML = `${item} <iconify-icon icon="tabler:x" width="10"></iconify-icon>`;
      
      // Click on tag to remove it!
      tag.addEventListener('click', () => {
        const filtered = items.filter(x => x !== item);
        input.value = filtered.join(', ');
        input.dispatchEvent(new Event('change', { bubbles: true }));
        render();
      });

      container.appendChild(tag);
    });
  };

  render();
  
  // Update tags in real-time as user types or programmatically updates
  input.addEventListener('input', render);
  input.addEventListener('change', render);
}

// ── Live Neovim Preview Engine ──────────────────────────────
function updateLivePreview(settings) {
  const box = document.getElementById('live-preview-box');
  if (!box || !settings) return;

  const ui = settings.ui || {};
  const ed = settings.editor || {};
  const lsp = settings.lsp || {};

  const theme = ui.theme || 'tokyonight-night';
  const valThemeEl = document.getElementById('pv-val-theme');
  const valTransEl = document.getElementById('pv-val-trans');
  const valHintsEl = document.getElementById('pv-val-hints');

  if (valThemeEl) valThemeEl.textContent = `"${theme}"`;
  if (valTransEl) valTransEl.textContent = ui.transparent ? 'true' : 'false';
  if (valHintsEl) valHintsEl.textContent = lsp.enable_inlay_hints ? 'true' : 'false';

  let baseThemeKey = 'tokyonight';
  if (theme.includes('kanagawa')) baseThemeKey = 'kanagawa';
  else if (theme.includes('catppuccin')) baseThemeKey = 'catppuccin';
  else if (theme.includes('rose-pine')) baseThemeKey = 'rose-pine';
  else if (theme.includes('gruvbox')) baseThemeKey = 'gruvbox';
  else if (theme.includes('nord')) baseThemeKey = 'nord';

  const t = THEMES[baseThemeKey] || THEMES.tokyonight;
  const editorEl = document.getElementById('pv-editor');
  if (editorEl) {
    editorEl.style.backgroundColor = ui.transparent ? 'rgba(25, 23, 36, 0.75)' : t.bg;
    editorEl.style.color = t.field;
  }

  const blEl = document.getElementById('pv-bufferline');
  if (blEl) {
    blEl.className = 'live-preview-bufferline bufferline-' + (ui.bufferline_style || 'nvchad');
  }

  document.querySelectorAll('.pv-ln').forEach((ln, idx) => {
    const lineNum = idx + 1;
    if (ed.relative_line_numbers && lineNum !== 7) {
      ln.textContent = Math.abs(lineNum - 7);
    } else {
      ln.textContent = lineNum;
    }
  });

  document.querySelectorAll('.pv-indent').forEach(ind => {
    ind.className = ed.show_indent_guides ? 'pv-indent indent-guide' : 'pv-indent';
  });
}

// ── Presets Manager ──────────────────────────────────────────
const PRESETS = {
  web: {
    ui: { theme: 'tokyonight-night', background: 'dark', transparent: true, bufferline_style: 'nvchad' },
    editor: { format_on_save: true, auto_save: true, highlight_current_line: true },
    lsp: { enable_inlay_hints: true, show_inline_errors: true },
    extras: ['plugins.extras.lang.go', 'plugins.extras.lang.rust'],
    custom_tools: { lsp_servers: ['tailwindcss', 'prismals'], mason_tools: ['prettier', 'eslint_d'] }
  },
  systems: {
    ui: { theme: 'kanagawa-wave', background: 'dark', transparent: false, bufferline_style: 'slant' },
    editor: { relative_line_numbers: true, format_on_save: true, scrolloff: 10 },
    lsp: { enable_inlay_hints: true, show_inline_errors: true },
    extras: ['plugins.extras.lang.rust', 'plugins.extras.lang.go'],
    custom_tools: { lsp_servers: ['clangd', 'rust_analyzer'], mason_tools: ['clang-format', 'stylua'] }
  },
  minimal: {
    ui: { theme: 'catppuccin-latte', background: 'light', transparent: false, bufferline_style: 'default', cmdheight: 0 },
    editor: { show_line_numbers: true, relative_line_numbers: false, auto_save: false },
    lsp: { enable_inlay_hints: false, show_inline_errors: false },
    extras: [],
    custom_tools: { lsp_servers: [], mason_tools: [] }
  },
  qa: {
    ui: { theme: 'gruvbox', background: 'dark', transparent: true, bufferline_style: 'block' },
    editor: { highlight_current_line: true, format_on_save: true },
    lsp: { show_inline_errors: true },
    extras: ['plugins.extras.testing.neotest'],
    custom_tools: { lsp_servers: [], mason_tools: [] }
  }
};

function initPresets() {
  document.querySelectorAll('.preset-pill').forEach(btn => {
    btn.addEventListener('click', () => {
      const presetKey = btn.dataset.preset;
      const preset = PRESETS[presetKey];
      if (!preset) return;

      document.querySelectorAll('.preset-pill').forEach(p => p.classList.remove('active'));
      btn.classList.add('active');

      const merged = Object.assign({}, currentSettings || {}, preset);
      populateForm(merged);
      updateLivePreview(merged);
      showToast(`Preset "${btn.textContent.trim()}" applied! 🚀`, 'success');

      const settingsSection = document.getElementById('settings');
      if (settingsSection) {
        settingsSection.dispatchEvent(new Event('change', { bubbles: true }));
      }
    });
  });
}

// ── Search & Filter Settings ────────────────────────────────
function initSettingsSearch() {
  const input = document.getElementById('settings-search');
  if (!input) return;

  input.addEventListener('input', () => {
    const q = input.value.toLowerCase().trim();
    const cards = document.querySelectorAll('#settings-cards-grid > div');

    cards.forEach(card => {
      let cardHasMatch = false;
      const items = card.querySelectorAll('.space-y-4 > div, .space-y-2 > div, label');

      items.forEach(item => {
        const text = item.textContent.toLowerCase();
        if (!q || text.includes(q)) {
          item.style.display = '';
          cardHasMatch = true;
        } else {
          item.style.display = 'none';
        }
      });

      card.style.display = (!q || cardHasMatch) ? '' : 'none';
    });
  });
}

// ── Export Settings Lua Handler ─────────────────────────────
function initExportLua() {
  const btn = document.getElementById('export-lua-btn');
  if (!btn) return;

  btn.addEventListener('click', () => {
    const settings = collectFormSettings();
    const luaStr = `-- lua/settings.lua\nreturn ` + JSON.stringify(settings, null, 2)
      .replace(/"([^"]+)":/g, '$1 =')
      .replace(/:/g, ' =');

    navigator.clipboard.writeText(luaStr).then(() => {
      showToast('Exported Lua configuration copied to clipboard! 📋', 'success');
    }).catch(err => {
      showToast('Export failed: ' + err.message, 'error');
    });
  });
}

// ── Web Doctor & System Health Checker ───────────────────────
async function initWebDoctor() {
  const grid = document.getElementById('doctor-grid');
  if (!grid) return;

  try {
    const res = await fetch('/api/doctor');
    if (!res.ok) throw new Error('API unavailable');
    const data = await res.json();

    grid.innerHTML = '';
    Object.keys(data).forEach(key => {
      const item = data[key];
      const card = document.createElement('div');
      card.className = 'p-3 rounded-lg border border-ink/10 dark:border-white/10 bg-paper/80 dark:bg-inkdark/80 font-mono text-xs flex flex-col justify-between gap-1.5 shadow-sm transition-all hover:border-moss/40 dark:hover:border-brass/40';

      const statusBadge = item.installed
        ? `<span class="inline-flex items-center gap-1 text-[10px] px-2 py-0.5 rounded-full bg-moss/10 dark:bg-moss/20 text-moss dark:text-moss-light font-semibold"><iconify-icon icon="tabler:circle-check" width="12"></iconify-icon> OK</span>`
        : (item.required
            ? `<span class="inline-flex items-center gap-1 text-[10px] px-2 py-0.5 rounded-full bg-rust/10 text-rust font-semibold"><iconify-icon icon="tabler:alert-circle" width="12"></iconify-icon> Missing</span>`
            : `<span class="inline-flex items-center gap-1 text-[10px] px-2 py-0.5 rounded-full bg-brass/10 text-brass font-semibold"><iconify-icon icon="tabler:info-circle" width="12"></iconify-icon> Optional</span>`);

      card.innerHTML = `
        <div class="flex items-center justify-between gap-2">
          <span class="font-semibold text-ink dark:text-[#EDE7DA] truncate">${item.label}</span>
          ${statusBadge}
        </div>
        <span class="text-[10px] text-ink/50 dark:text-[#A79C87] font-mono truncate" title="${item.version}">${item.installed ? item.version : 'Not installed'}</span>
      `;
      grid.appendChild(card);
    });
  } catch (err) {
    grid.innerHTML = `
      <div class="col-span-full p-4 rounded-lg bg-rust/10 border border-rust/30 text-xs text-rust flex items-center gap-2">
        <iconify-icon icon="tabler:alert-triangle" width="16"></iconify-icon>
        <span>Health doctor unavailable in standalone preview mode. Run Neovim with <code class="bg-black/10 dark:bg-black/30 px-1 py-0.5 rounded font-mono">:NamiSettings</code> to enable system diagnostics.</span>
      </div>`;
  }
}

// ── Web Setup Runner Stream ──────────────────────────────────
function initWebSetupRunner() {
  const btn = document.getElementById('run-web-setup-btn');
  const box = document.getElementById('setup-terminal-box');
  const output = document.getElementById('setup-terminal-output');
  const badge = document.getElementById('setup-status-badge');

  if (!btn || !box || !output) return;

  btn.addEventListener('click', () => {
    box.classList.remove('hidden');
    output.textContent = '🚀 Launching automated setup.sh process...\n';
    btn.disabled = true;
    btn.classList.add('opacity-50', 'cursor-not-allowed');

    if (badge) {
      badge.textContent = 'Running...';
      badge.className = 'text-[10px] px-2 py-0.5 rounded bg-brass/20 text-brass';
    }

    try {
      const source = new EventSource('/api/setup-stream');

      source.onmessage = (event) => {
        try {
          const msg = JSON.parse(event.data);
          if (msg.type === 'log') {
            output.textContent += msg.text + '\n';
            output.scrollTop = output.scrollHeight;
          } else if (msg.type === 'done') {
            source.close();
            btn.disabled = false;
            btn.classList.remove('opacity-50', 'cursor-not-allowed');

            if (msg.success) {
              output.textContent += '\n✅ Setup completed successfully!\n';
              if (badge) {
                badge.textContent = 'Completed! ⚡';
                badge.className = 'text-[10px] px-2 py-0.5 rounded bg-moss/20 text-moss dark:text-moss-light';
              }
              showToast('Automated setup completed successfully! ⚡', 'success');
            } else {
              output.textContent += `\n⚠️ Setup finished with exit code ${msg.code}.\n`;
              if (badge) {
                badge.textContent = 'Error';
                badge.className = 'text-[10px] px-2 py-0.5 rounded bg-rust/20 text-rust';
              }
            }
            initWebDoctor();
          }
        } catch (e) {
          console.error('Error parsing SSE setup log:', e);
        }
      };

      source.onerror = () => {
        source.close();
        btn.disabled = false;
        btn.classList.remove('opacity-50', 'cursor-not-allowed');
        output.textContent += '\n⚠️ Connection to setup stream closed.\n';
        if (badge) {
          badge.textContent = 'Disconnected';
          badge.className = 'text-[10px] px-2 py-0.5 rounded bg-rust/20 text-rust';
        }
      };
    } catch (err) {
      btn.disabled = false;
      btn.classList.remove('opacity-50', 'cursor-not-allowed');
      showToast('Failed to start setup runner: ' + err.message, 'error');
    }
  });
}

// ── Boot ─────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  initTabs();
  initCopy();
  initTheme();
  initThemeToggle();
  initKeymaps();
  initLangs();
  initObserver();
  initSettings();
  initPresets();
  initSettingsSearch();
  initExportLua();
  initWebDoctor();
  initWebSetupRunner();
});

