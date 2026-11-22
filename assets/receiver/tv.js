/* Deeprowss live TV (receiver website + Windows app).
   Same sources as the Android app: your own channels (tv.json) merged with the
   IPTV Nexus online-channel API, grouped by category, with country filter,
   search, favourites, recently watched, backup streams and channel zapping. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
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
        const o = {
          id: s(raw.id), name, url: s(best.url), category: cat, logo: s(raw.logo), country: s(raw.country),
          quality: s(best.quality) || s(raw.best_quality), score: typeof raw.score === 'number' ? raw.score : 0,
          referer: s(best.referrer), userAgent: s(best.user_agent),
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
      const useAlt = !c.altUrl && n.url !== c.url;
      return { ...c, logo: n.logo || c.logo, country: n.country || c.country, quality: n.quality || c.quality, score: n.score || c.score,
        altUrl: useAlt ? n.url : c.altUrl, altReferer: useAlt ? n.referer : c.altReferer, altUserAgent: useAlt ? n.userAgent : c.altUserAgent };
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
    let h = '<h4>BROWSE</h4>' + row('all', '📡', 'All channels') + row('fav', '♥', 'Favourites') + row('recent', '🕘', 'Recently watched') + '<h4 style="margin-top:18px">CATEGORIES</h4>';
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
    if (st.cat === 'fav') { const f = new Set(favs().map(keyOf)); base = base.filter(c => f.has(keyOf(c))); const have = new Set(base.map(keyOf)); if (!st.country) favs().forEach(c => { if (!have.has(keyOf(c))) base.push(c); }); }
    else if (st.cat === 'recent') { const rec = readList(RECENT_KEY); base = rec.filter(c => !st.country || c.country === st.country); }
    else if (st.cat !== 'all') base = base.filter(c => c.category === st.cat);
    const q = st.q.toLowerCase();
    if (q) base = base.filter(c => c.name.toLowerCase().includes(q) || (c.country && (c.country.toLowerCase() === q || countryName(c.country).toLowerCase().includes(q))) || catLabel(c.category).toLowerCase().includes(q));
    filtered = base;
  }
  function cardHtml(c, i) {
    const q = qualityLabel(c.quality), fav = isFav(c);
    return '<div class="chw"><button type="button" class="ch" data-i="' + i + '" aria-label="' + esc(c.name) + '"><span class="lg"><span class="ini">' + esc(initials(c.name)) + '</span>' +
      (c.logo ? '<img loading="lazy" decoding="async" referrerpolicy="no-referrer" alt="" src="' + esc(c.logo) + '">' : '') + '<span class="lv">LIVE</span></span>' +
      '<span class="bd"><span class="nm">' + esc(c.name) + '</span><span class="mt"><span class="p2">' + esc(catLabel(c.category)) + '</span>' +
      (c.country ? '<span class="p2">' + esc(c.country) + '</span>' : '') + (q ? '<span class="p2 q">' + q + '</span>' : '') + '</span></span></button>' +
      '<button type="button" class="fav' + (fav ? ' on' : '') + '" data-fav="' + i + '" aria-label="' + (fav ? 'Remove from favourites' : 'Add to favourites') + '">' + (fav ? '♥' : '♡') + '</button></div>';
  }
  function title() {
    if (st.q) return 'Search';
    if (st.cat === 'all') return 'All channels'; if (st.cat === 'fav') return 'Favourites'; if (st.cat === 'recent') return 'Recently watched';
    return catLabel(st.cat);
  }
  function renderStatus() {
    const el = $('tvStatus');
    if (st.loading) { el.innerHTML = '<span class="spin"></span>Updating online channels…'; return; }
    const parts = [own.length + ' own', nexus.length ? nexus.length.toLocaleString() + ' online (IPTV Nexus)' : 'online list not loaded'];
    el.textContent = parts.join(' · ') + (st.nexusInfo ? ' · ' + st.nexusInfo : '') + (st.failed ? ' · update failed, showing saved copy' : '');
  }
  function render() {
    renderSide(); applyFilter(); renderStatus();
    $('tvTitle').textContent = title();
    $('tvCount').textContent = filtered.length.toLocaleString() + ' channels';
    const grid = $('tvGrid'); grid.innerHTML = ''; shown = 0;
    if (!filtered.length) {
      grid.innerHTML = '<div class="tv-empty">' + (st.loading ? 'Loading channels…' : st.cat === 'fav' ? 'No favourites yet. Tap the heart on any channel.' : st.cat === 'recent' ? 'Nothing watched yet.' : 'No channels found.') + '</div>';
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
  function streamOf(c, alt) {
    return alt && c.altUrl ? { url: c.altUrl, referer: c.altReferer, ua: c.altUserAgent } : { url: c.url, referer: c.referer, ua: c.userAgent };
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
  function openEmbed(c, alt, url, method, via) {
    const s = streamOf(c, alt);
    const info = window.deeprowssPlayTv(url, c.name + (alt && c.altUrl ? ' · Backup stream' : ''), {
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
    if (main) { main.disabled = !cur; main.classList.toggle('active', !!cur && !cur.alt); }
    if (backup) { backup.disabled = !cur || !cur.c.altUrl; backup.classList.toggle('active', !!cur && !!cur.alt); }
  }
  function armEmbedFallback(token, c, alt) {
    clearTimeout(fallbackWatchdog);
    if (alt || !c.altUrl) return;
    fallbackWatchdog = setTimeout(() => {
      if (token !== playToken || !cur || cur.c !== c || cur.alt || cur.embedLoaded) return;
      say('Main stream is taking too long. Switching to backup…');
      play(c, true);
    }, 18000);
  }
  /* A direct stream that cannot be read here (CORS, hotlink protection, geo): try the channel's own player page,
     then the backup stream, like the phone app's Reload does. */
  function streamFailed(reason) {
    if (!cur || cur.mode !== 'media' || cur.failed || $('playerPanel').style.display !== 'block') return;
    cur.failed = true; clearWatchdog();
    const c = cur.c, alt = cur.alt;
    if (!alt && c.altUrl) { say('Main stream unavailable. Switching to backup…'); play(c, true); return; }
    if (cur.wrapper) { say('Trying an alternate player…'); openEmbed(c, alt, cur.wrapper, 0, 'wrapper'); return; }
    say('This channel could not be opened here. Try Backup stream or another channel.');
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
  async function play(c, alt) {
    const s = streamOf(c, alt), r = resolve(s.url);
    if (r.kind === 'invalid') { say('This channel link is not valid.'); return; }
    let kind = r.kind;
    const token = ++playToken;
    clearWatchdog();
    if (kind === 'embed') { const k = await sniff(r.url); if (token !== playToken) return; if (k) kind = k; }
    cur = { c, alt: !!alt && !!c.altUrl, idx: filtered.findIndex(x => keyOf(x) === keyOf(c)), mode: 'media', wrapper: '', failed: false };
    pushRecent(c);
    if (kind === 'embed') {
      /* Web channels get their own iframe page (not the movie iframe) and several ways to open it. */
      openEmbed(c, cur.alt, r.url, 0, 'embed');
      armEmbedFallback(token, c, cur.alt);
    } else {
      cur.wrapper = wrapperOf(s.url, r.url);
      /* Windows app / Android TV app: send the channel's Referer + User-Agent and lift CORS for the stream. */
      if (desktop && desktop.setStreamHeaders) desktop.setStreamHeaders({ referer: s.referer || '', userAgent: s.ua || '' });
      window.__tvKeep = true; // clearMedia() inside deeprowssPlay must not drop the headers we are about to set
      try { if (window.DeeprowssTv && window.DeeprowssTv.setStream) window.DeeprowssTv.setStream(s.referer || '', s.ua || '', true); } catch (_) {}
      try { window.deeprowssPlay(r.url, kind, c.name + (cur.alt ? ' · Backup stream' : '')); } finally { window.__tvKeep = false; }
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
    if (cur.mode === 'embed') { openEmbed(cur.c, cur.alt, cur.embedUrl, (cur.method + 1) % Math.max(1, cur.count), cur.via); return; }
    if (cur.wrapper) { cur.failed = true; clearWatchdog(); openEmbed(cur.c, cur.alt, cur.wrapper, 0, 'wrapper'); }
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
      st.cat = b.dataset.cat; try { localStorage.setItem(LAST_CAT_KEY, st.cat); } catch (_) {}
      render(); $('tvMain').scrollTo({ top: 0 });
    });
    $('tvGrid').addEventListener('click', e => {
      const f = e.target.closest('[data-fav]');
      if (f) { const i = Number(f.dataset.fav); toggleFav(filtered[i]); refreshFav(i); renderSide(); return; }
      const b = e.target.closest('.ch'); if (b) play(filtered[Number(b.dataset.i)], false);
    });
    $('tvGrid').addEventListener('error', e => { if (e.target && e.target.tagName === 'IMG') e.target.remove(); }, true);
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
    $('mainStream').querySelector('.lbl').textContent = 'Switch 1';
    $('mainStream').title = 'Switch to stream 1';
    $('mainStream').setAttribute('aria-label', 'Switch to stream 1');
    $('backupStream').querySelector('.lbl').textContent = 'Switch 2';
    $('backupStream').title = 'Switch to stream 2';
    $('backupStream').setAttribute('aria-label', 'Switch to stream 2');
    $('mainStream').onclick = () => { if (cur) play(cur.c, false); };
    $('backupStream').onclick = () => { if (cur && cur.c.altUrl) play(cur.c, true); };
    if ($('tvMethod')) $('tvMethod').onclick = nextWay;
    $('prevCh').onclick = () => zap(-1);
    $('nextCh').onclick = () => zap(1);
    document.addEventListener('keydown', e => {
      if (document.body.dataset.mode !== 'tv' || $('playerPanel').style.display !== 'block' || /input|textarea|select/i.test(e.target.tagName)) return;
      if (e.key === 'PageUp' || e.key === ']' ) { e.preventDefault(); zap(-1); }
      else if (e.key === 'PageDown' || e.key === '[') { e.preventDefault(); zap(1); }
      else if (e.key.toLowerCase() === 'b') { if (cur && cur.c.altUrl) play(cur.c, !cur.alt); }
      else if (e.key.toLowerCase() === 'r') nextWay();
    });
  }
  function enter() {
    build();
    if (!all.length && !st.loading) { render(); load(false); }
    else { render(); const stale = !st.loading && nexusAge() > cfg.refreshMin * 60000; if (stale) load(false); }
  }
  window.addEventListener('hashchange', () => { if (location.hash === '#tv') enter(); });
  if (location.hash === '#tv') enter();
  // Public bridge for the fixture popup. Reuses the same TV player and failover logic as channel playback.
  window.deeprowssPlayFixture = (fixture, useBackup) => {
    const selectedUrl = useBackup ? fixture && fixture.altUrl : fixture && fixture.url;
    if (!fixture || !/^https?:\/\//i.test(String(selectedUrl || ''))) return false;
    build();
    document.body.classList.add('fixture-streaming');
    const item = {
      id: 'fixture:' + String(fixture.id || fixture.home || 'match'),
      name: String(fixture.home || 'Home') + ' vs ' + String(fixture.away || 'Away'),
      url: String(fixture.url), altUrl: String(fixture.altUrl || ''),
      referer: String(fixture.referer || ''), userAgent: String(fixture.ua || ''),
      altReferer: String(fixture.altReferer || ''), altUserAgent: String(fixture.altUa || ''),
      category: 'sports', country: '', logo: ''
    };
    play(item, !!useBackup);
    return true;
  };
  window.deeprowssTvRemote = command => {
    if (!cur || $('playerPanel').style.display !== 'block') return false;
    if (command === 'mainstream') { play(cur.c, false); return true; }
    if (command === 'backupstream' && cur.c.altUrl) { play(cur.c, true); return true; }
    if (command === 'previous') { zap(-1); return true; }
    if (command === 'next') { zap(1); return true; }
    return false;
  };
  window.deeprowssTv = { reload: () => load(true) };
})();
