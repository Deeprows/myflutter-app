/* Deeprowss receiver library: same TMDB discovery and remote feeds as the mobile app. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const ROOT = 'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/';
  const MOVIES_URL = ROOT + 'movies.json';
  const CHANNELS_URL = ROOT + 'tv.json';
  const CONFIG_URL = ROOT + 'app_config.json';
  const NEXUS_URL = 'https://dearbulut.github.io/iptv/api/v1/channels.online.json';
  const FALLBACK_KEY = 'b83de997ce0ca0406c12cab7f256e43a';
  const IMG = 'https://image.tmdb.org/t/p/';
  let config = {}, apiKey = FALLBACK_KEY, language = 'en-US';
  let embedBase = 'https://vsembed.su/embed', altEmbedBase = 'https://web.nxsha.app/embed', downloadBase = 'https://web.nxsha.app/dl';
  let movies = [], channels = [], trending = [], top10 = [], trendingMovies = [], trailers = [];
  let genre = 'All', mediaType = 'all', channelCategory = 'All', channelCountry = 'All', favoritesOnly = false, query = '', activeMovie = null;
  let searchTimer, remoteConfigTimer;
  const genreNames = {28:'Action',12:'Adventure',16:'Animation',35:'Comedy',80:'Crime',99:'Documentary',18:'Drama',10751:'Family',14:'Fantasy',36:'History',27:'Horror',10402:'Music',9648:'Mystery',10749:'Romance',878:'Sci-Fi',10770:'TV Movie',53:'Thriller',10752:'War',37:'Western',10759:'Action & Adventure',10762:'Kids',10763:'News',10764:'Reality',10765:'Sci-Fi & Fantasy',10766:'Soap',10767:'Talk',10768:'War & Politics'};
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const title = m => m?.name || m?.title || m?.original_title || m?.original_name || 'Untitled';
  const image = m => m?.image || m?.poster || m?.posterUrl || (m?.poster_path ? IMG + 'w500' + m.poster_path : '');
  const isTv = m => m?.type === 'tv' || m?.mediaType === 'tv' || m?.media_type === 'tv' || /\/tv\//i.test(m?.url || '') || /series|season|episode/i.test(title(m));
  const idOf = m => Number(m?.tmdbId || m?.tmdb_id || m?.id) || null;
  const safeUrl = (raw, base) => { if (!raw) return ''; try { const u = new URL(raw, base || 'https://deeprows.github.io/myflutter-app/'); return ['http:','https:'].includes(u.protocol) ? u.href : ''; } catch (_) { return ''; } };
  const fresh = url => url + (url.includes('?') ? '&' : '?') + '_refresh=' + Date.now();
  async function getJson(url) { const r = await fetch(fresh(url), {cache:'no-store'}); if (!r.ok) throw Error('HTTP ' + r.status); return r.json(); }
  async function loadConfig() {
    try {
      config = await getJson(CONFIG_URL);
      const t = config.tmdb || {};
      apiKey = t.enabled === false ? '' : (t.apiKey || t.key || FALLBACK_KEY);
      if (t.language) language = t.language;
      const m = config.movies || {};
      embedBase = (m.embedBase || embedBase).replace(/\/+$/, '');
      altEmbedBase = (m.altEmbedBase || altEmbedBase).replace(/\/+$/, '');
      downloadBase = (m.downloadBase || downloadBase).replace(/\/+$/, '');
    } catch (_) { /* use the last known values */ }
  }
  async function tmdb(path, params = {}) {
    if (!apiKey) return null;
    const u = new URL('https://api.themoviedb.org/3' + path);
    u.searchParams.set('api_key', apiKey);
    u.searchParams.set('language', language);
    Object.entries(params).forEach(([k,v]) => u.searchParams.set(k, v));
    const r = await fetch(u.href);
    if (!r.ok) throw Error('TMDB ' + r.status);
    return r.json();
  }
  function fromTmdb(raw, type) {
    if (!raw || !raw.id) return null;
    const tv = (raw.media_type || type) === 'tv';
    const name = raw[tv ? 'name' : 'title'] || raw.name || raw.title;
    if (!name) return null;
    const date = raw[tv ? 'first_air_date' : 'release_date'] || '';
    const gs = (raw.genre_ids || []).map(x => genreNames[x]).filter(Boolean);
    return {
      name: name + (date ? ' (' + date.slice(0,4) + ')' : ''),
      title: name, type: tv ? 'tv' : 'movie', tmdbId: raw.id,
      url: embedBase + '/' + (tv ? 'tv' : 'movie') + '/' + raw.id,
      downloadUrl: downloadBase + '/' + (tv ? 'tv' : 'movie') + '/' + raw.id,
      rating: raw.vote_average ? Number(raw.vote_average).toFixed(1) + '/10' : '',
      genre: gs.join(','), genres: gs, image: image(raw),
      overview: raw.overview || '', release_date: date, backdrop_path: raw.backdrop_path
    };
  }
  function movieCard(m, rank) {
    const el = document.createElement('article');
    el.className = 'libcard';
    const poster = document.createElement('div');
    poster.className = 'libposter';
    const src = image(m);
    poster.innerHTML = src ? '<img loading="lazy" src="' + esc(src) + '" alt="' + esc(title(m)) + '">' : '<div style="height:100%;display:grid;place-items:center;color:#8a9ab0">▣</div>';
    if (rank !== null && rank !== undefined) poster.insertAdjacentHTML('beforeend', '<span class="rank">' + (rank + 1) + '</span>');
    const name = document.createElement('strong');
    name.textContent = title(m);
    const meta = document.createElement('small');
    meta.textContent = [isTv(m) ? 'Series' : 'Movie', m.rating || '', m.year || (m.date || m.release_date || '').slice(0,4)].filter(Boolean).join(' · ');
    el.append(poster, name, meta);
    el.onclick = () => openDetails(m);
    return el;
  }
  function sectionMarkup(label, items, ranked) {
    if (!items.length) return '';
    const key = label.toLowerCase().replace(/[^a-z]/g, '');
    return '<section class="libsection"><div class="libsection-head"><h3>' + esc(label) + '</h3><span class="libmuted">' + (ranked ? 'TOP 10' : '') + '</span></div><div class="librail" id="rail-' + key + '"></div></section>';
  }
  function renderTrends() {
    const root = $('trendSections');
    root.innerHTML = sectionMarkup('Trending Now', trending) + sectionMarkup('Top 10', top10, true) + sectionMarkup('Trending Movies', trendingMovies) + (trailers.length ? '<section class="libsection"><div class="libsection-head"><h3>Latest Trailers</h3><span class="libmuted">WATCH PREVIEWS</span></div><div class="librail" id="rail-trailers"></div></section>' : '');
    [['Trending Now',trending],['Top 10',top10],['Trending Movies',trendingMovies]].forEach(([label, list]) => {
      const node = $('rail-' + label.toLowerCase().replace(/[^a-z]/g, ''));
      if (node) list.forEach((m,i) => node.append(movieCard(m, label === 'Top 10' ? i : null)));
    });
    const rail = $('rail-trailers');
    if (rail) trailers.forEach(t => {
      const el = document.createElement('div'); el.className = 'libtrailer';
      el.innerHTML = '<div class="thumb"><img loading="lazy" src="https://img.youtube.com/vi/' + encodeURIComponent(t.key) + '/hqdefault.jpg"><span class="playicon">▶</span></div><b>' + esc(t.title) + '</b>';
      el.onclick = () => openTrailer(t.key, t.title); rail.append(el);
    });
  }
  async function loadTrends() {
    if (!apiKey) { $('trendSections').innerHTML = '<div class="libmuted">TMDB is disabled. Set tmdb.enabled and tmdb.apiKey in app_config.json to enable live recommendations.</div>'; return; }
    try {
      const [tr, top, mov, now] = await Promise.all([
        tmdb('/trending/all/week', {page:1}), tmdb('/movie/top_rated', {page:1}),
        tmdb('/trending/movie/week', {page:1}), tmdb('/movie/now_playing', {page:1})
      ]);
      trending = (tr?.results || []).map(x => fromTmdb(x)).filter(Boolean).slice(0,15);
      top10 = (top?.results || []).map(x => fromTmdb(x,'movie')).filter(Boolean).sort((a,b) => parseFloat(b.rating || 0) - parseFloat(a.rating || 0)).slice(0,10);
      trendingMovies = (mov?.results || []).map(x => fromTmdb(x,'movie')).filter(Boolean).slice(0,20);
      const current = (now?.results || []).slice(0,9);
      const found = await Promise.all(current.map(async m => {
        try {
          const v = await tmdb('/movie/' + m.id + '/videos');
          const choices = (v?.results || []).filter(x => x.site === 'YouTube' && x.type === 'Trailer' && x.key).sort((a,b) => (b.published_at || '').localeCompare(a.published_at || ''));
          return choices[0] ? {key:choices[0].key,title:m.title || m.original_title} : null;
        } catch (_) { return null; }
      }));
      trailers = found.filter(Boolean).slice(0,12);
      renderTrends();
      if (trending[0]?.backdrop_path) { $('libHeroImage').src = IMG + 'w1280' + trending[0].backdrop_path; $('libHeroImage').hidden = false; }
    } catch (e) { $('trendSections').innerHTML = '<div class="libmuted">Could not load TMDB sections. Check the TMDB key or connection.</div>'; }
  }
  async function loadMovies() {
    try { const data = await getJson(MOVIES_URL); movies = (Array.isArray(data) ? data : data.movies || []).filter(m => m && safeUrl(m.url || m.embedUrl || m.streamUrl)); renderMovies(); }
    catch (_) { $('libMovieGrid').innerHTML = '<div class="libempty">Could not load the Deeprowss movie catalogue.</div>'; }
  }
  const genres = ['All','Action','Adventure','Animation','Comedy','Crime','Documentary','Drama','Family','Fantasy','Horror','Mystery','Romance','Sci-Fi','Thriller','War'];
  function renderFilters() {
    const root = $('libFilters'); root.innerHTML = '';
    ['All','Movies','Series',...genres.slice(1)].forEach(g => {
      const selected = (g === 'All' && genre === 'All' && mediaType === 'all') || (g === 'Movies' && mediaType === 'movie') || (g === 'Series' && mediaType === 'tv') || (!['All','Movies','Series'].includes(g) && genre === g);
      const b = document.createElement('button'); b.className = 'libchip' + (selected ? ' active' : ''); b.textContent = g;
      b.onclick = () => { if (g === 'Movies' || g === 'Series') { const next = g === 'Movies' ? 'movie' : 'tv'; mediaType = mediaType === next ? 'all' : next; genre = 'All'; } else { genre = g; mediaType = 'all'; } renderMovies(); };
      root.append(b);
    });
  }
  async function searchTmdb(q) {
    if (!apiKey || q.length < 2) return [];
    try { const d = await tmdb('/search/multi', {query:q,include_adult:'false'}); return (d?.results || []).map(x => fromTmdb(x)).filter(Boolean).slice(0,30); } catch (_) { return []; }
  }
  const discoverIds = {
    Action:['28','10759'], Adventure:['12','10759'], Animation:['16','16'],
    Comedy:['35','35'], Crime:['80','80'], Documentary:['99','99'],
    Drama:['18','18'], Family:['10751','10751'], Fantasy:['14','10765'],
    History:['36',null], Horror:['27',null], Music:['10402',null],
    Mystery:['9648','9648'], Romance:['10749',null], 'Sci-Fi':['878','10765'],
    Thriller:['53',null], War:['10752','10768'], Western:['37','37']
  };
  async function discoverGenre(g) {
    if (!apiKey || g === 'All') return [];
    const pair = discoverIds[g];
    if (!pair) return [];
    const [a,b] = await Promise.all([
      pair[0] ? tmdb('/discover/movie',{with_genres:pair[0],sort_by:'popularity.desc',include_adult:'false', 'vote_count.gte':50}) : Promise.resolve(null),
      pair[1] ? tmdb('/discover/tv',{with_genres:pair[1],sort_by:'popularity.desc',include_adult:'false', 'vote_count.gte':50}) : Promise.resolve(null)
    ]);
    const movies = (a?.results || []).map(x => fromTmdb(x,'movie')).filter(Boolean);
    const shows = (b?.results || []).map(x => fromTmdb(x,'tv')).filter(Boolean);
    const result = [];
    for (let i=0; i<Math.max(movies.length,shows.length); i++) {
      if (movies[i]) result.push(movies[i]);
      if (shows[i]) result.push(shows[i]);
    }
    return result;
  }
  async function renderMovies() {
    renderFilters();
    const requestedQuery = query, requestedGenre = genre, requestedType = mediaType;
    const q = requestedQuery.toLowerCase();
    const typeMatches = m => requestedType === 'all' || isTv(m) === (requestedType === 'tv');
    const genreMatches = m => requestedGenre === 'All' || (m.genre || m.genres?.join(',') || '').toLowerCase().includes(requestedGenre.toLowerCase());
    let list = movies.filter(m => typeMatches(m) && genreMatches(m) && (!q || (title(m) + ' ' + (m.genre || '')).toLowerCase().includes(q)));
    if (q.length >= 2) {
      const extra = await searchTmdb(requestedQuery);
      if (query !== requestedQuery || genre !== requestedGenre || mediaType !== requestedType) return;
      const seen = new Set(list.map(m => String(idOf(m) || m.url)));
      extra.forEach(m => { const k = String(idOf(m) || m.url); if (!seen.has(k) && typeMatches(m) && genreMatches(m)) { list.push(m); seen.add(k); } });
    } else if (requestedGenre !== 'All') {
      try {
        const extra = await discoverGenre(requestedGenre);
        if (query !== requestedQuery || genre !== requestedGenre || mediaType !== requestedType) return;
        const seen = new Set(list.map(m => String(idOf(m) || m.url)));
        extra.forEach(m => { const k = String(idOf(m) || m.url); if (!seen.has(k) && typeMatches(m) && genreMatches(m)) { list.push(m); seen.add(k); } });
      } catch (_) {}
    }
    $('libCatalogTitle').textContent = q ? 'Search Results' : requestedGenre !== 'All' ? requestedGenre : requestedType === 'tv' ? 'TV Series' : requestedType === 'movie' ? 'Movies' : 'All Movies & Series';
    $('libCount').textContent = list.length + ' titles';
    const grid = $('libMovieGrid'); grid.innerHTML = '';
    if (!list.length) { grid.innerHTML = '<div class="libempty">No titles found.</div>'; return; }
    list.forEach(m => grid.append(movieCard(m)));
  }
  function saveList(key, movie) {
    let rows = []; try { rows = JSON.parse(localStorage.getItem(key) || '[]'); } catch (_) {}
    const k = String(idOf(movie) || movie.url);
    rows = rows.filter(x => String(x.tmdbId || x.url) !== k);
    rows.unshift(movie); localStorage.setItem(key, JSON.stringify(rows.slice(0,150)));
  }
  function isSaved(movie) {
    try { return JSON.parse(localStorage.getItem('deeprowss_watch_later') || '[]').some(x => String(x.tmdbId || x.url) === String(idOf(movie) || movie.url)); } catch (_) { return false; }
  }
  function playMovie(movie) {
    const raw = movie.url || movie.embedUrl || movie.streamUrl || (idOf(movie) ? embedBase + '/' + (isTv(movie) ? 'tv' : 'movie') + '/' + idOf(movie) : '');
    const url = safeUrl(raw); if (!url) { alert('This title has no playable URL.'); return; }
    saveList('deeprowss_watch_history', movie); window.deeprowssPlay(url, 'embed', title(movie));
  }
  function openTrailer(key, name) { window.deeprowssPlay('https://www.youtube.com/embed/' + encodeURIComponent(key) + '?autoplay=1&rel=0', 'embed', name + ' · Trailer'); }
  async function resolveTmdb(movie) {
    let id = idOf(movie), tv = isTv(movie);
    if (id) return {id,tv};
    const raw = movie.url || '';
    const match = raw.match(/\/(movie|tv)\/(tt\d+|\d+)/i) || raw.match(/[?&]imdb=(tt\d+)/i);
    if (match) {
      tv = match[1] ? match[1].toLowerCase() === 'tv' : tv; id = match[2] || match[1];
      if (/^\d+$/.test(String(id))) return {id:Number(id),tv};
      const found = await tmdb('/find/' + id,{external_source:'imdb_id'});
      const row = (tv ? found.tv_results : found.movie_results)?.[0] || (found.movie_results || found.tv_results || [])[0];
      if (row) return {id:row.id,tv:!!(found.tv_results || []).some(x => x.id === row.id)};
    }
    const name = title(movie).replace(/\s*\(\d{4}\)\s*$/,'');
    const d = await tmdb(tv ? '/search/tv' : '/search/movie',{query:name});
    const norm = s => String(s || '').toLowerCase().replace(/[^a-z0-9]/g,'');
    const wanted = norm(name);
    const row = (d?.results || []).find(x => [x.title,x.name,x.original_title,x.original_name].some(n => norm(n) === wanted));
    return row ? {id:row.id,tv} : null;
  }
  async function openDetails(movie) {
    activeMovie = movie; $('movieDetails').classList.add('open');
    $('detailTitle').textContent = title(movie); $('detailPoster').src = image(movie);
    $('detailBackdrop').hidden = true; $('detailOverview').textContent = movie.overview || 'Loading movie overview…';
    $('detailMeta').innerHTML = ''; $('detailCredits').textContent = 'Loading cast and crew…';
    $('detailTrailerWrap').hidden = true; $('detailTrailer').src = 'about:blank'; $('detailSimilar').innerHTML = '';
    $('detailSave').textContent = isSaved(movie) ? '✓ Saved' : '＋ Watch later';
    $('detailAlt').hidden = true;
    const dl = movie.downloadUrl || movie.download_url || '';
    const downloadUrl = dl ? safeUrl(dl) : '';
    $('detailDownload').hidden = !downloadUrl;
    $('detailDownload').onclick = () => { if (downloadUrl) window.open(downloadUrl,'_blank','noopener'); };
    $('detailPlay').onclick = () => { $('movieDetails').classList.remove('open'); playMovie(movie); };
    $('detailSave').onclick = () => {
      let rows = []; try { rows = JSON.parse(localStorage.getItem('deeprowss_watch_later') || '[]'); } catch (_) {}
      const key = String(idOf(movie) || movie.url);
      if (rows.some(x => String(x.tmdbId || x.url) === key)) {
        rows = rows.filter(x => String(x.tmdbId || x.url) !== key);
        localStorage.setItem('deeprowss_watch_later',JSON.stringify(rows));
        $('detailSave').textContent = '＋ Watch later';
      } else {
        saveList('deeprowss_watch_later',movie);
        $('detailSave').textContent = '✓ Saved';
      }
    };
    try {
      if (!apiKey) throw Error('TMDB is disabled');
      const target = await resolveTmdb(movie); if (!target) throw Error('No TMDB match found');
      const type = target.tv ? 'tv' : 'movie';
      const d = await tmdb('/' + type + '/' + target.id,{append_to_response:'credits,videos,similar'});
      if (activeMovie !== movie) return;
      if (d.poster_path) $('detailPoster').src = IMG + 'w500' + d.poster_path;
      if (d.backdrop_path) { $('detailBackdrop').src = IMG + 'w1280' + d.backdrop_path; $('detailBackdrop').hidden = false; }
      const year = (d.release_date || d.first_air_date || '').slice(0,4);
      const meta = [target.tv ? 'Series' : 'Movie',year,d.vote_average ? '★ ' + Number(d.vote_average).toFixed(1) + '/10' : '',d.runtime ? d.runtime + ' min' : (d.episode_run_time?.[0] ? d.episode_run_time[0] + ' min' : ''),(d.genres || []).map(g => g.name).join(' · ')];
      $('detailMeta').innerHTML = meta.filter(Boolean).map(x => '<span>' + esc(x) + '</span>').join('');
      $('detailOverview').textContent = d.overview || 'No overview available.';
      const cast = (d.credits?.cast || []).slice(0,8).map(x => x.name + ' as ' + x.character).join(' · ');
      const crew = (d.credits?.crew || []).filter(x => ['Director','Creator'].includes(x.job)).slice(0,3).map(x => x.name).join(', ');
      $('detailCredits').textContent = [crew ? 'Director / Creator: ' + crew : '',cast ? 'Cast: ' + cast : ''].filter(Boolean).join('\n');
      const vids = (d.videos?.results || []).filter(v => v.site === 'YouTube' && ['Trailer','Teaser'].includes(v.type) && v.key).sort((a,b) => (b.official === true) - (a.official === true) || (b.published_at || '').localeCompare(a.published_at || ''));
      if (vids[0]) { $('detailTrailerWrap').hidden = false; $('detailTrailer').src = 'https://www.youtube.com/embed/' + encodeURIComponent(vids[0].key); }
      (d.similar?.results || []).map(x => fromTmdb(x,type)).filter(Boolean).slice(0,12).forEach(x => $('detailSimilar').append(movieCard(x)));
      if (!movie.tmdbId) { movie.tmdbId = target.id; movie.type = type; movie.url = movie.url || embedBase + '/' + type + '/' + target.id; movie.downloadUrl = movie.downloadUrl || downloadBase + '/' + type + '/' + target.id; }
      $('detailAlt').hidden = false;
      $('detailAlt').onclick = () => { $('movieDetails').classList.remove('open'); const alt = altEmbedBase + '/' + type + '/' + target.id + (target.tv ? '/1/1' : ''); window.deeprowssPlay(alt,'embed',title(movie) + ' · Alternate Player'); };
    } catch (e) {
      $('detailCredits').textContent = 'Movie information unavailable: ' + e.message;
      $('detailOverview').textContent = movie.overview || 'This title can still be played using its configured player.';
    }
  }
  function showPage(page) {
    document.querySelectorAll('[data-libpage]').forEach(b => b.classList.toggle('active',b.dataset.libpage === page));
    document.querySelectorAll('.libpage').forEach(p => p.classList.toggle('active',p.id === (page === 'movies' ? 'libMovies' : 'libChannels')));
    $('libSearch').placeholder = page === 'channels' ? 'Search live channels…' : 'Search movies, series or genres…';
    if (page === 'cast') { window.deeprowssShowJoin(); return; }
    window.deeprowssShowLibrary();
  }
  document.querySelectorAll('[data-libpage]').forEach(b => b.onclick = () => showPage(b.dataset.libpage));
  $('backBrowse').onclick = () => showPage('movies');
  $('detailClose').onclick = () => { $('movieDetails').classList.remove('open'); $('detailTrailer').src = 'about:blank'; };
  $('movieDetails').addEventListener('click',e => { if (e.target === $('movieDetails')) $('detailClose').click(); });
  $('libBrowse').onclick = () => $('libMovieGrid').scrollIntoView({behavior:'smooth'});
  $('libSearch').oninput = e => {
    query = e.target.value.trim(); clearTimeout(searchTimer);
    if ($('libChannels').classList.contains('active')) { renderChannels(); return; }
    searchTimer = setTimeout(renderMovies,350);
  };
  function channelCategoryName(c) { const x = String(c.category || 'General').replace(/[_-]/g,' '); return x.charAt(0).toUpperCase() + x.slice(1); }
  async function loadChannels() {
    let own = [], extra = [];
    try { const d = await getJson(CHANNELS_URL); own = Array.isArray(d) ? d : d.channels || []; } catch (_) {}
    try {
      const d = await getJson(NEXUS_URL), rows = Array.isArray(d) ? d : d.channels || [];
      extra = rows.filter(c => c && c.name && Array.isArray(c.streams)).map(c => {
        const streams = c.streams.filter(s => s?.url && (!s.health || s.health.status === 'online')).sort((a,b) => (b.rank || 0) - (a.rank || 0));
        const s = streams[0], backup = streams[1]; return s ? {name:c.name,url:s.url,altUrl:backup?.url || '',category:(c.categories || [])[0] || 'other',logo:c.logo,country:c.country,quality:s.quality || c.best_quality} : null;
      }).filter(Boolean);
    } catch (_) {}
    const map = new Map();
    [...own,...extra].forEach(c => { if (!c?.name || !c?.url) return; const key = c.name.toLowerCase(); if (!map.has(key)) map.set(key,{...c,url:safeUrl(c.url,'https://footbolive.online/')}); });
    channels = [...map.values()].filter(c => c.url); renderChannels();
  }
  function channelKey(c){return String(c.name||'').toLowerCase()+'|'+String(c.url||'');}
  function isChannelSaved(c){try{return (JSON.parse(localStorage.getItem('deeprowss_channel_favorites')||'[]')).includes(channelKey(c));}catch(_){return false;}}
  function toggleChannelSaved(c){let rows=[];try{rows=JSON.parse(localStorage.getItem('deeprowss_channel_favorites')||'[]');}catch(_){}const k=channelKey(c);rows=rows.includes(k)?rows.filter(x=>x!==k):[...rows,k];localStorage.setItem('deeprowss_channel_favorites',JSON.stringify(rows));}
  let expandedChannelCategory = null;
  const CHANNEL_PREVIEW_LIMIT = 6;
  function renderChannels() {
    const q = query.toLowerCase();
    const list = channels.filter(c => (channelCategory === 'All' || channelCategoryName(c) === channelCategory) && (channelCountry === 'All' || String(c.country || '').toUpperCase() === channelCountry) && (!favoritesOnly || isChannelSaved(c)) && (!q || (c.name + ' ' + channelCategoryName(c) + ' ' + (c.country || '')).toLowerCase().includes(q)));
    $('channelCount').textContent = list.length + ' channels available';
    const categories = ['All',...new Set(channels.map(channelCategoryName).sort())];
    $('channelFilters').innerHTML = '';
    const fav = document.createElement('button');
    fav.className = 'libchip' + (favoritesOnly ? ' active' : '');
    fav.textContent = '★ Favorites';
    fav.onclick = () => { favoritesOnly = !favoritesOnly; channelCategory = 'All'; expandedChannelCategory = null; renderChannels(); };
    $('channelFilters').append(fav);
    categories.forEach(cat => {
      const b = document.createElement('button');
      b.className = 'libchip' + ((expandedChannelCategory === cat || (!expandedChannelCategory && channelCategory === cat)) ? ' active' : '');
      b.textContent = cat;
      b.onclick = () => { channelCategory = cat; expandedChannelCategory = cat === 'All' ? null : cat; renderChannels(); };
      $('channelFilters').append(b);
    });
    const countries = [...new Set(channels.map(c => String(c.country || '').toUpperCase()).filter(Boolean))].sort();
    if (countries.length) {
      const sep = document.createElement('span'); sep.className = 'libmuted'; sep.textContent = 'COUNTRY'; sep.style.alignSelf = 'center'; $('channelFilters').append(sep);
      ['All',...countries].forEach(country => {
        const b = document.createElement('button'); b.className = 'libchip' + (channelCountry === country ? ' active' : ''); b.textContent = country;
        b.onclick = () => { channelCountry = country; expandedChannelCategory = null; channelCategory = 'All'; renderChannels(); };
        $('channelFilters').append(b);
      });
    }
    const groups = $('channelGroups'); groups.innerHTML = '';
    const buckets = new Map();
    list.forEach(c => { const cat = channelCategoryName(c); if (!buckets.has(cat)) buckets.set(cat, []); buckets.get(cat).push(c); });
    const icons = {sports:'⚽',sport:'⚽',news:'▤',movies:'▣',movie:'▣',entertainment:'🎭',music:'♫',kids:'🧸',documentary:'▧',religion:'✦',general:'▦'};
    const categoryIcon = cat => {
      const key = String(cat).toLowerCase();
      const found = Object.keys(icons).find(k => key.includes(k));
      return icons[found] || '▦';
    };
    function makeChannel(c, cat) {
      const wrap = document.createElement('div'); wrap.className = 'libchannel-wrap';
      const b = document.createElement('button'); b.className = 'libchannel';
      const logo = c.logo ? safeUrl(c.logo) : '';
      b.innerHTML = (logo ? '<img loading="lazy" src="' + esc(logo) + '" alt="">' : '<span class="libchannel-fallback">' + categoryIcon(cat) + '</span>') +
        '<span class="libchannel-name"><b>' + esc(c.name) + '</b></span>';
      b.title = c.name;
      b.onclick = () => { const url=safeUrl(c.url),kind=/\.m3u8(\?|$)/i.test(url)?'hls':/\.mpd(\?|$)/i.test(url)?'dash':/\.(mp4|webm)(\?|$)/i.test(url)?'video':'embed'; window.deeprowssPlay(url,kind,c.name); };
      const star=document.createElement('button'); star.type='button'; star.className='libchannel-star'; star.title='Add or remove favourite'; star.textContent=isChannelSaved(c)?'★':'☆';
      star.onclick=()=>{toggleChannelSaved(c);star.textContent=isChannelSaved(c)?'★':'☆';};
      wrap.append(b,star);
      if(c.altUrl) {
        const alt=document.createElement('button'); alt.type='button'; alt.className='libchannel-alt'; alt.title='Play backup stream'; alt.textContent='↻';
        alt.onclick=()=>{const u=safeUrl(c.altUrl);if(u)window.deeprowssPlay(u,/\.m3u8(\?|$)/i.test(u)?'hls':/\.mpd(\?|$)/i.test(u)?'dash':/\.(mp4|webm)(\?|$)/i.test(u)?'video':'embed',c.name+' · Backup');};
        wrap.append(alt);
      }
      return wrap;
    }
    const onlyCategory = !!expandedChannelCategory;
    for (const [cat,items] of buckets) {
      const expanded = onlyCategory && expandedChannelCategory === cat;
      const section=document.createElement('section'); section.className='libchannel-row' + (expanded ? ' is-expanded' : '');
      const head=document.createElement('button'); head.type='button'; head.className='libchannel-section-head';
      head.innerHTML='<span class="libchannel-category-icon">'+categoryIcon(cat)+'</span><strong>'+esc(cat)+'</strong><span class="libchannel-category-count">'+items.length+'</span><span class="libchannel-chevron">›</span>';
      head.onclick=()=>{channelCategory=cat;expandedChannelCategory=cat;renderChannels();groups.scrollIntoView({behavior:'smooth',block:'start'});};
      if (onlyCategory && !expanded) continue;
      section.append(head);
      const shown = expanded ? items : items.slice(0, CHANNEL_PREVIEW_LIMIT);
      const grid=document.createElement('div'); grid.className='libchannel-grid' + (expanded ? ' is-expanded' : ' is-preview');
      shown.forEach(c=>grid.append(makeChannel(c,cat))); section.append(grid);
      if(!expanded && items.length>CHANNEL_PREVIEW_LIMIT) {
        const more=document.createElement('button'); more.type='button'; more.className='libchannel-more';
        more.textContent='View all '+items.length+' channels  →';
        more.onclick=()=>{channelCategory=cat;expandedChannelCategory=cat;renderChannels();groups.scrollIntoView({behavior:'smooth',block:'start'});};
        section.append(more);
      }
      groups.append(section);
    }
    if (!list.length) groups.innerHTML = '<div class="libempty">No channels found.</div>';
    if (onlyCategory && !buckets.size) {
      const back=document.createElement('button'); back.type='button'; back.className='libchannel-back'; back.textContent='← All channel categories';
      back.onclick=()=>{expandedChannelCategory=null;channelCategory='All';renderChannels();}; groups.prepend(back);
    } else if (onlyCategory) {
      const back=document.createElement('button'); back.type='button'; back.className='libchannel-back'; back.textContent='← All channel categories';
      back.onclick=()=>{expandedChannelCategory=null;channelCategory='All';renderChannels();}; groups.prepend(back);
    }
  }
  $('refreshChannels').onclick = loadChannels;
  $('libSearch').addEventListener('keydown',e => { if (e.key === 'Escape') { $('libSearch').value = ''; query = ''; renderMovies(); renderChannels(); } });
  async function refreshAll() { await loadConfig(); await Promise.all([loadMovies(),loadChannels()]); await loadTrends(); renderMovies(); }

  // The mobile app's saved-title and history shortcuts are available here too.
  const quickLists = document.createElement('div');
  quickLists.className = 'detail-actions';
  quickLists.style.margin = '0 0 18px';
  quickLists.innerHTML = '<button type="button" class="secondary" id="showWatchLater">▣ Watch Later</button><button type="button" class="secondary" id="showWatchHistory">◷ Watch History</button>';
  $('libHero').after(quickLists);
  const savedPanel = document.createElement('section');
  savedPanel.className = 'libsection';
  savedPanel.id = 'savedMoviesPanel';
  savedPanel.hidden = true;
  savedPanel.innerHTML = '<div class="libsection-head"><h3 id="savedMoviesTitle">Your Library</h3><button id="closeSavedMovies" class="secondary" type="button">Close</button></div><div class="libgrid" id="savedMoviesGrid"></div>';
  quickLists.after(savedPanel);
  function showSavedList(key,label) {
    let rows = []; try { rows = JSON.parse(localStorage.getItem(key) || '[]'); } catch (_) {}
    $('savedMoviesTitle').textContent = label;
    $('savedMoviesGrid').innerHTML = '';
    if (!rows.length) $('savedMoviesGrid').innerHTML = '<div class="libempty">Nothing here yet.</div>';
    else rows.forEach(m => {
      const item = movieCard(m);
      const remove = document.createElement('button');
      remove.type = 'button'; remove.className = 'secondary'; remove.textContent = 'Remove';
      remove.style.cssText = 'width:100%;margin-top:6px;padding:7px;font-size:11px';
      remove.onclick = event => {
        event.stopPropagation();
        const next = rows.filter(x => String(x.tmdbId || x.url) !== String(idOf(m) || m.url));
        localStorage.setItem(key,JSON.stringify(next));
        showSavedList(key,label);
      };
      item.append(remove); $('savedMoviesGrid').append(item);
    });
    savedPanel.hidden = false;
    savedPanel.scrollIntoView({behavior:'smooth',block:'start'});
  }
  $('showWatchLater').onclick = () => showSavedList('deeprowss_watch_later','Watch Later');
  $('showWatchHistory').onclick = () => showSavedList('deeprowss_watch_history','Watch History');
  $('closeSavedMovies').onclick = () => { savedPanel.hidden = true; };

  window.deeprowssShowLibrary();
  refreshAll();
  remoteConfigTimer = setInterval(async () => { await loadConfig(); await loadTrends(); }, 5 * 60 * 1000);
  setInterval(loadChannels, 30 * 60 * 1000);
  setInterval(loadMovies, 10 * 60 * 1000);
})();
