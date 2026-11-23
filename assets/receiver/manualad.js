/* Deeprowss receiver · Manual image ad (website, Windows app, Android TV, webOS, Tizen).
   Shows the same popup as the phone app, driven by the same file: assets/data/manual_ad.json

     { "enabled": true, "id": "...", "image_url": "https://...png",
       "download_url": "https://...apk", "url": "" }

   Rules (identical to the app):
   - Shown only when enabled is not false, image_url is a web link, and download_url or url is a web link.
   - download_url gives a "Download now" button, otherwise url gives a "Visit page" button.
   - Someone who already pressed the button never sees that ad again. Changing the id, image_url,
     download_url or url makes it a new ad that shows again.
   - Edit the file on GitHub and every receiver picks it up (no rebuild). It is read from GitHub first,
     then from the last saved copy, then from the copy bundled with the app.

   Receiver specifics: shown on the home screen (never over a playing video), once per visit for each ad,
   and on a TV (where a browser can't save files) the button is replaced by a QR code to scan with a phone. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const desktop = window.deeprowssDesktop || null;
  const UA = navigator.userAgent || '';

  const REMOTE = 'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/manual_ad.json';
  const LOCAL = ['data/manual_ad.json', '../data/manual_ad.json'];
  const CACHE_KEY = 'deeprowss_manual_ad_cache', CLICKED_KEY = 'deeprowss_manual_ad_clicked';
  const RECHECK_MS = 30 * 60 * 1000;

  let modalOpen = false, busy = false, waiting = false, shownKey = '', lastCheck = 0, current = null;

  /* ---------- helpers ---------- */
  const web = u => { try { const x = new URL(String(u || '').trim()); return /^https?:$/.test(x.protocol) ? x.href : ''; } catch (_) { return ''; } };
  const isTvDevice = () => document.documentElement.classList.contains('tv') || /Android TV|AFTT|BRAVIA|SMART-TV|SmartTV|Tizen|Web0S|WebOS|CrKey|GoogleTV/i.test(UA);
  const store = {
    get: k => { try { return localStorage.getItem(k); } catch (_) { return null; } },
    set: (k, v) => { try { localStorage.setItem(k, v); } catch (_) {} }
  };
  const clickedList = () => { try { const l = JSON.parse(store.get(CLICKED_KEY) || '[]'); return Array.isArray(l) ? l : []; } catch (_) { return []; } };
  const wasClicked = key => clickedList().includes(key);
  function markClicked(key) {
    const l = clickedList(); if (!l.includes(key)) l.push(key);
    store.set(CLICKED_KEY, JSON.stringify(l.length > 40 ? l.slice(-40) : l));
  }

  /* ---------- the ad file ---------- */
  function parse(raw) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
    const v = k => String(raw[k] == null ? '' : raw[k]).trim();
    const ad = { enabled: raw.enabled !== false, id: v('id'), image: web(v('image_url')), download: web(v('download_url')), page: web(v('url') || v('link')) };
    ad.key = [ad.id, v('image_url'), v('download_url'), v('url') || v('link')].join('|');
    ad.visible = ad.enabled && !!ad.image && !!(ad.download || ad.page);
    return ad;
  }
  async function fetchText(u) {
    const r = await fetch(u + (u.includes('?') ? '&' : '?') + '_refresh=' + Date.now(), { cache: 'no-store' });
    if (!r.ok) throw new Error('http ' + r.status);
    return r.text();
  }
  async function load() {
    try {
      const body = await fetchText(REMOTE);
      const ad = parse(JSON.parse(body));
      if (ad) { store.set(CACHE_KEY, body); return ad; }
    } catch (_) {}
    try { const c = store.get(CACHE_KEY); if (c) { const ad = parse(JSON.parse(c)); if (ad) return ad; } } catch (_) {}
    for (const u of LOCAL) { try { const ad = parse(JSON.parse(await fetchText(u))); if (ad) return ad; } catch (_) {} }
    return null;
  }

  /* ---------- popup ---------- */
  const css = document.createElement('style');
  css.textContent = `
  .ma-sheet{z-index:96;align-items:center}
  .ma-pop{position:relative;width:min(calc(100% - 20px),540px);margin:auto;overflow:hidden;background:#101722;border:1px solid #2c3d52;border-radius:22px;box-shadow:0 30px 90px #000d;animation:up .25s ease both}
  .ma-img{position:relative;display:block;width:100%;min-height:200px;background:#0b121b}
  .ma-img img{display:block;width:100%;height:auto;max-height:calc(90dvh - 84px);object-fit:contain;opacity:0;transition:opacity .25s}
  .ma-img.ready img{opacity:1}
  .ma-img .ma-spin{position:absolute;left:50%;top:50%;width:34px;height:34px;margin:-17px 0 0 -17px;border-radius:50%;border:3px solid #2b4560;border-top-color:var(--accent);animation:spin .8s linear infinite}
  .ma-img.ready .ma-spin{display:none}
  .ma-img.bad{min-height:200px;display:grid;place-items:center;color:#6f8196;font-size:14px}
  .ma-act{padding:8px}
  .ma-btn{width:100%;display:flex;align-items:center;justify-content:center;gap:9px;padding:14px 16px;font-size:16px;font-weight:900;border-radius:12px}
  .ma-btn svg{width:20px;height:20px;fill:none;stroke:currentColor;stroke-width:2.4;stroke-linecap:round;stroke-linejoin:round}
  .ma-x{position:absolute;top:8px;right:8px;z-index:3;width:38px;height:38px;padding:0;border-radius:50%;background:#000b;color:#fff;border:1px solid #ffffff2a;font-size:15px}
  .ma-x:hover,.ma-x:focus-visible{background:var(--accent);color:var(--ink)}
  .ma-qr{display:flex;align-items:center;gap:16px;padding:6px 6px 2px}
  .ma-qrbox{flex:none;display:grid;place-items:center;min-width:148px;min-height:148px;padding:8px;background:#fff;border-radius:12px}
  .ma-qr p{margin:0 0 10px;font-size:14px;line-height:1.5;color:#c3d0de}
  .ma-qr .secondary{padding:10px 18px}
  .ma-qr small{display:block;margin-top:8px;font-size:11px;color:#6f8196;word-break:break-all}
  html.tv .ma-img img{max-height:calc(90dvh - 190px)}
  @media(max-width:520px){.ma-qr{flex-direction:column;text-align:center}}
  `;
  document.head.appendChild(css);

  const modal = document.createElement('div');
  modal.className = 'sheet ma-sheet'; modal.id = 'maModal';
  modal.setAttribute('role', 'dialog'); modal.setAttribute('aria-modal', 'true'); modal.setAttribute('aria-label', 'Advertisement');
  modal.addEventListener('click', e => { if (e.target === modal) closeModal(); });

  const ICON_DL = '<svg viewBox="0 0 24 24"><path d="M12 3v12M7 11l5 5 5-5M4 20h16"/></svg>';
  const ICON_OPEN = '<svg viewBox="0 0 24 24"><path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>';

  function open(ad) {
    current = ad; shownKey = ad.key;
    const url = ad.download || ad.page, isDl = !!ad.download, tv = isTvDevice();
    const action = tv
      ? '<div class="ma-qr"><div class="ma-qrbox" id="maQr"></div><div><p>' + (isDl ? 'Scan this code with your phone to download.' : 'Scan this code with your phone to open the page.') + '</p>' +
        '<button type="button" class="secondary" id="maClose">Close</button><small>' + esc(url) + '</small></div></div>'
      : '<button type="button" class="ma-btn" id="maGo">' + (isDl ? ICON_DL + '<span>Download now</span>' : ICON_OPEN + '<span>Visit page</span>') + '</button>';
    modal.innerHTML = '<div class="ma-pop"><button type="button" class="ma-x" id="maX" aria-label="Close advertisement">✕</button>' +
      '<div class="ma-img" id="maImg"><span class="ma-spin"></span><img alt="' + esc(ad.id) + '" decoding="async" referrerpolicy="no-referrer"></div>' +
      '<div class="ma-act">' + action + '</div></div>';
    const wrap = $('maImg'), img = wrap.querySelector('img');
    img.onload = () => wrap.classList.add('ready');
    img.onerror = () => { wrap.classList.add('bad'); wrap.innerHTML = '<span>Image could not be loaded</span>'; };
    img.src = ad.image;
    $('maX').onclick = closeModal;
    const go = $('maGo');
    if (go) go.onclick = () => {
      markClicked(ad.key); closeModal();
      if (desktop && desktop.openDownload) desktop.openDownload(url);
      else { const w = window.open(url, '_blank', 'noopener'); if (!w) location.href = url; }
    };
    const cl = $('maClose'); if (cl) cl.onclick = closeModal;
    if (tv) {
      markClicked(ad.key); // the code is the "click": a TV viewer sees each ad once
      try { if (window.QRCode) new window.QRCode($('maQr'), { text: url, width: 132, height: 132, colorDark: '#000000', colorLight: '#ffffff', correctLevel: window.QRCode.CorrectLevel.M }); else $('maQr').style.display = 'none'; }
      catch (_) { $('maQr').style.display = 'none'; }
    }
    modal.classList.add('open'); modalOpen = true;
    setTimeout(() => { const b = $('maGo') || $('maClose') || $('maX'); if (b) b.focus({ preventScroll: true }); }, 60);
  }
  function closeModal() {
    modal.classList.remove('open'); modalOpen = false; current = null; modal.innerHTML = '';
    if (document.body.dataset.view === 'landing') { const t = $('goMovies'); if (t && (window.deeprowssDesktop || isTvDevice())) t.focus({ preventScroll: true }); }
  }

  /* ---------- when to show ---------- */
  const atHome = () => { const pp = $('playerPanel'); return document.body.dataset.view === 'landing' && !document.querySelector('.sheet.open') && !(pp && pp.style.display === 'block'); };
  async function check() {
    if (busy || modalOpen || window.deeprowssPremiumActive) return;
    busy = true;
    try {
      const ad = await load();
      lastCheck = Date.now();
      if (!ad || !ad.visible || ad.key === shownKey || wasClicked(ad.key)) { waiting = false; return; }
      if (!atHome()) { waiting = true; return; }
      waiting = false; open(ad);
    } finally { busy = false; }
  }

  window.addEventListener('deeprowss-premium-change', e => { if (e.detail && e.detail.active && modalOpen) closeModal(); });

  document.addEventListener('keydown', e => {
    if (!modalOpen) return;
    if (e.key === 'Escape' || e.key === 'Backspace') { e.preventDefault(); e.stopPropagation(); closeModal(); }
  }, true);
  const prevBack = window.deeprowssHandleBack;
  window.deeprowssHandleBack = () => { if (modalOpen) { closeModal(); return true; } return prevBack ? prevBack() : false; };
  window.addEventListener('hashchange', () => {
    if (modalOpen) closeModal();
    if (document.body.dataset.view === 'landing' && (waiting || Date.now() - lastCheck > RECHECK_MS)) setTimeout(check, 700);
  });

  /* ---------- start ---------- */
  document.body.appendChild(modal);
  const startAdChecks = () => setTimeout(check, 2200);
  if (window.__deeprowssPremiumReady && typeof window.__deeprowssPremiumReady.then === 'function') {
    window.__deeprowssPremiumReady.then(startAdChecks).catch(startAdChecks);
  } else {
    startAdChecks();
  }
})();
