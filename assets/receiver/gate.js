/* Deeprowss receiver Premium gate.
   Three distinct free movie/series titles per visitor; after that Play,
   Alternate player and Download require Premium. Decoder numbers are issued
   and checked by the Deeprowss Worker against the real subscription expiry. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const API = 'https://deeprowss-feed.deeprows.workers.dev';
  const ROOT = 'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/';
  const CODE_KEY = 'deeprowss_decoder_code_v2';
  const DEVICE_KEY = 'deeprowss_receiver_device_v1';
  const PENDING_KEY = 'deeprowss_receiver_payment_ref';
  const FREE_LIMIT = 3;
  let cfg = {}, unlocked = false, code = '', codeExpiry = 0, modalOpen = false;
  let plan = { available: true, recurring: false, recurring_year: false, price_display: '₦2,000', year_price_display: '₦20,000' };
  let period = 'month', method = 'card', autoRenew = false, verifyTimer = null, verifyCount = 0;

  const digits = s => String(s || '').replace(/\D/g, '').slice(0, 10);
  const pretty = s => { const n = digits(s); return [n.slice(0,3), n.slice(3,6), n.slice(6)].filter(Boolean).join(' '); };
  const escapeHtml = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function deviceId() {
    try {
      let id = localStorage.getItem(DEVICE_KEY) || '';
      if (!/^[a-f0-9]{32}$/i.test(id)) {
        const b = new Uint8Array(16);
        crypto.getRandomValues(b);
        id = Array.from(b, x => x.toString(16).padStart(2, '0')).join('');
        localStorage.setItem(DEVICE_KEY, id);
      }
      return id;
    } catch (_) { return 'receiverdevice000000000000000000'; }
  }
  async function api(path, method, body) {
    try {
      const r = await fetch(API + path, {
        method: method || 'GET',
        cache: 'no-store',
        headers: body ? { 'content-type': 'application/json' } : {},
        body: body ? JSON.stringify(body) : undefined
      });
      const data = await r.json().catch(() => ({}));
      return { ok: r.ok, status: r.status, data };
    } catch (_) { return { ok: false, status: 0, data: {} }; }
  }
  function gateOn() { return !(cfg.receiverGate && cfg.receiverGate.enabled === false); }
  function currencyForLocale() {
    const lang = String(navigator.language || 'en-NG');
    const region = (lang.split('-').pop() || 'NG').toUpperCase();
    const map = { EG:'EGP', NG:'NGN', US:'USD', GB:'GBP', GH:'GHS', ZA:'ZAR', KE:'KES', UG:'UGX', TZ:'TZS', CA:'CAD', AU:'AUD', IN:'INR', AE:'AED', SA:'SAR' };
    return map[region] || 'NGN';
  }
  function shownPrice(year) {
    const local = year ? plan.year_local_display : plan.local_display;
    const base = year ? plan.year_price_display : plan.price_display;
    return local || base || (year ? '₦20,000' : '₦2,000');
  }
  async function loadConfig() {
    for (const u of [ROOT + 'app_config.json', 'data/app_config.json', '../data/app_config.json']) {
      try {
        const r = await fetch(u + '?_gate=' + Date.now(), { cache: 'no-store' });
        if (r.ok) { cfg = await r.json(); break; }
      } catch (_) {}
    }
    const p = await api('/sub/config?cur=' + encodeURIComponent(currencyForLocale()));
    if (p.ok) plan = p.data;
    render();
  }

  async function validateCode(raw) {
    const n = digits(raw);
    if (!/^\d{10}$/.test(n)) return { valid: false };
    const r = await api('/receiver/decoder/validate', 'POST', { code: n });
    return r.ok && r.data.valid === true ? r.data : { valid: false };
  }
  async function unlock(raw, messageEl) {
    const n = digits(raw);
    if (!/^\d{10}$/.test(n)) {
      if (messageEl) { messageEl.classList.add('err'); messageEl.textContent = 'Enter the 10-digit Decoder number.'; }
      return false;
    }
    if (messageEl) messageEl.textContent = 'Checking your Premium subscription…';
    const result = await validateCode(n);
    if (!result.valid) {
      if (messageEl) { messageEl.classList.add('err'); messageEl.textContent = 'This Decoder number is invalid or its Premium subscription has expired.'; }
      return false;
    }
    code = n; unlocked = true; codeExpiry = Number(result.expires_at || 0);
    try { localStorage.setItem(CODE_KEY, code); } catch (_) {}
    if (messageEl) messageEl.textContent = 'Premium unlocked.';
    closeModal(); render();
    return true;
  }
  async function refreshEntitlement() {
    const saved = digits(localStorage.getItem(CODE_KEY) || '');
    if (saved) {
      const result = await validateCode(saved);
      if (result.valid) {
        code = saved; unlocked = true; codeExpiry = Number(result.expires_at || 0);
        render(); return true;
      }
      try { localStorage.removeItem(CODE_KEY); } catch (_) {}
    }
    code = ''; unlocked = false; codeExpiry = 0;
    // A paid receiver can recover its current code after a reload, provided
    // its local receiver ID is still present.
    const status = await api('/receiver/sub/status?device=' + encodeURIComponent(deviceId()));
    if (status.ok && status.data.active) {
      const issued = await api('/receiver/decoder/issue', 'POST', { device_id: deviceId() });
      if (issued.ok && issued.data.active && issued.data.code) {
        code = digits(issued.data.code); unlocked = true; codeExpiry = Number(issued.data.expires_at || 0);
        try { localStorage.setItem(CODE_KEY, code); } catch (_) {}
      }
    }
    render(); return unlocked;
  }

  const css = document.createElement('style');
  css.textContent = [
    '.gate-box{position:relative;z-index:3;flex:0 1 430px;min-width:0;margin:2px 18px 0;text-shadow:none}',
    '.gate-card{padding:12px 14px;border-radius:16px;background:var(--glass,#0b131dcc);border:1px solid #2c3d52;backdrop-filter:blur(14px)}',
    '.gate-row{display:flex;align-items:center;gap:8px}',
    '.gate-key{flex:none;width:34px;height:34px;border-radius:10px;display:grid;place-items:center;font-size:17px;background:#1db4ea22;border:1px solid #1db4ea55}',
    '.gate-box input{flex:1;min-width:0;margin:0;padding:10px 12px;font-size:16px;font-weight:800;letter-spacing:.12em;border-radius:10px;border:1px solid #33465c;background:#060a10;color:#fff}',
    '.gate-box .gate-go{flex:none;padding:10px 16px;font-size:14px}',
    '.gate-msg{min-height:16px;margin:7px 2px 0;font-size:12px;line-height:1.35;color:#8fa0b5}',
    '.gate-msg.err{color:#ff8f8f}',
    '.gate-link{background:none;border:0;padding:2px 0;color:var(--accent2,#6fd6fb);font-size:12px;font-weight:700;text-decoration:underline;cursor:pointer;border-radius:6px}',
    '.gate-ok{display:flex;align-items:center;gap:10px}',
    '.gate-ok .gate-key{background:#2ecc7122;border-color:#2ecc7188}',
    '.gate-ok b{display:block;font-size:14px;color:#7be8a4;letter-spacing:.04em}',
    '.gate-ok small{display:block;margin-top:2px;font-size:12px;letter-spacing:.14em;color:#b6c6d8}',
    '.gate-ok .gate-grow{flex:1;min-width:0}',
    '.gate-sheet{z-index:100;align-items:center}',
    '.gate-pop{position:relative;width:min(100%,520px);max-height:90vh;overflow:auto;margin:auto;padding:28px 24px 24px;text-align:left;background:#0d1520;border:1px solid #34485e;border-radius:24px;box-shadow:0 30px 90px #000c;animation:up .25s ease both}',
    '.gate-pop .gate-x{position:absolute;top:10px;right:10px;width:36px;height:36px;padding:0;border-radius:50%;background:#16222f;border:1px solid #2c3d52;color:#fff;font-size:15px}',
    '.gate-pop h2{margin:0 44px 8px 0;font-size:24px;font-weight:900;line-height:1.2;color:#fff}',
    '.gate-pop p{margin:0 0 14px;font-size:14px;line-height:1.5;color:#aebdce}',
    '.gate-features{display:grid;grid-template-columns:1fr 1fr;gap:7px;margin:14px 0 18px;padding:0;list-style:none}',
    '.gate-features li{font-size:12px;color:#d7e1ec;padding:8px 9px;border:1px solid #293b50;border-radius:9px;background:#111d2a}',
    '.gate-plans,.gate-methods{display:flex;gap:8px;margin:10px 0}',
    '.gate-choice{flex:1;min-width:0;padding:11px 8px;border:1px solid #33465c;border-radius:12px;background:#101c2a;color:#dbe7f3;text-align:center;font-weight:800;cursor:pointer}',
    '.gate-choice.active{border-color:#f3c76b;background:#f3c76b18;color:#ffe2a0}',
    '.gate-choice small{display:block;margin-top:4px;font-size:11px;color:#9aabc0;font-weight:600}',
    '.gate-field{display:block;margin:12px 0 6px;font-size:12px;font-weight:800;color:#dceaf6}',
    '.gate-pop input[type=email],.gate-pop input[type=text]{box-sizing:border-box;width:100%;min-width:0;padding:12px;border:1px solid #33465c;border-radius:10px;background:#060a10;color:#fff;font-size:15px}',
    '.gate-toggle{display:flex;align-items:center;gap:8px;margin:10px 0;color:#b8c7d8;font-size:12px}',
    '.gate-pay{width:100%;min-height:48px;margin-top:8px;border:0;border-radius:13px;background:linear-gradient(110deg,#f3c76b,#d99a32);color:#201707;font-size:15px;font-weight:900;cursor:pointer}',
    '.gate-pay:disabled{opacity:.45;cursor:not-allowed}',
    '.gate-verify{width:100%;min-height:42px;margin-top:8px;border:1px solid #52667d;border-radius:12px;background:#172536;color:#e6f0fa;font-weight:800;cursor:pointer}',
    '.gate-status{min-height:18px;margin:8px 0;font-size:12px;line-height:1.4;color:#a9bad0}',
    '.gate-helpline{margin-top:16px;padding:12px;border:1px solid #24563b;border-radius:12px;background:#0c2118;color:#d6f6e3;font-size:13px}',
    '.gate-helpline a{display:inline-block;margin-left:5px;color:#86efac;font-weight:900;text-decoration:underline}',
    '.gate-code{margin-top:12px;padding:12px;border:1px solid #2c3d52;border-radius:12px;background:#080f18}',
    '.gate-code button{margin-top:8px}',
    '@media(max-width:860px){.home-top{flex-wrap:wrap;gap:12px}.gate-box{order:3;flex:1 1 100%;margin:0}.gate-features{grid-template-columns:1fr 1fr}}'
  ].join('');
  document.head.appendChild(css);
  // Preserve the receiver's mobile layout: the decoder entry stays hidden on
  // the pages.dev phone homepage, while channel taps still open the gate.
  css.textContent += '\n@media(max-width:600px){#landing .gate-box{display:none!important}}';

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
    const state = !gateOn() ? 'off' : (unlocked ? 'ok' : 'lock');
    if (state === shown) return;
    shown = state;
    if (state === 'off') { box.hidden = true; return; }
    box.hidden = false;
    document.body.classList.toggle('gate-locked', !unlocked);
    if (unlocked) {
      const exp = codeExpiry ? new Date(codeExpiry).toLocaleDateString() : 'Active';
      box.innerHTML = '<div class="gate-card"><div class="gate-ok"><span class="gate-key">✓</span><div class="gate-grow"><b>Premium active</b><small>' + escapeHtml(pretty(code)) + ' · until ' + escapeHtml(exp) + '</small></div><button type="button" class="gate-link" id="gateManage">Subscription</button></div></div>';
      $('gateManage').onclick = () => openModal();
      return;
    }
    box.innerHTML = '<div class="gate-card"><div class="gate-row"><span class="gate-key">🔑</span><input id="gateInput" type="text" inputmode="numeric" autocomplete="off" maxlength="12" placeholder="Decoder number" aria-label="Decoder number"><button type="button" class="gate-go" id="gateGo">Unlock</button></div><div class="gate-msg" id="gateMsg">Enter your active Premium Decoder number from the Deeprowss App. <button type="button" class="gate-link" id="gateGet">Subscribe</button></div></div>';
    const input = $('gateInput'), msg = $('gateMsg');
    input.addEventListener('input', () => { const v = pretty(input.value); if (input.value !== v) input.value = v; msg.classList.remove('err'); });
    const submit = () => unlock(input.value, msg);
    input.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); submit(); } });
    $('gateGo').onclick = submit;
    $('gateGet').onclick = () => openModal();
  }

  const modal = document.createElement('div');
  modal.className = 'sheet gate-sheet'; modal.id = 'gateModal';
  modal.setAttribute('role', 'dialog'); modal.setAttribute('aria-modal', 'true'); modal.setAttribute('aria-label', 'Deeprowss Premium subscription');

  function modalMarkup() {
    const recurring = period === 'year' ? plan.recurring_year : plan.recurring;
    return '<div class="gate-pop">' +
      '<button type="button" class="gate-x" id="gateX" aria-label="Close">✕</button>' +
      '<h2>Deeprowss Premium</h2>' +
      '<p>Unlock unlimited movies and series, Play, Alternate player, Downloads and Smart Decoder. Visitors can watch 3 movie titles free.</p>' +
      '<ul class="gate-features"><li>✓ No pop-ups</li><li>✓ Stream without interruptions</li><li>✓ Movies and series</li><li>✓ Smart Decoder access</li></ul>' +
      '<div class="gate-plans">' +
        '<button type="button" class="gate-choice ' + (period === 'month' ? 'active' : '') + '" data-period="month">Monthly<small>' + escapeHtml(shownPrice(false)) + ' / month</small></button>' +
        '<button type="button" class="gate-choice ' + (period === 'year' ? 'active' : '') + '" data-period="year">Yearly<small>' + escapeHtml(shownPrice(true)) + ' / year · Save more</small></button>' +
      '</div>' +
      '<label class="gate-field" for="gateEmail">Your e-mail (for the receipt)</label>' +
      '<input id="gateEmail" type="email" autocomplete="email" placeholder="you@example.com">' +
      '<div class="gate-field">Payment method</div>' +
      '<div class="gate-methods">' +
        '<button type="button" class="gate-choice ' + (method === 'card' ? 'active' : '') + '" data-method="card">Card</button>' +
        '<button type="button" class="gate-choice ' + (method === 'ussd' ? 'active' : '') + '" data-method="ussd">USSD</button>' +
        '<button type="button" class="gate-choice ' + (method === 'bank_transfer' ? 'active' : '') + '" data-method="bank_transfer">Bank transfer</button>' +
      '</div>' +
      (method === 'card' && recurring ? '<label class="gate-toggle"><input id="gateAuto" type="checkbox" ' + (autoRenew ? 'checked' : '') + '> Renew automatically by card</label>' : '') +
      '<button type="button" class="gate-pay" id="gatePay" ' + (plan.available ? '' : 'disabled') + '>' + (plan.available ? 'Pay securely with Paystack · ' + escapeHtml(shownPrice(period === 'year')) : 'Online payment unavailable') + '</button>' +
      '<button type="button" class="gate-verify" id="gateVerify">I have paid · Verify payment</button>' +
      '<div class="gate-status" id="gateStatus">Pay securely with Paystack, or contact our WhatsApp helpline for manual activation.</div>' +
      '<div class="gate-code"><label class="gate-field" for="gateModalCode">Already have a Decoder number from the Deeprowss App?</label><input id="gateModalCode" type="text" inputmode="numeric" maxlength="12" placeholder="000 000 0000"><button type="button" class="gate-verify" id="gateModalUnlock">Unlock with Decoder number</button></div>' +
      '<div class="gate-helpline">WhatsApp helpline: <a href="https://wa.me/2347041629630?text=' + encodeURIComponent('Hello Deeprowss, I want to subscribe to Premium. Receiver ID: ' + deviceId()) + '" target="_blank" rel="noopener noreferrer">+234 704 162 9630</a></div>' +
    '</div>';
  }
  function bindModal() {
    $('gateX').onclick = closeModal;
    const help = modal.querySelector('.gate-helpline a');
    if (help) help.onclick = e => {
      e.preventDefault();
      openExternal(help.href);
    };
    modal.querySelectorAll('[data-period]').forEach(b => b.addEventListener('click', () => { period = b.dataset.period; fillModal(); }));
    modal.querySelectorAll('[data-method]').forEach(b => b.addEventListener('click', () => { method = b.dataset.method; if (method !== 'card') autoRenew = false; fillModal(); }));
    const auto = $('gateAuto'); if (auto) auto.onchange = () => { autoRenew = auto.checked; };
    $('gatePay').onclick = startCheckout;
    $('gateVerify').onclick = verifyPayment;
    const codeInput = $('gateModalCode');
    codeInput.addEventListener('input', () => { const v = pretty(codeInput.value); if (v !== codeInput.value) codeInput.value = v; });
    $('gateModalUnlock').onclick = () => unlock(codeInput.value, $('gateStatus'));
  }
  function openExternal(url) {
    try {
      if (window.DeeprowssTv && typeof window.DeeprowssTv.openExternal === 'function') {
        window.DeeprowssTv.openExternal(url); return true;
      }
      if (window.deeprowssDesktop && typeof window.deeprowssDesktop.openExternal === 'function') {
        window.deeprowssDesktop.openExternal(url); return true;
      }
      const win = window.open(url, '_blank', 'noopener');
      return !!win;
    } catch (_) { return false; }
  }
  function fillModal() { modal.innerHTML = modalMarkup(); bindModal(); }
  function openModal() {
    fillModal(); modal.classList.add('open'); modalOpen = true;
    const email = localStorage.getItem('deeprowss_receiver_email') || '';
    if ($('gateEmail')) $('gateEmail').value = email;
    if (localStorage.getItem(PENDING_KEY)) startVerifyPolling();
  }
  function closeModal() { modal.classList.remove('open'); modalOpen = false; }
  modal.addEventListener('click', e => { if (e.target === modal) closeModal(); });

  function channelsForMethod() {
    if (method === 'card') return ['card'];
    if (method === 'ussd') return ['ussd'];
    if (method === 'bank_transfer') return ['bank_transfer'];
    return [];
  }
  async function startCheckout() {
    const email = String($('gateEmail').value || '').trim();
    const status = $('gateStatus');
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
      status.textContent = 'Enter a valid e-mail address for your receipt.'; status.classList.add('err'); return;
    }
    status.classList.remove('err'); status.textContent = 'Creating your secure Paystack checkout…';
    try { localStorage.setItem('deeprowss_receiver_email', email); } catch (_) {}
    // Reserve a browser tab synchronously for normal browsers before awaiting
    // the Worker; native EXE / Android TV bridges open the checkout externally.
    let checkoutWindow = null;
    if (!(window.DeeprowssTv && typeof window.DeeprowssTv.openExternal === 'function') &&
        !(window.deeprowssDesktop && typeof window.deeprowssDesktop.openExternal === 'function')) {
      try { checkoutWindow = window.open('about:blank', '_blank'); } catch (_) {}
    }
    const result = await api('/receiver/sub/start', 'POST', {
      install_id: deviceId(), email: email, recurring: method === 'card' && autoRenew,
      period: period, channels: channelsForMethod()
    });
    if (!result.ok || !result.data.authorization_url) {
      status.classList.add('err'); status.textContent = result.data.error || 'Could not start payment. Use the WhatsApp helpline.';
      return;
    }
    try { localStorage.setItem(PENDING_KEY, result.data.reference || ''); } catch (_) {}
    status.textContent = 'Complete the Paystack payment in the opened page, then return here and tap Verify payment.';
    const checkoutUrl = result.data.authorization_url;
    let opened = false;
    try {
      if (window.DeeprowssTv && typeof window.DeeprowssTv.openExternal === 'function') {
        window.DeeprowssTv.openExternal(checkoutUrl); opened = true;
      } else if (window.deeprowssDesktop && typeof window.deeprowssDesktop.openExternal === 'function') {
        await window.deeprowssDesktop.openExternal(checkoutUrl); opened = true;
      } else if (checkoutWindow) {
        checkoutWindow.location.href = checkoutUrl;
        try { checkoutWindow.opener = null; } catch (_) {}
        opened = true;
      } else {
        const win = window.open(checkoutUrl, '_blank');
        opened = !!win;
        if (win) { try { win.opener = null; } catch (_) {} }
      }
    } catch (_) {}
    if (!opened) {
      try { if (checkoutWindow) checkoutWindow.close(); } catch (_) {}
      status.textContent += ' The checkout page could not open on this device. Use the WhatsApp helpline for manual activation.';
    }
    startVerifyPolling();
  }
  function startVerifyPolling() {
    if (verifyTimer) return;
    verifyCount = 0;
    verifyTimer = setInterval(async () => {
      verifyCount++;
      const done = await verifyPayment(true);
      if (done || verifyCount >= 40) { clearInterval(verifyTimer); verifyTimer = null; }
    }, 7000);
  }
  async function issueGuestCode() {
    const result = await api('/receiver/decoder/issue', 'POST', { device_id: deviceId() });
    if (!result.ok || !result.data.active || !result.data.code) return false;
    code = digits(result.data.code); unlocked = true; codeExpiry = Number(result.data.expires_at || 0);
    try { localStorage.setItem(CODE_KEY, code); localStorage.removeItem(PENDING_KEY); } catch (_) {}
    render(); return true;
  }
  async function verifyPayment(silent) {
    const ref = localStorage.getItem(PENDING_KEY) || '';
    const status = $('gateStatus');
    if (!ref) {
      if (status && !silent) status.textContent = 'No pending payment found. Start a subscription first.';
      return false;
    }
    const result = await api('/receiver/sub/verify?reference=' + encodeURIComponent(ref));
    if (result.ok && result.data.status === 'success') {
      const ok = await issueGuestCode();
      if (ok) {
        if (status) status.textContent = 'Payment confirmed. Your new Decoder number is active.';
        if (modalOpen) {
          fillModal();
          const s = $('gateStatus'); if (s) s.textContent = 'Premium is active. Your Decoder number: ' + pretty(code);
        }
        return true;
      }
      if (status) status.textContent = 'Payment received, but the Decoder number could not be issued yet. Tap Verify payment again.';
      return false;
    }
    if (status && !silent) status.textContent = result.data.status === 'pending'
      ? 'Payment is still processing. Please wait a moment and verify again.'
      : (result.data.error || 'Payment has not been confirmed yet.');
    return false;
  }

  window.deeprowssMovieAccess = async function(movie, action) {
    const title = String((movie && (movie.title || movie.name)) || movie || 'movie').toLowerCase();
    const type = movie && (movie.type === 'tv' || movie.isSeries) ? 'tv' : 'movie';
    const key = type + ':' + title.replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 100);
    const result = await api('/receiver/movie-access', 'POST', {
      device_id: deviceId(), decoder_code: unlocked ? code : '',
      movie_key: key, action: action || 'play'
    });
    if (result.ok && result.data.allowed === true) return true;
    openModal();
    const status = $('gateStatus');
    if (status) {
      if (!result.ok) {
        status.textContent = result.status === 404 || result.status === 503 || result.status === 0
          ? 'Premium access is being prepared on the server. Please try again shortly.'
          : (result.data.error || 'Could not verify movie access. Please try again.');
      } else {
        status.textContent = 'You have used your 3 free movie titles. Upgrade to Premium to continue.';
      }
    }
    return false;
  };

  // Keep the Decoder-number gate for live TV channels. Movie cards themselves
  // remain browsable; the three-title gate is applied to their action buttons.
  document.addEventListener('click', e => {
    if (unlocked || !gateOn()) return;
    const t = e.target && e.target.closest ? e.target : null;
    if (!t || t.closest('#gateModal') || t.closest('.rm,.fav,[data-fav]')) return;
    if (!t.closest('.ch')) return;
    e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
    openModal();
  }, true);

  document.addEventListener('keydown', e => {
    if (!modalOpen) return;
    if (e.key === 'Escape' || e.key === 'Backspace') { e.preventDefault(); e.stopPropagation(); closeModal(); }
  }, true);
  const prevBack = window.deeprowssHandleBack;
  window.deeprowssHandleBack = () => {
    if (modalOpen) { closeModal(); return true; }
    return prevBack ? prevBack() : false;
  };
  const subButton = $('subscriptionOpen');
  if (subButton) subButton.addEventListener('click', openModal);

  restoreStart();
  async function restoreStart() {
    document.body.appendChild(modal);
    render();
    await loadConfig();
    await refreshEntitlement();
    const pending = localStorage.getItem(PENDING_KEY);
    if (pending) startVerifyPolling();
  }
  setInterval(() => { if (unlocked) refreshEntitlement(); }, 60000);
  setInterval(loadConfig, 5 * 60 * 1000);
})();