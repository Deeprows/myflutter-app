/* Deeprowss receiver PWA service worker. Media and third-party embeds are never cached. */
const CACHE = 'deeprowss-receiver-shell-v62';
const SHELL = ['./', './index.html', './library.js', './tv.js', './shell.js', './adshield.js', './tvplus.js', './gate.js', './fixtures.js', './downloads.js', './manualad.js', './search.js', './kodi.css', './manifest.webmanifest', './icons/icon-192.png', './icons/icon-512.png', './icons/icon-512-maskable.png'];
self.addEventListener('install', event => {
  // Cache each file on its own so one missing file (e.g. library.js at the site root) never blocks the install.
  event.waitUntil(caches.open(CACHE)
    .then(cache => Promise.allSettled(SHELL.map(item => cache.add(item))))
    .then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;
  if (request.mode === 'navigate') {
    event.respondWith(fetch(request).then(response => {
      if (response.ok) caches.open(CACHE).then(cache => cache.put('./index.html', response.clone()));
      return response;
    }).catch(() => caches.match('./index.html')));
    return;
  }
  // Library / TV / shell scripts and theme: always try the network first so updates show immediately, cache as offline fallback.
  if (/\/(library|tv|shell|gate|fixtures|downloads|manualad|adshield|tvplus|search)\.js$|\/kodi\.css$/.test(url.pathname)) {
    event.respondWith(fetch(request).then(response => {
      if (response.ok) caches.open(CACHE).then(cache => cache.put(request, response.clone()));
      return response;
    }).catch(() => caches.match(request)));
  }
});
