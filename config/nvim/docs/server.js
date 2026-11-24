const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec, spawn } = require('child_process');

// ── Run a Lua snippet in Neovim ──────────────────────────────────────────────
// If a live server address is available, use --server (fast RPC).
// Otherwise fall back to launching a headless Neovim instance.
function nvimExec(luaSnippet, serverAddr, cb) {
  if (serverAddr) {
    // Use RPC — no full boot cost
    exec(`nvim --server "${serverAddr}" --remote-send "<cmd>lua ${luaSnippet.replace(/"/g, '\\"')}<CR>"`, cb);
  } else {
    // Headless fallback
    exec(`nvim --headless -c "lua ${luaSnippet}" -c "q"`, cb);
  }
}

// Evaluate a Lua expression and capture its stdout output via headless Neovim.
// (--server RPC cannot capture return values, so headless is always used here.)
function nvimEval(luaExpr, cb) {
  exec(`nvim --headless -c "lua io.stdout:write(vim.json.encode(${luaExpr}))" -c "q"`, cb);
}

const PORT = process.env.PORT || 8085;
const DOCS_DIR = __dirname;
const NVIM_CONFIG_DIR = path.resolve(DOCS_DIR, '..');
const SETTINGS_LUA_PATH = path.join(NVIM_CONFIG_DIR, 'lua', 'settings.lua');

// Helper to escape double quotes and convert a JS value to valid Lua syntax
function toLuaTable(val, indent = '') {
  if (val === null || val === undefined) {
    return 'nil';
  }
  if (typeof val === 'boolean') {
    return val ? 'true' : 'false';
  }
  if (typeof val === 'number') {
    return val.toString();
  }
  if (typeof val === 'string') {
    return JSON.stringify(val);
  }
  if (Array.isArray(val)) {
    if (val.length === 0) return '{}';
    const nextIndent = indent + '  ';
    const items = val.map(v => `${nextIndent}${toLuaTable(v, nextIndent)}`).join(',\n');
    return `{\n${items},\n${indent}}`;
  }
  if (typeof val === 'object') {
    const keys = Object.keys(val);
    if (keys.length === 0) return '{}';
    const nextIndent = indent + '  ';
    const items = keys.map(k => {
      const keyStr = /^[a-zA-Z_][a-zA-Z0-9_]*$/.test(k) ? k : `[${JSON.stringify(k)}]`;
      return `${nextIndent}${keyStr} = ${toLuaTable(val[k], nextIndent)}`;
    }).join(',\n');
    return `{\n${items},\n${indent}}`;
  }
  return 'nil';
}

function serializeToLua(settings) {
  return `-- ==============================================================================
-- 🌊  NamiConfig — User Settings (Generated)
-- ==============================================================================
-- Edit this file or use the web GUI to configure your Neovim experience.
-- Hot-reload: changes take effect on :w without restarting Neovim.
-- ==============================================================================

return ${toLuaTable(settings, '')}
`;
}

const MIME_TYPES = {
  '.html': 'text/html',
  '.css': 'text/css',
  '.js': 'application/javascript',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.json': 'application/json',
};

let sseClients = [];

// Watch settings.lua for changes and notify connected browsers
let watchTimeout = null;
if (fs.existsSync(SETTINGS_LUA_PATH)) {
  fs.watch(SETTINGS_LUA_PATH, (eventType) => {
    if (eventType === 'change') {
      clearTimeout(watchTimeout);
      watchTimeout = setTimeout(() => {
        console.log('settings.lua changed on disk. Notifying clients...');
        sseClients.forEach(client => {
          try {
            client.write('data: reload\n\n');
          } catch (e) {
            // ignore broken connection writes
          }
        });
      }, 100);
    }
  });
}

