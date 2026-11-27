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
          // Do not sandbox third-party channel pages: many providers detect sandboxed frames and refuse playback.
          f.removeAttribute('sandbox');
          f.setAttribute('scrolling', 'no');
          f.style.overflow = 'hidden';
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
  window.addEventListener('keydown', e => {
    const k = String(e.key || '').toLowerCase();
    const code = String(e.code || '').toLowerCase();
    const prev = ['channel_down','channeldown','mediatrackprevious'].includes(k) || code === 'mediatrackprevious';
    const next = ['channel_up','channelup','mediatracknext'].includes(k) || code === 'mediatracknext';
    // Typing must keep working inside text fields (e.g. the Decoder number box).
    const t = e.target;
    const typing = !!(t && (/^(input|textarea|select)$/i.test(t.tagName || '') || t.isContentEditable));
    if (!typing && (k === '1' || code === 'digit1' || k === '2' || code === 'digit2')) {
      e.preventDefault(); e.stopImmediatePropagation();
      if (window.deeprowssTvRemote) window.deeprowssTvRemote((k === '1' || code === 'digit1') ? 'mainstream' : 'backupstream');
      return;
    }
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
