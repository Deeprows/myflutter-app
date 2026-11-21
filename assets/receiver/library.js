/* Deeprowss movie library (receiver website).
   TMDB trending, Top 10, genres, search, details, trailers, series episodes,
   Watch Later + Watch History, plus the Deeprowss catalogue (movies.json). */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const ROOT = 'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/';
  const MOVIES_URL = ROOT + 'movies.json';
  const CONFIG_URL = ROOT + 'app_config.json';
  const FALLBACK_KEY = 'b83de997ce0ca0406c12cab7f256e43a';
  const IMG = 'https://image.tmdb.org/t/p/';
  const LATER_KEY = 'deeprowss_watch_later';
  const HISTORY_KEY = 'deeprowss_watch_history';

  let apiKey = FALLBACK_KEY, language = 'en-US';
  let embedBase = 'https://vsembed.su/embed', altEmbedBase = 'https://web.nxsha.app/embed', downloadBase = 'https://web.nxsha.app/dl';
  let catalogue = [];
  const state = { q: '', genre: 'All', type: 'all', lib: false, view: 'home', saved: LATER_KEY, page: 1, pages: 1, token: 0 };
  let activeMovie = null, sel = { s: 1, e: 1 }, searchTimer, mosaicCount = 0;

  const GENRES = {
    Action: [28, 10759], Adventure: [12, 10759], Animation: [16, 16], Comedy: [35, 35], Crime: [80, 80],
    Documentary: [99, 99], Drama: [18, 18], Family: [10751, 10751], Fantasy: [14, 10765], History: [36, null],
    Horror: [27, null], Mystery: [9648, 9648], Romance: [10749, null], 'Sci-Fi': [878, 10765],
    Thriller: [53, null], War: [10752, 10768], Western: [37, 37]
  };
  const genreNames = {28:'Action',12:'Adventure',16:'Animation',35:'Comedy',80:'Crime',99:'Documentary',18:'Drama',10751:'Family',14:'Fantasy',36:'History',27:'Horror',10402:'Music',9648:'Mystery',10749:'Romance',878:'Sci-Fi',10770:'TV Movie',53:'Thriller',10752:'War',37:'Western',10759:'Action & Adventure',10762:'Kids',10763:'News',10764:'Reality',10765:'Sci-Fi & Fantasy',10766:'Soap',10767:'Talk',10768:'War & Politics'};

  /* ---------- helpers ---------- */
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const title = m => m?.title || m?.name || m?.original_title || m?.original_name || 'Untitled';
  const cleanTitle = m => title(m).replace(/\s*\(\d{4}\)\s*$/, '');
  const idOf = m => Number(m?.tmdbId || m?.tmdb_id || m?.id) || null;
  const isTv = m => m?.type === 'tv' || m?.media_type === 'tv' || /\/tv\//i.test(m?.url || '');
  const keyOf = m => String(idOf(m) || m?.url || title(m));
  const ratingNum = m => { const raw = String(m?.rating ?? ''); let n = parseFloat(raw); if (/\/\s*100/.test(raw)) n /= 10; return Number.isFinite(n) && n > 0 ? n : 0; };
  const isNew = m => !m?.poster_path && m?.date && (Date.now() - Date.parse(m.date)) < 21 * 864e5 && (Date.now() - Date.parse(m.date)) > -864e5;
  const openDl = u => { if (window.deeprowssDesktop && window.deeprowssDesktop.openDownload) window.deeprowssDesktop.openDownload(u); else window.open(u, '_blank', 'noopener'); };
  const yearOf = m => (m?.release_date || m?.date || (/\((\d{4})\)/.exec(m?.name || '') || [])[1] || '').toString().slice(0, 4);
  const safeUrl = raw => { if (!raw) return ''; try { const u = new URL(raw); return ['http:', 'https:'].includes(u.protocol) ? u.href : ''; } catch (_) { return ''; } };
  function image(m, size = 'w342') {
    if (m?.poster_path) return IMG + size + m.poster_path;
    const s = m?.image || m?.poster || '';
    return /\/t\/p\/(w\d+|original)\//.test(s) ? s.replace(/\/t\/p\/(w\d+|original)\//, '/t/p/' + size + '/') : s;
  }
  const readList = key => { try { const v = JSON.parse(localStorage.getItem(key) || '[]'); return Array.isArray(v) ? v : []; } catch (_) { return []; } };
  const writeList = (key, rows) => { try { localStorage.setItem(key, JSON.stringify(rows.slice(0, 150))); } catch (_) {} };
  function saveList(key, movie) {
    const k = keyOf(movie);
    writeList(key, [movie, ...readList(key).filter(x => keyOf(x) !== k)]);
  }
  const isSaved = m => readList(LATER_KEY).some(x => keyOf(x) === keyOf(m));
  async function getJson(url) {
    const r = await fetch(url + (url.includes('?') ? '&' : '?') + '_refresh=' + Date.now(), { cache: 'no-store' });
    if (!r.ok) throw Error('HTTP ' + r.status);
    return r.json();
  }
  async function getJsonFb(url, local) { try { return await getJson(url); } catch (e) { try { return await getJson(local); } catch (_) { throw e; } } }
  async function tmdb(path, params = {}) {
    if (!apiKey) return null;
    const u = new URL('https://api.themoviedb.org/3' + path);
    u.searchParams.set('api_key', apiKey);
    u.searchParams.set('language', language);
    Object.entries(params).forEach(([k, v]) => u.searchParams.set(k, v));
    const r = await fetch(u.href);
    if (!r.ok) throw Error('TMDB ' + r.status);
    return r.json();
  }
  async function loadConfig() {
    try {
      const c = await getJsonFb(CONFIG_URL, 'data/app_config.json'), t = c.tmdb || {}, m = c.movies || {};
      apiKey = t.enabled === false ? '' : (t.apiKey || t.key || FALLBACK_KEY);
      if (t.language) language = t.language;
      embedBase = (m.embedBase || embedBase).replace(/\/+$/, '');
      altEmbedBase = (m.altEmbedBase || altEmbedBase).replace(/\/+$/, '');
      downloadBase = (m.downloadBase || downloadBase).replace(/\/+$/, '');
    } catch (_) { /* keep last known values */ }
  }
  function fromTmdb(raw, type) {
    if (!raw || !raw.id || raw.media_type === 'person') return null;
    const kind = raw.media_type || type || (raw.first_air_date !== undefined || raw.name ? 'tv' : 'movie');
    const tv = kind === 'tv';
    const name = raw[tv ? 'name' : 'title'] || raw.title || raw.name;
    if (!name) return null;
    const date = raw[tv ? 'first_air_date' : 'release_date'] || '';
    const gs = (raw.genre_ids || []).map(x => genreNames[x]).filter(Boolean);
    return {
      name: name + (date ? ' (' + date.slice(0, 4) + ')' : ''), title: name, type: tv ? 'tv' : 'movie', tmdbId: raw.id,
      url: embedBase + '/' + (tv ? 'tv' : 'movie') + '/' + raw.id,
      downloadUrl: downloadBase + '/' + (tv ? 'tv' : 'movie') + '/' + raw.id,
      rating: raw.vote_average ? Number(raw.vote_average).toFixed(1) + '/10' : '',
      genre: gs.join(','), genres: gs, poster_path: raw.poster_path || '', image: raw.poster_path ? IMG + 'w500' + raw.poster_path : '',
      overview: raw.overview || '', release_date: date, backdrop_path: raw.backdrop_path || ''
    };
  }
  const mapList = (d, type, n) => (d?.results || []).map(x => fromTmdb(x, type)).filter(m => m && (m.poster_path || m.image)).slice(0, n || 20);

  /* ---------- cards & rails ---------- */
  function card(m, { kind = 'p', rank = null } = {}) {
    const b = document.createElement('button');
    b.type = 'button'; b.className = 'card ' + kind; b.setAttribute('aria-label', title(m));
    const src = image(m, kind === 'h' ? 'w500' : 'w342'), r = ratingNum(m);
    const meta = [isTv(m) ? 'Series' : 'Movie', yearOf(m)].filter(Boolean).join(' · ');
    let h = '<span class="poster">' + (src ? '<img loading="lazy" decoding="async" alt="" src="' + esc(src) + '">' : '<span class="noimg">▣</span>');
    if (rank !== null) h += '<span class="rank">' + (rank + 1) + '</span>';
    if (r && kind !== 'h') h += '<span class="star">★ ' + r.toFixed(1) + '</span>';
    if (kind !== 'h' && rank === null && isNew(m)) h += '<span class="new">NEW</span>';
    if (kind === 'h') {
      h += '<span class="over"><span class="badge-t">🔥 TRENDING</span><span class="ct">' + esc(cleanTitle(m)) + '</span><span class="cm">' + esc(yearOf(m)) + (r ? ' · ★ ' + r.toFixed(1) + '/10' : '') + '</span></span></span>';
    } else {
      h += '</span><span class="ct">' + esc(cleanTitle(m)) + '</span><span class="cm">' + esc(meta) + '</span>';
    }
    b.innerHTML = h;
    b.onclick = () => openDetails(m);
    return b;
  }
  const SKELETON = '<div class="skel"></div>'.repeat(8);
  function makeRail(id, label, sub) {
    const s = document.createElement('section');
    s.className = 'sec'; s.id = 'sec-' + id;
    s.innerHTML = '<div class="sec-head"><h3>' + esc(label) + '</h3><span>' + esc(sub || '') + '</span></div>' +
      '<div class="railwrap"><button class="arrow prev" type="button" aria-label="Scroll left">‹</button><div class="rail">' + SKELETON + '</div><button class="arrow next" type="button" aria-label="Scroll right">›</button></div>';
    const rail = s.querySelector('.rail');
    s.querySelector('.prev').onclick = () => rail.scrollBy({ left: -rail.clientWidth * .8, behavior: 'smooth' });
    s.querySelector('.next').onclick = () => rail.scrollBy({ left: rail.clientWidth * .8, behavior: 'smooth' });
    return s;
  }
  function fillRail(sec, items, opts = {}) {
    if (!items.length) { sec.remove(); return; }
    const rail = sec.querySelector('.rail'); rail.innerHTML = '';
    items.forEach((m, i) => rail.append(card(m, { kind: opts.kind || 'p', rank: opts.ranked ? i : null })));
  }
  function addMosaic(items) {
    const root = $('mosaic'); if (!root) return;
    for (const m of items) {
      if (mosaicCount >= 36) return;
      const src = m.poster_path ? IMG + 'w185' + m.poster_path : '';
      if (!src) continue;
      const i = new Image(); i.alt = ''; i.decoding = 'async'; i.src = src; root.append(i); mosaicCount++;
    }
  }

  const RAILS = [
    { id: 'trending', label: 'Trending Now', sub: 'THIS WEEK', kind: 'h', path: '/trending/all/week', n: 12 },
    { id: 'today', label: 'Top 10 Today', sub: 'TOP 10', ranked: 1, path: '/trending/all/day', n: 10 },
    { id: 'topmovies', label: 'Top 10 Movies', sub: 'TOP RATED', ranked: 1, path: '/movie/top_rated', type: 'movie', n: 10, sort: 1 },
    { id: 'topseries', label: 'Top 10 Series', sub: 'TOP RATED', ranked: 1, path: '/tv/top_rated', type: 'tv', n: 10, sort: 1 },
    { id: 'tmovies', label: 'Trending Movies', sub: 'THIS WEEK', path: '/trending/movie/week', type: 'movie' },
    { id: 'tseries', label: 'Trending Series', sub: 'THIS WEEK', path: '/trending/tv/week', type: 'tv' },
    { id: 'now', label: 'In Cinemas Now', sub: 'NOW PLAYING', path: '/movie/now_playing', type: 'movie', trailers: 1 },
    { id: 'popmovies', label: 'Popular Movies', sub: 'POPULAR', path: '/movie/popular', type: 'movie' },
    { id: 'popseries', label: 'Popular Series', sub: 'POPULAR', path: '/tv/popular', type: 'tv' }
  ];

  async function loadHome() {
    const root = $('homeRails'); root.innerHTML = '';
    const history = readList(HISTORY_KEY).slice(0, 15);
    if (history.length) { const s = makeRail('continue', 'Continue Watching', 'HISTORY'); root.append(s); fillRail(s, history); }
    if (!apiKey) { root.insertAdjacentHTML('beforeend', '<div class="empty">TMDB is disabled. Set tmdb.enabled in app_config.json to show live movies.</div>'); renderCatalogueRail(); return; }
    let ok = 0, done = 0;
    const secs = RAILS.map(r => { const s = makeRail(r.id, r.label, r.sub); root.append(s); return s; });
    const catSlot = document.createElement('div'); catSlot.id = 'catSlot'; root.append(catSlot);
    const token = ++state.token;
    await Promise.all(RAILS.map(async (r, i) => {
      try {
        const d = await tmdb(r.path, { page: 1 });
        if (token !== state.token) return;
        let items = mapList(d, r.type, 40);
        if (r.sort) items.sort((a, b) => ratingNum(b) - ratingNum(a));
        items = items.slice(0, r.n || 20);
        ok++; fillRail(secs[i], items, r);
        if (r.id === 'trending' && items[0]) {
          const feat = items.filter(x => x.backdrop_path).slice(0, 10).map(x => ({ backdrop: IMG + 'w1280' + x.backdrop_path, title: cleanTitle(x), year: yearOf(x), rating: ratingNum(x), overview: x.overview, tv: isTv(x) }));
          window.deeprowssFeatureList = feat; window.dispatchEvent(new CustomEvent('deeprowss:feature', { detail: feat }));
          const bg = items.find(x => x.backdrop_path) || items[0];
          if (bg.backdrop_path) $('heroBg').style.backgroundImage = 'url(' + IMG + 'w1280' + bg.backdrop_path + ')';
        }
        if (i < 3) addMosaic(items);
        if (r.trailers) loadTrailers(items.slice(0, 10));
      } catch (_) { secs[i].remove(); }
      finally { done++; }
    }));
    if (token !== state.token) return;
    renderCatalogueRail();
    if (!ok) root.insertAdjacentHTML('afterbegin', '<div class="empty">Could not load movies. Check your connection.<br><button type="button" class="chip on" id="retryHome">Try again</button></div>');
    const retry = $('retryHome'); if (retry) retry.onclick = () => loadHome();
  }
  async function loadTrailers(movies) {
    const found = await Promise.all(movies.map(async m => {
      try {
        const v = await tmdb('/movie/' + m.tmdbId + '/videos');
        const t = (v?.results || []).filter(x => x.site === 'YouTube' && x.type === 'Trailer' && x.key).sort((a, b) => (b.published_at || '').localeCompare(a.published_at || ''))[0];
        return t ? { key: t.key, name: cleanTitle(m) } : null;
      } catch (_) { return null; }
    }));
    const list = found.filter(Boolean).slice(0, 12);
    if (!list.length || state.view !== 'home') return;
    const s = makeRail('trailers', 'Latest Trailers', 'WATCH PREVIEWS');
    const rail = s.querySelector('.rail'); rail.innerHTML = '';
    list.forEach(t => {
      const b = document.createElement('button'); b.type = 'button'; b.className = 'tcard';
      b.innerHTML = '<span class="thumb"><img loading="lazy" alt="" src="https://img.youtube.com/vi/' + encodeURIComponent(t.key) + '/hqdefault.jpg"><span class="playicon">▶</span></span><span class="ct">' + esc(t.name) + '</span>';
      b.onclick = () => window.deeprowssPlay('https://www.youtube.com/embed/' + encodeURIComponent(t.key) + '?autoplay=1&rel=0', 'embed', t.name + ' · Trailer');
      rail.append(b);
    });
    const anchor = $('sec-popmovies') || $('catSlot'); if (anchor) anchor.before(s); else $('homeRails').append(s);
  }
  function renderCatalogueRail() {
    const slot = $('catSlot') || $('homeRails');
    if ($('sec-picks') || !catalogue.length) return;
    const s = makeRail('picks', 'Deeprowss Picks', 'CURATED'); slot.append(s);
    const items = [...catalogue].sort((a, b) => String(b.date || '').localeCompare(String(a.date || ''))).slice(0, 24);
    fillRail(s, items);
  }
  async function loadCatalogue() {
    try {
      const d = await getJsonFb(MOVIES_URL, 'data/movies.json');
      catalogue = (Array.isArray(d) ? d : d.movies || []).filter(m => m && safeUrl(m.url || m.embedUrl || m.streamUrl));
      if (state.view === 'home') renderCatalogueRail();
    } catch (_) { /* catalogue is optional */ }
  }

  /* ---------- filters, search, results ---------- */
  function renderChips() {
    const root = $('libFilters'); root.innerHTML = '';
    const chip = (label, on, fn) => { const b = document.createElement('button'); b.type = 'button'; b.className = 'chip' + (on ? ' on' : ''); b.textContent = label; b.onclick = fn; root.append(b); };
    chip('All', state.type === 'all' && state.genre === 'All' && !state.lib, () => { state.type = 'all'; state.genre = 'All'; state.lib = false; refresh(); });
    chip('Movies', state.type === 'movie', () => { state.type = state.type === 'movie' ? 'all' : 'movie'; refresh(); });
    chip('Series', state.type === 'tv', () => { state.type = state.type === 'tv' ? 'all' : 'tv'; refresh(); });
    chip('★ Deeprowss Library', state.lib, () => { state.lib = !state.lib; refresh(); });
    Object.keys(GENRES).forEach(g => chip(g, state.genre === g, () => { state.genre = state.genre === g ? 'All' : g; refresh(); }));
  }
  async function fetchResults(page) {
    const q = state.q, g = state.genre, t = state.type;
    const typeOk = m => t === 'all' || isTv(m) === (t === 'tv');
    const genreOk = m => g === 'All' || (m.genres || []).includes(g) || String(m.genre || '').toLowerCase().includes(g.toLowerCase());
    if (state.lib) {
      const ql = q.toLowerCase();
      const items = catalogue.filter(m => typeOk(m) && genreOk(m) && (q.length < 2 || title(m).toLowerCase().includes(ql)))
        .sort((a, b) => String(b.date || '').localeCompare(String(a.date || '')));
      return { items, pages: 1 };
    }
    if (q.length >= 2) {
      const ql = q.toLowerCase();
      const items = page === 1 ? catalogue.filter(m => typeOk(m) && genreOk(m) && title(m).toLowerCase().includes(ql)) : [];
      const seen = new Set(items.map(keyOf));
      let pages = 1;
      if (apiKey) {
        const d = await tmdb('/search/multi', { query: q, include_adult: 'false', page });
        pages = d?.total_pages || 1;
        mapList(d, null, 40).forEach(m => { if (!seen.has(keyOf(m)) && typeOk(m) && genreOk(m)) { items.push(m); seen.add(keyOf(m)); } });
      }
      return { items, pages };
    }
    if (!apiKey) return { items: [], pages: 1 };
    const calls = [];
    if (g !== 'All') {
      const pair = GENRES[g] || [];
      const base = { sort_by: 'popularity.desc', 'vote_count.gte': 50, include_adult: 'false', page };
      if (t !== 'tv' && pair[0]) calls.push(tmdb('/discover/movie', { ...base, with_genres: pair[0] }).then(d => [d, 'movie']));
      if (t !== 'movie' && pair[1]) calls.push(tmdb('/discover/tv', { ...base, with_genres: pair[1] }).then(d => [d, 'tv']));
    } else {
      if (t !== 'tv') calls.push(tmdb('/movie/popular', { page }).then(d => [d, 'movie']));
      if (t !== 'movie') calls.push(tmdb('/tv/popular', { page }).then(d => [d, 'tv']));
    }
    const res = await Promise.all(calls);
    const lists = res.map(([d, type]) => mapList(d, type, 40));
    const items = [];
    for (let i = 0; i < Math.max(0, ...lists.map(l => l.length)); i++) lists.forEach(l => { if (l[i]) items.push(l[i]); });
    return { items, pages: Math.min(Math.max(0, ...res.map(([d]) => d?.total_pages || 1)), 20) };
  }
  function setView(v) {
    state.view = v;
    $('homeRails').hidden = v !== 'home'; $('resultsWrap').hidden = v !== 'results'; $('savedWrap').hidden = v !== 'saved';
    $('heroBlock').hidden = v === 'saved';
    $('btnLater').classList.toggle('on', v === 'saved' && state.saved === LATER_KEY);
    $('btnHistory').classList.toggle('on', v === 'saved' && state.saved === HISTORY_KEY);
    $('movTitle').textContent = v === 'saved' ? (state.saved === LATER_KEY ? 'Watch Later' : 'Watch History') : 'Movies';
  }
  async function refresh() {
    renderChips();
    const filtered = state.q.length >= 2 || state.genre !== 'All' || state.type !== 'all' || state.lib;
    if (!filtered) { setView('home'); if (!$('homeRails').children.length) loadHome(); else refreshContinue(); return; }
    setView('results'); state.page = 1;
    const token = ++state.token;
    $('resTitle').textContent = state.q.length >= 2 ? 'Search Results' : state.lib ? 'Deeprowss Library' : state.genre !== 'All' ? state.genre : state.type === 'tv' ? 'Series' : 'Movies';
    $('resCount').textContent = 'Loading…'; $('resGrid').innerHTML = '<div class="skel"></div>'.repeat(10); $('loadMore').hidden = true;
    try {
      const r = await fetchResults(1);
      if (token !== state.token) return;
      state.pages = r.pages; $('resGrid').innerHTML = '';
      r.items.forEach(m => $('resGrid').append(card(m)));
      $('resCount').textContent = r.items.length + ' titles';
      if (!r.items.length) $('resGrid').innerHTML = '<div class="empty">No titles found.</div>';
      $('loadMore').hidden = state.page >= state.pages || !r.items.length;
    } catch (_) { if (token === state.token) $('resGrid').innerHTML = '<div class="empty">Could not load results. Check your connection.</div>'; $('resCount').textContent = ''; }
  }
  function refreshContinue() {
    const old = $('sec-continue'), history = readList(HISTORY_KEY).slice(0, 15);
    if (old) old.remove();
    if (!history.length) return;
    const s = makeRail('continue', 'Continue Watching', 'HISTORY'); $('homeRails').prepend(s); fillRail(s, history);
  }
  $('loadMore').onclick = async () => {
    if (state.page >= state.pages) return;
    const token = state.token, btn = $('loadMore'); btn.disabled = true; btn.textContent = 'Loading…';
    try {
      const r = await fetchResults(state.page + 1);
      if (token !== state.token) return;
      state.page++; const have = new Set([...$('resGrid').children].map(x => x.dataset.k));
      r.items.forEach(m => { if (!have.has(keyOf(m))) { const c = card(m); c.dataset.k = keyOf(m); $('resGrid').append(c); } });
      $('resCount').textContent = $('resGrid').children.length + ' titles';
    } catch (_) {}
    btn.disabled = false; btn.textContent = 'Load more'; btn.hidden = state.page >= state.pages;
  };
  $('libSearch').oninput = e => {
    state.q = e.target.value.trim(); $('clearSearch').hidden = !state.q;
    clearTimeout(searchTimer); searchTimer = setTimeout(refresh, 350);
  };
  $('libSearch').addEventListener('keydown', e => { if (e.key === 'Enter') { clearTimeout(searchTimer); refresh(); e.target.blur(); } if (e.key === 'Escape') $('clearSearch').click(); });
  $('clearSearch').onclick = () => { $('libSearch').value = ''; state.q = ''; $('clearSearch').hidden = true; refresh(); };

  /* ---------- Watch Later / History ---------- */
  function showSaved(key) {
    state.saved = key; state.token++;
    const rows = readList(key), grid = $('savedGrid');
    setView('saved'); grid.innerHTML = '';
    $('savedHint').textContent = rows.length ? rows.length + ' saved' : '';
    $('clearSaved').hidden = !rows.length || key !== HISTORY_KEY;
    if (!rows.length) { grid.innerHTML = '<div class="empty">' + (key === LATER_KEY ? 'Nothing saved yet. Open any title and tap “Watch later”.' : 'Nothing watched yet.') + '</div>'; return; }
    rows.forEach(m => {
      const wrap = document.createElement('div'); wrap.className = 'savedItem';
      const rm = document.createElement('button'); rm.type = 'button'; rm.className = 'rm'; rm.textContent = 'Remove';
      rm.onclick = () => { writeList(key, readList(key).filter(x => keyOf(x) !== keyOf(m))); showSaved(key); };
      wrap.append(card(m), rm); grid.append(wrap);
    });
  }
  $('btnLater').onclick = () => state.view === 'saved' && state.saved === LATER_KEY ? backHome() : showSaved(LATER_KEY);
  $('btnHistory').onclick = () => state.view === 'saved' && state.saved === HISTORY_KEY ? backHome() : showSaved(HISTORY_KEY);
  $('clearSaved').onclick = () => { writeList(HISTORY_KEY, []); showSaved(HISTORY_KEY); };
  function backHome() { refresh(); $('moviesView').scrollTo({ top: 0, behavior: 'smooth' }); }
  $('movBack').onclick = () => {
    if (!$('movieDetails').hidden && $('movieDetails').classList.contains('open')) { closeDetails(); return; }
    if (state.view !== 'home' || state.q || state.genre !== 'All' || state.type !== 'all' || state.lib) {
      state.q = ''; state.genre = 'All'; state.type = 'all'; state.lib = false; $('libSearch').value = ''; $('clearSearch').hidden = true; backHome();
    } else window.deeprowssGo('landing');
  };

  /* ---------- details sheet ---------- */
  function closeDetails() { $('movieDetails').classList.remove('open'); $('detailTrailer').innerHTML = ''; activeMovie = null; }
  function playTitle(movie, alt) {
    const id = idOf(movie), tv = isTv(movie);
    let url;
    if (alt) url = altEmbedBase + '/' + (tv ? 'tv' : 'movie') + '/' + id + (tv ? '/' + sel.s + '/' + sel.e : '');
    else if (tv && id) url = embedBase + '/tv/' + id + '/' + sel.s + '/' + sel.e;
    else url = movie.url || movie.embedUrl || movie.streamUrl || (id ? embedBase + '/movie/' + id : '');
    url = safeUrl(url);
    if (!url) { alert('This title has no playable URL.'); return; }
    saveList(HISTORY_KEY, movie);
    closeDetails();
    window.deeprowssPlay(url, 'embed', cleanTitle(movie) + (tv ? ' · S' + sel.s + ' E' + sel.e : '') + (alt ? ' · Alternate Player' : ''));
  }
  async function resolveTmdb(movie) {
    let id = idOf(movie), tv = isTv(movie);
    if (id) return { id, tv };
    const raw = movie.url || '';
    const match = raw.match(/\/(movie|tv)\/(tt\d+|\d+)/i);
    if (match) {
      tv = match[1].toLowerCase() === 'tv'; id = match[2];
      if (/^\d+$/.test(id)) return { id: Number(id), tv };
      const found = await tmdb('/find/' + id, { external_source: 'imdb_id' });
      const row = (tv ? found.tv_results : found.movie_results)?.[0] || (found.movie_results || found.tv_results || [])[0];
      if (row) return { id: row.id, tv: !!(found.tv_results || []).some(x => x.id === row.id) };
    }
    const name = cleanTitle(movie);
    const d = await tmdb(tv ? '/search/tv' : '/search/movie', { query: name });
    const norm = s => String(s || '').toLowerCase().replace(/[^a-z0-9]/g, '');
    const row = (d?.results || []).find(x => [x.title, x.name, x.original_title, x.original_name].some(n => norm(n) === norm(name)));
    return row ? { id: row.id, tv } : null;
  }
  function setupEpisodes(seasons) {
    const list = (seasons || []).filter(s => s.season_number > 0 && s.episode_count > 0);
    const wrap = $('detailEpisodes'); wrap.hidden = !list.length;
    if (!list.length) return;
    const ss = $('detailSeason'), ee = $('detailEpisode');
    ss.innerHTML = list.map(s => '<option value="' + s.season_number + '">Season ' + s.season_number + '</option>').join('');
    const fillEpisodes = () => {
      const s = list.find(x => x.season_number === sel.s) || list[0]; sel.s = s.season_number;
      ee.innerHTML = Array.from({ length: s.episode_count }, (_, i) => '<option value="' + (i + 1) + '">Episode ' + (i + 1) + '</option>').join('');
      sel.e = Math.min(sel.e, s.episode_count); ee.value = sel.e;
    };
    sel = { s: list[0].season_number, e: 1 }; ss.value = sel.s; fillEpisodes();
    ss.onchange = () => { sel.s = Number(ss.value); sel.e = 1; fillEpisodes(); };
    ee.onchange = () => { sel.e = Number(ee.value) || 1; };
  }
  async function openDetails(movie) {
    activeMovie = movie; sel = { s: 1, e: 1 };
    const sheet = $('movieDetails'); sheet.classList.add('open'); $('sheetCard').scrollTop = 0;
    $('detailTitle').textContent = cleanTitle(movie);
    $('detailPoster').src = image(movie, 'w342') || ''; $('detailPoster').hidden = !image(movie, 'w342');
    $('detailBackdrop').hidden = true; $('detailOverview').textContent = movie.overview || 'Loading…';
    $('detailMeta').innerHTML = [isTv(movie) ? 'Series' : 'Movie', yearOf(movie), ratingNum(movie) ? '★ ' + ratingNum(movie).toFixed(1) : '', movie.date && !movie.release_date ? 'Added ' + movie.date : ''].filter(Boolean).map(x => '<span>' + esc(x) + '</span>').join('');
    $('detailCast').innerHTML = ''; $('detailTrailer').innerHTML = ''; $('detailTrailerWrap').hidden = true;
    $('detailSimilar').innerHTML = ''; $('similarHead').hidden = true; $('detailEpisodes').hidden = true; $('detailAlt').hidden = true;
    const dl = safeUrl(movie.downloadUrl || movie.download_url || '');
    $('detailDownload').hidden = !dl; $('detailDownload').onclick = () => { if (dl) openDl(dl); };
    const refreshSave = () => { $('detailSave').textContent = isSaved(movie) ? '✓ Saved' : '＋ Watch later'; };
    refreshSave();
    $('detailSave').onclick = () => {
      if (isSaved(movie)) writeList(LATER_KEY, readList(LATER_KEY).filter(x => keyOf(x) !== keyOf(movie))); else saveList(LATER_KEY, movie);
      refreshSave();
    };
    $('detailPlay').onclick = () => playTitle(movie, false);
    try {
      if (!apiKey) throw Error('TMDB is disabled');
      const target = await resolveTmdb(movie); if (!target) throw Error('No match found');
      const type = target.tv ? 'tv' : 'movie';
      const d = await tmdb('/' + type + '/' + target.id, { append_to_response: 'credits,videos,similar' });
      if (activeMovie !== movie) return;
      if (!movie.tmdbId) { movie.tmdbId = target.id; movie.type = type; movie.downloadUrl = movie.downloadUrl || downloadBase + '/' + type + '/' + target.id; }
      if (d.poster_path) { $('detailPoster').src = IMG + 'w342' + d.poster_path; $('detailPoster').hidden = false; if (!movie.poster_path) movie.poster_path = d.poster_path; }
      if (d.backdrop_path) { $('detailBackdrop').src = IMG + 'w1280' + d.backdrop_path; $('detailBackdrop').hidden = false; }
      const runtime = d.runtime || d.episode_run_time?.[0];
      const meta = [target.tv ? 'Series' : 'Movie', (d.release_date || d.first_air_date || '').slice(0, 4), d.vote_average ? '★ ' + Number(d.vote_average).toFixed(1) : '', runtime ? runtime + ' min' : '', movie.date && !movie.release_date ? 'Added ' + movie.date : '', ...(d.genres || []).map(g => g.name)];
      $('detailMeta').innerHTML = meta.filter(Boolean).map(x => '<span>' + esc(x) + '</span>').join('');
      $('detailOverview').textContent = d.overview || movie.overview || 'No overview available.';
      if (!dl) { const u = safeUrl(downloadBase + '/' + type + '/' + target.id); $('detailDownload').hidden = !u; $('detailDownload').onclick = () => openDl(u); }
      const cast = (d.credits?.cast || []).slice(0, 12);
      $('detailCast').innerHTML = cast.map(c => '<div class="person">' + (c.profile_path ? '<img loading="lazy" alt="" src="' + IMG + 'w185' + esc(c.profile_path) + '">' : '<span class="av">' + esc((c.name || '?')[0]) + '</span>') + '<b>' + esc(c.name) + '</b><small>' + esc(c.character || '') + '</small></div>').join('');
      if (target.tv) setupEpisodes(d.seasons);
      $('detailAlt').hidden = false; $('detailAlt').onclick = () => playTitle(movie, true);
      const v = (d.videos?.results || []).filter(x => x.site === 'YouTube' && ['Trailer', 'Teaser'].includes(x.type) && x.key).sort((a, b) => (b.official === true) - (a.official === true) || (b.published_at || '').localeCompare(a.published_at || ''))[0];
      if (v) {
        $('detailTrailerWrap').hidden = false;
        $('detailTrailer').innerHTML = '<button type="button" class="trailer-thumb"><img alt="" src="https://img.youtube.com/vi/' + encodeURIComponent(v.key) + '/hqdefault.jpg"><span class="playicon">▶</span></button>';
        $('detailTrailer').firstChild.onclick = () => { $('detailTrailer').innerHTML = '<iframe src="https://www.youtube.com/embed/' + encodeURIComponent(v.key) + '?autoplay=1&rel=0" allow="autoplay; encrypted-media; fullscreen; picture-in-picture" allowfullscreen title="Trailer"></iframe>'; };
      }
      const sim = mapList(d.similar, type, 14);
      if (sim.length) { $('similarHead').hidden = false; sim.forEach(x => $('detailSimilar').append(card(x))); }
    } catch (e) {
      if (activeMovie === movie) $('detailOverview').textContent = movie.overview || 'This title can still be played with the default player.';
    }
  }
  $('detailClose').onclick = closeDetails;
  $('movieDetails').addEventListener('click', e => { if (e.target === $('movieDetails')) closeDetails(); });
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && $('movieDetails').classList.contains('open')) closeDetails(); });

  /* ---------- start ---------- */
  renderChips();
  (async () => {
    await loadConfig();
    loadCatalogue();
    loadHome();
  })();
  setInterval(loadConfig, 10 * 60 * 1000);
})();
