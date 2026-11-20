const { app, BrowserWindow, session } = require('electron');
const path = require('path');

function createWindow() {
  const win = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 900,
    minHeight: 600,
    show: false,
    autoHideMenuBar: true,
    backgroundColor: '#080b12',
    icon: path.join(__dirname, 'assets', 'deeprowss.ico'),
    fullscreen: false,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      allowRunningInsecureContent: true,
      autoplayPolicy: 'no-user-gesture-required'
    }
  });

  win.once('ready-to-show', () => win.show());
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', (event, target) => {
    // The application shell is local. Do not let embedded content replace it.
    if (target.startsWith('file://')) return;
    event.preventDefault();
  });

  win.loadFile(path.join(__dirname, 'desktop.html'));

  win.webContents.on('before-input-event', (_event, input) => {
    if (input.key === 'F11' && input.type === 'keyDown') {
      win.setFullScreen(!win.isFullScreen());
    }
    if (input.key === 'Escape' && input.type === 'keyDown' && win.isFullScreen()) {
      win.setFullScreen(false);
    }
  });
}

app.whenReady().then(() => {
  session.defaultSession.setPermissionRequestHandler((_wc, permission, callback) => {
    callback(['media', 'fullscreen', 'notifications'].includes(permission));
  });
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
