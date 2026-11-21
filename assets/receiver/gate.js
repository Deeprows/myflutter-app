/* Deeprowss receiver access gate (website, Windows app, Android TV).
   - The home screen has a "Decoder number" box. The number is shown in the header of
     Smart Decoder in the Deeprowss app.
   - Anyone can open the home screen, Movies and TV Channels, but tapping a movie or a
     channel card without an unlocked Decoder number shows a popup that sends the visitor
     to download the Deeprowss app (link = update.apkUrl, else share.link in app_config.json).
   - The number is "6 random digits + 4 check digits". The check digits are verified here, so
     no server is needed. This is a download funnel, not strong security.
   - Optional switch in app_config.json:  "receiverGate": { "enabled": false }  turns it off. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const KEY = 'deeprowss_decoder_unlock';
  const SALT = 'dpdec1'; // must match DecoderNumber._salt in the Flutter app
  const ROOT = 'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/';
  let cfg = {}, unlocked = false, number = '', modalOpen = false;

  /* ---------- number format (same maths as lib/services/decoder_number.dart) ---------- */
  const digits = s => String(s || '').replace(/\D/g, '');
  function check(prefix) {
    let h = 0x811C9DC5;
    const s = SALT + ':' + prefix;
    for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
    return h % 10000;
  }
  const isValid = n => /^\d{10}$/.test(n) && n.slice(6) === String(check(n.slice(0, 6))).padStart(4, '0');
  const pretty = n => { n = digits(n).slice(0, 10); return [n.slice(0, 3), n.slice(3, 6), n.slice(6)].filter(Boolean).join(' '); };

  const gateOn = () => !(cfg.receiverGate && cfg.receiverGate.enabled === false);
  const downloadUrl = () => {
    const u = (cfg.update && cfg.update.apkUrl) || (cfg.share && cfg.share.link) || '';
    try { const x = new URL(u); return /^https?:$/.test(x.protocol) ? x.href : ''; } catch (_) { return ''; }
  };
  const openDl = u => {
    if (window.deeprowssDesktop && window.deeprowssDesktop.openDownload) window.deeprowssDesktop.openDownload(u);
    else window.open(u, '_blank', 'noopener');
  };

  /* ---------- config (same file the movie library reads) ---------- */
  async function loadConfig() {
    for (const u of [ROOT + 'app_config.json', 'data/app_config.json', '../data/app_config.json']) {
      try {
        const r = await fetch(u + (u.includes('?') ? '&' : '?') + '_g=' + Date.now(), { cache: 'no-store' });
        if (r.ok) { cfg = await r.json(); break; }
      } catch (_) {}
    }
    render();
  }

  /* ---------- unlock state ---------- */
  function restore() {
    try {
      const n = digits(localStorage.getItem(KEY));
      if (isValid(n)) { unlocked = true; number = n; }
      else localStorage.removeItem(KEY);
    } catch (_) {}
  }
  function unlock(raw) {
    const n = digits(raw);
    if (!isValid(n)) return false;
    unlocked = true; number = n;
    try { localStorage.setItem(KEY, n); } catch (_) {}
    closeModal(); render();
    return true;
  }
  function lock() {
    unlocked = false; number = '';
    try { localStorage.removeItem(KEY); } catch (_) {}
    render();
  }

  /* ---------- styles ---------- */
  const css = document.createElement('style');
  css.textContent = `
  .gate-box{position:relative;z-index:3;flex:0 1 430px;min-width:0;margin:2px 18px 0;text-shadow:none}
  .gate-card{padding:12px 14px;border-radius:16px;background:var(--glass,#0b131dcc);border:1px solid #2c3d52;backdrop-filter:blur(14px)}
  .gate-row{display:flex;align-items:center;gap:8px}
  .gate-key{flex:none;width:34px;height:34px;border-radius:10px;display:grid;place-items:center;font-size:17px;background:#1db4ea22;border:1px solid #1db4ea55}
  .gate-box input{flex:1;min-width:0;margin:0;padding:10px 12px;font-size:16px;font-weight:800;letter-spacing:.12em;border-radius:10px;border:1px solid #33465c;background:#060a10}
  .gate-box input:focus{border-color:var(--accent,#1db4ea)}
  .gate-box .gate-go{flex:none;padding:10px 16px;font-size:14px}
  .gate-msg{min-height:16px;margin:7px 2px 0;font-size:12px;line-height:1.35;color:#8fa0b5}
  .gate-msg.err{color:#ff8f8f}
  .gate-link{background:none;border:0;padding:2px 0;color:var(--accent2,#6fd6fb);font-size:12px;font-weight:700;text-decoration:underline;cursor:pointer;border-radius:6px}
  .gate-ok{display:flex;align-items:center;gap:10px}
  .gate-ok .gate-key{background:#2ecc7122;border-color:#2ecc7188}
  .gate-ok b{display:block;font-size:14px;color:#7be8a4;letter-spacing:.04em}
  .gate-ok small{display:block;margin-top:2px;font-size:12px;letter-spacing:.14em;color:#b6c6d8}
  .gate-ok .gate-grow{flex:1;min-width:0}
  .gate-sheet{z-index:90}
  .gate-pop{position:relative;width:min(100%,460px);margin:auto;padding:30px 26px 26px;text-align:center;background:#0d1520;border:1px solid #2c3d52;border-radius:26px;box-shadow:0 30px 90px #000c;animation:up .25s ease both}
  .gate-sheet{align-items:center}
  .gate-pop .gate-x{position:absolute;top:10px;right:10px;width:38px;height:38px;padding:0;border-radius:50%;background:#16222f;border:1px solid #2c3d52;color:#fff;font-size:15px}
  .gate-pop .gate-ico{width:64px;height:64px;margin:0 auto 14px;border-radius:20px;display:grid;place-items:center;font-size:30px;background:linear-gradient(145deg,#6fd6fb,#0b84b8);box-shadow:0 10px 30px #1db4ea55}
  .gate-pop h2{margin:0 0 10px;font-size:23px;font-weight:800;line-height:1.2}
  .gate-pop p{margin:0 0 14px;font-size:15px;line-height:1.55;color:#aebdce}
  .gate-steps{list-style:none;margin:0 0 20px;padding:0;text-align:left}
  .gate-steps li{display:flex;gap:12px;align-items:flex-start;padding:9px 0;font-size:14px;line-height:1.4;color:#d7e1ec}
  .gate-steps i{flex:none;width:24px;height:24px;border-radius:50%;display:grid;place-items:center;font-style:normal;font-size:12px;font-weight:900;background:#1db4ea;color:#03121b}
  .gate-pop .gate-dl{width:100%;min-height:52px;font-size:16px;margin-bottom:10px}
  .gate-pop .gate-have{width:100%;min-height:46px}
  .gate-ver{margin-top:12px;font-size:11px;letter-spacing:.08em;color:#7f90a5}
  @media(max-width:860px){.home-top{flex-wrap:wrap;gap:12px}.gate-box{order:3;flex:1 1 100%;margin:0}}
  `;
  document.head.appendChild(css);

  /* ---------- home-screen box ---------- */
  const box = document.createElement('div');
  box.className = 'gate-box'; box.id = 'gateBox';
  function placeBox() {
    const top = document.querySelector('#landing .home-top');
    if (!top || box.parentNode === top) return;
    const clock = top.querySelector('.clock');
    top.insertBefore(box, clock || null);
  }
  let shown = '';
  function render() {
    placeBox();
    const st = !gateOn() ? 'off' : (unlocked ? 'ok' : 'lock');
    if (st === shown) return; // keep what the visitor is typing when the config refreshes
    shown = st;
    if (st === 'off') { box.hidden = true; return; }
    box.hidden = false;
    document.body.classList.toggle('gate-locked', !unlocked);
    if (unlocked) {
      box.innerHTML = '<div class="gate-card"><div class="gate-ok"><span class="gate-key">✓</span>' +
        '<div class="gate-grow"><b>Unlocked</b><small>' + pretty(number) + '</small></div>' +
        '<button type="button" class="gate-link" id="gateLock">Lock</button></div></div>';
      $('gateLock').onclick = lock;
      return;
    }
    box.innerHTML = '<div class="gate-card"><div class="gate-row"><span class="gate-key">🔑</span>' +
      '<input id="gateInput" type="text" inputmode="numeric" autocomplete="off" maxlength="12" placeholder="Decoder number" aria-label="Decoder number">' +
      '<button type="button" class="gate-go" id="gateGo">Unlock</button></div>' +
      '<div class="gate-msg" id="gateMsg">Enter the Decoder number from the Smart Decoder page in the Deeprowss app. ' +
      '<button type="button" class="gate-link" id="gateGet">Get your code</button></div></div>';
    const input = $('gateInput'), msg = $('gateMsg');
    input.addEventListener('input', () => {
      const p = pretty(input.value); if (input.value !== p) input.value = p;
      msg.classList.remove('err');
    });
    const submit = () => {
      if (unlock(input.value)) return;
      const m = $('gateMsg'); if (!m) return;
      m.classList.add('err');
      m.textContent = 'That number is not valid. Check the Decoder number at the top of Smart Decoder in the app.';
    };
    input.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); submit(); } });
    $('gateGo').onclick = submit;
    $('gateGet').onclick = () => openModal();
  }

  /* ---------- download popup ---------- */
  const modal = document.createElement('div');
  modal.className = 'sheet gate-sheet'; modal.id = 'gateModal';
  modal.setAttribute('role', 'dialog'); modal.setAttribute('aria-modal', 'true'); modal.setAttribute('aria-label', 'Get your access code');
  function fillModal() {
    const url = downloadUrl(), ver = cfg.update && cfg.update.version;
    modal.innerHTML = '<div class="gate-pop">' +
      '<button type="button" class="gate-x" id="gateX" aria-label="Close">✕</button>' +
      '<div class="gate-ico">🔑</div>' +
      '<h2>Get your one-time access code</h2>' +
      '<p>Download the Deeprowss app to get your free access code and start watching movies and live TV here.</p>' +
      '<ul class="gate-steps">' +
        '<li><i>1</i><span>Download and install the Deeprowss app on your phone.</span></li>' +
        '<li><i>2</i><span>Open <b>Smart Decoder</b>. Your Decoder number is at the top of the page.</span></li>' +
        '<li><i>3</i><span>Enter it in the box on this home screen to unlock everything.</span></li>' +
      '</ul>' +
      (url ? '<button type="button" class="gate-dl" id="gateDl">⬇ Download Deeprowss App</button>'
           : '<p>The download link is not available right now. Please try again in a moment.</p>') +
      '<button type="button" class="secondary gate-have" id="gateHave">I already have my code</button>' +
      (ver ? '<div class="gate-ver">LATEST VERSION ' + String(ver).replace(/[<>&"]/g, '') + '</div>' : '') +
      '</div>';
    $('gateX').onclick = closeModal;
    $('gateHave').onclick = () => {
      closeModal();
      if (window.deeprowssGo) window.deeprowssGo('landing');
      setTimeout(() => { const i = $('gateInput'); if (i) i.focus(); }, 120);
    };
    const dl = $('gateDl'); if (dl) dl.onclick = () => openDl(url);
  }
  function openModal() {
    fillModal();
    modal.classList.add('open'); modalOpen = true;
    setTimeout(() => { const f = $('gateDl') || $('gateHave'); if (f) f.focus(); }, 40);
  }
  function closeModal() { modal.classList.remove('open'); modalOpen = false; }
  modal.addEventListener('click', e => { if (e.target === modal) closeModal(); });

  /* ---------- block movie / channel cards while locked ---------- */
  document.addEventListener('click', e => {
    if (unlocked || !gateOn()) return;
    const t = e.target && e.target.closest ? e.target : null;
    if (!t || t.closest('#gateModal') || t.closest('.rm,.fav,[data-fav]')) return;
    if (!t.closest('.card, .ch')) return;
    e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
    openModal();
  }, true);

  document.addEventListener('keydown', e => {
    if (!modalOpen) return;
    if (e.key === 'Escape' || e.key === 'Backspace') { e.preventDefault(); e.stopPropagation(); closeModal(); }
  }, true);

  // The phone remote's Back key closes the popup first.
  const prevBack = window.deeprowssHandleBack;
  window.deeprowssHandleBack = () => { if (modalOpen) { closeModal(); return true; } return prevBack ? prevBack() : false; };

  /* ---------- start ---------- */
  restore();
  document.body.appendChild(modal);
  render();
  loadConfig();
  setInterval(loadConfig, 5 * 60 * 1000);
})();
