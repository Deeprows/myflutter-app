/* Deeprowss in-app updater for Windows and Android TV.
   A prompt appears only after the platform's direct download URL changes.
   The first successful check records the current URL as the installed baseline. */
(() => {
  'use strict';
  const ROOT = 'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/';
  const KEY = 'deeprowss_platform_update_url_v1';
  const PENDING = KEY + '_pending_' + (window.DeeprowssTv ? 'androidTv' : 'windows');
  const desktop = window.deeprowssDesktop || null;
  const tv = window.DeeprowssTv || null;
  const platform = desktop ? 'windows' : (tv ? 'androidTv' : '');
  if (!platform) return;
  const esc = s => String(s || '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const css = document.createElement('style');
  css.textContent = '.dw-update-shade{position:fixed;inset:0;z-index:9999;display:none;place-items:center;padding:24px;background:#000c}.dw-update-shade.open{display:grid}.dw-update-box{width:min(100%,480px);padding:28px;border:1px solid #34465d;border-radius:22px;background:#101a27;box-shadow:0 24px 80px #000c;color:#fff;text-align:center}.dw-update-box h3{margin:0 0 10px;font-size:25px}.dw-update-box p{color:#b6c4d4;line-height:1.6}.dw-update-actions{display:flex;gap:10px;margin-top:20px}.dw-update-actions button{flex:1;padding:13px 12px;border-radius:12px;font-weight:850}.dw-update-later{background:#263446;color:#fff}.dw-update-now{background:#ffc42e;color:#171100}';
  document.head.appendChild(css);
  const shade = document.createElement('div');
  shade.className = 'dw-update-shade';
  shade.innerHTML = '<div class="dw-update-box" role="dialog" aria-modal="true" aria-labelledby="dwUpdateTitle"><div style="font-size:36px;margin-bottom:8px">⬆</div><h3 id="dwUpdateTitle">Deeprowss update available</h3><p>A newer version is ready for this device. Update now to get the latest improvements.</p><div class="dw-update-actions"><button type="button" class="dw-update-later" id="dwUpdateLater">Later</button><button type="button" class="dw-update-now" id="dwUpdateNow">Update now</button></div></div>';
  document.body.appendChild(shade);
  const close = () => shade.classList.remove('open');
  shade.querySelector('#dwUpdateLater').onclick = () => { close(); try { localStorage.removeItem(PENDING); } catch (_) {} };
  async function check() {
    try {
      const r = await fetch(ROOT + 'download_links.json?_update=' + Date.now(), {cache:'no-store'});
      if (!r.ok) return;
      const j = await r.json();
      const url = String(j && j[platform] || '').trim();
      if (!/^https:\/\//i.test(url) || /^(off|auto)$/i.test(url)) return;
      const old = localStorage.getItem(KEY + '_' + platform) || '';
      if (!old) { localStorage.setItem(KEY + '_' + platform, url); return; }
      if (old === url) return;
      localStorage.setItem(KEY + '_' + platform, url);
      shade.classList.add('open');
      shade.querySelector('#dwUpdateNow').onclick = () => {
        close();
        if (platform === 'windows' && desktop && desktop.checkForUpdates) desktop.checkForUpdates();
        else if (platform === 'androidTv' && tv && tv.installUpdate) { localStorage.setItem(PENDING, url); tv.installUpdate(url); }
      };
    } catch (_) {}
  }
  window.deeprowssRetryPendingUpdate = () => {
    if (platform !== 'androidTv' || !tv || !tv.installUpdate) return;
    const pending = localStorage.getItem(PENDING) || '';
    if (pending) tv.installUpdate(pending);
  };
  window.deeprowssUpdateStarted = () => { try { localStorage.removeItem(PENDING); } catch (_) {} };
  check();
  document.addEventListener('visibilitychange', () => { if (!document.hidden) check(); });
})();