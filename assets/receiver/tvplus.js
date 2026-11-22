/* Deeprowss TV playback hardening + physical remote support.
   Sandbox blocks popups/top-level ad takeovers while retaining scripts, media and fullscreen. */
(() => {
  'use strict';
  const frame = () => document.getElementById('tvFrame');
  const original = window.deeprowssPlayTv;
  if (typeof original === 'function' && !original.__dwWrapped) {
    const wrapped = function(url, title, options) {
      const f = frame();
      if (f) {
        try {
          f.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-forms allow-presentation allow-orientation-lock');
          f.setAttribute('allow', 'autoplay; encrypted-media; fullscreen; picture-in-picture; accelerometer; gyroscope');
          f.setAttribute('referrerpolicy', 'origin');
        } catch (_) {}
      }
      return original.call(this, url, title, options);
    };
    wrapped.__dwWrapped = true;
    window.deeprowssPlayTv = wrapped;
  }
  function channel(delta) {
    const id = delta < 0 ? 'prevCh' : 'nextCh';
    const b = document.getElementById(id);
    if (b && !b.disabled && b.offsetParent !== null) b.click();
  }
  document.addEventListener('keydown', e => {
    const k = String(e.key || '').toLowerCase();
    const code = String(e.code || '').toLowerCase();
    const prev = ['channel_down','channelup_prev','mediatrackprevious'].includes(k) || code === 'mediatrackprevious' || k === 'channelup' && e.shiftKey;
    const next = ['channel_up','channelup','mediatracknext'].includes(k) || code === 'mediatracknext' || k === 'channelup';
    if (prev || next) {
      e.preventDefault(); e.stopImmediatePropagation();
      channel(prev ? -1 : 1);
      return;
    }
    // TV remotes often report these media keys instead of Arrow/Enter.
    if (code === 'mediaplaypause' && document.getElementById('play')) {
      e.preventDefault();
      document.getElementById('play').click();
    }
  }, true);
  // Keep keyboard focus on the live player after it opens, so a D-pad/OK remote
  // controls the receiver rather than moving focus to unrelated page tiles.
  const observer = new MutationObserver(() => {
    const p = document.getElementById('playerPanel');
    if (p && p.style.display === 'block' && document.activeElement !== p) {
      try { p.focus({ preventScroll: true }); } catch (_) {}
    }
  });
  const panel = document.getElementById('playerPanel');
  if (panel) observer.observe(panel, { attributes: true, attributeFilter: ['style'] });
})();
