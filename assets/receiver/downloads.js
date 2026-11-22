/* Deeprowss receiver · Download Apps page (website, Windows app, Android TV, webOS, Tizen).
   Adds the 5th home tile and a page where visitors pick the Deeprowss app they want:
   Mobile app, Android TV, LG webOS, Samsung Tizen or Windows.

   Where the files come from (nothing to rebuild when a new version is released):
   - Mobile app  : update.apkUrl (else share.link) in app_config.json.
   - Everything else: the newest GitHub Release that contains the file.
   - Manual links can be managed separately in assets/data/download_links.json (manual URL wins; use auto to use the existing automatic source, or off to hide an item).\n   - Any app can also be overridden in app_config.json:
       "downloads": { "webos": "https://example.com/file.ipk", "tizen": "off", "windows": "auto" }
     "auto" (or a missing key) = automatic, "off" = show "Coming soon", a https link = use that link.

   On a TV (Android TV / webOS / Tizen) a browser cannot save files, so the button shows a QR code
   instead: scan it with a phone and the file downloads there. In the Windows app the file is saved
   to the Downloads folder and appears in the app's Downloads panel. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const desktop = window.deeprowssDesktop || null;
  const UA = navigator.userAgent || '';

  const REPO = 'Deeprows/myflutter-app';
  const RELEASES = 'https://github.com/' + REPO + '/releases';
  const ROOT = 'https://raw.githubusercontent.com/' + REPO + '/main/assets/data/';
  const CACHE_KEY = 'deeprowss_dl_assets_v1', CACHE_MS = 30 * 60 * 1000;

  /* ---------- the apps ---------- */
  const APPS = [
    { id: 'mobile', art: 'phone', color: '#1db4ea', plat: 'ANDROID', name: 'Mobile App', tag: 'Phone & tablet',
      blurb: 'The complete Deeprowss experience in your pocket. Live football, scores, highlights, movies and TV, plus Smart Decoder to cast to any screen.',
      points: ['Live scores, fixtures & match alerts', 'Movies, series & live TV channels', 'Cast to this receiver with a QR scan'],
      note: 'Android only. Allow installs from your browser or file manager when Android asks.',
      actions: [{ slot: 'main', label: 'Download APK' }] },
    { id: 'androidTv', art: 'tv', color: '#3ddc84', plat: 'ANDROID TV', name: 'Android TV', tag: 'Android TV & Google TV',
      blurb: 'Made for the big screen and your remote. Browse movies and channels, or receive video cast from your phone.',
      points: ['Full remote-control navigation', 'Movies, live TV & football fixtures', 'Phone casting built in'],
      note: 'Install with Downloader or a USB drive. Turn on "Install unknown apps" for the app you use.',
      actions: [{ slot: 'main', label: 'Download TV APK' }] },
    { id: 'webos', art: 'tv', color: '#e0245e', plat: 'LG WEBOS', name: 'LG webOS', tag: 'LG Smart TV',
      blurb: 'The Deeprowss receiver as a native LG TV app, so everything you love opens straight from your TV home screen.',
      points: ['Magic Remote friendly', 'Movies, live TV & football fixtures', 'Phone casting built in'],
      note: 'Developer Mode must be on for manual installs. Install the IPK with webOS Dev Manager or ares-install.',
      actions: [{ slot: 'main', label: 'Download IPK' }] },
    { id: 'tizen', art: 'tv', color: '#4a8dff', plat: 'SAMSUNG TIZEN', name: 'Samsung Tizen', tag: 'Samsung Smart TV',
      blurb: 'The Deeprowss receiver prepared for Samsung Smart TVs. Open the project in Tizen Studio, sign it and install it on your TV.',
      points: ['Remote-control friendly', 'Movies, live TV & football fixtures', 'Phone casting built in'],
      note: 'Samsung needs your own signing certificate before a TV will accept the app.',
      actions: [{ slot: 'main', label: 'Download package' }] },
    { id: 'windows', art: 'laptop', color: '#29b6f6', plat: 'WINDOWS', name: 'Windows', tag: 'Windows 10 & 11',
      blurb: 'Deeprowss Cinema for your PC or laptop: full-screen movies, live TV and phone-to-PC casting.',
      points: ['Installer updates itself automatically', 'Portable version, no install needed', 'Downloads saved to your Downloads folder'],
      note: 'Builds are unsigned, so SmartScreen may warn. Choose More info, then Run anyway.',
      actions: [{ slot: 'main', label: 'Download installer' }, { slot: 'portable', label: 'Download portable', alt: true }] }
  ];
  const KEY_OF = (id, slot) => slot === 'portable' ? 'windowsPortable' : id;
  const MATCH = {
    windows: [/(installer|setup|nsis).*\.exe$/i],
    windowsPortable: [/portable.*\.exe$/i],
    androidTv: [/(android[-_ ]?tv|[-_ ]tv[-_.]).*\.apk$/i, /\.apk$/i],
    webos: [/\.ipk$/i],
    tizen: [/\.wgt$/i, /tizen.*\.zip$/i]
  };

  /* ---------- state ---------- */
  let cfg = {}, cfgDone = false, manualLinks = {}, manualDone = false, assets = {}, assetsDone = false, started = false, modalOpen = false;

  /* ---------- helpers ---------- */
  const safeUrl = u => { try { const x = new URL(String(u || '').trim()); return /^https?:$/.test(x.protocol) ? x.href : ''; } catch (_) { return ''; } };
  const fmtSize = n => { n = Number(n) || 0; if (!n) return ''; const mb = n / 1048576; return (mb >= 100 ? mb.toFixed(0) : mb.toFixed(1)) + ' MB'; };
  const isTvDevice = () => document.documentElement.classList.contains('tv') || /Android TV|AFTT|BRAVIA|SMART-TV|SmartTV|Tizen|Web0S|WebOS|CrKey|GoogleTV/i.test(UA);
  function detect() {
    if (desktop) return 'windows';
    if (/Web0S|WebOS/i.test(UA)) return 'webos';
    if (/Tizen/i.test(UA)) return 'tizen';
    if (/Android TV|AFTT|GoogleTV|BRAVIA/i.test(UA) || (document.documentElement.classList.contains('tv') && /Android/i.test(UA))) return 'androidTv';
    if (/Android/i.test(UA)) return 'mobile';
    if (/Windows/i.test(UA)) return 'windows';
    return '';
  }
  async function getJson(name) {
    for (const u of [ROOT + name, 'data/' + name, '../data/' + name]) {
      try { const r = await fetch(u + '?_d=' + Date.now(), { cache: 'no-store' }); if (r.ok) return await r.json(); } catch (_) {}
    }
    return null;
  }

  /* ---------- data: config + latest GitHub release ---------- */
  function pickAssets(releases) {
    const out = {};
    for (const key of Object.keys(MATCH)) {
      let found = null;
      for (const rx of MATCH[key]) {
        for (const rel of releases) {
          if (!rel || rel.draft) continue;
          const a = (rel.assets || []).find(x => rx.test(x.name || '') && !/\.(blockmap|yml|yaml)$/i.test(x.name || '') && !(key === 'windows' && /portable/i.test(x.name)));
          if (a) { found = { url: a.browser_download_url, size: a.size, tag: rel.tag_name || '' }; break; }
        }
        if (found) break;
      }
      if (found) out[key] = found;
    }
    return out;
  }
  async function loadAssets() {
    try {
      const c = JSON.parse(localStorage.getItem(CACHE_KEY) || 'null');
      if (c && Date.now() - c.t < CACHE_MS && c.assets) { assets = c.assets; assetsDone = true; refresh(); return; }
    } catch (_) {}
    try {
      const r = await fetch('https://api.github.com/repos/' + REPO + '/releases?per_page=10', { headers: { Accept: 'application/vnd.github+json' } });
      if (r.ok) {
        assets = pickAssets(await r.json());
        try { localStorage.setItem(CACHE_KEY, JSON.stringify({ t: Date.now(), assets })); } catch (_) {}
      }
    } catch (_) {}
    assetsDone = true; refresh();
  }
  async function loadConfig() {
    const j = await getJson('app_config.json');
    if (j && typeof j === 'object') cfg = j;
    cfgDone = true; refresh();
  }
  async function loadManualLinks() {
    const j = await getJson('download_links.json');
    if (j && typeof j === 'object' && !Array.isArray(j)) manualLinks = j;
    manualDone = true; refresh();
  }

  /* ---------- what each button does ---------- */
  function resolve(key) {
    const manual = manualLinks[key];
    if (typeof manual === 'string' && manual.trim() && manual.trim().toLowerCase() !== 'auto') {
      if (manual.trim().toLowerCase() === 'off') return { state: 'off' };
      const u = safeUrl(manual); if (u) return { state: 'ok', url: u, version: 'Manual link' };
    }
    const ov = cfg.downloads && cfg.downloads[key];
    if (typeof ov === 'string' && ov.trim() && ov.trim().toLowerCase() !== 'auto') {
      if (ov.trim().toLowerCase() === 'off') return { state: 'off' };
      const u = safeUrl(ov); if (u) return { state: 'ok', url: u };
    }
    if (key === 'mobile') {
      if (!cfgDone) return { state: 'loading' };
      const u = safeUrl((cfg.update && cfg.update.apkUrl) || (cfg.share && cfg.share.link));
      return u ? { state: 'ok', url: u, version: cfg.update && cfg.update.version } : { state: 'off' };
    }
    if (!assetsDone) return { state: 'loading' };
    const a = assets[key];
    if (a) return { state: 'ok', url: a.url, size: a.size, version: a.tag };
    return { state: 'fallback', url: RELEASES + '/latest' };
  }
  function showQr(url, name) {
    modal.innerHTML = '<div class="dl-pop"><button type="button" class="dl-x" id="dlX" aria-label="Close">✕</button>' +
      '<h3>Scan to download</h3><p>Point your phone camera at the code to get <b>' + esc(name) + '</b>.</p>' +
      '<div class="dl-qrbox" id="dlQr"></div><div class="dl-url">' + esc(url) + '</div>' +
      '<button type="button" class="secondary" id="dlClose">Close</button></div>';
    try {
      if (window.QRCode) new window.QRCode($('dlQr'), { text: url, width: 224, height: 224, colorDark: '#000000', colorLight: '#ffffff', correctLevel: window.QRCode.CorrectLevel.M });
      else $('dlQr').style.display = 'none';
    } catch (_) { $('dlQr').style.display = 'none'; }
    $('dlX').onclick = $('dlClose').onclick = closeModal;
    modal.classList.add('open'); modalOpen = true;
    setTimeout(() => { const b = $('dlClose'); if (b) b.focus(); }, 40);
  }
  function closeModal() {
    modal.classList.remove('open'); modalOpen = false;
    const b = document.querySelector('#dlGrid .dl-btn:not(:disabled)'); if (b && document.body.dataset.view === 'downloads') b.focus({ preventScroll: true });
  }
  function activate(id, slot, qr) {
    const app = APPS.find(a => a.id === id); if (!app) return;
    const t = resolve(KEY_OF(id, slot));
    if (t.state === 'off' || t.state === 'loading' || !t.url) return;
    if (qr || isTvDevice()) { showQr(t.url, app.name + (slot === 'portable' ? ' (portable)' : '')); return; }
    if (desktop && desktop.openDownload) { desktop.openDownload(t.url); return; }
    const w = window.open(t.url, '_blank', 'noopener'); if (!w) location.href = t.url;
  }

  /* ---------- artwork ---------- */
  function art(kind) {
    const s = 'fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"';
    if (kind === 'phone') return '<svg viewBox="0 0 160 110" aria-hidden="true"><g ' + s + '><rect x="58" y="6" width="44" height="98" rx="9"/><path d="M72 13h16"/><rect x="65" y="22" width="30" height="62" rx="3" class="fillc"/><circle cx="80" cy="94" r="3"/></g><g ' + s + ' opacity=".5"><path d="M28 40c-8 10-8 20 0 30M16 32c-14 16-14 38 0 54M132 40c8 10 8 20 0 30M144 32c14 16 14 38 0 54"/></g><path d="M74 44l13 8-13 8z" fill="currentColor"/></svg>';
    if (kind === 'laptop') return '<svg viewBox="0 0 160 110" aria-hidden="true"><g ' + s + '><rect x="32" y="14" width="96" height="64" rx="6"/><rect x="39" y="21" width="82" height="50" rx="2" class="fillc"/><path d="M14 90h132l-8 8H22z"/></g><path d="M73 36l18 10-18 10z" fill="currentColor"/></svg>';
    return '<svg viewBox="0 0 160 110" aria-hidden="true"><g ' + s + '><rect x="14" y="12" width="132" height="76" rx="7"/><rect x="21" y="19" width="118" height="62" rx="2" class="fillc"/><path d="M62 100h36M80 88v12"/></g><path d="M73 40l20 11-20 11z" fill="currentColor"/></svg>';
  }

  /* ---------- page ---------- */
  const css = document.createElement('style');
  css.textContent = `
  #landing .tiles{grid-template-columns:repeat(5,minmax(0,1fr));max-width:1680px;gap:18px}
  #landing .tile b{font-size:clamp(19px,1.7vw,26px)}
  #landing .tile small{font-size:clamp(12px,1vw,14px)}
  @media(min-width:821px) and (max-width:1280px){#landing .tile{min-height:140px;padding:66px 14px 16px}#landing .tile small{display:none}#landing .tile svg{width:40px;height:40px;left:14px;top:16px}}
  @media(max-width:820px){#landing .tiles{grid-template-columns:1fr;gap:10px;max-width:none}#landing .tile{height:78px}#landing .tile b{font-size:21px}#landing .tile small{display:block;font-size:12px}}
  #goDownloads svg{stroke:#ffd166}
  #goDownloads::after{background:radial-gradient(circle,#ffd16633,transparent 70%)}

  #downloadsView .dl-body{max-width:1560px;margin:0 auto;padding:6px 26px 60px}
  .dl-hero{text-align:center;padding:30px 12px 30px}
  .dl-kicker{display:inline-block;padding:6px 14px;border-radius:7px;background:#ffd16620;border:1px solid #ffd16660;color:#ffd166;font-size:11px;font-weight:800;letter-spacing:.22em}
  .dl-hero h1{margin:16px 0 12px;font-size:clamp(30px,4.4vw,56px);line-height:1.06;font-weight:700;letter-spacing:-.01em}
  .dl-hero h1 span{background:linear-gradient(90deg,#6fd6fb,#ffd166);-webkit-background-clip:text;background-clip:text;color:transparent}
  .dl-hero p{max-width:660px;margin:0 auto;font-size:17px;line-height:1.65;color:#a9bacb}
  .dl-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(262px,1fr));gap:20px;align-items:stretch}
  .dl-card{--c:#1db4ea;position:relative;display:flex;flex-direction:column;padding:0 22px 20px;border-radius:22px;overflow:hidden;text-align:left;
    background:linear-gradient(165deg,#15222f,#0a1119);border:1px solid #ffffff1c;box-shadow:0 18px 50px #0009;
    transition:transform .2s ease,box-shadow .2s ease,border-color .2s ease}
  .dl-card::before{content:"";position:absolute;left:0;right:0;top:0;height:4px;background:linear-gradient(90deg,var(--c),transparent)}
  .dl-card:hover,.dl-card:focus-within{transform:translateY(-6px);border-color:var(--c);box-shadow:0 0 0 1px var(--c),0 26px 70px #000c,0 0 50px color-mix(in srgb,var(--c) 28%,transparent)}
  .dl-card.mine{border-color:var(--c)}
  .dl-rec{position:absolute;z-index:2;top:14px;right:14px;padding:5px 10px;border-radius:99px;background:var(--c);color:#04121a;font-size:10px;font-weight:900;letter-spacing:.12em}
  .dl-art{position:relative;display:grid;place-items:center;height:150px;margin:0 -22px 16px;color:var(--c);
    background:radial-gradient(circle at 50% 70%,color-mix(in srgb,var(--c) 30%,transparent),transparent 68%),linear-gradient(#0d1824,#0a1119)}
  .dl-art svg{width:172px;height:auto;filter:drop-shadow(0 8px 20px color-mix(in srgb,var(--c) 55%,transparent))}
  .dl-art .fillc{fill:color-mix(in srgb,var(--c) 14%,transparent)}
  .dl-plat{position:absolute;left:16px;top:14px;padding:4px 9px;border-radius:6px;border:1px solid color-mix(in srgb,var(--c) 60%,transparent);background:#050a10b0;color:var(--c);font-size:10px;font-weight:900;letter-spacing:.14em}
  .dl-card h3{margin:0;font-size:25px;font-weight:700;color:#fff}
  .dl-tag{margin:3px 0 12px;font-size:13px;font-weight:600;color:var(--c)}
  .dl-card p{margin:0 0 14px;font-size:14px;line-height:1.6;color:#a9bacb}
  .dl-card ul{margin:0 0 14px;padding:0;list-style:none;display:grid;gap:7px}
  .dl-card li{position:relative;padding-left:22px;font-size:13px;line-height:1.45;color:#d3deea}
  .dl-card li::before{content:"";position:absolute;left:2px;top:.42em;width:10px;height:6px;border-left:2.4px solid var(--c);border-bottom:2.4px solid var(--c);transform:rotate(-45deg)}
  .dl-meta{min-height:18px;margin:auto 0 10px;font-size:12px;font-weight:700;letter-spacing:.04em;color:#7f93a8}
  .dl-actions{display:grid;gap:9px}
  .dl-btn{width:100%;display:flex;align-items:center;justify-content:center;gap:9px;padding:14px 16px;font-size:15px;font-weight:800;border-radius:12px}
  .dl-btn svg{width:19px;height:19px;fill:none;stroke:currentColor;stroke-width:2.4;stroke-linecap:round;stroke-linejoin:round;flex:none}
  .dl-btn:not(.secondary){background:var(--c);color:#04121a}
  .dl-btn.secondary{background:#16222f;border:1px solid #33465c;color:#e9f0f7}
  .dl-btn:disabled{opacity:.55;cursor:not-allowed}
  .dl-btn:focus-visible{outline:3px solid #fff;outline-offset:2px}
  .dl-qr{margin-top:8px;padding:6px;background:transparent;color:#8fa0b5;font-size:12px;font-weight:700;border:0;text-decoration:underline;text-underline-offset:3px;border-radius:8px}
  .dl-qr:hover,.dl-qr:focus-visible{color:#fff}
  .dl-note{margin-top:8px;font-size:11.5px;line-height:1.5;color:#6f8297}
  .dl-foot{margin:34px auto 0;max-width:760px;text-align:center;font-size:12.5px;line-height:1.7;color:#6f8297}
  .dl-foot a{color:#8fd6f5}
  html.tv .dl-card h3{font-size:28px}html.tv .dl-card p,html.tv .dl-card li{font-size:16px}html.tv .dl-btn{font-size:18px;padding:17px 16px}
  html.tv .dl-btn:focus{transform:scale(1.04)}

  .dl-modal{z-index:95;align-items:center}
  .dl-pop{position:relative;width:min(100%,420px);margin:auto;padding:30px 26px 24px;text-align:center;background:#0d1520;border:1px solid #2c3d52;border-radius:26px;box-shadow:0 30px 90px #000c;animation:up .25s ease both;max-height:94dvh;overflow-y:auto}
  .dl-pop h3{margin:0 0 8px;font-size:24px;font-weight:700}
  .dl-pop p{margin:0 0 16px;font-size:14px}
  .dl-x{position:absolute;top:12px;right:12px;width:38px;height:38px;padding:0;border-radius:50%;background:#000b;color:#fff;border:1px solid #ffffff2a;font-size:15px}
  .dl-qrbox{display:inline-grid;place-items:center;min-width:244px;min-height:244px;padding:10px;margin-bottom:12px;background:#fff;border-radius:16px}
  .dl-qrbox img,.dl-qrbox canvas{display:block}
  .dl-url{margin:0 0 16px;font-size:11px;line-height:1.4;color:#7f93a8;word-break:break-all}
  .dl-pop .secondary{width:100%}
  @media(max-width:640px){#downloadsView .dl-body{padding:4px 16px 46px}.dl-grid{grid-template-columns:1fr}.dl-hero{padding:20px 4px 22px}.dl-hero p{font-size:15px}}
  `;
  document.head.appendChild(css);

  const DL_ICON = '<svg viewBox="0 0 24 24"><path d="M12 3v12M7 11l5 5 5-5M4 20h16"/></svg>';
  function build() {
    const grid = $('dlGrid'); if (!grid) return;
    grid.innerHTML = APPS.map(a =>
      '<article class="dl-card" id="dl-' + a.id + '" style="--c:' + a.color + '" aria-label="' + esc(a.name) + '">' +
        '<span class="dl-rec" hidden>● YOUR DEVICE</span>' +
        '<div class="dl-art">' + art(a.art) + '<span class="dl-plat">' + esc(a.plat) + '</span></div>' +
        '<h3>' + esc(a.name) + '</h3><div class="dl-tag">' + esc(a.tag) + '</div>' +
        '<p>' + esc(a.blurb) + '</p>' +
        '<ul>' + a.points.map(p => '<li>' + esc(p) + '</li>').join('') + '</ul>' +
        '<div class="dl-meta" data-meta></div>' +
        '<div class="dl-actions">' + a.actions.map(x =>
          '<button type="button" class="dl-btn' + (x.alt ? ' secondary' : '') + '" data-app="' + a.id + '" data-slot="' + x.slot + '" data-label="' + esc(x.label) + '">' + DL_ICON + '<span></span></button>').join('') +
        '</div>' +
        '<button type="button" class="dl-qr" data-app="' + a.id + '" data-slot="main" data-qr="1">Show QR code</button>' +
        '<div class="dl-note">' + esc(a.note) + '</div>' +
      '</article>').join('');
    const mine = detect();
    if (mine) { const c = $('dl-' + mine); if (c) { c.classList.add('mine'); c.querySelector('.dl-rec').hidden = false; grid.insertBefore(c, grid.firstChild); } }
    grid.addEventListener('click', e => {
      const b = e.target.closest('[data-app]'); if (!b || b.disabled) return;
      activate(b.dataset.app, b.dataset.slot, !!b.dataset.qr);
    });
    refresh();
  }
  function refresh() {
    const tv = isTvDevice();
    APPS.forEach(a => {
      const card = $('dl-' + a.id); if (!card) return;
      let meta = '';
      card.querySelectorAll('.dl-btn').forEach(b => {
        const t = resolve(KEY_OF(a.id, b.dataset.slot)), span = b.querySelector('span');
        b.disabled = t.state === 'off' || t.state === 'loading';
        span.textContent = t.state === 'off' ? 'Coming soon'
          : t.state === 'loading' ? 'Checking latest version…'
          : t.state === 'fallback' ? (tv ? 'Show QR for releases page' : 'Open releases page')
          : (tv ? 'Show QR to download' : b.dataset.label);
        if (b.dataset.slot === 'main' && t.state === 'ok') meta = [t.version, fmtSize(t.size)].filter(Boolean).join(' · ');
      });
      const m = card.querySelector('[data-meta]'); if (m) m.textContent = meta;
      const q = card.querySelector('.dl-qr'), main = resolve(a.id);
      if (q) q.hidden = tv || main.state === 'off' || main.state === 'loading';
    });
  }

  /* ---------- popup + back handling ---------- */
  const modal = document.createElement('div');
  modal.className = 'sheet dl-modal'; modal.id = 'dlModal';
  modal.setAttribute('role', 'dialog'); modal.setAttribute('aria-modal', 'true'); modal.setAttribute('aria-label', 'Scan to download');
  modal.addEventListener('click', e => { if (e.target === modal) closeModal(); });
  document.addEventListener('keydown', e => {
    if (!modalOpen) return;
    if (e.key === 'Escape' || e.key === 'Backspace') { e.preventDefault(); e.stopPropagation(); closeModal(); }
  }, true);
  const prevBack = window.deeprowssHandleBack;
  window.deeprowssHandleBack = () => { if (modalOpen) { closeModal(); return true; } return prevBack ? prevBack() : false; };

  /* ---------- start ---------- */
  function start() {
    if (started) return; started = true;
    loadConfig(); loadManualLinks(); loadAssets();
  }
  document.body.appendChild(modal);
  build();
  window.addEventListener('hashchange', () => { if (location.hash === '#downloads') { start(); refresh(); } });
  if (location.hash === '#downloads') start(); else setTimeout(start, 4000);
})();
