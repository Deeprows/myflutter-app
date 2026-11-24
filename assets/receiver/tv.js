/* Deeprowss live TV (receiver website + Windows app).
   Same sources as the Android app: your own channels (tv.json) merged with the
   IPTV Nexus online-channel API, grouped by category, with country filter,
   search, favourites, recently watched, backup streams and channel zapping. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  // Remove only the visible provider label; leave channel data and playback untouched.
  function removeProviderLabel(root) {
    if (!root || !document.createTreeWalker) return;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      if (/IPTV\\s+Nexus/i.test(node.nodeValue || '')) {
        node.nodeValue = node.nodeValue.replace(/IPTV\\s+Nexus/gi, '');
      }
    }
  }
  removeProviderLabel(document.body);
  if (!window.__deeprowssProviderLabelObserver) {
    window.__deeprowssProviderLabelObserver = new MutationObserver(records => {
      for (const record of records) {
        if (record.type === 'characterData') removeProviderLabel(record.target.parentNode);
        else for (const added of record.addedNodes) if (added.nodeType === 1) removeProviderLabel(added);
      }
    });
    window.__deeprowssProviderLabelObserver.observe(document.body, { childList: true, subtree: true, characterData: true });
  }
  if (!document.getElementById('fixture-stream-control-style')) {
    const style = document.createElement('style');
    style.id = 'fixture-stream-control-style';
    style.textContent = 'body.fixture-streaming .controls .tvonly{display:inline-flex!important}';
    document.head.appendChild(style);
  }
  const ROOT = 'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/';
  const OWN_URL = ROOT + 'tv.json';
  const CONFIG_URL = ROOT + 'app_config.json';
  const FAV_KEY = 'deeprowss_tv_favs', RECENT_KEY = 'deeprowss_tv_recent', LAST_CAT_KEY = 'deeprowss_tv_cat';
  const cfg = { base: 'https://dearbulut.github.io/iptv', path: '/api/v1/channels.online.json', refreshMin: 180, hideNsfw: true,
    /* Same site address the phone app opens web channels under (player.embedOrigin / player.origin in app_config.json). */
    frameOrigin: 'https://footbolive.online/', framePage: '' };
  const desktop = window.deeprowssDesktop || null;

  const CATS = [
    { id: 'sports', label: 'Sports', icon: '⚽' }, { id: 'news', label: 'News', icon: '📰' },
    { id: 'movies', label: 'Movies', icon: '🎬' }, { id: 'entertainment', label: 'Entertainment', icon: '🎭' },
    { id: 'music', label: 'Music', icon: '🎵' }, { id: 'kids', label: 'Kids', icon: '🧸' },
    { id: 'documentary', label: 'Documentary', icon: '🌍' }, { id: 'lifestyle', label: 'Lifestyle', icon: '🌿' },
    { id: 'religious', label: 'Religious', icon: '🕊' }, { id: 'general', label: 'General', icon: '📺' },
    { id: 'other', label: 'Other', icon: '📡' }
  ];
  const CAT_IDS = new Set(CATS.map(c => c.id));
  const catLabel = id => (CATS.find(c => c.id === id) || { label: 'Other' }).label;

  let own = [], nexus = [], all = [], filtered = [], shown = 0;
  const st = { cat: localStorage.getItem(LAST_CAT_KEY) || 'all', country: '', q: '', loading: false, nexusInfo: '', failed: false };
  let cur = null, built = false, io = null, searchTimer;
  const CHUNK = 90;
  let nexusStamp = 0;
  const nexusAge = () => (nexusStamp ? Date.now() - nexusStamp : 0);
  const regionNames = (() => { try { return new Intl.DisplayNames(['en'], { type: 'region' }); } catch (_) { return null; } })();
  const countryName = c => { try { return (regionNames && regionNames.of(c)) || c; } catch (_) { return c; } };

  /* ---------- helpers ---------- */
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const opt = v => { const s = String(v ?? '').trim(); return !s || s === 'null' ? '' : s; };
  const keyOf = c => c.id || (c.name + '|' + c.url);
  const readList = k => { try { const v = JSON.parse(localStorage.getItem(k) || '[]'); return Array.isArray(v) ? v : []; } catch (_) { return []; } };
  const writeList = (k, rows) => { try { localStorage.setItem(k, JSON.stringify(rows)); } catch (_) {} };
  const initials = n => n.replace(/[^\p{L}\p{N} ]/gu, '').trim().split(/\s+/).slice(0, 2).map(w => w[0]).join('').toUpperCase() || 'TV';
  function qualityLabel(q) {
    const n = parseInt((/\d+/.exec(q || '') || [])[0], 10);
    if (!n) return ''; if (n >= 2160) return '4K'; if (n >= 1080) return 'FHD'; if (n >= 720) return 'HD'; return 'SD';
  }
  async function getJson(url, local) {
    const tryGet = async u => { const r = await fetch(u + (u.includes('?') ? '&' : '?') + '_r=' + Date.now(), { cache: 'no-store' }); if (!r.ok) throw Error('HTTP ' + r.status); return r.json(); };
    try { return await tryGet(url); } catch (e) { if (!local) throw e; return tryGet(local); }
  }

  /* ---------- stream resolver (port of the Android StreamResolver) ---------- */
  const MEDIA_EXT = /\.(mp4|m4v|webm|mov|ogv|ogg|mkv|mp3|aac|m4a)(\?|#|$)/i;
  const HTTP = /^https?:\/\//i;
  function kindOf(u) {
    const l = u.toLowerCase();
    if (l.includes('.m3u8')) return 'hls'; if (l.includes('.mpd')) return 'dash'; if (MEDIA_EXT.test(l)) return 'video'; return 'embed';
  }
  function extractInner(s) {
    const h = s.indexOf('#');
    if (h >= 0 && h < s.length - 1) {
      let f = s.slice(h + 1);
      if (/^https?%3A/i.test(f)) { try { f = decodeURIComponent(f); } catch (_) {} }
      if (HTTP.test(f)) return f;
    }
    try {
      const u = new URL(s, 'http://x.invalid/');
      for (const k of ['url', 'src', 'file', 'source', 'stream']) {
        const v = u.searchParams.get(k);
        if (v && HTTP.test(v) && kindOf(v) !== 'embed') return v;
      }
    } catch (_) {}
    return null;
  }
  function resolve(raw) {
    let t = String(raw || '').trim();
    if (!t) return { url: '', kind: 'invalid' };
    if (t.includes('<')) { const m = /src\s*=\s*["']([^"']+)["']/i.exec(t); if (m) t = m[1].replace(/&amp;/g, '&').trim(); }
    const s = t.split(/\s+/)[0];
    let c = extractInner(s) || s;
    if (c.startsWith('//')) c = 'https:' + c;
    if (!HTTP.test(c)) return { url: c, kind: 'invalid' };
    return { url: c, kind: kindOf(c) };
  }
  /* Links without an extension (get.php?id=1, /live/abc): ask the server what they really are. */
  async function sniff(url) {
    const ac = new AbortController(), timer = setTimeout(() => ac.abort(), 6000);
    try {
      const r = await fetch(url, { signal: ac.signal, redirect: 'follow', cache: 'no-store' });
      const type = (r.headers.get('content-type') || '').toLowerCase(), fin = (r.url || '').toLowerCase();
      ac.abort();
      if (!r.ok) return null;
      if (type.includes('mpegurl')) return 'hls';
      if (type.includes('dash+xml')) return 'dash';
      if (type.startsWith('video/') || type.startsWith('audio/')) return 'video';
      if (fin.includes('.m3u8')) return 'hls';
      if (MEDIA_EXT.test(fin)) return 'video';
      if (type.includes('octet-stream') || type.includes('mp2t')) return 'video';
      return null;
    } catch (_) { return null; } finally { clearTimeout(timer); }
  }

  /* ---------- Nexus API (parsed in a background worker, cached in IndexedDB) ---------- */
  function nexusWorkerMain() {
    const CAT_MAP = { sports: 'sports', movies: 'movies', series: 'movies', classic: 'movies', music: 'music', news: 'news', kids: 'kids', animation: 'kids', entertainment: 'entertainment', comedy: 'entertainment', documentary: 'documentary', science: 'documentary', education: 'documentary', lifestyle: 'lifestyle', culture: 'lifestyle', relax: 'lifestyle', outdoor: 'lifestyle', travel: 'lifestyle', cooking: 'lifestyle', family: 'lifestyle', religious: 'religious', general: 'general', 'public': 'general' };
    const ORDER = ['sports', 'news', 'kids', 'animation', 'movies', 'series', 'classic', 'music', 'documentary', 'science', 'education', 'entertainment', 'comedy', 'lifestyle', 'culture', 'relax', 'outdoor', 'travel', 'cooking', 'family', 'religious', 'general', 'public'];
    const s = v => { const t = String(v == null ? '' : v).trim(); return t || undefined; };
    function slim(data, hideNsfw) {
      const list = Array.isArray(data) ? data : (data && Array.isArray(data.channels) ? data.channels : []);
      const out = [];
      for (const raw of list) {
        if (!raw || typeof raw !== 'object') continue;
        if (hideNsfw && raw.is_nsfw === true) continue;
        const name = s(raw.name); if (!name) continue;
        const streams = [];
        if (Array.isArray(raw.streams)) for (const x of raw.streams) {
          if (!x || typeof x !== 'object' || !s(x.url)) continue;
          if (x.health && x.health.status === 'online') streams.push(x);
        }
        if (!streams.length) continue;
        streams.sort((a, b) => (Number(b.rank) || 0) - (Number(a.rank) || 0));
        const cats = new Set(Array.isArray(raw.categories) ? raw.categories.map(String) : []);
        let cat = 'other';
        for (const k of ORDER) if (cats.has(k)) { cat = CAT_MAP[k]; break; }
        const best = streams[0], alt = streams[1];
        const allStreams = streams.map(x => ({ url: s(x.url), referer: s(x.referrer), ua: s(x.user_agent), quality: s(x.quality) })).filter(x => x.url);
        const o = {
          id: s(raw.id), name, url: s(best.url), category: cat, logo: s(raw.logo), country: s(raw.country),
          quality: s(best.quality) || s(raw.best_quality), score: typeof raw.score === 'number' ? raw.score : 0,
          referer: s(best.referrer), userAgent: s(best.user_agent), streams: allStreams,
          altUrl: alt ? s(alt.url) : undefined, altReferer: alt ? s(alt.referrer) : undefined, altUserAgent: alt ? s(alt.user_agent) : undefined
        };
        Object.keys(o).forEach(k => o[k] === undefined && delete o[k]);
        out.push(o);
      }
      out.sort((a, b) => ((b.score || 0) - (a.score || 0)) || a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
      return out;
    }
    self.onmessage = async e => {
      try {
        const r = await fetch(e.data.url, { cache: 'no-store' });
        if (!r.ok) throw new Error('HTTP ' + r.status);
        self.postMessage({ ok: true, list: slim(await r.json(), e.data.hideNsfw) });
      } catch (err) { self.postMessage({ ok: false, error: String((err && err.message) || err) }); }
    };
  }
  function fetchNexus(force) {
    return new Promise((resolveP, rejectP) => {
      let w;
      try { w = new Worker(URL.createObjectURL(new Blob(['(' + nexusWorkerMain.toString() + ')()'], { type: 'text/javascript' }))); }
      catch (e) { rejectP(e); return; }
      const timer = setTimeout(() => { w.terminate(); rejectP(Error('Timed out')); }, 120000);
      w.onmessage = e => { clearTimeout(timer); w.terminate(); e.data.ok ? resolveP(e.data.list) : rejectP(Error(e.data.error)); };
      w.onerror = e => { clearTimeout(timer); w.terminate(); rejectP(Error(e.message || 'Worker failed')); };
      w.postMessage({ url: cfg.base.replace(/\/+$/, '') + cfg.path + (force ? '?_r=' + Date.now() : ''), hideNsfw: cfg.hideNsfw });
    });
  }
  const idb = (() => {
    let dbp;
    const open = () => dbp || (dbp = new Promise((res, rej) => {
      const r = indexedDB.open('deeprowss_tv', 1);
      r.onupgradeneeded = () => r.result.createObjectStore('kv');
      r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
    }));
    return {
      async get(k) { try { const db = await open(); return await new Promise((res, rej) => { const q = db.transaction('kv').objectStore('kv').get(k); q.onsuccess = () => res(q.result); q.onerror = () => rej(q.error); }); } catch (_) { return undefined; } },
      async set(k, v) { try { const db = await open(); await new Promise((res, rej) => { const t = db.transaction('kv', 'readwrite'); t.objectStore('kv').put(v, k); t.oncomplete = res; t.onerror = () => rej(t.error); }); } catch (_) {} }
    };
  })();

  /* ---------- My playlists (shared with Settings > Playlists) ---------- */
  const PL_KEY = (() => {
    const ua = navigator.userAgent || '';
    if (window.deeprowssDesktop) return 'deeprowss_exe_settings';
    if (window.DeeprowssTv || /Android TV|AFTT|BRAVIA|GoogleTV|CrKey/i.test(ua)) return 'deeprowss_androidTv_settings';
    if (/Web0S|WebOS|webOS/i.test(ua)) return 'deeprowss_webos_settings';
    return 'deeprowss_web_settings';
  })();
  const plData = new Map(), plState = new Map();           /* url -> channels[] / {loading, error, at} */
  function plList() {
    try { const o = JSON.parse(localStorage.getItem(PL_KEY) || '{}') || {}; return Array.isArray(o.playlists) ? o.playlists.filter(p => p && p.name && p.url) : []; } catch (_) { return []; }
  }
  function plSave(list) {
    let o = {}; try { o = JSON.parse(localStorage.getItem(PL_KEY) || '{}') || {}; } catch (_) {}
    o.playlists = list; try { localStorage.setItem(PL_KEY, JSON.stringify(o)); } catch (_) {}
    window.dispatchEvent(new Event('deeprowss:playlists'));
  }
  const isPl = () => String(st.cat).startsWith('pl:');
  const curPl = () => (isPl() ? plList()[Number(String(st.cat).slice(3))] || null : null);
  function parseM3u(body, base) {
    const out = []; let name = '', group = '', logo = '', country = '', referer = '', ua = '';
    for (const raw of String(body || '').replace(/^\uFEFF/, '').split(/\r?\n/)) {
      const line = raw.trim(); if (!line) continue;
      if (line.startsWith('#EXTINF')) {
        const comma = line.lastIndexOf(',');
        name = comma >= 0 ? line.slice(comma + 1).trim() : '';
        group = (line.match(/group-title="([^"]*)"/i) || [])[1] || '';
        logo = (line.match(/tvg-logo="([^"]*)"/i) || [])[1] || '';
        country = ((line.match(/tvg-country="([^"]*)"/i) || [])[1] || '').split(/[;,]/)[0].trim().toUpperCase();
        if (!name) name = (line.match(/tvg-name="([^"]*)"/i) || [])[1] || '';
      } else if (line.startsWith('#EXTGRP:')) group = line.slice(8).trim();
      else if (/^#EXTVLCOPT:http-referrer=/i.test(line)) referer = line.split('=').slice(1).join('=').trim();
      else if (/^#EXTVLCOPT:http-user-agent=/i.test(line)) ua = line.split('=').slice(1).join('=').trim();
      else if (!line.startsWith('#')) {
        let url = ''; try { url = new URL(line, base).href; } catch (_) {}
        if (/^https?:/i.test(url)) out.push({ name: name || url.split('/').pop().split('?')[0] || 'Channel ' + (out.length + 1), url, category: 'other', group: group || undefined,
          logo: /^https?:/i.test(logo) ? logo : undefined, country: /^[A-Z]{2}$/.test(country) ? country : undefined, referer: referer || undefined, userAgent: ua || undefined, own: false, pl: true });
        name = ''; group = ''; logo = ''; country = ''; referer = ''; ua = '';
      }
    }
    return out;
  }
  async function fetchText(url) {
    if (window.DeeprowssTv && window.DeeprowssTv.fetchPlaylist) {
      const native = JSON.parse(window.DeeprowssTv.fetchPlaylist(url));
      if (!native.ok) throw Error(native.error || 'HTTP ' + native.status);
      return String(native.body || '');
    }
    const r = await fetch(url, { cache: 'no-store' });
    if (!r.ok) throw Error('HTTP ' + r.status);
    return r.text();
  }
  async function loadPl(p, force) {
    if (!p) return;
    const stt = plState.get(p.url) || {};
    if (stt.loading) return;
    if (!plData.has(p.url)) {                              /* instant display from the saved copy */
      const cached = await idb.get('pl:' + p.url);
      if (cached && Array.isArray(cached.rows) && cached.rows.length) { plData.set(p.url, cached.rows); plState.set(p.url, { at: cached.at || 0 }); if (curPl() && curPl().url === p.url) render(); else renderSide(); }
    }
    const have = plData.has(p.url), age = Date.now() - ((plState.get(p.url) || {}).at || 0);
    if (have && !force && age < 3600000) return;
    plState.set(p.url, { ...(plState.get(p.url) || {}), loading: true, error: '' });
    if (curPl() && curPl().url === p.url) render();
    try {
      const rows = parseM3u(await fetchText(p.url), p.url);
      if (!rows.length) throw Error('No channels found in this playlist.');
      plData.set(p.url, rows); plState.set(p.url, { at: Date.now() });
      idb.set('pl:' + p.url, { at: Date.now(), rows });
    } catch (e) {
      plState.set(p.url, { ...(plState.get(p.url) || {}), loading: false, error: (e && e.message) || 'Could not load this playlist.' });
      if (!have) plData.delete(p.url);
    }
    if (isPl()) render(); else renderSide();
  }
  function plModal() {
    let m = $('tvPlModal');
    if (!m) {
      const css = document.createElement('style');
      css.textContent = '#tvPlModal{position:fixed;inset:0;z-index:80;display:none;align-items:center;justify-content:center;background:#02060bcc;backdrop-filter:blur(6px)}#tvPlModal.open{display:flex}' +
        '#tvPlModal .box{width:min(560px,92vw);padding:26px;border-radius:22px;background:linear-gradient(160deg,#141c2b,#0b111b);border:1px solid #ffffff1c;box-shadow:0 30px 80px #000c;color:#fff}' +
        '#tvPlModal h3{margin:0 0 6px;font-size:22px}#tvPlModal p{margin:0 0 16px;color:#8da0b6;font-size:13.5px;line-height:1.45}' +
        '#tvPlModal input{display:block;width:100%;box-sizing:border-box;margin:0 0 12px;padding:13px 15px;border-radius:13px;border:1px solid #ffffff22;background:#060a11;color:#fff;font:inherit;font-size:15px}' +
        '#tvPlModal input:focus{outline:2px solid var(--accent2,#6fd6fb);outline-offset:1px}#tvPlModal .row{display:flex;gap:10px;justify-content:flex-end;margin-top:6px}' +
        '#tvPlModal button{padding:11px 20px;border-radius:99px;border:1px solid #ffffff26;background:#ffffff10;color:#fff;font:inherit;font-weight:700;cursor:pointer}#tvPlModal button.go{background:linear-gradient(135deg,var(--accent2,#6fd6fb),#3b7bff);color:#04121c;border-color:transparent}' +
        '#tvPlModal button:focus-visible{outline:3px solid #fff;outline-offset:2px}#tvPlModal .err{min-height:18px;margin:0 0 6px;color:#ff9cac;font-size:13px}' +
        '#tvPlBar{display:flex;gap:10px;flex-wrap:wrap;padding:0 28px 10px}#tvPlBar[hidden]{display:none}#tvPlBar button{padding:8px 16px;border-radius:99px;border:1px solid #ffffff22;background:#ffffff0d;color:#d6e2ee;font:inherit;font-size:13px;font-weight:700;cursor:pointer}#tvPlBar button:focus-visible,#tvPlBar button:hover{border-color:var(--accent2,#6fd6fb);color:#fff}' +
        '.cat.pl-add .ci{background:linear-gradient(135deg,var(--accent2,#6fd6fb),#3b7bff);color:#04121c;font-weight:900;font-size:18px}';
      document.head.appendChild(css);
      m = document.createElement('div'); m.id = 'tvPlModal'; m.setAttribute('role', 'dialog'); m.setAttribute('aria-modal', 'true');
      m.innerHTML = '<div class="box"><h3>Add your playlist</h3><p>Paste the name and link of your M3U / M3U8 playlist. It will appear under “My playlists” and in Settings › Playlists.</p>' +
        '<input id="tvPlName" placeholder="Playlist name" autocomplete="off"><input id="tvPlUrl" placeholder="https://example.com/playlist.m3u" inputmode="url" autocomplete="off"><div class="err" id="tvPlErr"></div>' +
        '<div class="row"><button type="button" id="tvPlCancel">Cancel</button><button type="button" class="go" id="tvPlAdd">Add playlist</button></div></div>';
      document.body.appendChild(m);
      const close = () => { m.classList.remove('open'); const b = document.querySelector('#tvCats .pl-add'); if (b) b.focus(); };
      const submit = () => {
        const name = $('tvPlName').value.trim(), raw = $('tvPlUrl').value.trim(); let u;
        try { u = new URL(raw); if (!/^https?:$/.test(u.protocol)) throw 0; } catch (_) { $('tvPlErr').textContent = 'Enter a valid playlist link starting with http:// or https://'; return; }
        const list = plList();
        if (list.some(p => p.url === u.href)) { $('tvPlErr').textContent = 'This playlist is already added.'; return; }
        list.push({ name: name || u.hostname, url: u.href }); plSave(list);
        $('tvPlName').value = ''; $('tvPlUrl').value = ''; $('tvPlErr').textContent = '';
        m.classList.remove('open');
        st.cat = 'pl:' + (list.length - 1); try { localStorage.setItem(LAST_CAT_KEY, st.cat); } catch (_) {}
        render(); loadPl(list[list.length - 1], true);
      };
      $('tvPlCancel').onclick = close; $('tvPlAdd').onclick = submit;
      m.addEventListener('click', e => { if (e.target === m) close(); });
      m.addEventListener('keydown', e => {
        if (e.key === 'Escape' || e.key === 'Backspace' && !/INPUT/.test(e.target.tagName)) { e.preventDefault(); e.stopPropagation(); close(); }
        else if (e.key === 'Enter' && e.target.id === 'tvPlUrl') { e.preventDefault(); submit(); }
      }, true);
    }
    $('tvPlErr').textContent = ''; m.classList.add('open'); setTimeout(() => $('tvPlName').focus(), 40);
  }
  function renderPlBar() {
    let bar = $('tvPlBar');
    if (!bar) { bar = document.createElement('div'); bar.id = 'tvPlBar'; bar.hidden = true; const s0 = $('tvStatus'); s0.parentNode.insertBefore(bar, s0.nextSibling); plModal(); $('tvPlModal').classList.remove('open'); }
    const p = curPl(); bar.hidden = !p; if (!p) return;
    bar.innerHTML = '<button type="button" data-pl="reload">↻ Reload playlist</button><button type="button" data-pl="remove">🗑 Remove playlist</button>';
    bar.onclick = e => {
      const b = e.target.closest('[data-pl]'); if (!b) return;
      if (b.dataset.pl === 'reload') { loadPl(p, true); return; }
      if (b.dataset.armed !== '1') { b.dataset.armed = '1'; b.textContent = 'Press again to remove'; setTimeout(() => { if (b.isConnected) { b.dataset.armed = ''; b.textContent = '🗑 Remove playlist'; } }, 4000); return; }
      const list = plList().filter(x => x.url !== p.url); plSave(list); plData.delete(p.url); plState.delete(p.url);
      st.cat = 'all'; try { localStorage.setItem(LAST_CAT_KEY, 'all'); } catch (_) {}
      render();
    };
  }
  window.addEventListener('deeprowss:playlists', () => { if (isPl() && !curPl()) st.cat = 'all'; if (built) { try { render(); } catch (_) {} } });

  /* ---------- channel lists ---------- */
  function parseChannel(raw, isOwn) {
    if (!raw || typeof raw !== 'object') return null;
    const name = opt(raw.name), url = opt(raw.url);
    if (!name || !url) return null;
    const cat = opt(raw.category).toLowerCase();
    return {
      id: opt(raw.id) || undefined, name, url, category: CAT_IDS.has(cat) ? cat : 'other', logo: opt(raw.logo) || undefined,
      country: opt(raw.country).toUpperCase() || undefined, quality: opt(raw.quality) || undefined, score: Number(raw.score) || 0,
      referer: opt(raw.referer) || undefined, userAgent: opt(raw.userAgent) || undefined,
      altUrl: opt(raw.altUrl) || undefined, altReferer: opt(raw.altReferer) || undefined, altUserAgent: opt(raw.altUserAgent) || undefined,
      streams: Array.isArray(raw.streams) ? raw.streams.map(x => ({ url: opt(x && x.url), referer: opt(x && (x.referer || x.referrer)), ua: opt(x && (x.ua || x.userAgent || x.user_agent)) })).filter(x => x.url) : undefined,
      own: !!isOwn
    };
  }
  /* Same rules as the Android mergeChannels(): your channel stays first, the Nexus one becomes its backup. */
  function merge(a, b) {
    if (!b.length) return a.slice();
    const byName = new Map();
    for (const c of b) { const k = c.name.toLowerCase(); if (!byName.has(k)) byName.set(k, c); }
    const ownNames = new Set(a.map(c => c.name.toLowerCase())), ownUrls = new Set(a.map(c => c.url));
    const out = a.map(c => {
      const n = byName.get(c.name.toLowerCase());
      if (!n) return c;
      const ownStreams = streamList(c), providerStreams = streamList(n);
      const mergedStreams = [...ownStreams, ...providerStreams.filter(x => !ownStreams.some(y => y.url === x.url))];
      const useAlt = !c.altUrl && n.url !== c.url;
      return { ...c, logo: n.logo || c.logo, country: n.country || c.country, quality: n.quality || c.quality, score: n.score || c.score,
        streams: mergedStreams, altUrl: useAlt ? n.url : c.altUrl, altReferer: useAlt ? n.referer : c.altReferer, altUserAgent: useAlt ? n.userAgent : c.altUserAgent };
    });
    for (const c of b) { if (ownNames.has(c.name.toLowerCase()) || ownUrls.has(c.url)) continue; out.push(c); }
    return out;
  }
  const favs = () => readList(FAV_KEY);
  const isFav = c => favs().some(x => keyOf(x) === keyOf(c));
  function toggleFav(c) {
    const k = keyOf(c), list = favs();
    writeList(FAV_KEY, list.some(x => keyOf(x) === k) ? list.filter(x => keyOf(x) !== k) : [c, ...list].slice(0, 400));
  }
  function pushRecent(c) { const k = keyOf(c); writeList(RECENT_KEY, [c, ...readList(RECENT_KEY).filter(x => keyOf(x) !== k)].slice(0, 40)); }

  /* ---------- UI ---------- */
  function baseForCountry() { return st.country ? all.filter(c => c.country === st.country) : all; }
  function counts() {
    const base = baseForCountry(), n = { all: base.length }, f = new Set(favs().map(keyOf));
    n.fav = base.filter(c => f.has(keyOf(c))).length; n.recent = readList(RECENT_KEY).length;
    for (const c of base) n[c.category] = (n[c.category] || 0) + 1;
    return n;
  }
  function renderSide() {
    const n = counts(), side = $('tvCats');
    const row = (id, icon, label) => '<button type="button" class="cat' + (st.cat === id ? ' on' : '') + '" data-cat="' + id + '"><span class="ci">' + icon + '</span><span>' + esc(label) + '</span><span class="n">' + (n[id] || 0) + '</span></button>';
    let h = '<h4>BROWSE</h4>' + row('all', '📡', 'All channels') + row('fav', '♥', 'Favourites') + row('recent', '🕘', 'Recently watched');
    h += '<h4 style="margin-top:18px">MY PLAYLISTS</h4>';
    plList().forEach((p, i) => { const id = 'pl:' + i, rows = plData.get(p.url); n[id] = rows ? rows.length : 0; h += row(id, '🎞', p.name).replace('<span class="n">0</span>', '<span class="n">' + (rows ? rows.length.toLocaleString() : '↻') + '</span>'); });
    h += '<button type="button" class="cat pl-add" data-cat="pl-add"><span class="ci">+</span><span>Add playlist</span></button>';
    h += '<h4 style="margin-top:18px">CATEGORIES</h4>';
    for (const c of CATS) if (n[c.id]) h += row(c.id, c.icon, c.label);
    side.innerHTML = h;
  }
  function renderCountries() {
    const sel = $('tvCountry'), m = new Map();
    for (const c of all) if (c.country) m.set(c.country, (m.get(c.country) || 0) + 1);
    const rows = [...m.entries()].map(([code, n]) => ({ code, n, name: countryName(code) })).sort((a, b) => a.name.localeCompare(b.name));
    sel.innerHTML = '<option value="">All countries</option>' + rows.map(r => '<option value="' + esc(r.code) + '">' + esc(r.name) + ' (' + r.n + ')</option>').join('');
    sel.value = st.country;
  }
  function applyFilter() {
    let base = baseForCountry();
    if (isPl()) { const p = curPl(); base = p ? (plData.get(p.url) || []) : []; }
    else if (st.cat === 'fav') { const f = new Set(favs().map(keyOf)); base = base.filter(c => f.has(keyOf(c))); const have = new Set(base.map(keyOf)); if (!st.country) favs().forEach(c => { if (!have.has(keyOf(c))) base.push(c); }); }
    else if (st.cat === 'recent') { const rec = readList(RECENT_KEY); base = rec.filter(c => !st.country || c.country === st.country); }
    else if (st.cat !== 'all') base = base.filter(c => c.category === st.cat);
    const q = st.q.toLowerCase();
    if (q) base = base.filter(c => c.name.toLowerCase().includes(q) || (c.group && c.group.toLowerCase().includes(q)) || (c.country && (c.country.toLowerCase() === q || countryName(c.country).toLowerCase().includes(q))) || catLabel(c.category).toLowerCase().includes(q));
    filtered = base;
  }
  function cardHtml(c, i) {
    const q = qualityLabel(c.quality), fav = isFav(c);
    return '<div class="chw"><button type="button" class="ch" data-i="' + i + '" aria-label="' + esc(c.name) + '"><span class="lg"><span class="ini">' + esc(initials(c.name)) + '</span>' +
      (c.logo ? '<img loading="lazy" decoding="async" referrerpolicy="no-referrer" alt="" src="' + esc(c.logo) + '">' : '') + '<span class="lv">LIVE</span></span>' +
      '<span class="bd"><span class="nm">' + esc(c.name) + '</span><span class="mt"><span class="p2">' + esc(c.group || catLabel(c.category)) + '</span>' +
      (c.country ? '<span class="p2">' + esc(c.country) + '</span>' : '') + (q ? '<span class="p2 q">' + q + '</span>' : '') + '</span></span></button>' +
      '<button type="button" class="fav' + (fav ? ' on' : '') + '" data-fav="' + i + '" aria-label="' + (fav ? 'Remove from favourites' : 'Add to favourites') + '">' + (fav ? '♥' : '♡') + '</button></div>';
  }
  function title() {
    if (st.q) return 'Search';
    if (isPl()) { const p = curPl(); return p ? p.name : 'My playlist'; }
    if (st.cat === 'all') return 'All channels'; if (st.cat === 'fav') return 'Favourites'; if (st.cat === 'recent') return 'Recently watched';
    return catLabel(st.cat);
  }
  function renderStatus() {
    const el = $('tvStatus');
    if (isPl()) { const p = curPl(), x = (p && plState.get(p.url)) || {}; el.textContent = !p ? '' : x.loading ? 'Loading playlist…' : x.error ? x.error + (plData.has(p.url) ? ' · showing saved copy' : '') : 'Your playlist · ' + (plData.has(p.url) ? plData.get(p.url).length.toLocaleString() + ' channels' : 'not loaded yet'); return; }
    if (st.loading) { el.innerHTML = '<span class="spin"></span>Updating online channels…'; return; }
    const parts = [own.length + ' own', nexus.length ? nexus.length.toLocaleString() + ' online channels' : 'online list not loaded'];
    el.textContent = parts.join(' · ') + (st.nexusInfo ? ' · ' + st.nexusInfo : '') + (st.failed ? ' · update failed, showing saved copy' : '');
  }
  function render() {
    renderSide(); applyFilter(); renderStatus(); renderPlBar();
    $('tvTitle').textContent = title();
    $('tvCount').textContent = filtered.length.toLocaleString() + ' channels';
    const grid = $('tvGrid'); grid.innerHTML = ''; shown = 0;
    if (!filtered.length) {
      grid.innerHTML = '<div class="tv-empty">' + (isPl() ? (((curPl() && (plState.get(curPl().url) || {}).loading)) ? 'Loading your playlist…' : ((curPl() && (plState.get(curPl().url) || {}).error) || 'No channels found.')) : st.loading ? 'Loading channels…' : st.cat === 'fav' ? 'No favourites yet. Tap the heart on any channel.' : st.cat === 'recent' ? 'Nothing watched yet.' : 'No channels found.') + '</div>';
      return;
    }
    more();
  }
  function more() {
    if (shown >= filtered.length) return;
    const end = Math.min(filtered.length, shown + CHUNK);
    let h = ''; for (let i = shown; i < end; i++) h += cardHtml(filtered[i], i);
    $('tvGrid').insertAdjacentHTML('beforeend', h); shown = end;
    $('tvSentinel').textContent = shown < filtered.length ? 'Loading more…' : '';
  }
  function refreshFav(i) {
    const w = $('tvGrid').querySelector('[data-fav="' + i + '"]'); if (!w) return;
    const on = isFav(filtered[i]); w.classList.toggle('on', on); w.textContent = on ? '♥' : '♡';
  }

  /* ---------- playback ---------- */
  function streamList(c) {
    if (!c) return [];
    const out = [];
    const add = (url, referer, ua) => {
      const u = String(url || '').trim();
      if (!/^https?:\/\//i.test(u) || out.some(x => x.url === u)) return;
      out.push({ url: u, referer: String(referer || ''), ua: String(ua || '') });
    };
    add(c.url, c.referer, c.userAgent || c.ua);
    if (Array.isArray(c.streams)) c.streams.forEach(x => x && add(x.url, x.referer || x.referrer, x.ua || x.userAgent || x.user_agent));
    Object.keys(c).filter(key => /^altUrl\d*$/i.test(key))
      .sort((a,b) => Number(a.replace(/\D/g,'')) - Number(b.replace(/\D/g,'')))
      .forEach(key => add(c[key], c[key.replace(/^altUrl/i,'altReferer')], c[key.replace(/^altUrl/i,'altUa')]));
    return out;
  }
  function streamIndexOf(c, choice) {
    const list = streamList(c);
    if (typeof choice === 'number' && Number.isFinite(choice)) return Math.max(0, Math.min(list.length - 1, Math.floor(choice)));
    return choice ? Math.min(1, Math.max(0, list.length - 1)) : 0;
  }
  function streamOf(c, choice) {
    const list = streamList(c);
    return list[streamIndexOf(c, choice)] || list[0] || { url: '', referer: '', ua: '' };
  }
  /* The link as the phone app would open it as a web page (wrapper players such as anym3u8player / m3u8-player pages). */
  function wrapperOf(s, inner) {
    let x = String(s || '').trim();
    if (x.includes('<')) { const m = /src\s*=\s*["']([^"']+)["']/i.exec(x); if (m) x = m[1].replace(/&amp;/g, '&').trim(); }
    x = x.split(/\s+/)[0]; if (x.startsWith('//')) x = 'https:' + x;
    if (!HTTP.test(x) || x === inner) return '';
    try { return MEDIA_EXT.test(new URL(x).pathname) || /\.(m3u8|mpd)$/i.test(new URL(x).pathname) ? '' : x; } catch (_) { return ''; }
  }
  function showTvButton(on, label) {
    const b = $('tvMethod'); if (!b) return;
    b.classList.toggle('nomethod', !on);
    const l = b.querySelector('.lbl'); if (l && label) l.textContent = label;
  }
  function openEmbed(c, streamIndex, url, method, via) {
    const s = streamOf(c, streamIndex);
    const info = window.deeprowssPlayTv(url, c.name + (streamIndex > 0 ? ' · Backup stream ' + (streamIndex + 1) : ''), {
      method, referer: s.referer || '', ua: s.ua || '', origin: cfg.frameOrigin, framePage: cfg.framePage
    });
    if (!info) return;
    cur.mode = 'embed'; cur.embedUrl = url; cur.method = info.method; cur.count = info.count; cur.via = via || ''; cur.embedLoaded = false;
    updateStreamButtons();
    showTvButton(true, 'Try another way (' + (info.method + 1) + '/' + info.count + ')');
    const ps = $('playState'); if (ps) ps.textContent = 'LIVE · WEB';
  }
  let watchdog = 0, fallbackWatchdog = 0;
  window.addEventListener('deeprowss-tv-embed-loaded', () => { if (cur && cur.mode === 'embed') { cur.embedLoaded = true; clearTimeout(fallbackWatchdog); } });
  function clearWatchdog() { clearTimeout(watchdog); clearTimeout(fallbackWatchdog); watchdog = 0; fallbackWatchdog = 0; }
  function updateStreamButtons() {
    const main = $('mainStream'), backup = $('backupStream');
    const total = cur ? streamList(cur.c).length : 0, index = cur ? (cur.streamIndex || 0) : 0;
    if (main) {
      main.hidden = total < 2;
      main.disabled = !cur || total < 2;
      main.classList.toggle('active', total > 1);
      const label = main.querySelector('.lbl');
      if (label) label.textContent = 'Switch ' + (index + 1) + '/' + total;
      main.title = total > 1 ? 'Switch stream ' + (index + 1) + ' of ' + total : 'No backup streams';
      main.setAttribute('aria-label', total > 1 ? 'Switch stream ' + (index + 1) + ' of ' + total : 'No backup streams');
    }
    if (backup) { backup.hidden = true; backup.disabled = true; }
  }
  function armEmbedFallback(token, c, streamIndex) {
    clearTimeout(fallbackWatchdog);
    if (streamIndex + 1 >= streamList(c).length) return;
    fallbackWatchdog = setTimeout(() => {
      if (token !== playToken || !cur || cur.c !== c || cur.streamIndex !== streamIndex || cur.embedLoaded) return;
      say('Stream is taking too long. Switching to backup ' + (streamIndex + 2) + '…');
      play(c, streamIndex + 1);
    }, 18000);
  }
  /* A direct stream that cannot be read here (CORS, hotlink protection, geo): try the channel's own player page,
     then the backup stream, like the phone app's Reload does. */
  function streamFailed(reason) {
    if (!cur || cur.mode !== 'media' || cur.failed || $('playerPanel').style.display !== 'block') return;
    cur.failed = true; clearWatchdog();
    const c = cur.c, streamIndex = cur.streamIndex || 0;
    if (streamIndex + 1 < streamList(c).length) { say('Stream unavailable. Switching to backup ' + (streamIndex + 2) + '…'); play(c, streamIndex + 1); return; }
    if (cur.wrapper) { say('Trying an alternate player…'); openEmbed(c, streamIndex, cur.wrapper, 0, 'wrapper'); return; }
    say('This channel could not be opened. Try another stream or channel.');
  }
  window.deeprowssTvFail = streamFailed;
  function armWatchdog(token) {
    clearWatchdog();
    watchdog = setTimeout(() => {
      if (token !== playToken || !cur || cur.mode !== 'media' || $('playerPanel').style.display !== 'block') return;
      const v = $('screen');
      if (v && (v.readyState >= 3 || (!v.paused && v.currentTime > 0))) return;
      streamFailed('no data');
    }, 15000);
  }
  async function play(c, choice) {
    if (!c.pl && typeof window.deeprowssTvAccess === 'function') {
      const allowed = await window.deeprowssTvAccess(c);
      if (!allowed) return;
    }
    const streamIndex = streamIndexOf(c, choice), s = streamOf(c, streamIndex), r = resolve(s.url);
    if (r.kind === 'invalid') { say('This channel link is not valid.'); return; }
    let kind = r.kind;
    const token = ++playToken;
    clearWatchdog();
    if (kind === 'embed') { const k = await sniff(r.url); if (token !== playToken) return; if (k) kind = k; }
    cur = { c, streamIndex, alt: streamIndex > 0, idx: filtered.findIndex(x => keyOf(x) === keyOf(c)), mode: 'media', wrapper: '', failed: false };
    pushRecent(c);
    if (kind === 'embed') {
      /* Web channels get their own iframe page (not the movie iframe) and several ways to open it. */
      openEmbed(c, streamIndex, r.url, 0, 'embed');
      armEmbedFallback(token, c, streamIndex);
    } else {
      cur.wrapper = wrapperOf(s.url, r.url);
      /* Windows app / Android TV app: send the channel's Referer + User-Agent and lift CORS for the stream. */
      if (desktop && desktop.setStreamHeaders) desktop.setStreamHeaders({ referer: s.referer || '', userAgent: s.ua || '' });
      window.__tvKeep = true; // clearMedia() inside deeprowssPlay must not drop the headers we are about to set
      try { if (window.DeeprowssTv && window.DeeprowssTv.setStream) window.DeeprowssTv.setStream(s.referer || '', s.ua || '', true); } catch (_) {}
      try { window.deeprowssPlay(r.url, kind, c.name + (streamIndex > 0 ? ' · Backup stream ' + (streamIndex + 1) : '')); } finally { window.__tvKeep = false; }
      const ps = $('playState'); if (ps) ps.textContent = 'LIVE';
      showTvButton(false);
      armWatchdog(token);
    }
    updateStreamButtons();
    if (!$('tvView').classList.contains('active')) return;
    renderSide();
  }
  /* "Try another way": next opening method for a web channel, or the channel's own page for a direct stream. */
  function nextWay() {
    if (!cur || $('playerPanel').style.display !== 'block') return;
    if (cur.mode === 'embed') { openEmbed(cur.c, cur.streamIndex || 0, cur.embedUrl, (cur.method + 1) % Math.max(1, cur.count), cur.via); return; }
    if (cur.wrapper) { cur.failed = true; clearWatchdog(); openEmbed(cur.c, cur.streamIndex || 0, cur.wrapper, 0, 'wrapper'); }
  }
  let playToken = 0;
  function say(msg) { const s = $('tvStatus'); if (s) { s.textContent = msg; setTimeout(renderStatus, 4000); } }
  function zap(d) {
    if (!cur || !filtered.length) return;
    let i = cur.idx; if (i < 0) i = 0;
    const n = filtered[(i + d + filtered.length) % filtered.length];
    play(n, false);
  }

  /* ---------- loading ---------- */
  async function loadOwn() {
    try { const d = await getJson(OWN_URL, 'data/tv.json'); own = (Array.isArray(d) ? d : d.channels || []).map(x => parseChannel(x, true)).filter(Boolean); }
    catch (_) { if (!own.length) own = []; }
  }
  async function loadConfig() {
    try {
      const c = await getJson(CONFIG_URL, 'data/app_config.json'), t = c.tv || c.nexus || {};
      if (t.nexusBase) cfg.base = String(t.nexusBase); if (t.nexusPath) cfg.path = String(t.nexusPath);
      if (Number(t.refreshMinutes) > 0) cfg.refreshMin = Number(t.refreshMinutes); if (t.hideNsfw === false) cfg.hideNsfw = false;
      const pl = c.player || {}, fo = String(pl.embedOrigin || pl.origin || '').trim();
      if (/^https?:\/\//i.test(fo)) cfg.frameOrigin = fo.endsWith('/') ? fo : fo + '/';
      const fp = String(t.framePage || pl.tvFramePage || '').trim(); if (/^https:\/\//i.test(fp)) cfg.framePage = fp;
    } catch (_) {}
  }
  function rebuild() { all = merge(own, nexus); renderCountries(); render(); }
  async function load(force) {
    if (st.loading) return;
    await loadConfig(); await loadOwn();
    const cached = await idb.get('nexus');
    if (cached && Array.isArray(cached.list)) {
      nexus = cached.list.map(x => parseChannel(x, false)).filter(Boolean); nexusStamp = cached.t;
      st.nexusInfo = 'updated ' + new Date(cached.t).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
    }
    rebuild();
    const stale = !cached || (Date.now() - cached.t) > cfg.refreshMin * 60000;
    if (!force && !stale) return;
    st.loading = true; st.failed = false; renderStatus();
    try {
      const list = await fetchNexus(force);
      if (list.length) {
        nexus = list.map(x => parseChannel(x, false)).filter(Boolean);
        const t = Date.now(); nexusStamp = t; st.nexusInfo = 'updated ' + new Date(t).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
        idb.set('nexus', { t, list });
      } else st.failed = true;
    } catch (_) { st.failed = true; }
    st.loading = false; rebuild();
  }

  /* ---------- wiring ---------- */
  function build() {
    if (built) return; built = true;
    $('tvCats').addEventListener('click', e => {
      const b = e.target.closest('[data-cat]'); if (!b) return;
      if (b.dataset.cat === 'pl-add') { plModal(); return; }
      st.cat = b.dataset.cat; try { localStorage.setItem(LAST_CAT_KEY, st.cat); } catch (_) {}
      render(); $('tvMain').scrollTo({ top: 0 });
      if (isPl()) loadPl(curPl(), false);
    });
    $('tvGrid').addEventListener('click', e => {
      const f = e.target.closest('[data-fav]');
      if (f) { const i = Number(f.dataset.fav); toggleFav(filtered[i]); refreshFav(i); renderSide(); return; }
      const b = e.target.closest('.ch'); if (b) play(filtered[Number(b.dataset.i)], false);
    });
    $('tvGrid').addEventListener('error', e => { if (e.target && e.target.tagName === 'IMG') e.target.remove(); }, true);
    $('tvGrid').addEventListener('load', e => { if (e.target && e.target.tagName === 'IMG') { const lg = e.target.closest('.lg'); if (lg) lg.classList.add('has'); } }, true);
    $('tvGrid').addEventListener('keydown', e => {
      if (e.key.toLowerCase() !== 'f' || e.ctrlKey || e.altKey || e.metaKey) return;
      const b = e.target.closest('.ch'); if (!b) return;
      const i = Number(b.dataset.i); toggleFav(filtered[i]); refreshFav(i); renderSide();
    });
    $('tvSearch').addEventListener('input', e => {
      st.q = e.target.value.trim(); $('tvClear').hidden = !st.q;
      clearTimeout(searchTimer); searchTimer = setTimeout(() => { render(); $('tvMain').scrollTo({ top: 0 }); }, 220);
    });
    $('tvSearch').addEventListener('keydown', e => { if (e.key === 'Escape') { e.stopPropagation(); $('tvClear').click(); } });
    $('tvClear').onclick = () => { $('tvSearch').value = ''; st.q = ''; $('tvClear').hidden = true; render(); };
    $('tvCountry').onchange = e => { st.country = e.target.value; render(); $('tvMain').scrollTo({ top: 0 }); };
    $('tvRefresh').onclick = () => load(true);
    if ('IntersectionObserver' in window) {
      io = new IntersectionObserver(es => { if (es.some(x => x.isIntersecting)) more(); }, { root: $('tvMain'), rootMargin: '600px' });
      io.observe($('tvSentinel'));
    } else $('tvMain').addEventListener('scroll', () => { const m = $('tvMain'); if (m.scrollTop + m.clientHeight > m.scrollHeight - 800) more(); });
    $('mainStream').querySelector('.lbl').textContent = 'Switch 1/1';
    $('backupStream').hidden = true;
    $('mainStream').onclick = () => {
      if (!cur) return;
      const total = streamList(cur.c).length;
      if (total > 1) play(cur.c, ((cur.streamIndex || 0) + 1) % total);
    };
    $('backupStream').onclick = () => {
      if (cur && streamList(cur.c).length > 1) play(cur.c, ((cur.streamIndex || 0) + 1) % streamList(cur.c).length);
    };
    if ($('tvMethod')) $('tvMethod').onclick = nextWay;
    $('prevCh').onclick = () => zap(-1);
    $('nextCh').onclick = () => zap(1);
    document.addEventListener('keydown', e => {
      if (document.body.dataset.mode !== 'tv' || $('playerPanel').style.display !== 'block' || /input|textarea|select/i.test(e.target.tagName)) return;
      if (e.key === 'PageUp' || e.key === ']' ) { e.preventDefault(); zap(-1); }
      else if (e.key === 'PageDown' || e.key === '[') { e.preventDefault(); zap(1); }
      else if (e.key.toLowerCase() === 'b') { if (cur && streamList(cur.c).length > 1) play(cur.c, ((cur.streamIndex || 0) + 1) % streamList(cur.c).length); }
      else if (e.key.toLowerCase() === 'r') nextWay();
    });
  }
  function enter() {
    build();
    if (isPl()) { if (curPl()) loadPl(curPl(), false); else st.cat = 'all'; }
    if (!all.length && !st.loading) { render(); load(false); }
    else { render(); const stale = !st.loading && nexusAge() > cfg.refreshMin * 60000; if (stale) load(false); }
  }
  window.addEventListener('hashchange', () => { if (location.hash === '#tv') enter(); });
  if (location.hash === '#tv') enter();
  // Public bridge for the fixture popup. Reuses the same TV player and failover logic as channel playback.
  window.deeprowssPlayFixture = (fixture, useBackup) => {
    if (!fixture) return false;
    const streams = Array.isArray(fixture.streams) ? fixture.streams : [
      { url: fixture.url, referer: fixture.referer, ua: fixture.ua },
      ...Object.keys(fixture).filter(key => /^altUrl\d*$/i.test(key)).sort((a,b) => Number(a.replace(/\D/g,'')) - Number(b.replace(/\D/g,''))).map(key => ({
        url: fixture[key], referer: fixture[key.replace(/^altUrl/i,'altReferer')], ua: fixture[key.replace(/^altUrl/i,'altUa')]
      }))
    ].filter(x => x && x.url);
    const selectedUrl = streams[useBackup ? 1 : 0] && streams[useBackup ? 1 : 0].url;
    if (!/^https?:\/\//i.test(String(selectedUrl || ''))) return false;
    build();
    document.body.classList.add('fixture-streaming');
    const item = {
      id: 'fixture:' + String(fixture.id || fixture.home || 'match'),
      name: String(fixture.home || 'Home') + ' vs ' + String(fixture.away || 'Away'),
      url: String(fixture.url || selectedUrl), altUrl: String(fixture.altUrl || ''),
      referer: String(fixture.referer || ''), userAgent: String(fixture.ua || ''),
      streams, category: 'sports', country: '', logo: ''
    };
    play(item, !!useBackup);
    return true;
  };
  window.deeprowssTvRemote = command => {
    if (!cur || $('playerPanel').style.display !== 'block') return false;
    if (command === 'mainstream') { play(cur.c, 0); return true; }
    if (command === 'backupstream' && streamList(cur.c).length > 1) { play(cur.c, ((cur.streamIndex || 0) + 1) % streamList(cur.c).length); return true; }
    if (command === 'previous') { zap(-1); return true; }
    if (command === 'next') { zap(1); return true; }
    return false;
  };
  window.deeprowssTv = { reload: () => load(true) };
})();
