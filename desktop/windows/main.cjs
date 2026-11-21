const { app, BrowserWindow, session, shell, dialog, ipcMain, Menu, Notification } = require('electron');
const { autoUpdater } = require('electron-updater');
const path = require('path');
const fs = require('fs');
const http = require('http');

const icon = path.join(__dirname, 'assets', 'deeprowss.ico');
const firstExisting = (...dirs) => dirs.find((d) => { try { return fs.statSync(d).isDirectory(); } catch (_) { return false; } }) || dirs[0];
// Packaged builds carry copies of assets/receiver and assets/data; `npm start` in the repo uses the originals.
const RECEIVER_DIR = firstExisting(path.join(__dirname, 'receiver'), path.join(__dirname, '..', '..', 'assets', 'receiver'));
const DATA_DIR = firstExisting(path.join(__dirname, 'data'), path.join(__dirname, '..', '..', 'assets', 'data'));

let mainWin = null;
let origin = '';
let htmlFullscreen = false;

/* ------------------------------------------------------------------ */
/* Local web server: the Deeprowss receiver runs from http://127.0.0.1 */
/* (a real http origin, so YouTube / embed players accept it and the   */
/* saved favourites / history keep the same storage between launches). */
/* ------------------------------------------------------------------ */
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.webmanifest': 'application/manifest+json', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.webp': 'image/webp'
};

function handleRequest(req, res) {
  try {
    let pathname = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname);
    if (pathname.endsWith('/')) pathname += 'index.html';
    let base = RECEIVER_DIR;
    let rel = pathname;
    if (pathname.startsWith('/data/')) { base = DATA_DIR; rel = pathname.slice('/data'.length); }
    const file = path.normalize(path.join(base, rel));
    if (file !== base && !file.startsWith(base + path.sep)) { res.writeHead(403); res.end('Forbidden'); return; }
    fs.readFile(file, (err, buf) => {
      if (err) { res.writeHead(404, { 'Content-Type': 'text/plain' }); res.end('Not found'); return; }
      res.writeHead(200, {
        'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
        'Cache-Control': 'no-cache'
      });
      res.end(req.method === 'HEAD' ? undefined : buf);
    });
  } catch (_) { res.writeHead(400); res.end('Bad request'); }
}

function listen(server, port) {
  return new Promise((resolve, reject) => {
    const onError = (error) => { server.removeListener('listening', onListening); reject(error); };
    const onListening = () => { server.removeListener('error', onError); resolve(server.address().port); };
    server.once('error', onError);
    server.once('listening', onListening);
    server.listen(port, '127.0.0.1');
  });
}

async function startServer() {
  // A fixed port keeps the page origin (and therefore saved favourites and history) the same every launch.
  const ports = [47831, 47832, 47833, 47834, 47835, 0];
  for (const port of ports) {
    const server = http.createServer(handleRequest);
    try {
      return await listen(server, port);
    } catch (_) { try { server.close(); } catch (__) {} }
  }
  throw new Error('Could not start the internal Deeprowss server.');
}

/* ------------------------------------------------------------------ */
/* Network: stream headers + CORS/embedding relaxations for the player */
/* ------------------------------------------------------------------ */
let streamHeaders = null; // { referer, userAgent } for the channel that is playing
const SERVICE_HOSTS = /(^|\.)(themoviedb\.org|tmdb\.org|githubusercontent\.com|github\.io|workers\.dev|youtube\.com|ytimg\.com|googleapis\.com|gstatic\.com|jsdelivr\.net|cdnjs\.cloudflare\.com)$/i;
const hostOf = (u) => { try { return new URL(u).hostname; } catch (_) { return ''; } };
const fromApp = (details) => !!origin && String(details.referrer || '').startsWith(origin);

function configureNetwork(ses) {
  ses.webRequest.onBeforeSendHeaders({ urls: ['http://*/*', 'https://*/*'] }, (details, callback) => {
    const headers = details.requestHeaders;
    if (streamHeaders && !details.url.startsWith(origin) && !SERVICE_HOSTS.test(hostOf(details.url)) && fromApp(details)) {
      if (streamHeaders.referer) {
        headers.Referer = streamHeaders.referer;
        try { headers.Origin = new URL(streamHeaders.referer).origin; } catch (_) {}
      }
      if (streamHeaders.userAgent) headers['User-Agent'] = streamHeaders.userAgent;
    }
    callback({ requestHeaders: headers });
  });

  ses.webRequest.onHeadersReceived({ urls: ['http://*/*', 'https://*/*'] }, (details, callback) => {
    const headers = details.responseHeaders || {};
    const drop = (names) => Object.keys(headers).forEach((k) => { if (names.includes(k.toLowerCase())) delete headers[k]; });
    let statusLine = details.statusLine;

    if (details.resourceType === 'subFrame') {
      // Embedded players must be allowed to open inside the app.
      drop(['x-frame-options']);
      Object.keys(headers).forEach((k) => {
        if (k.toLowerCase() === 'content-security-policy') {
          headers[k] = headers[k].map((v) => v.replace(/frame-ancestors[^;]*;?/gi, ''));
        }
      });
    } else if (fromApp(details) && !details.url.startsWith(origin)) {
      // The app's own player (hls.js / dash.js / sniffing) may read any live stream, like the Android native player.
      drop(['access-control-allow-origin', 'access-control-allow-headers', 'access-control-allow-methods', 'access-control-expose-headers', 'access-control-allow-credentials']);
      headers['Access-Control-Allow-Origin'] = ['*'];
      headers['Access-Control-Allow-Headers'] = ['*'];
      headers['Access-Control-Allow-Methods'] = ['GET, HEAD, OPTIONS'];
      headers['Access-Control-Expose-Headers'] = ['*'];
      if (details.method === 'OPTIONS' && details.statusCode >= 400) statusLine = 'HTTP/1.1 204 No Content';
    }
    callback({ responseHeaders: headers, statusLine });
  });

  ses.setPermissionRequestHandler((_wc, permission, callback) => {
    callback(['media', 'fullscreen', 'notifications', 'clipboard-sanitized-write'].includes(permission));
  });
}

