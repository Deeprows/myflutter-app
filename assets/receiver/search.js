/* Deeprowss home search bar.
   One box on the home screen that searches movies & series, TV channels and
   live / upcoming football matches. Works in the Windows app, on Android TV,
   LG / Samsung TVs and on the website (deeprowss.pages.dev).
   It talks to the other receiver scripts through small bridges:
     window.deeprowssMovies, window.deeprowssTvSearch, window.deeprowssFixtureSearch */
(() => {
  'use strict';
  const land = document.getElementById('landing');
  if (!land || document.getElementById('dwSearch')) return;

  const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const safeImg = u => /^https?:\/\//i.test(String(u || '')) ? String(u) : '';

  const css = document.createElement('style');
  css.textContent = `
  /* The dock spans the bottom row; place() (below) measures the free gap between the
     keyboard hints on the left and the exit / settings / Subscribe cluster on the right
     and centres the field inside it, so it never overlaps either side. */
  .dw-search{position:absolute;z-index:9;left:0;right:0;top:auto;bottom:14px;height:38px;pointer-events:none;--dws-left:50%;--dws-w:440px}
  .dws-field{pointer-events:auto;position:absolute;left:var(--dws-left);top:0;transform:translateX(-50%);display:flex;align-items:center;gap:8px;width:var(--dws-w);max-width:440px;height:38px;padding:0 10px 0 12px;border-radius:999px;border:1px solid rgb(var(--n5,70 85 105));background:rgba(8,12,18,.88);backdrop-filter:blur(10px);color:#e8eef5;transition:border-color .15s,box-shadow .15s}
  .dws-field:focus-within{border-color:rgb(var(--ar,29 180 234));box-shadow:0 0 0 3px rgba(var(--ar,29,180,234),.25)}
  .dws-field svg{flex:none;width:18px;height:18px;fill:none;stroke:#9fb0c3;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
  .dws-field input{flex:1;min-width:0;height:100%;padding:0;border:0;outline:0;background:transparent;color:inherit;font:600 14px/1 inherit;font-family:inherit}
  .dws-field input::placeholder{color:#8a9bb0;font-weight:500}
  .dws-x{flex:none;width:24px;height:24px;min-height:24px;padding:0;border:0;border-radius:50%;background:#ffffff1f;color:#fff;font-size:12px;cursor:pointer}
  .dws-panel{pointer-events:auto;position:absolute;left:50%;bottom:48px;transform:translateX(-50%);width:min(560px,92vw);max-height:min(62vh,440px);overflow:auto;border-radius:16px;border:1px solid #34465b;background:#0b121bf2;backdrop-filter:blur(14px);box-shadow:0 -14px 40px #000a;padding:6px}
  .dws-panel[hidden]{display:none}
  .dws-h{margin:8px 10px 4px;font-size:11px;font-weight:800;letter-spacing:.12em;color:#7f90a5;text-transform:uppercase}
  .dws-item{display:flex;align-items:center;gap:12px;width:100%;min-height:52px;padding:6px 10px;border:1px solid transparent;border-radius:12px;background:transparent;color:#e8eef5;text-align:left;cursor:pointer;font:inherit}
  .dws-item:hover,.dws-item:focus{outline:0;background:#ffffff12;border-color:rgb(var(--ar,29 180 234))}
  .dws-th{flex:none;display:grid;place-items:center;width:36px;height:36px;border-radius:9px;background:#ffffff14;overflow:hidden;font-size:17px}
  .dws-th.p{width:32px;height:46px}
  .dws-th img{width:100%;height:100%;object-fit:cover}
  .dws-th.l img{object-fit:contain;padding:3px;background:#fff}
  .dws-tx{flex:1;min-width:0}
  .dws-tx b{display:block;font-size:14px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .dws-tx small{display:block;margin-top:2px;font-size:12px;color:#8fa0b4;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .dws-tag{flex:none;padding:3px 9px;border-radius:999px;font-size:11px;font-weight:800;background:#ffffff1a;color:#cfe0f1}
  .dws-tag.live{background:#e5243b;color:#fff}
  .dws-empty{padding:18px 12px;text-align:center;color:#8fa0b4;font-size:13px}
  `;
  document.head.appendChild(css);

  const box = document.createElement('div');
  box.id = 'dwSearch'; box.className = 'dw-search';
  box.innerHTML =
    '<div class="dws-field" role="search">' +
      '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>' +
      '<input id="dwSearchInput" type="text" inputmode="search" enterkeyhint="search" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="Search movies, TV, matches" aria-label="Search movies, TV channels and live matches" aria-controls="dwSearchPanel">' +
      '<button class="dws-x" id="dwSearchClear" type="button" aria-label="Clear search" hidden>✕</button>' +
    '</div>' +
    '<div class="dws-panel" id="dwSearchPanel" role="listbox" aria-label="Search results" hidden></div>';
  land.appendChild(box);

  const input = document.getElementById('dwSearchInput');
  const clearBtn = document.getElementById('dwSearchClear');
  const panel = document.getElementById('dwSearchPanel');

  let token = 0, timer = 0, flat = [];
  const state = { fx: null, tv: null, mv: null };   // null = still searching

  const whenText = start => {
    const d = new Date(start), now = new Date();
    const time = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    const same = d.toDateString() === now.toDateString();
    return same ? 'Today ' + time : d.toLocaleDateString([], { weekday: 'short', day: 'numeric', month: 'short' }) + ' ' + time;
  };

  function row(kind, i, thumb, title, sub, tag, live) {
    return '<button type="button" class="dws-item" role="option" data-kind="' + kind + '" data-i="' + i + '">' + thumb +
      '<span class="dws-tx"><b>' + esc(title) + '</b><small>' + esc(sub) + '</small></span>' +
      (tag ? '<span class="dws-tag' + (live ? ' live' : '') + '">' + esc(tag) + '</span>' : '') + '</button>';
  }

  function render() {
    flat = [];
    let html = '';
    const add = (label, list, make) => {
      if (!list || !list.length) return;
      html += '<div class="dws-h">' + label + '</div>';
      list.forEach(it => { html += make(it, flat.length); flat.push(it); });
    };
    add('Live matches', state.fx && state.fx.slice(0, 5).map(x => Object.assign({ kind: 'fx' }, x)), (x, i) => {
      const logo = safeImg(x.homeLogo);
      const th = '<span class="dws-th l">' + (logo ? '<img alt="" src="' + esc(logo) + '" onerror="this.remove()">' : '⚽') + '</span>';
      return row('fx', i, th, x.home + ' vs ' + x.away, x.league + ' · ' + whenText(x.start), x.live ? 'LIVE' : 'Soon', x.live);
    });
    add('TV channels', state.tv && state.tv.slice(0, 8).map(x => Object.assign({ kind: 'tv' }, x)), (x, i) => {
      const logo = safeImg(x.logo);
      const th = '<span class="dws-th l">' + (logo ? '<img alt="" src="' + esc(logo) + '" onerror="this.remove()">' : '📺') + '</span>';
      return row('tv', i, th, x.name, [x.category, x.country].filter(Boolean).join(' · ') || 'Live channel', '▶ Watch');
    });
    add('Movies & series', state.mv && state.mv.slice(0, 8).map(x => Object.assign({ kind: 'mv' }, x)), (x, i) => {
      const img = safeImg(x.poster);
      const th = '<span class="dws-th p">' + (img ? '<img alt="" src="' + esc(img) + '" onerror="this.remove()">' : '🎬') + '</span>';
      const sub = [x.tv ? 'Series' : 'Movie', x.year, x.rating ? '★ ' + x.rating.toFixed(1) : ''].filter(Boolean).join(' · ');
      return row('mv', i, th, x.title, sub, 'Open');
    });
    const pending = state.fx === null || state.tv === null || state.mv === null;
    if (!flat.length) html = '<div class="dws-empty">' + (pending ? 'Searching…' : 'Nothing found. Try another name.') + '</div>';
    else if (pending) html += '<div class="dws-empty">Searching…</div>';
    panel.innerHTML = html;
    panel.hidden = false;
  }

  const bridge = (name, method, q) => {
    const b = window[name];
    if (!b || typeof b[method] !== 'function') return Promise.resolve([]);
    return Promise.resolve(b[method](q)).then(r => Array.isArray(r) ? r : []).catch(() => []);
  };

  function run(q) {
    const my = ++token;
    state.fx = state.tv = state.mv = null;
    render();
    const done = key => list => { if (my !== token) return; state[key] = list; render(); };
    bridge('deeprowssFixtureSearch', 'search', q).then(done('fx'));
    bridge('deeprowssTvSearch', 'search', q).then(done('tv'));
    bridge('deeprowssMovies', 'search', q).then(done('mv'));
  }

  function closePanel() { token++; panel.hidden = true; panel.innerHTML = ''; flat = []; }
  function reset() { input.value = ''; clearBtn.hidden = true; closePanel(); }

  function openItem(it) {
    if (!it) return;
    closePanel(); input.blur();
    if (it.kind === 'fx') { const b = window.deeprowssFixtureSearch; if (b) b.open(it); }
    else if (it.kind === 'tv') { const b = window.deeprowssTvSearch; if (b) b.play(it); }
    else if (it.kind === 'mv') { const b = window.deeprowssMovies; if (b) b.open(it); }
  }

  input.addEventListener('input', () => {
    const q = input.value.trim();
    clearBtn.hidden = !input.value;
    clearTimeout(timer);
    if (q.length < 2) { closePanel(); return; }
    timer = setTimeout(() => run(q), 280);
  });
  clearBtn.addEventListener('click', () => { reset(); input.focus(); });
  panel.addEventListener('click', e => {
    const b = e.target.closest('.dws-item'); if (!b) return;
    openItem(flat[Number(b.dataset.i)]);
  });

  /* Keyboard / TV remote: Down jumps from the box into the results, Up / Down move
     between them, Up from the first one returns to the box, Esc / Back steps out. */
  const items = () => [...panel.querySelectorAll('.dws-item')];
  box.addEventListener('keydown', e => {
    const k = e.key;
    if (e.target === input) {
      if (k === 'ArrowDown' || k === 'Enter') {
        const first = items()[0];
        if (first) { e.preventDefault(); e.stopPropagation(); first.focus(); first.scrollIntoView({ block: 'nearest' }); }
        else if (k === 'Enter' && input.value.trim().length >= 2) { e.preventDefault(); clearTimeout(timer); run(input.value.trim()); }
        return;
      }
      if (k === 'Escape' || k === 'GoBack' || k === 'BrowserBack') {
        e.preventDefault(); e.stopPropagation();
        if (input.value || !panel.hidden) reset(); else input.blur();
      }
      return;
    }
    if (!e.target.classList.contains('dws-item')) return;
    const list = items(), i = list.indexOf(e.target);
    if (k === 'ArrowDown') { e.preventDefault(); e.stopPropagation(); (list[i + 1] || list[i]).focus(); (list[i + 1] || list[i]).scrollIntoView({ block: 'nearest' }); }
    else if (k === 'ArrowUp') { e.preventDefault(); e.stopPropagation(); if (i > 0) { list[i - 1].focus(); list[i - 1].scrollIntoView({ block: 'nearest' }); } else input.focus(); }
    else if (k === 'ArrowLeft' || k === 'ArrowRight') { e.preventDefault(); e.stopPropagation(); }
    else if (k === 'Escape' || k === 'Backspace' || k === 'GoBack' || k === 'BrowserBack') { e.preventDefault(); e.stopPropagation(); input.focus(); }
  });


  /* "/" or Ctrl+K focuses the bar from anywhere on the home screen. */
  document.addEventListener('keydown', e => {
    if (!land.classList.contains('active')) return;
    if (/^(INPUT|TEXTAREA|SELECT)$/i.test(e.target.tagName)) return;
    if (document.querySelector('.sheet.open,.dw-shade.open,.dw-legal-shade.open')) return;
    if (e.key === '/' || ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k')) { e.preventDefault(); input.focus(); input.select(); }
  });


  /* Centre the search field in the free gap of the bottom row. */
  function place() {
    const W = land.clientWidth;
    // Phones / narrow screens keep the original centred dock.
    if (W <= 820) {
      box.style.setProperty('--dws-w', 'min(440px,' + Math.max(0, W - 32) + 'px)');
      box.style.setProperty('--dws-left', '50%');
      box.style.bottom = '';
      const h = land.querySelector('.home-hint'); if (h) h.style.visibility = '';
      return;
    }
    const hint = land.querySelector('.home-hint');
    const foot = land.querySelector('.receiver-footer');
    const lr = land.getBoundingClientRect();
    const hintShown = !!hint && getComputedStyle(hint).display !== 'none';
    let left = 24, right = W - 24;
    if (hintShown) {
      let hr = 0;
      hint.querySelectorAll('span').forEach(sp => { hr = Math.max(hr, sp.getBoundingClientRect().right - lr.left); });
      if (hr) left = hr;
    }
    if (foot && getComputedStyle(foot).display === 'flex') {
      let fl = Infinity;
      Array.from(foot.children).forEach(c => {
        if (c.hidden || getComputedStyle(c).display === 'none') return;
        const r = c.getBoundingClientRect();
        if (r.width) fl = Math.min(fl, r.left - lr.left);
      });
      if (isFinite(fl)) right = fl;
    }
    // Narrow windows: the keyboard hints are the least important item, so drop them
    // rather than letting the bar overlap them.
    if (hintShown && right - left < 260) {
      hint.style.visibility = 'hidden';
      left = 24;
    } else if (hint) {
      hint.style.visibility = '';
    }
    const gap = Math.max(0, right - left);
    const w = Math.max(160, Math.min(440, gap - 32));
    const centre = gap >= 192 ? left + gap / 2 : W / 2;
    box.style.setProperty('--dws-w', w + 'px');
    box.style.setProperty('--dws-left', Math.round(centre) + 'px');
    // Line the bar up with the middle of the footer row.
    if (foot) {
      const fr = foot.getBoundingClientRect();
      if (fr.height) {
        const mid = fr.top + fr.height / 2 - lr.top;
        box.style.bottom = Math.max(4, Math.round(land.clientHeight - mid - 19)) + 'px';
      }
    }
  }
  window.addEventListener('resize', place);
  window.addEventListener('load', place);
  [0, 300, 1200, 3000].forEach(t => setTimeout(place, t));   // the footer buttons are added late by other scripts
  if (window.ResizeObserver) { const ro = new ResizeObserver(place); ro.observe(land); const f = land.querySelector('.receiver-footer'); if (f) ro.observe(f); }
  if (window.MutationObserver) { const f = land.querySelector('.receiver-footer'); if (f) new MutationObserver(place).observe(f, { childList: true, subtree: true }); }
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(place);

  /* Click outside closes the list; leaving the home screen resets the bar. */
  document.addEventListener('click', e => { if (!box.contains(e.target)) { token++; panel.hidden = true; } });
  window.addEventListener('hashchange', () => { if (location.hash && location.hash !== '#landing') reset(); setTimeout(place, 80); });
})();
