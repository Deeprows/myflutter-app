const { app, BrowserWindow, session } = require('electron');
const path = require('path');
const RECEIVER_URL = 'https://deeprows.github.io/myflutter-app/';
const ALLOWED_HOSTS = new Set(['deeprows.github.io']);
function createWindow() {
  const win = new BrowserWindow({
    width: 1440, height: 900, minWidth: 900, minHeight: 560,
    show: false, autoHideMenuBar: true, backgroundColor: '#080b12',
    icon: path.join(__dirname, 'assets', 'deeprowss.ico'),
    fullscreen: true,
    webPreferences: { nodeIntegration: false, contextIsolation: true, sandbox: true, autoplayPolicy: 'no-user-gesture-required' }
  });
  win.once('ready-to-show', () => win.show());
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', (event, target) => {
    try { const u = new URL(target); if (!ALLOWED_HOSTS.has(u.hostname)) event.preventDefault(); }
    catch (_) { event.preventDefault(); }
  });
  win.loadURL(RECEIVER_URL);
  win.webContents.on('before-input-event', (_event, input) => {
    if (input.key === 'F11' && input.type === 'keyDown') win.setFullScreen(!win.isFullScreen());
    if (input.key === 'Escape' && input.type === 'keyDown' && win.isFullScreen()) win.setFullScreen(false);
  });
}
app.whenReady().then(() => {
  session.defaultSession.setPermissionRequestHandler((_wc, permission, callback) => callback(['media','fullscreen'].includes(permission)));
  createWindow();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
