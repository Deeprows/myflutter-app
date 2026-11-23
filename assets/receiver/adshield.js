/* Deeprowss receiver ad guard.
   On deeprowss.pages.dev the guard is enabled only for verified Premium users
   while browsing Movies. Cross-origin player frames remain browser-isolated. */
(() => {
  'use strict';
  if (window.__dwReceiverShield) return;
  window.__dwReceiverShield = true;

  const BAD = /(doubleclick|googlesyndication|googleadservices|googletagservices|imasdk|adnxs|adsterra|propellerads|popads|popcash|exoclick|exosrv|juicyads|trafficjunky|clickadu|hilltopads|adcash|taboola|outbrain|mgid|criteo|onclickads|onclkds|monetag|admaven|richpush|bidvertiser|tsyndicate|exdynsrv|popunder)/i;
  const AD = /(^|\\b)(advertisement|sponsored|promoted|close ad|skip ad)(\\b|$)/i;
  const ownerHost = location.hostname === 'deeprowss.pages.dev';
  const premiumMovies = () => !ownerHost || (!!window.deeprowssPremiumActive &&
    (document.body?.dataset.view === 'movies' || document.body?.dataset.mode === 'movies' || location.hash === '#movies'));

  let started = false;
  function startShield() {
    if (started) return;
    started = true;

    const nativeOpen = window.open;
    try {
      window.open = function (...args) {
        if (premiumMovies()) return null;
        return typeof nativeOpen === 'function' ? nativeOpen.apply(this, args) : null;
      };
    } catch (_) {}

    document.addEventListener('click', e => {
      if (!premiumMovies()) return;
      const a = e.target && e.target.closest ? e.target.closest('a[href],a[target="_blank"],a[target="_new"]') : null;
      if (a && BAD.test((a.href || '') + ' ' + (a.getAttribute('onclick') || ''))) {
        e.preventDefault();
        e.stopImmediatePropagation();
      }
    }, true);

    const css = document.createElement('style');
    css.textContent = 'iframe[src*="doubleclick"],iframe[src*="googlesyndication"],iframe[src*="adsterra"],iframe[src*="popads"],iframe[src*="exoclick"],[id*="google_ads"],[id*="div-gpt-ad"],ins.adsbygoogle{display:none!important}';
    (document.head || document.documentElement).appendChild(css);

    function sweep() {
      if (!premiumMovies()) return;
      try {
        document.querySelectorAll('script[src],iframe[src],img[src],video[src],source[src],embed[src]').forEach(n => {
          const u = n.src || n.getAttribute('src') || '';
          if (BAD.test(u) && !(n.matches('iframe') && n.id === 'tvFrame')) n.remove();
        });
        document.querySelectorAll('body *').forEach(n => {
          if (!(n instanceof HTMLElement) || n.id === 'tvFrame' || n.querySelector('video')) return;
          const cs = getComputedStyle(n), r = n.getBoundingClientRect();
          if (!['fixed','sticky','absolute'].includes(cs.position) || Number(cs.zIndex) < 100 || r.width < 30 || r.height < 20) return;
          const label = (n.innerText || '').trim().slice(0, 100);
          const src = n.querySelector('img,iframe')?.getAttribute('src') || '';
          if (BAD.test(src) || AD.test(label)) { n.style.setProperty('display','none','important'); n.remove(); }
        });
      } catch (_) {}
    }

    sweep();
    let queued = false;
    new MutationObserver(() => {
      if (!premiumMovies() || queued) return;
      queued = true;
      setTimeout(() => { queued = false; sweep(); }, 250);
    }).observe(document.documentElement, { childList: true, subtree: true });
    setInterval(sweep, 1800);
  }

  if (!ownerHost) {
    startShield();
  } else {
    // gate.js publishes this event only after the server-backed Premium check.
    window.addEventListener('deeprowss-premium-change', e => {
      if (e.detail && e.detail.active) startShield();
    });
    if (window.deeprowssPremiumActive) startShield();
  }
})();