const trusted = (event) => !!origin && !!event.senderFrame && event.senderFrame === event.sender.mainFrame && String(event.senderFrame.url || '').startsWith(origin);

ipcMain.on('stream:headers', (event, headers) => {
  if (!trusted(event)) return;
  const referer = String((headers && headers.referer) || '').slice(0, 2000);
  const userAgent = String((headers && headers.userAgent) || '').slice(0, 500);
  streamHeaders = (referer || userAgent) ? { referer: /^https?:\/\//i.test(referer) ? referer : '', userAgent } : null;
});

/* ------------------------------------------------------------------ */
/* Downloads: clean download window + Downloads-folder manager         */
/* ------------------------------------------------------------------ */
const downloads = new Map(); // id -> record shown in the app
const liveItems = new Map(); // id -> Electron DownloadItem
const downloadWins = new Map(); // webContents id -> BrowserWindow
let dlSeq = 0;
let notifyTimer = null;
const storeFile = () => path.join(app.getPath('userData'), 'downloads.json');

function loadDownloads() {
  try {
    const rows = JSON.parse(fs.readFileSync(storeFile(), 'utf8'));
    for (const r of Array.isArray(rows) ? rows : []) {
      if (!r || !r.id || !r.name) continue;
      downloads.set(r.id, { ...r, state: r.state === 'progressing' ? 'cancelled' : r.state, paused: false });
    }
  } catch (_) {}
}
function persistDownloads() {
  try { fs.writeFileSync(storeFile(), JSON.stringify([...downloads.values()].slice(-100))); } catch (_) {}
}
const snapshot = () => [...downloads.values()].reverse();
function notifyDownloads(immediate) {
  const send = () => {
    notifyTimer = null;
    if (mainWin && !mainWin.isDestroyed()) {
      mainWin.webContents.send('dl:update', snapshot());
      const active = [...downloads.values()].filter((d) => d.state === 'progressing' && d.total > 0);
      const total = active.reduce((a, d) => a + d.total, 0);
      mainWin.setProgressBar(active.length && total ? Math.min(1, active.reduce((a, d) => a + d.received, 0) / total) : -1);
    }
  };
  if (immediate) { if (notifyTimer) clearTimeout(notifyTimer); send(); } else if (!notifyTimer) notifyTimer = setTimeout(send, 400);
}
function uniquePath(dir, name) {
  const ext = path.extname(name), base = path.basename(name, ext);
  let p = path.join(dir, name), i = 1;
  while (fs.existsSync(p)) p = path.join(dir, `${base} (${i++})${ext}`);
  return p;
}

function configureDownloads(ses) {
  ses.on('will-download', (_event, item, wc) => {
    const name = String(item.getFilename() || 'download').replace(/[<>:"/\\|?*\x00-\x1f]/g, '_').slice(0, 180) || 'download';
    const file = uniquePath(app.getPath('downloads'), name);
    item.setSavePath(file);
    const id = `${Date.now()}-${++dlSeq}`;
    const rec = { id, name: path.basename(file), path: file, received: 0, total: item.getTotalBytes(), state: 'progressing', paused: false };
    downloads.set(id, rec);
    liveItems.set(id, item);

    const win = wc ? downloadWins.get(wc.id) : null;
    if (win && !win.isDestroyed()) win.hide(); // closed once the file is saved

    item.on('updated', (_e, state) => {
      rec.received = item.getReceivedBytes();
      rec.total = item.getTotalBytes();
      rec.paused = item.isPaused();
      rec.state = state === 'interrupted' ? 'interrupted' : 'progressing';
      notifyDownloads(false);
    });
    item.once('done', (_e, state) => {
      rec.received = item.getReceivedBytes();
      rec.total = item.getTotalBytes() || rec.received;
      rec.state = state;
      rec.paused = false;
      liveItems.delete(id);
      if (win && !win.isDestroyed()) win.close();
      persistDownloads();
      notifyDownloads(true);
      if (state === 'completed' && Notification.isSupported()) {
        const n = new Notification({ title: 'Download complete', body: rec.name, icon });
        n.on('click', () => shell.showItemInFolder(rec.path));
        n.show();
      }
    });
    notifyDownloads(true);
  });
}

function openDownloadWindow(url) {
  const w = new BrowserWindow({
    width: 1100, height: 760, parent: mainWin || undefined, autoHideMenuBar: true, backgroundColor: '#0b1118',
    title: 'Deeprowss · Download', icon,
    webPreferences: { nodeIntegration: false, contextIsolation: true, sandbox: true }
  });
  const wcId = w.webContents.id;
  downloadWins.set(wcId, w);
  w.on('closed', () => downloadWins.delete(wcId));
  w.webContents.setWindowOpenHandler(() => ({ action: 'deny' })); // download pages are full of pop-up ads
  w.loadURL(url).catch(() => {}); // a redirect to a file aborts the navigation; the download itself continues
}

ipcMain.handle('dl:open', (event, url) => {
  if (!trusted(event)) return false;
  try {
    const u = new URL(String(url));
    if (!['http:', 'https:'].includes(u.protocol)) return false;
    openDownloadWindow(u.href);
    return true;
  } catch (_) { return false; }
});
ipcMain.handle('dl:list', (event) => (trusted(event) ? { folder: app.getPath('downloads'), items: snapshot() } : { folder: '', items: [] }));
ipcMain.handle('dl:action', (event, id, action) => {
  if (!trusted(event)) return false;
  const rec = downloads.get(id), item = liveItems.get(id);
  if (!rec) return false;
  if (action === 'pause' && item) item.pause();
  else if (action === 'resume' && item && item.canResume()) item.resume();
  else if (action === 'cancel' && item) item.cancel();
  else if (action === 'open') shell.openPath(rec.path);
  else if (action === 'folder') shell.showItemInFolder(rec.path);
  else if (action === 'remove' && !item) { downloads.delete(id); persistDownloads(); }
  notifyDownloads(true);
  return true;
});

/* ------------------------------------------------------------------ */
/* Window                                                               */
/* ------------------------------------------------------------------ */
function createWindow() {
  const win = new BrowserWindow({
    width: 1440, height: 900, minWidth: 900, minHeight: 600, show: false, autoHideMenuBar: true,
    backgroundColor: '#060a10', title: 'Deeprowss Cinema', icon, fullscreen: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      nodeIntegration: false, contextIsolation: true, sandbox: true,
      autoplayPolicy: 'no-user-gesture-required'
    }
  });
  mainWin = win;
  win.once('ready-to-show', () => win.show());
  win.on('closed', () => { mainWin = null; });
  win.on('page-title-updated', (event) => event.preventDefault());
  win.webContents.on('enter-html-full-screen', () => { htmlFullscreen = true; });
  win.webContents.on('leave-html-full-screen', () => { htmlFullscreen = false; });

  // Embedded players and ads can never open new windows; downloads go through the preload bridge.
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', (event, target) => { if (!target.startsWith(origin)) event.preventDefault(); });

  win.webContents.on('before-input-event', (event, input) => {
    if (input.type !== 'keyDown') return;
    if (input.key === 'F11') { win.setFullScreen(!win.isFullScreen()); event.preventDefault(); }
    else if (input.key === 'Escape' && win.isFullScreen() && !htmlFullscreen) { win.setFullScreen(false); event.preventDefault(); }
    else if (input.key === 'F5' || (input.control && input.key.toLowerCase() === 'r')) { win.webContents.reloadIgnoringCache(); event.preventDefault(); }
  });

  win.loadURL(`${origin}/index.html`).catch(() => win.loadFile(path.join(__dirname, 'desktop.html')));
}

function configureAutoUpdates() {
  // Auto-update the installed NSIS build. Portable builds cannot safely
  // replace their running executable, so they remain manual-download builds.
  if (!app.isPackaged || process.env.PORTABLE_EXECUTABLE_DIR) return;
  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = true;
  autoUpdater.on('update-downloaded', async () => {
    const choice = await dialog.showMessageBox({
      type: 'info', buttons: ['Restart and install', 'Later'], defaultId: 0, cancelId: 1,
      title: 'Deeprowss Cinema update ready', message: 'A new version has been downloaded.',
      detail: 'Restart Deeprowss Cinema to install the update.'
    });
    if (choice.response === 0) autoUpdater.quitAndInstall();
  });
  autoUpdater.on('error', (error) => console.error('Deeprowss auto-update error:', error));
  setTimeout(() => autoUpdater.checkForUpdatesAndNotify().catch((error) => {
    console.error('Deeprowss update check failed:', error);
  }), 8000);
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWin) { if (mainWin.isMinimized()) mainWin.restore(); mainWin.focus(); }
  });

  app.whenReady().then(async () => {
    Menu.setApplicationMenu(null);
    try {
      const port = await startServer();
      origin = `http://127.0.0.1:${port}`;
    } catch (error) {
      dialog.showErrorBox('Deeprowss Cinema', String(error && error.message ? error.message : error));
      app.quit();
      return;
    }
    loadDownloads();
    configureNetwork(session.defaultSession);
    configureDownloads(session.defaultSession);
    configureAutoUpdates();
    createWindow();
    app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
  });

  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
  });
}
