/* Deeprowss receiver · Download Apps page.
   All app download destinations are controlled only by assets/data/download_links.json.
   Put your own direct HTTPS download links in that JSON; no GitHub Releases lookup or app_config fallback is used. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const desktop = window.deeprowssDesktop || null;
  const UA = navigator.userAgent || '';
  const ROOT = 'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/';
  const CACHE_KEY = 'deeprowss_dl_assets_v2';

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
      points: ['Installer updates itself automatically', 'Downloads saved to your Downloads folder'],
      note: 'Builds are unsigned, so SmartScreen may warn. Choose More info, then Run anyway.',
      actions: [{ slot: 'main', label: 'Download installer' }] }
  ];
  const KEY_OF = (id, slot) => id;
  const MATCH = {
    windows: [/(installer|setup|nsis).*\.exe$/i],
    androidTv: [/(android[-_ ]?tv|[-_ ]tv[-_.]).*\.apk$/i, /\.apk$/i],
    webos: [/\.ipk$/i],
    tizen: [/\.wgt$/i, /tizen.*\.zip$/i]
  };

  let manualLinks = {}, manualDone = false, started = false, modalOpen = false;
  const safeUrl = u => { try { const x = new URL(String(u || '').trim()); return x.protocol === 'https:' ? x.href : ''; } catch (_) { return ''; } };
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
  async function loadManualLinks() {
    manualDone = false;
    try { const cached = JSON.parse(localStorage.getItem(CACHE_KEY) || 'null'); if (cached && cached.links && typeof cached.links === 'object') manualLinks = cached.links; } catch (_) {}
    for (const u of [ROOT + 'download_links.json', 'data/download_links.json', '../data/download_links.json']) {
      try {
        const r = await fetch(u + '?_d=' + Date.now(), { cache: 'no-store' });
        if (!r.ok) continue;
        const j = await r.json();
        if (j && typeof j === 'object' && !Array.isArray(j)) {
          manualLinks = j;
          try { localStorage.setItem(CACHE_KEY, JSON.stringify({ links: j, savedAt: Date.now() })); } catch (_) {}
          break;
        }
      } catch (_) {}
    }
    manualDone = true; refresh();
  }
  function resolve(key) {
    if (!manualDone && !Object.prototype.hasOwnProperty.call(manualLinks, key)) return { state: 'loading' };
    const value = manualLinks[key];
    if (typeof value !== 'string' || !value.trim() || value.trim().toLowerCase() === 'off' || value.trim().toLowerCase() === 'auto') return { state: 'off' };
    const url = safeUrl(value);
    return url ? { state: 'ok', url, version: '' } : { state: 'off' };
  }
  function showQr(url, name) {
    modal.innerHTML = '<div class="dl-pop"><button type="button" class="dl-x" id="dlX" aria-label="Close">✕</button>' +
      '<h3>Scan to download</h3><p>Point your phone camera at the code to get <b>' + esc(name) + '</b>.</p>' +
      '<div class="dl-qrbox" id="dlQr"></div><div class="dl-url">' + esc(url) + '</div>' +
      '<button type="button" class="secondary" id="dlClose">Close</button></div>';
    try { if (window.QRCode) new window.QRCode($('dlQr'), { text: url, width: 224, height: 224, colorDark: '#000000', colorLight: '#ffffff', correctLevel: window.QRCode.CorrectLevel.M }); else $('dlQr').style.display = 'none'; }
    catch (_) { $('dlQr').style.display = 'none'; }
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
    if (t.state !== 'ok' || !t.url) return;
    if (qr || isTvDevice()) { showQr(t.url, app.name); return; }
    if (desktop && desktop.openDownload) { desktop.openDownload(t.url); return; }
    const w = window.open(t.url, '_blank', 'noopener'); if (!w) location.href = t.url;
  }
  function art(kind) {
    const s = 'fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"';
    if (kind === 'phone') return '<svg viewBox="0 0 160 110" aria-hidden="true"><g ' + s + '><rect x="58" y="6" width="44" height="98" rx="9"/><path d="M72 13h16"/><rect x="65" y="22" width="30" height="62" rx="3" class="fillc"/><circle cx="80" cy="94" r="3"/></g><g ' + s + ' opacity=".5"><path d="M28 40c-8 10-8 20 0 30M16 32c-14 16-14 38 0 54M132 40c8 10 8 20 0 30M144 32c14 16 14 38 0 54"/></g><path d="M74 44l13 8-13 8z" fill="currentColor"/></svg>';
    if (kind === 'laptop') return '<svg viewBox="0 0 160 110" aria-hidden="true"><g ' + s + '><rect x="32" y="14" width="96" height="64" rx="6"/><rect x="39" y="21" width="82" height="50" rx="2" class="fillc"/><path d="M14 90h132l-8 8H22z"/></g><path d="M73 36l18 10-18 10z" fill="currentColor"/></svg>';
    return '<svg viewBox="0 0 160 110" aria-hidden="true"><g ' + s + '><rect x="14" y="12" width="132" height="76" rx="7"/><rect x="21" y="19" width="118" height="62" rx="2" class="fillc"/><path d="M62 100h36M80 88v12"/></g><path d="M73 40l20 11-20 11z" fill="currentColor"/></svg>';
  }
  const css = document.createElement('style');
  css.textContent = `
  #landing .tiles{grid-template-columns:repeat(5,minmax(0,1fr));max-width:1680px;gap:18px}
  #landing .tile b{font-size:clamp(19px,1.7vw,26px)}
  #landing .tile small{font-size:clamp(12px,1vw,14px)}
  @media(min-width:821px) and (max-width:1280px){#landing .tile{min-height:140px;padding:66px 14px 16px}#landing .tile small{display:none}#landing .tile svg{width:40px;height:40px;left:14px;top:16px}}
  @media(max-width:820px){#landing .tiles{grid-template-columns:1fr;gap:10px;max-width:none}#landing .tile{height:78px}#landing .tile b{font-size:21px}#landing .tile small{display:block;font-size:12px}}
  #goDownloads svg{stroke:#ffd166}
  #goDownloads::after{background:radial-gradient(circle,#ffd16633,transparent 70%)}
  #downloadsView .bar h2{display:flex;align-items:center;gap:12px;margin:0 0 0 6px;font-size:20px;font-weight:700;letter-spacing:-.01em}
  #downloadsView .dl-body{max-width:1480px;margin:0 auto;padding:10px 28px 64px}
  .dl-hero{position:relative;isolation:isolate;text-align:center;padding:46px 12px 38px}
  .dl-hero::before{content:"";position:absolute;z-index:-1;left:-10%;right:-10%;top:-40px;height:340px;background:radial-gradient(55% 100% at 50% 0%,#1db4ea2b,transparent 72%),radial-gradient(35% 80% at 88% 8%,#ffd16618,transparent 70%),radial-gradient(35% 80% at 10% 8%,#3b7bff1c,transparent 70%);pointer-events:none;-webkit-mask-image:radial-gradient(75% 100% at 50% 0,#000 35%,transparent 100%);mask-image:radial-gradient(75% 100% at 50% 0,#000 35%,transparent 100%)}
  .dl-kicker{display:inline-flex;align-items:center;gap:8px;padding:7px 15px;border-radius:99px;background:#ffd16616;border:1px solid #ffd16650;color:#ffd166;font-size:11px;font-weight:800;letter-spacing:.2em}
  .dl-kicker::before{content:"";width:6px;height:6px;border-radius:50%;background:currentColor;box-shadow:0 0 10px currentColor}
  .dl-hero h1{margin:20px 0 14px;font-size:clamp(32px,4.8vw,62px);line-height:1.05;font-weight:800;letter-spacing:-.035em}
  .dl-hero h1 span{background:linear-gradient(90deg,#6fd6fb,#7f9bff 55%,#ffd166);-webkit-background-clip:text;background-clip:text;color:transparent}
  .dl-hero p{max-width:640px;margin:0 auto;font-size:17px;line-height:1.65;color:#a3b4c6}
  .dl-chips{display:flex;flex-wrap:wrap;justify-content:center;gap:10px;margin-top:24px}
  .dl-chips span{display:inline-flex;align-items:center;gap:8px;padding:8px 15px;border-radius:99px;background:#ffffff0c;border:1px solid #ffffff14;font-size:13px;font-weight:600;color:#c6d4e2}
  .dl-chips svg{width:15px;height:15px;fill:none;stroke:#6fd6fb;stroke-width:2.6;stroke-linecap:round;stroke-linejoin:round}
  .dl-grid{display:grid;grid-template-columns:repeat(var(--cols,4),minmax(0,1fr));gap:18px;align-items:stretch}
  .dl-grid .dl-card{--c:#1db4ea;width:auto;position:relative;display:flex;flex-direction:column;padding:0;border-radius:24px;overflow:hidden;text-align:left;background:linear-gradient(180deg,#121e2c,#0a121b);border:1px solid #ffffff14;box-shadow:0 14px 40px #0007;transition:transform .22s cubic-bezier(.2,.8,.2,1),box-shadow .22s,border-color .22s}
  .dl-grid .dl-card:hover,.dl-grid .dl-card:focus-within{transform:translateY(-5px);border-color:color-mix(in srgb,var(--c) 75%,transparent);box-shadow:0 0 0 1px color-mix(in srgb,var(--c) 45%,transparent),0 26px 60px #000b,0 0 56px color-mix(in srgb,var(--c) 22%,transparent)}
  .dl-rec{position:absolute;z-index:3;top:14px;right:14px;display:flex;align-items:center;gap:7px;padding:5px 11px 5px 9px;border-radius:99px;background:var(--c);color:#04121a;font-size:10px;font-weight:900;letter-spacing:.12em;box-shadow:0 6px 18px color-mix(in srgb,var(--c) 45%,transparent)}
  .dl-rec[hidden]{display:none}
  .dl-rec::before{content:"";width:6px;height:6px;border-radius:50%;background:#04121a;animation:dlpulse 1.8s infinite}
  @keyframes dlpulse{0%,100%{opacity:1}50%{opacity:.25}}
  .dl-art{position:relative;display:grid;place-items:center;height:164px;overflow:hidden;color:var(--c);background:radial-gradient(70% 95% at 50% 105%,color-mix(in srgb,var(--c) 38%,transparent),transparent 72%),linear-gradient(#0e1a27,#0b131c)}
  .dl-art::after{content:"";position:absolute;inset:0;pointer-events:none;background-image:linear-gradient(#ffffff09 1px,transparent 1px),linear-gradient(90deg,#ffffff09 1px,transparent 1px);background-size:26px 26px;-webkit-mask-image:radial-gradient(circle at 50% 60%,#000,transparent 72%);mask-image:radial-gradient(circle at 50% 60%,#000,transparent 72%)}
  .dl-art svg{position:relative;z-index:1;width:166px;height:auto;filter:drop-shadow(0 10px 24px color-mix(in srgb,var(--c) 55%,transparent));transition:transform .3s}
  .dl-card:hover .dl-art svg{transform:scale(1.06)}
  .dl-art .fillc{fill:color-mix(in srgb,var(--c) 14%,transparent)}
  .dl-plat{position:absolute;z-index:2;left:16px;top:14px;padding:4px 10px;border-radius:99px;border:1px solid color-mix(in srgb,var(--c) 55%,transparent);background:#050a10b8;color:var(--c);font-size:10px;font-weight:900;letter-spacing:.14em}
  .dl-main{display:flex;flex-direction:column;flex:1;padding:20px 22px 22px}
  .dl-card h3{margin:0;font-size:25px;font-weight:800;letter-spacing:-.02em;color:#fff}
  .dl-tag{margin:3px 0 12px;font-size:13px;font-weight:700;color:var(--c)}
  .dl-card p{margin:0 0 14px;font-size:14px;line-height:1.6;color:#a3b4c6}
  .dl-card ul{margin:0 0 16px;padding:0;list-style:none;display:grid;gap:8px}
  .dl-card li{position:relative;padding-left:26px;font-size:13px;line-height:1.45;color:#d3deea}
  .dl-card li::before{content:"";position:absolute;left:0;top:.05em;width:17px;height:17px;border-radius:50%;background:color-mix(in srgb,var(--c) 18%,transparent)}
  .dl-card li::after{content:"";position:absolute;left:5px;top:.42em;width:7px;height:4px;border-left:2px solid var(--c);border-bottom:2px solid var(--c);transform:rotate(-45deg)}
  .dl-meta{display:flex;align-items:center;gap:8px;min-height:20px;margin:auto 0 12px;padding-top:4px;font-size:12px;font-weight:700;color:#7f93a8}
  .dl-meta .ok{display:inline-flex;align-items:center;gap:7px;color:#6ee7a8}
  .dl-meta .ok::before{content:"";width:7px;height:7px;border-radius:50%;background:#34d98a;box-shadow:0 0 10px #34d98a}
  .dl-meta .soon{display:inline-flex;align-items:center;gap:7px;color:#9aa8b8}
  .dl-meta .soon::before{content:"";width:7px;height:7px;border-radius:50%;background:#6c7b8c}
  .dl-actions{display:flex;gap:10px}
  .dl-btn{flex:1;min-width:0;display:flex;align-items:center;justify-content:center;gap:9px;padding:14px 16px;font-size:15px;font-weight:800;border-radius:14px;transition:filter .15s,transform .15s,box-shadow .15s}
  .dl-btn svg{width:19px;height:19px;fill:none;stroke:currentColor;stroke-width:2.4;stroke-linecap:round;stroke-linejoin:round;flex:none}
  .dl-btn:not(.secondary){background:var(--c);color:#04121a;box-shadow:0 10px 26px color-mix(in srgb,var(--c) 32%,transparent)}
  .dl-btn:not(.secondary):hover:not(:disabled){filter:brightness(1.1);transform:translateY(-1px)}
  .dl-btn.secondary{background:#ffffff0d;border:1px solid #ffffff1f;color:#e9f0f7}
  .dl-btn.dl-qrbtn{flex:none;width:50px;padding:0}
  .dl-btn.dl-qrbtn:hover:not(:disabled){background:#ffffff1c}
  .dl-btn:disabled{opacity:1;cursor:not-allowed}
  .dl-btn:not(.secondary):disabled{background:#182433;color:#7f93a8;box-shadow:none}
  .dl-btn.secondary:disabled{opacity:.4}
  .dl-btn:focus-visible{outline:3px solid #fff;outline-offset:2px}
  .dl-card.soon .dl-art{filter:saturate(.45)}
  .dl-tips{margin-top:14px;padding-top:10px;border-top:1px solid #ffffff10}
  .dl-tips summary{display:flex;align-items:center;gap:8px;list-style:none;cursor:pointer;font-size:12.5px;font-weight:700;color:#8fa0b5;border-radius:8px}
  .dl-tips summary::-webkit-details-marker{display:none}
  .dl-tips summary::after{content:"+";margin-left:auto;width:20px;height:20px;border-radius:50%;display:grid;place-items:center;background:#ffffff0d;font-size:14px;line-height:1}
  .dl-tips[open] summary::after{content:"–"}
  .dl-tips summary:hover{color:#fff}
  .dl-tips summary:focus-visible{outline:2px solid var(--c);outline-offset:3px}
  .dl-note{margin-top:8px;font-size:12px;line-height:1.55;color:#7f93a8}
  .dl-grid .dl-card.feature{grid-column:1/-1;flex-direction:row;border-color:color-mix(in srgb,var(--c) 50%,transparent);box-shadow:0 0 0 1px color-mix(in srgb,var(--c) 26%,transparent),0 24px 70px #000a,0 0 80px color-mix(in srgb,var(--c) 14%,transparent)}
  .dl-card.feature .dl-art{flex:0 0 42%;height:auto;min-height:340px}
  .dl-card.feature .dl-art svg{width:min(300px,78%)}
  .dl-card.feature .dl-main{justify-content:center;padding:34px 40px}
  .dl-card.feature h3{font-size:36px}
  .dl-card.feature .dl-tag{font-size:15px;margin-bottom:14px}
  .dl-card.feature p{max-width:600px;font-size:16px}
  .dl-card.feature ul{grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:10px 24px;max-width:640px}
  .dl-card.feature li{font-size:14px}
  .dl-card.feature .dl-meta{margin-top:4px}
  .dl-card.feature .dl-actions{max-width:460px}
  .dl-card.feature .dl-btn{padding:17px 18px;font-size:16.5px}
  .dl-card.feature .dl-btn.dl-qrbtn{width:58px}
  .dl-card.feature .dl-tips{max-width:640px}
  .dl-foot{margin:36px auto 0;max-width:760px;text-align:center;font-size:12.5px;line-height:1.7;color:#6f8297}
  .dl-foot a{color:#8fd6f5}
  @media(max-width:1180px){.dl-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
  @media(max-width:640px){.dl-grid{grid-template-columns:1fr}}
  @media(max-width:900px){.dl-grid .dl-card.feature{flex-direction:column}.dl-card.feature .dl-art{flex:none;min-height:0;height:190px}.dl-card.feature .dl-main{padding:22px}.dl-card.feature h3{font-size:28px}}
  @media(prefers-reduced-motion:reduce){.dl-grid .dl-card,.dl-art svg,.dl-btn{transition:none}.dl-rec::before{animation:none}}
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
  @media(max-width:640px){#downloadsView .dl-body{padding:4px 16px 46px}.dl-grid{grid-template-columns:1fr}.dl-hero{padding:26px 4px 24px}.dl-hero p{font-size:15px}.dl-chips{gap:8px}.dl-chips span{padding:7px 12px;font-size:12px}.dl-card.feature h3{font-size:26px}}
  `;
  document.head.appendChild(css);
  const DL_ICON = '<svg viewBox="0 0 24 24"><path d="M12 3v12M7 11l5 5 5-5M4 20h16"/></svg>';
  const QR_ICON = '<svg viewBox="0 0 24 24"><rect x="3" y="3" width="7" height="7" rx="1.2"/><rect x="14" y="3" width="7" height="7" rx="1.2"/><rect x="3" y="14" width="7" height="7" rx="1.2"/><path d="M14 14h3v3M21 14v.01M14 21h3M21 17v4"/></svg>';
  function build() {
    const grid = $('dlGrid'); if (!grid) return;
    grid.innerHTML = APPS.map(a =>
      '<article class="dl-card" id="dl-' + a.id + '" style="--c:' + a.color + '" aria-label="' + esc(a.name) + '">' +
        '<span class="dl-rec" hidden>YOUR DEVICE</span>' +
        '<div class="dl-art">' + art(a.art) + '<span class="dl-plat">' + esc(a.plat) + '</span></div>' +
        '<div class="dl-main">' +
          '<h3>' + esc(a.name) + '</h3><div class="dl-tag">' + esc(a.tag) + '</div>' +
          '<p>' + esc(a.blurb) + '</p>' +
          '<ul>' + a.points.map(p => '<li>' + esc(p) + '</li>').join('') + '</ul>' +
          '<div class="dl-meta" data-meta></div>' +
          '<div class="dl-actions">' + a.actions.map(x =>
            '<button type="button" class="dl-btn' + (x.alt ? ' secondary' : '') + '" data-app="' + a.id + '" data-slot="' + x.slot + '" data-label="' + esc(x.label) + '">' + DL_ICON + '<span></span></button>' +
            '<button type="button" class="dl-btn secondary dl-qrbtn" data-app="' + a.id + '" data-slot="' + x.slot + '" data-qr="1" title="Show QR code" aria-label="Show QR code for ' + esc(a.name) + '">' + QR_ICON + '</button>').join('') +
          '</div>' +
          '<details class="dl-tips"><summary>Install tips</summary><div class="dl-note">' + esc(a.note) + '</div></details>' +
        '</div>' +
      '</article>').join('');
    const mine = detect();
    if (mine) { const c = $('dl-' + mine); if (c) { c.classList.add('mine', 'feature'); c.querySelector('.dl-rec').hidden = false; grid.insertBefore(c, grid.firstChild); } }
    grid.style.setProperty('--cols', String(Math.min(5, APPS.length - (mine && $('dl-' + mine) ? 1 : 0))));
    grid.addEventListener('click', e => { const b = e.target.closest('[data-app]'); if (!b || b.disabled) return; activate(b.dataset.app, b.dataset.slot, !!b.dataset.qr); });
    refresh();
  }
  function refresh() {
    const tv = isTvDevice();
    APPS.forEach(a => {
      const card = $('dl-' + a.id); if (!card) return;
      let meta = '', off = false;
      card.querySelectorAll('.dl-btn').forEach(b => {
        const t = resolve(KEY_OF(a.id, b.dataset.slot));
        b.disabled = t.state === 'off' || t.state === 'loading';
        if (b.dataset.qr) { b.hidden = tv; return; } // on a TV the main button already opens the QR code
        const span = b.querySelector('span');
        span.textContent = t.state === 'off' ? 'Coming soon' : t.state === 'loading' ? 'Loading download links…' : (tv ? 'Show QR to download' : b.dataset.label);
        if (b.dataset.slot === 'main') {
          if (t.state === 'ok') meta = '<span class="ok">Ready to download</span>' + (fmtSize(t.size) ? '<span>' + esc(fmtSize(t.size)) + '</span>' : '');
          else if (t.state === 'off') { off = true; meta = '<span class="soon">Not available yet</span>'; }
        }
      });
      card.classList.toggle('soon', off);
      const m = card.querySelector('[data-meta]'); if (m) m.innerHTML = meta;
      const tips = card.querySelector('.dl-tips'); if (tips && tv) tips.open = true;
    });
  }
  const modal = document.createElement('div');
  modal.className = 'sheet dl-modal'; modal.id = 'dlModal';
  modal.setAttribute('role', 'dialog'); modal.setAttribute('aria-modal', 'true'); modal.setAttribute('aria-label', 'Scan to download');
  modal.addEventListener('click', e => { if (e.target === modal) closeModal(); });
  document.addEventListener('keydown', e => { if (!modalOpen) return; if (e.key === 'Escape' || e.key === 'Backspace') { e.preventDefault(); e.stopPropagation(); closeModal(); } }, true);
  const prevBack = window.deeprowssHandleBack;
  window.deeprowssHandleBack = () => { if (modalOpen) { closeModal(); return true; } return prevBack ? prevBack() : false; };
  function start() { if (started) return; started = true; loadManualLinks(); }
  document.body.appendChild(modal);
  build();
  window.addEventListener('hashchange', () => { if (location.hash === '#downloads') { start(); refresh(); } });
  if (location.hash === '#downloads') start(); else setTimeout(start, 4000);
})();
