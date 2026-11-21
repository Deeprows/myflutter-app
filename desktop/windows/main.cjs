const { app, BrowserWindow, session, shell, dialog } = require('electron');
const { autoUpdater } = require('electron-updater');
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
  win.webContents.setWindowOpenHandler(({ url }) => {
    // Movie download links open in the user's browser, not inside an
    // untrusted embedded player window. Keep the host allowlist explicit.
    try {
      const parsed = new URL(url);
      const allowed = new Set([
        'web.nxsha.app',
        'meetdownload.com',
        'www.meetdownload.com',
        'wildshare.net',
        'www.wildshare.net',
        'archive.org',
        'www.archive.org'
      ]);
      if (parsed.protocol === 'https:' && allowed.has(parsed.hostname.toLowerCase())) {
        shell.openExternal(parsed.href);
      }
    } catch (_) {}
    return { action: 'deny' };
  });
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

function configureAutoUpdates() {
  // Auto-update the installed NSIS build. Portable builds cannot safely
  // replace their running executable, so they remain manual-download builds.
  if (!app.isPackaged || process.env.PORTABLE_EXECUTABLE_DIR) return;
  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = true;
  autoUpdater.on('update-downloaded', async () => {
    const choice = await dialog.showMessageBox({
      type: 'info',
      buttons: ['Restart and install', 'Later'],
      defaultId: 0,
      cancelId: 1,
      title: 'Deeprowss Cinema update ready',
      message: 'A new version has been downloaded.',
      detail: 'Restart Deeprowss Cinema to install the update.'
    });
    if (choice.response === 0) autoUpdater.quitAndInstall();
  });
  autoUpdater.on('error', (error) => console.error('Deeprowss auto-update error:', error));
  setTimeout(() => autoUpdater.checkForUpdatesAndNotify().catch((error) => {
    console.error('Deeprowss update check failed:', error);
  }), 8000);
}

app.whenReady().then(() => {
  configureAutoUpdates();
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
