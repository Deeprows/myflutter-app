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

  /* ---------- fanart (TMDB trending backdrops sent by library.js) ---------- */
  let items = [], idx = 0, layer = 0, timer = 0;
  function show(i) {
    const it = items[i]; if (!it) return;
    const layers = document.querySelectorAll('#fanart .fa'); if (layers.length < 2) return;
    const img = new Image();
    img.onload = () => {
      const next = layers[(layer + 1) % 2], prev = layers[layer];
      next.style.backgroundImage = 'url("' + it.backdrop + '")';
      next.classList.remove('on'); void next.offsetWidth; next.classList.add('on');
      prev.classList.remove('on'); layer = (layer + 1) % 2;
      const f = $('homeFeature'); if (!f) return;
      f.hidden = false; f.style.animation = 'none'; void f.offsetWidth; f.style.animation = '';
      $('featTitle').textContent = it.title;
      $('featMeta').innerHTML = [it.tv ? 'Series' : 'Movie', it.year, it.rating ? '<span class="st">★ ' + it.rating.toFixed(1) + '</span>' : ''].filter(Boolean)
        .map(x => x.startsWith('<') ? x : '<span>' + esc(x) + '</span>').join('');
      $('featText').textContent = it.overview || '';
    };
    img.src = it.backdrop;
  }
  function setItems(list) {
    if (!Array.isArray(list) || !list.length) return;
    items = list; idx = 0; show(0);
    clearInterval(timer); timer = setInterval(() => { if (document.hidden) return; idx = (idx + 1) % items.length; show(idx); }, 11000);
  }
  window.addEventListener('deeprowss:feature', e => setItems(e.detail));
  if (window.deeprowssFeatureList) setItems(window.deeprowssFeatureList);

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
