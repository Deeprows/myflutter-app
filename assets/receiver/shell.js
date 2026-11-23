/* Deeprowss home shell: Kodi-style clock + rotating fanart, the Windows Downloads panel
   and Esc / Backspace "back" handling. Works on the website and inside the Windows app. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const desktop = window.deeprowssDesktop || null;
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  /* ---------- clock ---------- */
  function tick() {
    const d = new Date();
    if ($('clockTime')) $('clockTime').textContent = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    if ($('clockDate')) $('clockDate').textContent = d.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' });
  }
  tick(); setInterval(tick, 15000);

  /* ---------- fanart carousel (TMDB trending backdrops sent by library.js) ----------
     Animated: Ken-Burns pan (alternating direction), cross-fade, staggered text, auto-advance progress dots.
     Clickable: tap the backdrop, the title block or "More info" to open that title; dots jump to a slide;
     swipe left/right on touch screens; hover/focus pauses auto-advance. */
  const SLIDE_MS = 11000;
  let items = [], idx = 0, layer = 0, timer = 0, paused = false, shownAt = 0, token = 0;
  const landing = $('landing');
  function ensureControls() {
    const f = $('homeFeature'); if (!f || f.querySelector('.fcta')) return;
    const row = document.createElement('div'); row.className = 'fcta';
    row.innerHTML = '<button type="button" class="fmore" id="featMore"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/></svg>More info</button><div class="fdots" id="featDots" role="tablist" aria-label="Trending titles"></div>';
    f.appendChild(row);
    $('featMore').addEventListener('click', e => { e.stopPropagation(); openCurrent(); });
    $('featDots').addEventListener('click', e => {
      const b = e.target.closest('.fdot'); if (!b) return; e.stopPropagation();
      goTo(Number(b.dataset.i), true);
    });
  }
  function renderDots() {
    const box = $('featDots'); if (!box) return;
    if (box.children.length !== items.length) {
      box.innerHTML = items.map((it, i) => '<button type="button" class="fdot" role="tab" data-i="' + i + '" aria-label="' + esc(it.title) + '"></button>').join('');
    }
    [...box.children].forEach((d, i) => {
      const on = i === idx; if (!on) d.classList.remove('on'); d.setAttribute('aria-selected', on ? 'true' : 'false');
      d.classList.remove('paused');
      if (on) { d.style.setProperty('--dur', SLIDE_MS + 'ms'); d.classList.remove('on'); void d.offsetWidth; d.classList.add('on'); }
    });
  }
  function openCurrent() {
    const it = items[idx]; if (!it || !it.movie) return;
    if (typeof window.deeprowssOpenDetails === 'function') window.deeprowssOpenDetails(it.movie);
  }
  function show(i, dir) {
    const it = items[i]; if (!it) return;
    const my = ++token;
    const layers = document.querySelectorAll('#fanart .fa'); if (layers.length < 2) return;
    const img = new Image();
    img.onload = () => {
      if (my !== token) return;
      const next = layers[(layer + 1) % 2], prev = layers[layer];
      next.style.backgroundImage = 'url("' + it.backdrop + '")';
      next.classList.toggle('rev', i % 2 === 1);
      next.classList.toggle('from-left', dir < 0);
      next.classList.remove('on'); void next.offsetWidth; next.classList.add('on');
      prev.classList.remove('on'); layer = (layer + 1) % 2;
      const f = $('homeFeature'); if (!f) return;
      ensureControls();
      f.hidden = false; f.classList.remove('anim'); void f.offsetWidth; f.classList.add('anim');
      f.classList.toggle('clickable', !!it.movie);
      $('featTitle').textContent = it.title;
      $('featMeta').innerHTML = [it.tv ? 'Series' : 'Movie', it.year, it.rating ? '<span class="st">★ ' + it.rating.toFixed(1) + '</span>' : ''].filter(Boolean)
        .map(x => x.startsWith('<') ? x : '<span>' + esc(x) + '</span>').join('');
      $('featText').textContent = it.overview || '';
      landing.classList.toggle('hero-click', !!it.movie);
      renderDots(); shownAt = Date.now(); schedule();
    };
    img.src = it.backdrop;
  }
  function goTo(i, user) {
    if (!items.length) return;
    const n = (i + items.length) % items.length;
    const dir = i < idx && !(idx === 0 && n === items.length - 1 && !user) ? -1 : 1;
    idx = n; show(idx, user ? dir : 1);
  }
  function schedule() {
    clearTimeout(timer);
    if (paused || items.length < 2) { const d = document.querySelector('.fdot.on'); if (d) d.classList.toggle('paused', paused); return; }
    const d = document.querySelector('.fdot.on'); if (d) d.classList.remove('paused');
    timer = setTimeout(() => { if (document.hidden || document.body.dataset.view !== 'landing') { schedule(); return; } goTo(idx + 1, false); }, SLIDE_MS);
  }
  function setPaused(p) {
    if (p === paused) return; paused = p;
    if (p) { clearTimeout(timer); const d = document.querySelector('.fdot.on'); if (d) d.classList.add('paused'); }
    else { renderDots(); schedule(); } // restart the full interval after a pause
  }
  function setItems(list) {
    if (!Array.isArray(list) || !list.length) return;
    items = list; idx = 0; show(0, 1);
  }
  window.addEventListener('deeprowss:feature', e => setItems(e.detail));
  if (window.deeprowssFeatureList) setItems(window.deeprowssFeatureList);

  // click on the backdrop (the landing itself) or on the title block opens the current title
  landing.addEventListener('click', e => {
    if (e.target === landing || e.target.closest('#homeFeature') ) {
      if (e.target.closest('.fdots,.fmore')) return;
      openCurrent();
    }
  });
  const feat = $('homeFeature');
  if (feat) {
    feat.setAttribute('tabindex', '0'); feat.setAttribute('role', 'button');
    feat.addEventListener('keydown', e => { if ((e.key === 'Enter' || e.key === ' ') && e.target === feat) { e.preventDefault(); openCurrent(); } });
    ['mouseenter', 'focusin'].forEach(t => feat.addEventListener(t, () => setPaused(true)));
    ['mouseleave', 'focusout'].forEach(t => feat.addEventListener(t, () => setPaused(false)));
  }
  // swipe left / right on touch screens
  let sx = 0, sy = 0, st = 0;
  landing.addEventListener('touchstart', e => { if (e.touches.length !== 1) return; sx = e.touches[0].clientX; sy = e.touches[0].clientY; st = Date.now(); }, { passive: true });
  landing.addEventListener('touchend', e => {
    if (!st || !e.changedTouches.length) return;
    const dx = e.changedTouches[0].clientX - sx, dy = e.changedTouches[0].clientY - sy; const quick = Date.now() - st < 700; st = 0;
    if (quick && Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 1.6) goTo(idx + (dx < 0 ? 1 : -1), true);
  }, { passive: true });
  // the details sheet is open over the home screen: pause so the slide doesn't change underneath it
  new MutationObserver(() => setPaused(!!document.querySelector('.sheet.open'))).observe(document.body, { subtree: true, attributes: true, attributeFilter: ['class'] });

  /* ---------- Downloads panel (Windows app) ---------- */
  const fmt = n => { n = Number(n) || 0; const u = ['B', 'KB', 'MB', 'GB']; let i = 0; while (n >= 1024 && i < 3) { n /= 1024; i++; } return n.toFixed(i ? 1 : 0) + ' ' + u[i]; };
  function renderDownloads(list) {
    const active = list.filter(d => d.state === 'progressing').length;
    const badge = $('dlBadge'); if (badge) { badge.hidden = !active; badge.textContent = active; }
    if (!$('dlSheet') || !$('dlSheet').classList.contains('open')) return;
    const box = $('dlList');
    if (!list.length) { box.innerHTML = '<div class="dl-empty">No downloads yet.<br>Open a movie and press Download.</div>'; return; }
    box.innerHTML = list.map(d => {
      const pct = d.total ? Math.min(100, Math.round(d.received / d.total * 100)) : 0;
      let status = d.state === 'progressing' ? (d.paused ? 'Paused' : 'Downloading') + ' · ' + fmt(d.received) + (d.total ? ' of ' + fmt(d.total) : '') : d.state === 'completed' ? 'Completed · ' + fmt(d.total || d.received) : d.state === 'cancelled' ? 'Cancelled' : 'Failed';
      const btn = (a, t) => '<button type="button" class="secondary" data-a="' + a + '" data-id="' + esc(d.id) + '">' + t + '</button>';
      let acts = '';
      if (d.state === 'progressing') acts = btn(d.paused ? 'resume' : 'pause', d.paused ? 'Resume' : 'Pause') + btn('cancel', 'Cancel');
      else if (d.state === 'completed') acts = btn('open', 'Open') + btn('folder', 'Show in folder') + btn('remove', 'Remove');
      else acts = btn('remove', 'Remove');
      return '<div class="dl-row"><b>' + esc(d.name) + '</b>' + (d.state === 'progressing' ? '<div class="dl-bar"><i style="width:' + pct + '%"></i></div>' : '') +
        '<small>' + esc(status) + '</small><div class="dl-act">' + acts + '</div></div>';
    }).join('');
  }
  async function openDownloads() {
    const sheet = $('dlSheet'); sheet.classList.add('open');
    try { const info = await desktop.downloads.list(); $('dlPath').textContent = 'Saved to: ' + (info.folder || ''); renderDownloads(info.items || []); } catch (_) {}
  }
  if (desktop && desktop.downloads) {
    const b = $('btnDownloads'); if (b) { b.hidden = false; b.onclick = openDownloads; }
    $('dlClose').onclick = () => $('dlSheet').classList.remove('open');
    $('dlSheet').addEventListener('click', e => { if (e.target === $('dlSheet')) $('dlSheet').classList.remove('open'); });
    $('dlList').addEventListener('click', e => {
      const t = e.target.closest('[data-a]'); if (!t) return;
      desktop.downloads.action(t.dataset.id, t.dataset.a);
    });
    desktop.onDownloads(list => renderDownloads(list));
    desktop.downloads.list().then(i => renderDownloads(i.items || [])).catch(() => {});
  }

  /* ---------- back key ---------- */
  document.addEventListener('keydown', e => {
    if (e.key !== 'Escape' && e.key !== 'Backspace') return;
    if (/input|textarea|select/i.test(e.target.tagName)) return;
    if ($('dlSheet') && $('dlSheet').classList.contains('open')) { $('dlSheet').classList.remove('open'); e.preventDefault(); return; }
    if (document.querySelector('.sheet.open') || $('playerPanel').style.display === 'block') return;
    if (window.deeprowssHandleBack && window.deeprowssHandleBack()) e.preventDefault();
  });
})();
