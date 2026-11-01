// deckstrap desktop app (Electron main process).
//
// The app is a window around the installer: it starts the Python backend that
// ships inside the AppImage (resources/deckstrap/lib/server.py), then loads
// the backend's page in a frameless, maximized BrowserWindow. All install
// logic lives in the deckstrap tool; this file only manages the window and
// the backend process.
//
//   deckstrap-ui.AppImage [--profile FILE] [--assets DIR] [--profile-url URL] [--dry-run]
//                         [--no-sudo]        (UI development only: skip the password)
//                         [--backend-url URL] (attach to an already running backend)
'use strict';
const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const { spawn, spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

function parseArgs(argv) {
  const o = { profile: '', assets: '', profileUrl: '', dryRun: false, noSudo: false, backendUrl: '', dev: false, smoke: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i], next = () => argv[++i] || '';
    if (a === '--profile') o.profile = next();
    else if (a === '--assets') o.assets = next();
    else if (a === '--profile-url') o.profileUrl = next();
    else if (a === '--backend-url') o.backendUrl = next();
    else if (a === '--dry-run') o.dryRun = true;
    else if (a === '--no-sudo') o.noSudo = true;
    else if (a === '--dev') o.dev = true;
    else if (a === '--smoke') o.smoke = true;   // start backend, load the page, print its title, quit
  }
  return o;
}

// Where the deckstrap tool lives: inside the AppImage when packaged, the repo
// root when running from source (app/ is one level below it).
function toolDir() {
  return app.isPackaged ? path.join(process.resourcesPath, 'deckstrap') : path.join(__dirname, '..');
}

// python3 on SteamOS/Linux; the Windows launcher "py -3" for development.
function pythonCommand() {
  const candidates = process.platform === 'win32'
    ? [['py', ['-3']], ['python', []], ['python3', []]]
    : [['python3', []], ['python', []]];
  for (const [cmd, pre] of candidates) {
    const r = spawnSync(cmd, [...pre, '-c', 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)'], { stdio: 'ignore' });
    if (r.status === 0) return [cmd, pre];
  }
  return null;
}

function startBackend(opts) {
  return new Promise((resolve, reject) => {
    const tool = toolDir();
    const server = path.join(tool, 'lib', 'server.py');
    if (!fs.existsSync(server)) return reject(new Error(`backend not found at ${server}`));
    const py = pythonCommand();
    if (!py) return reject(new Error('python3 was not found; it ships with SteamOS, so this should not happen on a Deck'));
    const profile = opts.profile || path.join(tool, 'profile.example.json');
    const args = [...py[1], server, '--profile', profile];
    if (opts.assets) args.push('--assets', opts.assets);
    if (opts.noSudo) args.push('--insecure-no-sudo');
    const proc = spawn(py[0], args, { env: { ...process.env, PYTHONUNBUFFERED: '1' } });
    let out = '', err = '';
    const timer = setTimeout(() => reject(new Error('the backend did not start within 20 s\n' + err)), 20000);
    proc.stdout.on('data', (d) => {
      out += d.toString();
      const m = out.match(/URL=(\S+)/);
      if (m) { clearTimeout(timer); resolve({ proc, url: m[1] }); }
    });
    proc.stderr.on('data', (d) => { err += d.toString(); });
    proc.on('exit', (code) => { clearTimeout(timer); reject(new Error(`the backend exited with code ${code}\n${err}`)); });
  });
}

let backend = null;

async function createWindow() {
  const opts = parseArgs(process.argv.slice(app.isPackaged ? 1 : 2));
  let url;
  try {
    if (opts.backendUrl) {
      url = opts.backendUrl;
    } else {
      backend = await startBackend(opts);
      url = backend.url;
    }
  } catch (e) {
    dialog.showErrorBox('deckstrap could not start', String(e.message || e));
    app.quit();
    return;
  }
  const extra = new URLSearchParams({ app: 'electron' });
  if (opts.profileUrl) extra.set('profile_url', opts.profileUrl);
  if (opts.dryRun) extra.set('dry', '1');
  url += (url.includes('?') ? '&' : '?') + extra.toString();

  const win = new BrowserWindow({
    width: 1280, height: 800, minWidth: 960, minHeight: 600,
    frame: false, autoHideMenuBar: true, backgroundColor: '#0e1116', show: false,
    title: 'deckstrap',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true },
  });
  win.once('ready-to-show', () => { if (!opts.smoke) { win.maximize(); win.show(); } });
  win.on('closed', () => { stopBackend(); app.quit(); });
  await win.loadURL(url);
  if (opts.smoke) {
    // wait for the page to show a profile name (a --profile-url pack takes a few seconds to fetch)
    const name = await win.webContents.executeJavaScript(`new Promise(r => { const t0 = Date.now(); const tick = () => {
      const n = document.getElementById("profileName").textContent; if (n || Date.now() - t0 > 30000) r(n); else setTimeout(tick, 500); }; tick(); })`);
    console.log(`smoke ok: title="${win.getTitle()}" profile="${name}" electron=${process.versions.electron}`);
    win.close();
  }
}

function stopBackend() {
  if (backend && backend.proc && !backend.proc.killed) {
    try { backend.proc.kill(); } catch (_) { /* already gone */ }
  }
  backend = null;
}

ipcMain.on('win:close', (e) => BrowserWindow.fromWebContents(e.sender)?.close());
ipcMain.on('win:minimize', (e) => BrowserWindow.fromWebContents(e.sender)?.minimize());
ipcMain.on('win:toggle-maximize', (e) => { const w = BrowserWindow.fromWebContents(e.sender); if (!w) return; w.isMaximized() ? w.unmaximize() : w.maximize(); });

app.whenReady().then(createWindow);
app.on('window-all-closed', () => { stopBackend(); app.quit(); });
app.on('before-quit', stopBackend);