const server = http.createServer((req, res) => {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  // Parse query params if any
  const parsedUrl = new URL(req.url, `http://localhost:${PORT}`);
  const reqPath = parsedUrl.pathname;

  // API: Server-Sent Events for browser auto-reload
  if (reqPath === '/api/events') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    });
    res.write('\n');
    sseClients.push(res);
    req.on('close', () => {
      sseClients = sseClients.filter(c => c !== res);
    });
    return;
  }

  // API: Get current settings from Neovim
  if (reqPath === '/api/settings' && req.method === 'GET') {
    nvimEval("require('core.settings_loader').load()", (err, stdout, stderr) => {
      if (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Failed to query Neovim', details: stderr }));
        return;
      }
      
      const startIdx = stdout.indexOf('{');
      const endIdx = stdout.lastIndexOf('}');
      if (startIdx === -1 || endIdx === -1) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid response from Neovim', output: stdout }));
        return;
      }

      const jsonStr = stdout.slice(startIdx, endIdx + 1);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(jsonStr);
    });
    return;
  }

  // API: Save settings back to lua/settings.lua
  if (reqPath === '/api/settings' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const settings = JSON.parse(body);
        const luaContent = serializeToLua(settings);
        fs.writeFile(SETTINGS_LUA_PATH, luaContent, 'utf8', (err) => {
          if (err) {
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Failed to write settings file' }));
            return;
          }

          // If Neovim server address is available, trigger reload
          const nvimServer = process.env.NVIM_SERVER || parsedUrl.searchParams.get('server');
          if (nvimServer) {
            exec(`nvim --server "${nvimServer}" --remote-send "<cmd>lua require('core.settings_loader').apply()<CR>"`, (err2, stdout2, stderr2) => {
              if (err2) {
                console.error('Failed to notify Neovim:', stderr2);
              }
            });
          }

          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: true }));
        });
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid JSON payload' }));
      }
    });
    return;
  }

  // API: System Doctor - Check installed tools
  if (reqPath === '/api/doctor' && req.method === 'GET') {
    const tools = [
      { id: 'nvim', cmd: 'nvim --version', label: 'Neovim 0.10+', req: true },
      { id: 'git', cmd: 'git --version', label: 'Git', req: true },
      { id: 'node', cmd: 'node --version', label: 'Node.js', req: true },
      { id: 'npm', cmd: 'npm --version', label: 'npm', req: true },
      { id: 'rg', cmd: 'rg --version', label: 'ripgrep', req: true },
      { id: 'fd', cmd: 'fd --version', label: 'fd', req: true },
      { id: 'lazygit', cmd: 'lazygit --version', label: 'lazygit', req: true },
      { id: 'python3', cmd: 'python3 --version', label: 'Python 3', req: true },
      { id: 'make', cmd: 'make --version', label: 'make / compiler', req: true },
      { id: 'go', cmd: 'go version', label: 'Go', req: false },
      { id: 'rustc', cmd: 'rustc --version', label: 'Rust', req: false },
    ];

    let results = {};
    let pending = tools.length;

    tools.forEach(t => {
      exec(t.cmd, { env: process.env }, (err, stdout) => {
        if (!err && stdout) {
          const firstLine = stdout.trim().split('\n')[0];
          results[t.id] = { installed: true, version: firstLine, label: t.label, required: t.req };
        } else {
          results[t.id] = { installed: false, version: 'Not found', label: t.label, required: t.req };
        }
        pending--;
        if (pending === 0) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(results));
        }
      });
    });
    return;
  }

  // API: Live Setup Runner SSE Stream
  if (reqPath === '/api/setup-stream' && req.method === 'GET') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    });
    res.write('data: ' + JSON.stringify({ type: 'start', message: 'Starting NamiConfig Automated Setup...' }) + '\n\n');

    const setupScript = path.join(NVIM_CONFIG_DIR, 'setup.sh');
    const child = spawn('bash', [setupScript], {
      cwd: NVIM_CONFIG_DIR,
      env: Object.assign({}, process.env, { TERM: 'xterm-256color' })
    });

    const sendLine = (data, isError = false) => {
      const lines = data.toString().split('\n');
      lines.forEach(l => {
        if (l.trim()) {
          const payload = JSON.stringify({ type: 'log', text: l, isError });
          res.write(`data: ${payload}\n\n`);
        }
      });
    };

    child.stdout.on('data', data => sendLine(data, false));
    child.stderr.on('data', data => sendLine(data, true));

    child.on('close', code => {
      const payload = JSON.stringify({ type: 'done', code, success: code === 0 });
      res.write(`data: ${payload}\n\n`);
      res.end();
    });

    req.on('close', () => {
      if (!child.killed) child.kill();
    });
    return;
  }

  // API: YouTube Player Status
  if (reqPath === '/api/youtube/status' && req.method === 'GET') {
    nvimEval("require('core.youtube_player').get_status_data()", (err, stdout) => {
      if (err || !stdout) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ active: false }));
        return;
      }
      const startIdx = stdout.indexOf('{');
      const endIdx = stdout.lastIndexOf('}');
      if (startIdx === -1 || endIdx === -1) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ active: false }));
        return;
      }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(stdout.slice(startIdx, endIdx + 1));
    });
    return;
  }

  // API: YouTube Player Play URL
  if (reqPath === '/api/youtube/play' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const { url } = JSON.parse(body);
        if (!url) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Missing url parameter' }));
          return;
        }
        const safeUrl = JSON.stringify(url);
        const nvimServer = process.env.NVIM_SERVER || parsedUrl.searchParams.get('server');
        nvimExec(`require('core.youtube_player').play(${safeUrl})`, nvimServer, (err) => {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: !err }));
        });
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid JSON' }));
      }
    });
    return;
  }

  // API: YouTube Player Control
  if (reqPath === '/api/youtube/control' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const { action, value } = JSON.parse(body);
        let luaCmd = '';
        if (action === 'toggle')   luaCmd = "require('core.youtube_player').toggle_pause()";
        else if (action === 'stop')     luaCmd = "require('core.youtube_player').stop()";
        else if (action === 'vol_up')   luaCmd = "require('core.youtube_player').adjust_volume(5)";
        else if (action === 'vol_down') luaCmd = "require('core.youtube_player').adjust_volume(-5)";
        else if (action === 'seek_fw')  luaCmd = "require('core.youtube_player').seek(10)";
        else if (action === 'seek_bw')  luaCmd = "require('core.youtube_player').seek(-10)";
        else if (action === 'volume' && value !== undefined)
          luaCmd = `require('core.youtube_player').set_volume(${parseInt(value, 10)})`;

        if (!luaCmd) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Invalid control action' }));
          return;
        }

        const nvimServer = process.env.NVIM_SERVER || parsedUrl.searchParams.get('server');
        nvimExec(luaCmd, nvimServer, (err) => {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: !err }));
        });
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid JSON' }));
      }
    });
    return;
  }

  // API: Shutdown the server
  if (reqPath === '/api/shutdown' && req.method === 'POST') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true }));
    console.log('Shutdown request received. Stopping server...');
    process.exit(0);
  }

  // Static File Serving
  let filePath = path.join(DOCS_DIR, reqPath === '/' ? 'index.html' : reqPath);
  if (!filePath.startsWith(DOCS_DIR)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  const ext = path.extname(filePath);
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, content) => {
    if (err) {
      if (err.code === 'ENOENT') {
        res.writeHead(404);
        res.end('Not Found');
      } else {
        res.writeHead(500);
        res.end('Internal Server Error: ' + err.code);
      }
    } else {
      res.writeHead(200, { 'Content-Type': contentType });
      res.end(content, 'utf-8');
    }
  });
});

server.listen(PORT, () => {
  console.log(`NamiConfig Server running on http://localhost:${PORT}`);
  if (process.env.NVIM_SERVER) {
    console.log(`Connected to Neovim server: ${process.env.NVIM_SERVER}`);
  }
});
