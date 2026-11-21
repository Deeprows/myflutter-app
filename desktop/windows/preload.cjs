// Safe bridge between the Deeprowss page and the Windows app. Only the top-level page
// (never embedded players) receives this object.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('deeprowssDesktop', {
  platform: process.platform,
  // Opens a movie download page in a clean window; files are saved to the Downloads folder.
  openDownload: (url) => ipcRenderer.invoke('dl:open', String(url || '')),
  // Referer / User-Agent that a live TV stream needs (same as the Android native player).
  setStreamHeaders: (headers) => ipcRenderer.send('stream:headers', {
    referer: String((headers && headers.referer) || ''),
    userAgent: String((headers && headers.userAgent) || '')
  }),
  downloads: {
    list: () => ipcRenderer.invoke('dl:list'),
    action: (id, action) => ipcRenderer.invoke('dl:action', String(id), String(action))
  },
  // Used by the phone remote: window fullscreen, bring-to-front and keep the screen awake while playing.
  fullscreen: {
    get: () => ipcRenderer.invoke('win:state'),
    set: (mode) => ipcRenderer.invoke('win:fullscreen', String(mode || 'toggle')),
    on: (callback) => {
      const handler = (_event, value) => callback(!!value);
      ipcRenderer.on('win:fullscreen', handler);
      return () => ipcRenderer.removeListener('win:fullscreen', handler);
    }
  },
  tap: (fx, fy) => ipcRenderer.invoke('embed:tap', Number(fx), Number(fy)),
  focus: (raise) => ipcRenderer.send('win:focus', !!raise),
  keepAwake: (on) => ipcRenderer.send('power:awake', !!on),
  onDownloads: (callback) => {
    const handler = (_event, list) => callback(list);
    ipcRenderer.on('dl:update', handler);
    return () => ipcRenderer.removeListener('dl:update', handler);
  }
});
