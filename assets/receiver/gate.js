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
  const FREE_LIMIT = 3;
  let cfg = {}, unlocked = false, code = '', codeExpiry = 0, serverOffset = 0, modalOpen = false;
  let plans = [
    { days: 7, label: '7 days', ngn_display: '₦700' },
    { days: 14, label: '14 days', ngn_display: '₦1,200' },
    { days: 30, label: '30 days', ngn_display: '₦2,000' },
    { days: 60, label: '60 days', ngn_display: '₦3,600' },
    { days: 90, label: '90 days', ngn_display: '₦5,000' },
    { days: 180, label: '180 days', ngn_display: '₦9,000' },
    { days: 365, label: '1 year', ngn_display: '₦16,000' }
  ];
  let selectedDays = 30, selectedCurrency = 'auto', pricingCurrency = 'NGN', manualMethod = 'opay', paymentConfig = {};

  function updateSubscriptionButton() {
    const button = $('subscriptionOpen');
    if (!button) return;
    const now = Date.now() + serverOffset;
    const active = !!(unlocked && (!codeExpiry || now < codeExpiry));
    const daysLeft = codeExpiry ? Math.ceil((codeExpiry - now) / 86400000) : Infinity;
    const expiring = active && daysLeft <= 3;
    button.classList.toggle('is-subscribed', active && !expiring);
    button.classList.toggle('is-expiring', expiring);
    const label = button.querySelector('b');
    if (label) label.textContent = expiring ? 'Expiring' : (active ? 'Subscribed' : 'Subscribe');
    button.setAttribute('aria-label', expiring ? 'Premium subscription expiring soon' : (active ? 'Premium subscription active' : 'Subscribe to Deeprowss Premium'));
    // The EXE reports the real server expiry to Electron; Android TV and the
    // public website do not receive desktop beeps or Windows notifications.
    if (active && expiring && codeExpiry && window.deeprowssDesktop &&
        window.deeprowssDesktop.platform === 'win32' &&
        typeof window.deeprowssDesktop.notifySubscriptionExpiring === 'function') {
      window.deeprowssDesktop.notifySubscriptionExpiring(codeExpiry);
    }
  }
  function placeSubscriptionButton() {
    const button = $('subscriptionOpen');
    const landing = $('landing');
    const footer = landing && landing.querySelector('.receiver-footer');
    if (!button || !landing || !footer) return;
    const desktopLayout = window.deeprowssDesktop || document.documentElement.classList.contains('tv') || window.matchMedia('(min-width:821px)').matches;
    if (desktopLayout) {
      if (button.parentNode !== footer) footer.insertBefore(button, footer.firstElementChild || null);
    } else if (button.parentNode !== landing) {
      landing.insertBefore(button, footer);
    }
  }
  placeSubscriptionButton();
  window.addEventListener('resize', placeSubscriptionButton);

  function signalPremiumState() {
    updateSubscriptionButton();
    const active = !!(unlocked && (!codeExpiry || Date.now() + serverOffset < codeExpiry));
    window.deeprowssPremiumActive = active;
    window.dispatchEvent(new CustomEvent('deeprowss-premium-change', { detail: { active } }));
    if (typeof window.__deeprowssPremiumResolve === 'function') {
      window.__deeprowssPremiumResolve(active);
      window.__deeprowssPremiumResolve = null;
    }
  }

  const digits = s => String(s || '').replace(/\D/g, '').slice(0, 10);
  const pretty = s => { const n = digits(s); return [n.slice(0,3), n.slice(3,6), n.slice(6)].filter(Boolean).join(' '); };
  const escapeHtml = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let ephemeralDeviceId = '';
  function deviceId() {
    try {
      let id = localStorage.getItem(DEVICE_KEY) || '';
      if (!/^[a-f0-9]{32}$/i.test(id)) {
        const b = new Uint8Array(16);
        if (window.crypto && crypto.getRandomValues) crypto.getRandomValues(b);
        else for (let i = 0; i < b.length; i++) b[i] = Math.floor(Math.random() * 256);
        id = Array.from(b, x => x.toString(16).padStart(2, '0')).join('');
        localStorage.setItem(DEVICE_KEY, id);
      }
      return id;
    } catch (_) {
      if (!ephemeralDeviceId) ephemeralDeviceId = ('receiver' + Date.now().toString(36) + Math.random().toString(36).slice(2)).replace(/[^a-z0-9]/gi, '').slice(0, 48);
      return ephemeralDeviceId;
    }
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
  function selectedPlan() {
    return plans.find(p => Number(p.days) === selectedDays) || plans[0];
  }
  function planLabel(p) {
    const days = Number(p && p.days) || 30;
    return days % 365 === 0 ? (days / 365) + ' year' + (days === 365 ? '' : 's') : days + ' days';
  }
  function shownPrice() {
    const p = selectedPlan();
    return p.local_display || p.ngn_display || '₦2,000';
  }
  function amountLine() {
    const p = selectedPlan();
    return (p.ngn_display || '₦2,000') + (p.local_display ? ' (about ' + p.local_display + ')' : '');
  }
  async function loadPlans(currency, refreshModal) {
    const wanted = currency || currencyForLocale();
    const p = await api('/sub/ad-plans?cur=' + encodeURIComponent(wanted));
    if (p.ok && Array.isArray(p.data.plans) && p.data.plans.length) {
      const next = p.data.plans.filter(x => Number(x.days) > 0 && x.ngn_display);
      if (next.length) {
        plans = next;
        pricingCurrency = p.data.currency || wanted;
        if (!plans.some(x => Number(x.days) === selectedDays)) selectedDays = Number(plans[0].days);
      }
    }
    if (refreshModal && modalOpen) fillModal();
  }
  async function loadPaymentAccounts() {
    for (const u of [ROOT + 'payment_accounts.json', 'data/payment_accounts.json', '../data/payment_accounts.json']) {
      try {
        const r = await fetch(u + '?_payment=' + Date.now(), { cache: 'no-store' });
        if (r.ok) {
          const j = await r.json();
          if (j && Array.isArray(j.accounts)) { paymentConfig = j; return; }
        }
      } catch (_) {}
    }
  }
  function paymentAccount(id) {
    const rows = Array.isArray(paymentConfig.accounts) ? paymentConfig.accounts : [];
    const found = rows.find(x => x && x.id === id && x.enabled !== false);
    if (found) return found;
    if (id === 'opay') return { provider: 'OPAY', account_name: 'Taiwo', account_number: '9028840867' };
    if (id === 'wallet') return { provider: 'USDT', network: 'TRC20', wallet_name: 'Taiwo', wallet_address: 'TFijBKULxEJuJwgj9nrEcQHvTuweKQoZ2M' };
    return {};
  }
  async function loadConfig() {
    await loadPaymentAccounts();
    for (const u of [ROOT + 'app_config.json', 'data/app_config.json', '../data/app_config.json']) {
      try {
        const r = await fetch(u + '?_gate=' + Date.now(), { cache: 'no-store' });
        if (r.ok) { cfg = await r.json(); break; }
      } catch (_) {}
    }
    await loadPlans(selectedCurrency === 'auto' ? currencyForLocale() : selectedCurrency, true);
    render();
  }

  async function validateCode(raw) {
    const n = digits(raw);
    if (!/^\d{10}$/.test(n)) return { valid: false };
    const r = await api('/receiver/decoder/validate', 'POST', { code: n, device_id: deviceId() });
    if (r.data.limit_reached) return r.data;
    return r.ok && r.data.valid === true ? r.data : { valid: false };
  }
  // True while this device already has an active (unexpired) Premium subscription.
  function premiumActiveNow() {
    return !!(unlocked && (!codeExpiry || Date.now() + serverOffset < codeExpiry));
  }
  async function unlock(raw, messageEl) {
    // Re-checking the same Decoder number refreshes its expiry after an admin top-up.
    const n = digits(raw);
    if (!/^\d{10}$/.test(n)) {
      if (messageEl) { messageEl.classList.add('err'); messageEl.textContent = 'Enter the 10-digit Decoder number.'; }
      return false;
    }
    if (messageEl) messageEl.textContent = 'Checking your Premium subscription…';
    const result = await validateCode(n);
    if (!result.valid) {
      if (messageEl) {
        messageEl.classList.add('err');
        messageEl.textContent = result.limit_reached
          ? 'This Decoder number is already linked to 2 devices. Contact Admin on WhatsApp to add another device.'
          : 'This Decoder number is invalid or its Premium subscription has expired.';
      }
      return false;
    }
    code = n; unlocked = true; codeExpiry = Number(result.expires_at || 0); serverOffset = Number(result.now || Date.now()) - Date.now(); signalPremiumState();
    try { localStorage.setItem(CODE_KEY, code); } catch (_) {}
    if (messageEl && messageEl.id === 'gateCodeMsg') {
      // Subscribe page: confirm on the spot, then close the sheet a moment later.
      messageEl.classList.remove('err'); messageEl.classList.add('ok');
      messageEl.textContent = 'Premium activated' + (codeExpiry ? ' until ' + new Date(codeExpiry).toLocaleDateString() : '') + '. Enjoy Deeprowss!';
      render(); refreshStatusPanel();
      setTimeout(closeModal, 1800);
      return true;
    }
    if (messageEl) messageEl.textContent = 'Premium unlocked.';
    closeModal(); render();
    return true;
  }
  async function refreshEntitlement() {
    const saved = digits(localStorage.getItem(CODE_KEY) || '');
    if (saved) {
      const result = await validateCode(saved);
      if (result.valid) {
        code = saved; unlocked = true; codeExpiry = Number(result.expires_at || 0); serverOffset = Number(result.now || Date.now()) - Date.now();
        signalPremiumState(); render(); return true;
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
        code = digits(issued.data.code); unlocked = true; codeExpiry = Number(issued.data.expires_at || 0); serverOffset = Number(issued.data.now || Date.now()) - Date.now();
        try { localStorage.setItem(CODE_KEY, code); } catch (_) {}
      }
    }
    render(); return unlocked;
  }

  function activeUnlock() {
    if (unlocked && codeExpiry && Date.now() + serverOffset >= codeExpiry) {
      unlocked = false; code = ''; codeExpiry = 0;
      try { localStorage.removeItem(CODE_KEY); } catch (_) {}
      signalPremiumState(); render();
    }
    return unlocked;
  }

  if (window.deeprowssDesktop) document.documentElement.classList.add('desktop-app');


  const GATE_MODAL_CSS = `
.gate-sheet{z-index:100;align-items:center;padding:14px;background:radial-gradient(900px 500px at 15% 10%,#1b3a6b55,transparent 60%),radial-gradient(800px 500px at 90% 90%,#f59e0b26,transparent 60%),#04070dd9;backdrop-filter:blur(14px) saturate(1.2)}
.gate-pop{--g-line:#ffffff14;--g-soft:#ffffff0a;--g-text:#eaf1fb;--g-mute:#93a4ba;--g-gold:#ffc94d;--g-gold2:#f59e0b;--g-cyan:#38bdf8;--g-green:#34d399;
  position:relative;display:flex;flex-direction:column;width:min(100%,520px);max-height:94vh;margin:auto;padding:0;text-align:left;color:var(--g-text);
  background:linear-gradient(180deg,#0f1726f2,#090e18f7);border:1px solid #ffffff1f;border-radius:28px;overflow:hidden;
  box-shadow:0 40px 120px #000d,0 0 0 1px #00000066,inset 0 1px 0 #ffffff14;animation:up .28s cubic-bezier(.2,.8,.2,1) both}
.gate-pop *{box-sizing:border-box}
.gate-pop .gate-x{position:absolute;z-index:6;top:14px;right:14px;width:38px;height:38px;padding:0;display:grid;place-items:center;border-radius:50%;background:#ffffff0f;border:1px solid var(--g-line);color:#fff;font-size:14px;cursor:pointer;transition:.18s}
.gate-pop .gate-x:hover{background:#ffffff1f;transform:rotate(90deg)}
.gate-layout{flex:1;min-height:0;display:block;overflow-y:auto}
.gate-left,.gate-right{min-width:0;padding:26px 22px}
.gate-left{position:relative;background:radial-gradient(520px 320px at 0% 0%,#ffc94d1f,transparent 65%),radial-gradient(420px 300px at 100% 100%,#38bdf81c,transparent 65%),#ffffff05;border-bottom:1px solid var(--g-line)}
.gate-brand{display:inline-flex;align-items:center;gap:7px;padding:6px 12px 6px 8px;border-radius:99px;background:linear-gradient(110deg,#ffc94d26,#f59e0b14);border:1px solid #ffc94d40;color:var(--g-gold);font-size:11px;font-weight:900;letter-spacing:.14em}
.gate-brand i{display:grid;place-items:center;width:20px;height:20px;border-radius:50%;background:linear-gradient(135deg,var(--g-gold),var(--g-gold2));color:#2a1a02;font-style:normal;font-size:11px}
.gate-pop h2{margin:14px 48px 10px 0;font-size:30px;font-weight:900;line-height:1.1;letter-spacing:-.02em;background:linear-gradient(100deg,#fff 30%,#ffd98a);-webkit-background-clip:text;background-clip:text;color:transparent}
.gate-pop p{margin:0;font-size:13.5px;line-height:1.6;color:var(--g-mute)}
.gate-features{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin:18px 0 18px;padding:0;list-style:none}
.gate-features li{display:flex;align-items:center;gap:9px;padding:10px 11px;font-size:12px;font-weight:700;line-height:1.25;color:#dbe6f3;border:1px solid var(--g-line);border-radius:13px;background:var(--g-soft)}
.gate-features li::before{content:"✓";flex:none;display:grid;place-items:center;width:20px;height:20px;border-radius:50%;background:#34d3991f;border:1px solid #34d39966;color:var(--g-green);font-size:11px;font-weight:900}
.gate-substatus{position:relative;margin:0 0 14px;padding:16px;border-radius:20px;border:1px solid #34d3994d;background:linear-gradient(145deg,#0f2a22cc,#0a1712cc);overflow:hidden}
.gate-substatus::before{content:"";position:absolute;right:-50px;top:-50px;width:160px;height:160px;border-radius:50%;background:radial-gradient(#34d39933,transparent 70%);pointer-events:none}
.gate-substatus.is-warn{border-color:#fb923c55;background:linear-gradient(145deg,#2c1a0fcc,#170e08cc)}
.gate-substatus.is-warn::before{background:radial-gradient(#fb923c33,transparent 70%)}
.gate-substatus.is-off{border-color:#ffffff1f;background:linear-gradient(145deg,#141c2ccc,#0c121dcc)}
.gate-substatus.is-off::before{display:none}
.gate-substatus .status-head{position:relative;display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:12px;font-size:13px;font-weight:800;color:#f2f7f4}
.gate-substatus .status-pill{display:inline-flex;align-items:center;gap:6px;padding:5px 10px;border-radius:99px;background:#34d3992b;color:#6ee7b7;font-size:10px;font-weight:900;letter-spacing:.08em}
.gate-substatus .status-pill::before{content:"";width:6px;height:6px;border-radius:50%;background:currentColor;box-shadow:0 0 8px currentColor}
.gate-substatus.is-warn .status-pill{background:#fb923c2b;color:#fdba74}
.gate-substatus.is-off .status-pill{background:#ffffff14;color:#aab8cb}
.gate-substatus .status-main{position:relative;display:flex;align-items:center;gap:14px}
.gate-substatus .status-num{flex:none;display:grid;place-items:center;align-content:center;width:68px;height:68px;border-radius:50%;background:radial-gradient(circle,#0c1c16 62%,transparent 63%),conic-gradient(var(--g-green) var(--pct,0%),#ffffff14 0);font-size:24px;font-weight:900;color:#a7f3d0;line-height:1}
.gate-substatus.is-warn .status-num{background:radial-gradient(circle,#170e08 62%,transparent 63%),conic-gradient(#fb923c var(--pct,0%),#ffffff14 0);color:#fed7aa}
.gate-substatus.is-off .status-num{background:radial-gradient(circle,#0c121d 62%,transparent 63%),conic-gradient(#ffffff22 0,#ffffff14 0);color:#6b7c92}
.gate-substatus .status-days{font-size:20px;font-weight:900;line-height:1.2;color:#d1fae5}
.gate-substatus.is-warn .status-days{color:#fed7aa}
.gate-substatus.is-off .status-days{color:#cbd5e1}
.gate-substatus .status-sub{margin-top:3px;font-size:11.5px;color:#9db3a8}
.gate-substatus .status-grid{position:relative;display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:14px}
.gate-substatus .status-item{min-width:0;padding:10px 11px;border-radius:12px;background:#ffffff0a;border:1px solid #ffffff0d}
.gate-substatus .status-item small{display:block;margin-bottom:4px;font-size:10px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:#8ea39a}
.gate-substatus .status-item b{display:block;font-size:12.5px;color:#f1f8f4;overflow-wrap:anywhere}
.gate-substatus .status-note{position:relative;margin:12px 0 0;font-size:11.5px;line-height:1.5;color:#9db3a8}
.gate-check{width:100%;min-height:44px;margin-top:10px;border:1px solid #ffffff1f;border-radius:13px;background:#ffffff0d;color:#eaf1fb;font-size:13px;font-weight:800;cursor:pointer;transition:.18s}
.gate-check:hover:not(:disabled){background:#ffffff1a;border-color:#ffffff33}
.gate-check:disabled{opacity:.55;cursor:wait}
.gate-code{padding:16px;border:1px dashed #ffffff2b;border-radius:18px;background:#ffffff06}
.gate-code-head{display:flex;align-items:center;gap:9px;margin:0 0 8px;color:#fff;font-size:15px}
.gate-code-sub{margin:0 0 12px;color:#aebbd0;font-size:12.5px;line-height:1.55}
.gate-code-row{display:flex;gap:9px;align-items:stretch}
.gate-code-row input{flex:1 1 auto;min-width:0}
.gate-code-row .gate-verify{flex:0 0 auto;width:auto;white-space:nowrap;margin:0}
.gate-code.locked input,.gate-code.locked .gate-verify{opacity:.45;cursor:not-allowed;pointer-events:none;filter:grayscale(.6)}
.gate-code.locked .gate-verify:hover{transform:none;box-shadow:none}
.gate-code-msg{margin-top:10px;color:#aebbd0;font-size:12.5px;line-height:1.5}
.gate-code-msg.err{color:#ff8a9a;font-weight:700}
.gate-code-msg.ok{color:#5ee9a0;font-weight:700}
@media(max-width:520px){.gate-code-row{flex-direction:column}.gate-code-row .gate-verify{width:100%}}
.gate-code .gate-field{margin:0 0 10px}
.gate-field{display:block;margin:0 0 9px;font-size:12px;font-weight:800;line-height:1.4;color:#dbe6f3}
.gate-code input{width:100%;padding:13px 14px;border:1px solid #ffffff1f;border-radius:13px;background:#05080e;color:#fff;font-size:16px;font-weight:800;letter-spacing:.14em;transition:.18s}
.gate-code input::placeholder{letter-spacing:.02em;font-weight:500;color:#5d6e84}
.gate-code input:focus{outline:none;border-color:var(--g-gold);box-shadow:0 0 0 4px #ffc94d1f}
.gate-verify{width:100%;min-height:46px;margin-top:10px;border:0;border-radius:13px;background:linear-gradient(110deg,#ffd36b,var(--g-gold2));color:#241602;font-size:14px;font-weight:900;cursor:pointer;box-shadow:0 8px 24px #f59e0b33;transition:.18s}
.gate-verify:hover{transform:translateY(-1px);box-shadow:0 12px 30px #f59e0b4d}
.gate-step{display:flex;align-items:center;gap:10px;margin:0 0 11px;font-size:12px;font-weight:900;letter-spacing:.1em;text-transform:uppercase;color:#cfdbea}
.gate-step i{display:grid;place-items:center;width:22px;height:22px;border-radius:50%;background:#ffffff14;border:1px solid var(--g-line);font-style:normal;font-size:11px;color:var(--g-gold)}
.gate-total+.gate-step{margin-top:26px}
.gate-plan-select{width:100%;padding:12px 40px 12px 14px;border:1px solid #ffffff1f;border-radius:13px;background:#05080e url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8' fill='none' stroke='%2393a4ba' stroke-width='2'%3E%3Cpath d='M1 1.5l5 5 5-5'/%3E%3C/svg%3E") no-repeat right 15px center;color:#fff;font-size:14px;font-weight:700;appearance:none;-webkit-appearance:none;cursor:pointer;margin:0}
.gate-plan-select:focus{outline:none;border-color:var(--g-gold);box-shadow:0 0 0 4px #ffc94d1f}
.gate-plans{display:grid;grid-template-columns:repeat(auto-fill,minmax(112px,1fr));gap:9px;margin:12px 0 0}
.gate-plan{position:relative;display:flex;flex-direction:column;align-items:flex-start;gap:3px;min-width:0;padding:13px 12px 11px;border:1px solid #ffffff1a;border-radius:16px;background:#ffffff08;color:#dbe6f3;text-align:left;cursor:pointer;transition:.18s}
.gate-plan:hover{background:#ffffff12;transform:translateY(-2px)}
.gate-plan b{font-size:12px;font-weight:800;color:#b9c8da}
.gate-plan .price{font-size:17px;font-weight:900;color:#fff;letter-spacing:-.01em;overflow-wrap:anywhere}
.gate-plan small{font-size:10.5px;font-weight:600;color:#7f90a6;overflow-wrap:anywhere}
.gate-plan.active{border-color:var(--g-gold);background:linear-gradient(160deg,#ffc94d24,#f59e0b0d);box-shadow:0 0 0 3px #ffc94d1f,0 10px 28px #f59e0b1f}
.gate-plan.active b{color:var(--g-gold)}
.gate-plan .tag{position:absolute;top:-9px;right:10px;padding:3px 8px;border-radius:99px;background:linear-gradient(110deg,#ffd36b,var(--g-gold2));color:#241602;font-size:9px;font-weight:900;letter-spacing:.08em;text-transform:uppercase}
.gate-total{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-top:14px;padding:13px 15px;border-radius:15px;background:#ffffff0a;border:1px solid var(--g-line);font-size:12.5px;color:var(--g-mute)}
.gate-total b{font-size:20px;font-weight:900;color:var(--g-gold);letter-spacing:-.01em}
.gate-paystack{display:flex;align-items:center;justify-content:space-between;gap:10px;margin:0 0 12px;padding:13px 15px;border:1px solid var(--g-line);border-radius:15px;background:#ffffff08;color:#dbe6f3;font-size:13px;font-weight:800;opacity:.9}
.gate-coming{padding:5px 10px;border-radius:99px;background:#f59e0b24;color:#fbbf24;font-size:10px;font-weight:900;letter-spacing:.06em;white-space:nowrap}
.gate-methods{display:grid;grid-template-columns:1fr 1fr;gap:4px;margin:0 0 12px;padding:4px;border-radius:15px;background:#05080e;border:1px solid var(--g-line)}
.gate-choice{min-width:0;padding:11px 8px;border:0;border-radius:11px;background:transparent;color:#93a4ba;font-size:13px;font-weight:800;text-align:center;cursor:pointer;transition:.18s}
.gate-choice:hover{color:#fff}
.gate-choice.active{background:linear-gradient(110deg,#ffd36b,var(--g-gold2));color:#241602;box-shadow:0 6px 18px #f59e0b33}
.gate-account{padding:6px 16px 14px;border:1px solid var(--g-line);border-radius:18px;background:linear-gradient(160deg,#ffffff0d,#ffffff04)}
.gate-account-row{display:flex;align-items:center;gap:10px;padding:10px 0;font-size:12.5px;border-bottom:1px solid #ffffff0d}
.gate-account-row span{width:96px;flex:none;color:var(--g-mute)}
.gate-account-row b{min-width:0;flex:1;overflow-wrap:anywhere;font-size:13px;font-weight:800;color:#fff}
.gate-account-row.is-key b{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:12.5px;color:#fde7a8}
.gate-copy{flex:none;padding:7px 12px;border:1px solid #ffc94d55;border-radius:99px;background:#ffc94d14;color:var(--g-gold);font-size:11px;font-weight:900;cursor:pointer;transition:.18s}
.gate-copy:hover{background:#ffc94d2b}
.gate-account p{margin:12px 0 0;padding:11px 12px;border-radius:12px;background:#38bdf812;border:1px solid #38bdf82e;font-size:12px;line-height:1.55;color:#bfe6fa}
.gate-action{display:flex;align-items:center;justify-content:center;gap:9px;width:100%;min-height:52px;margin-top:16px;border:0;border-radius:15px;background:linear-gradient(110deg,#2ee574,#16b85a);color:#04210f;font-size:15px;font-weight:900;cursor:pointer;box-shadow:0 10px 30px #22c55e40;transition:.18s}
.gate-action:hover{transform:translateY(-1px);box-shadow:0 14px 36px #22c55e59}
.gate-status{min-height:18px;margin:12px 2px 0;font-size:12px;line-height:1.5;color:#9fb0c6}
.gate-helpline{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:8px;margin-top:14px;padding:12px 15px;border:1px solid #34d39933;border-radius:15px;background:#34d3990d;color:#c9f3df;font-size:12.5px}
.gate-helpline a{margin:0;color:#6ee7b7;font-weight:900;text-decoration:none}
.gate-helpline a:hover{text-decoration:underline}
.gate-pop button:focus-visible,.gate-pop select:focus-visible,.gate-pop input:focus-visible{outline:3px solid var(--g-cyan);outline-offset:2px}
@media(min-width:821px){.gate-sheet{padding:24px}.gate-pop{width:min(96vw,1080px);max-height:92vh}.gate-layout{display:grid;grid-template-columns:minmax(0,.92fr) minmax(0,1.08fr);overflow:hidden}.gate-left,.gate-right{overflow-y:auto;padding:34px 30px;}.gate-left{border-bottom:0;border-right:1px solid var(--g-line)}}
@media(min-width:700px){html.tv .gate-pop,html.desktop-app .gate-pop{width:min(96vw,1080px);max-height:92vh}
html.tv .gate-layout,html.desktop-app .gate-layout{display:grid;grid-template-columns:minmax(0,.92fr) minmax(0,1.08fr);overflow:hidden}
html.tv .gate-left,html.tv .gate-right,html.desktop-app .gate-left,html.desktop-app .gate-right{overflow-y:auto;padding:34px 30px}
html.tv .gate-left,html.desktop-app .gate-left{border-bottom:0;border-right:1px solid var(--g-line)}}
@media(max-width:420px){.gate-left,.gate-right{padding:22px 16px}.gate-pop h2{font-size:26px}.gate-features{grid-template-columns:1fr}.gate-account-row span{width:84px}}
@media(prefers-reduced-motion:reduce){.gate-pop,.gate-pop *{animation:none!important;transition:none!important}}
`;

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
    '@media(max-width:860px){.home-top{flex-wrap:wrap;gap:12px}.gate-box{order:3;flex:1 1 100%;margin:0}}'
  ].join('');
  document.head.appendChild(css);
  // Preserve the receiver's mobile layout: the decoder entry stays hidden on
  // the pages.dev phone homepage, while channel taps still open the gate.
  css.textContent += '\n#landing .gate-box{display:none!important}';
  css.textContent += GATE_MODAL_CSS;

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
    updateSubscriptionButton();
    const state = !gateOn() ? 'off' : (unlocked ? 'ok' : 'lock');
    if (state === shown) return;
    shown = state;
    if (state === 'off') { box.hidden = true; return; }
    box.hidden = false;
    document.body.classList.toggle('gate-locked', !unlocked);
    if (unlocked) {
      const exp = codeExpiry ? new Date(codeExpiry).toLocaleDateString() : 'Active';
      box.innerHTML = '<div class="gate-card"><div class="gate-ok"><span class="gate-key">✓</span><div class="gate-grow"><b>Subscribed</b><small>' + escapeHtml(pretty(code)) + ' · until ' + escapeHtml(exp) + '</small></div><button type="button" class="gate-link" id="gateManage">Subscribed</button></div></div>';
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

  function manualAccountMarkup() {
    const bank = paymentAccount('opay');
    const wallet = paymentAccount('wallet');
    const account = manualMethod === 'opay' ? bank : wallet;
    const rows = manualMethod === 'opay'
      ? [
          ['Provider', account.provider || account.name || 'OPay'],
          ['Account name', account.account_name || account.wallet_name || ''],
          ['Account number', account.account_number || '']
        ]
      : [
          ['Wallet', account.provider || account.name || 'USDT'],
          ['Network', account.network || 'TRC20'],
          ['Wallet name', account.wallet_name || account.account_name || ''],
          ['Wallet address', account.wallet_address || account.address || '']
        ];
    return '<div class="gate-account">' +
      rows.map((r, i) => {
        const last = i === rows.length - 1;
        return '<div class="gate-account-row' + (last ? ' is-key' : '') + '"><span>' + escapeHtml(r[0]) + '</span><b>' + escapeHtml(r[1]) + '</b>' +
          (last ? '<button type="button" class="gate-copy" data-copy="' + escapeHtml(r[1]) + '">Copy</button>' : '') +
          '</div>';
      }).join('') +
      '<p>' + (manualMethod === 'opay'
        ? 'Transfer ' + escapeHtml(amountLine()) + ' for the ' + escapeHtml(planLabel(selectedPlan())) + ' Premium plan.'
        : ((selectedPlan().usd_display || (pricingCurrency === 'USD' ? selectedPlan().local_display : ''))
          ? 'Send approximately ' + escapeHtml(selectedPlan().usd_display || selectedPlan().local_display) + ' worth of USDT'
          : 'Send the USDT equivalent of ' + escapeHtml(selectedPlan().ngn_display)) +
          ' for ' + escapeHtml(planLabel(selectedPlan())) + ' (naira price: ' + escapeHtml(amountLine()) + '). Use TRC20 only.') +
      '</p></div>';
  }
  function manualReceiptUrl() {
    const days = Number(selectedPlan().days);
    const method = manualMethod === 'opay' ? 'OPay bank transfer' : 'USDT ' + (paymentAccount('wallet').network || 'TRC20');
    const msg = 'Hello Deeprowss, I have made a manual Premium payment.\n' +
      'Plan: ' + planLabel(selectedPlan()) + ' (' + days + ' days)\n' +
      'Payment method: ' + method + '\n' +
      'Amount: ' + amountLine() + '\n' +
      (manualMethod === 'crypto' ? 'USDT estimate: ' + (selectedPlan().usd_display || (pricingCurrency === 'USD' ? selectedPlan().local_display : '') || 'see amount above') + '\n' : '') +
      'Please confirm my payment and activate Premium. I will attach my receipt.\n' +
      'Receiver ID: ' + deviceId();
    const base = String(paymentConfig.receipt_whatsapp || 'https://wa.me/2347041629630');
    return base + (base.indexOf('?') >= 0 ? '&' : '?') + 'text=' + encodeURIComponent(msg);
  }
  function manualHelpUrl(message) {
    const base = String(paymentConfig.receipt_whatsapp || 'https://wa.me/2347041629630');
    const msg = (message || 'Hello Deeprowss, I need help with Premium.') + ' Receiver ID: ' + deviceId();
    return base + (base.indexOf('?') >= 0 ? '&' : '?') + 'text=' + encodeURIComponent(msg);
  }
  async function copyManualValue(value) {
    try {
      await navigator.clipboard.writeText(value);
      const s = $('gateStatus'); if (s) s.textContent = 'Payment detail copied.';
    } catch (_) {
      const input = document.createElement('textarea');
      input.value = value; document.body.appendChild(input); input.select();
      try { document.execCommand('copy'); } catch (__) {}
      input.remove();
      const s = $('gateStatus'); if (s) s.textContent = 'Payment detail copied.';
    }
  }
  async function checkManualActivation() {
    const status = $('gateStatus');
    if (status) status.textContent = 'Checking your Premium activation…';
    const ok = await issueGuestCode();
    const current = $('gateStatus');
    if (ok) {
      if (current) current.textContent = 'Premium is active. Your Decoder number: ' + pretty(code) + '. Enter this on your other TV devices if needed.';
    } else if (current) {
      current.textContent = 'Your payment has not been confirmed yet. Send your receipt on WhatsApp; once the admin activates your ID, tap this button again.';
    }
  }
  function statusPanelMarkup(active, expiry, decoder) {
    const now = Date.now() + serverOffset;
    const remaining = active && expiry ? Math.max(0, Math.ceil((expiry - now) / 86400000)) : 0;
    const date = expiry ? new Date(expiry).toLocaleString() : 'Not available';
    const expiring = active && expiry && remaining <= 3;
    const label = !active ? 'INACTIVE' : (expiring ? 'EXPIRING SOON' : 'ACTIVE');
    const tone = !active ? 'is-off' : (expiring ? 'is-warn' : '');
    const pct = active ? Math.max(6, Math.min(100, Math.round(remaining / 30 * 100))) : 0;
    return '<section class="gate-substatus ' + tone + '" id="gateSubStatus">' +
      '<div class="status-head"><span>My subscription</span><span class="status-pill">' + label + '</span></div>' +
      '<div class="status-main"><div class="status-num" style="--pct:' + pct + '%">' + (active ? remaining : '–') + '</div>' +
        '<div><div class="status-days">' + (active ? (remaining + ' day' + (remaining === 1 ? '' : 's') + ' remaining') : 'No active Premium') + '</div>' +
        '<div class="status-sub">' + (active ? (expiring ? 'Renew soon to stay connected' : 'Premium is running smoothly') : 'Subscribe to unlock everything') + '</div></div></div>' +
      '<div class="status-grid">' +
        '<div class="status-item"><small>Expiry date</small><b>' + escapeHtml(date) + '</b></div>' +
        '<div class="status-item"><small>Decoder number</small><b>' + escapeHtml(decoder ? pretty(decoder) : 'Not issued') + '</b></div>' +
      '</div>' +
      '<p class="status-note">' + (active
        ? 'Your Premium access is checked against the Deeprowss server. Renew before this date to avoid interruption.'
        : 'If you have paid, send your receipt on WhatsApp. Access will appear here after payment confirmation.') + '</p>' +
      '<button type="button" class="gate-check" id="gateRefreshStatus">Refresh subscription status</button>' +
    '</section>';
  }
  async function refreshStatusPanel() {
    const panel = $('gateSubStatus');
    if (!panel) return;
    const refresh = $('gateRefreshStatus');
    if (refresh) { refresh.disabled = true; refresh.textContent = 'Checking…'; }
    let active = false, expiry = 0, decoder = code;
    if (decoder) {
      const validated = await validateCode(decoder);
      active = !!validated.valid;
      expiry = Number(validated.expires_at || 0);
      if (validated.now) serverOffset = Number(validated.now) - Date.now();
      if (!active) { unlocked = false; code = ''; codeExpiry = 0; try { localStorage.removeItem(CODE_KEY); } catch (_) {} }
    } else {
      const result = await api('/receiver/sub/status?device=' + encodeURIComponent(deviceId()));
      if (result.ok) {
        active = !!result.data.active;
        expiry = Number(result.data.expires_at || 0);
        if (result.data.now) serverOffset = Number(result.data.now) - Date.now();
        if (active) {
          const issued = await api('/receiver/decoder/issue', 'POST', { device_id: deviceId() });
          if (issued.ok && issued.data.active && issued.data.code) {
            decoder = digits(issued.data.code); code = decoder; unlocked = true;
            codeExpiry = Number(issued.data.expires_at || expiry);
            try { localStorage.setItem(CODE_KEY, decoder); } catch (_) {}
          }
        }
      }
    }
    const target = $('gateSubStatus');
    if (target) {
      target.outerHTML = statusPanelMarkup(active, expiry || codeExpiry, decoder);
      const btn = $('gateRefreshStatus');
      if (btn) btn.onclick = refreshStatusPanel;
    }
    if (!active) {
      const note = $('gateStatus');
      if (note) note.textContent = 'No active subscription was found for this receiver. You can renew below.';
    }
    signalPremiumState();
    render();
    // If the subscription just expired (or just became active) re-draw the
    // activation box so the Decoder form is enabled/disabled correctly.
    const codeBox = $('gateCode');
    if (codeBox && codeBox.classList.contains('locked') !== premiumActiveNow()) fillModal();
  }
  const CURRENCIES = [['NGN','Nigeria'],['EGP','Egypt'],['USD','United States'],['GBP','United Kingdom'],['GHS','Ghana'],['ZAR','South Africa'],['KES','Kenya'],['UGX','Uganda'],['TZS','Tanzania'],['AED','UAE'],['SAR','Saudi Arabia'],['INR','India'],['CAD','Canada'],['AUD','Australia']];
  function bestValueDays() {
    let best = 0, bestRate = Infinity;
    plans.forEach(p => {
      const n = Number(String(p.ngn_display || '').replace(/[^\d]/g, ''));
      const d = Number(p.days);
      if (n > 0 && d > 0 && n / d < bestRate) { bestRate = n / d; best = d; }
    });
    return plans.length > 2 ? best : 0;
  }
  function planCardsMarkup() {
    const best = bestValueDays();
    return '<div class="gate-plans" role="radiogroup" aria-label="Premium duration">' + plans.map(p => {
      const days = Number(p.days);
      const main = p.local_display || p.ngn_display;
      const sub = [p.local_display ? p.ngn_display : '', p.usd_display || ''].filter(Boolean).join(' · ');
      const on = days === selectedDays;
      return '<button type="button" class="gate-plan' + (on ? ' active' : '') + '" data-plan="' + days + '" role="radio" aria-checked="' + on + '">' +
        (days === best ? '<span class="tag">Best value</span>' : '') +
        '<b>' + escapeHtml(planLabel(p)) + '</b><span class="price">' + escapeHtml(main) + '</span>' +
        (sub ? '<small>' + escapeHtml(sub) + '</small>' : '') + '</button>';
    }).join('') + '</div>';
  }
  function deviceName() {
    try {
      if (window.deeprowssDesktop) return 'Windows app';
      if (window.DeeprowssTv) return 'Android TV';
      if (window.tizen) return 'Samsung TV';
      if (window.PalmSystem || window.webOS) return 'LG TV';
    } catch (_) {}
    return 'device';
  }
  function modalMarkup() {
    const active = premiumActiveNow();
    const lock = '';
    const codePanel = active
      ? '<div class="gate-code topup" id="gateCode"><div class="gate-code-head"><span aria-hidden="true">↗</span><b>Top up existing subscription</b></div>' +
        '<p class="gate-code-sub">Your Decoder number is active on up to 2 devices. To add more days, contact Admin and share your Decoder number.</p>' +
        '<div class="gate-code-row"><span class="gate-code-msg">' + escapeHtml(pretty(code)) + '</span><a class="gate-verify" id="gateTopup" href="' + escapeHtml(manualHelpUrl('Hello Deeprowss, please top up my existing Premium subscription. Decoder number: ' + pretty(code))) + '">Top up on WhatsApp</a></div>' +
        '<p class="gate-code-sub">Need to use your Decoder number on more than 2 devices? <a id="gateMoreDevices" href="' + escapeHtml(manualHelpUrl('Hello Deeprowss, I need to use my Decoder number on more than 2 devices. Decoder number: ' + pretty(code))) + '">Contact Admin</a>.</p></div>'
      : '<div class="gate-code" id="gateCode">' +
        '<div class="gate-code-head"><span aria-hidden="true">🔑</span><b>Activate with your Decoder number</b></div>' +
        '<p class="gate-code-sub">Already have Premium? Enter your 10-digit Decoder number to activate it on this ' + escapeHtml(deviceName()) + '.</p>' +
        '<label class="gate-field" for="gateModalCode">Decoder number</label>' +
        '<div class="gate-code-row"><input id="gateModalCode" type="text" inputmode="numeric" autocomplete="off" maxlength="12" placeholder="e.g. 1234 567 890" aria-label="Decoder number"' + lock + '><button type="button" class="gate-verify" id="gateModalUnlock"' + lock + '>Activate Premium</button></div>' +
        '<div class="gate-code-msg" id="gateCodeMsg" role="status" aria-live="polite">Find your Decoder number in your Premium account in the Deeprowss phone app.</div>' +
        '<p class="gate-code-sub">Each Decoder number works on up to 2 devices. Need more than 2? <a id="gateMoreDevices" href="' + escapeHtml(manualHelpUrl('Hello Deeprowss, I need to use my Decoder number on more than 2 devices.')) + '">Contact Admin on WhatsApp</a>.</p></div>';
    return '<div class="gate-pop">' +
      '<button type="button" class="gate-x" id="gateX" aria-label="Close">✕</button>' +
      '<div class="gate-layout">' +
      '<section class="gate-left">' +
      '<span class="gate-brand"><i>★</i>PREMIUM</span>' +
      '<h2>Deeprowss Premium</h2>' +
      '<p>Enjoy unlimited live TV, movies, alternate players, downloads and Smart Decoder access. Visitors get 10 TV channels each day and 3 free movie titles.</p>' +
      '<ul class="gate-features"><li>Unlimited live TV channels</li><li>No pop-ups</li><li>Unlimited movies and downloads</li><li>Smart Decoder access</li></ul>' +
      codePanel +
      statusPanelMarkup(active, codeExpiry, code) +
      '</section><section class="gate-right">' +
      '<div class="gate-step"><i>1</i>Choose your plan</div>' +
      '<label class="gate-field" for="gateCurrency">Pricing currency</label>' +
      '<select id="gateCurrency" class="gate-plan-select">' +
        '<option value="auto"' + (selectedCurrency === 'auto' ? ' selected' : '') + '>Automatic (device region)</option>' +
        CURRENCIES.map(c => '<option value="' + c[0] + '"' + (selectedCurrency === c[0] ? ' selected' : '') + '>' + c[1] + ' · ' + c[0] + '</option>').join('') +
      '</select>' +
      planCardsMarkup() +
      '<div class="gate-total"><span>Total · ' + escapeHtml(planLabel(selectedPlan())) + ' (' + escapeHtml(pricingCurrency) + ')</span><b>' + escapeHtml(shownPrice()) + '</b></div>' +
      '<div class="gate-step"><i>2</i>Pay</div>' +
      '<div class="gate-paystack"><span>Paystack online payment</span><b class="gate-coming">COMING SOON</b></div>' +
      '<div class="gate-field">Choose manual payment method</div>' +
      '<div class="gate-methods">' +
        '<button type="button" class="gate-choice ' + (manualMethod === 'opay' ? 'active' : '') + '" data-manual="opay">OPay</button>' +
        '<button type="button" class="gate-choice ' + (manualMethod === 'crypto' ? 'active' : '') + '" data-manual="crypto">USDT · TRC20</button>' +
      '</div>' +
      manualAccountMarkup() +
      '<button type="button" class="gate-action" id="gateReceipt">Send payment receipt on WhatsApp</button>' +
      '<button type="button" class="gate-check" id="gateCheck">I have paid · Check Premium activation</button>' +
      '<div class="gate-status" id="gateStatus">Make your transfer, then send the payment screenshot to our WhatsApp helpline. Your receiver ID is included automatically.</div>' +
      '<div class="gate-helpline"><span>WhatsApp helpline</span><a href="' + escapeHtml(manualHelpUrl()) + '" target="_blank" rel="noopener noreferrer">+234 704 162 9630</a></div>' +
      '</section></div></div>';
  }
  function bindModal() {
    $('gateX').onclick = closeModal;
    modal.querySelectorAll('#gateTopup,#gateMoreDevices').forEach(link => {
      link.onclick = e => { e.preventDefault(); openExternal(link.href); };
    });
    const help = modal.querySelector('.gate-helpline a');
    if (help) help.onclick = e => { e.preventDefault(); openExternal(help.href); };
    const currencySelect = $('gateCurrency');
    currencySelect.onchange = () => {
      selectedCurrency = currencySelect.value || 'auto';
      loadPlans(selectedCurrency === 'auto' ? currencyForLocale() : selectedCurrency, true);
    };
    modal.querySelectorAll('[data-plan]').forEach(b => b.addEventListener('click', () => { selectedDays = Number(b.dataset.plan) || 30; fillModal(); }));
    modal.querySelectorAll('[data-manual]').forEach(b => b.addEventListener('click', () => { manualMethod = b.dataset.manual; fillModal(); }));
    modal.querySelectorAll('[data-copy]').forEach(b => b.addEventListener('click', () => copyManualValue(b.dataset.copy || '')));
    $('gateReceipt').onclick = () => openExternal(manualReceiptUrl());
    $('gateCheck').onclick = checkManualActivation;
    const statusRefresh = $('gateRefreshStatus');
    if (statusRefresh) statusRefresh.onclick = refreshStatusPanel;
    const codeInput = $('gateModalCode');
    if (codeInput) {
      codeInput.addEventListener('input', () => { const v = pretty(codeInput.value); if (v !== codeInput.value) codeInput.value = v; });
      const codeMsg = $('gateCodeMsg');
      const activate = async () => {
        codeMsg.classList.remove('err', 'ok');
        const btn = $('gateModalUnlock');
        btn.disabled = true;
        const done = await unlock(codeInput.value, codeMsg);
        if (!done) { const b = $('gateModalUnlock'); if (b) b.disabled = false; }
      };
      codeInput.addEventListener('input', () => codeMsg.classList.remove('err', 'ok'));
      codeInput.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); activate(); } });
      $('gateModalUnlock').onclick = activate;
    }
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
  function fillModal() {
    const keep = ['.gate-layout', '.gate-left', '.gate-right'].map(q => { const el = modal.querySelector(q); return el ? el.scrollTop : 0; });
    modal.innerHTML = modalMarkup(); bindModal();
    ['.gate-layout', '.gate-left', '.gate-right'].forEach((q, i) => { const el = modal.querySelector(q); if (el) el.scrollTop = keep[i]; });
  }
  function openModal() {
    fillModal(); modal.classList.add('open'); modalOpen = true;
    refreshStatusPanel();
  }
  function closeModal() { modal.classList.remove('open'); modalOpen = false; }
  modal.addEventListener('click', e => { if (e.target === modal) closeModal(); });

  async function issueGuestCode() {
    const result = await api('/receiver/decoder/issue', 'POST', { device_id: deviceId() });
    if (!result.ok || !result.data.active || !result.data.code) return false;
    code = digits(result.data.code);
    unlocked = true;
    codeExpiry = Number(result.data.expires_at || 0);
    serverOffset = Number(result.data.now || Date.now()) - Date.now();
    try { localStorage.setItem(CODE_KEY, code); } catch (_) {}
    signalPremiumState();
    render();
    return true;
  }
  // On the public Deeprowss Pages website, every movie/TV play attempt offers
  // an app-download route or ad-supported playback. Other app/receiver builds
  // keep the existing Premium/free-allowance behaviour.
  const showWebChoice = location.hostname === 'deeprowss.pages.dev';
  let webChoiceResolve = null;
  const webChoiceModal = document.createElement('div');
  webChoiceModal.className = 'sheet web-choice-sheet';
  webChoiceModal.id = 'webPlaybackChoice';
  webChoiceModal.setAttribute('role', 'dialog');
  webChoiceModal.setAttribute('aria-modal', 'true');
  webChoiceModal.setAttribute('aria-label', 'Choose how to watch');
  webChoiceModal.innerHTML =
    '<section class="web-choice-pop">' +
      '<button type="button" class="web-choice-close" id="webChoiceClose" aria-label="Close">✕</button>' +
      '<div class="web-choice-mark">▶</div>' +
      '<h2>Ready to watch?</h2>' +
      '<p>Get the Deeprowss App for the best viewing experience, or continue here with ads.</p>' +
      '<div class="web-choice-actions">' +
        '<button type="button" class="web-choice-download" id="webChoiceDownload">⬇ Download Deeprowss App</button>' +
        '<button type="button" class="web-choice-ads" id="webChoiceAds">▶ Continue watching with ads</button>' +
      '</div>' +
    '</section>';
  const webChoiceStyle = document.createElement('style');
  webChoiceStyle.textContent =
    '.web-choice-sheet{z-index:120;align-items:center;justify-content:center;padding:18px;background:#02050bdc;backdrop-filter:blur(12px)}' +
    '.web-choice-pop{position:relative;width:min(100%,440px);padding:34px 26px 26px;text-align:center;border:1px solid #ffffff20;border-radius:26px;background:radial-gradient(ellipse at 50% 0%,#ffc42e20,transparent 65%),#101722;box-shadow:0 28px 90px #000c}' +
    '.web-choice-close{position:absolute;right:12px;top:12px;width:38px;height:38px;padding:0;border-radius:50%;background:#ffffff12;border:1px solid #ffffff20;color:#fff}' +
    '.web-choice-mark{display:grid;place-items:center;width:58px;height:58px;margin:0 auto 15px;border-radius:18px;background:#ffc42e20;color:#ffd166;font-size:25px}' +
    '.web-choice-pop h2{margin:0 0 10px;color:#fff;font-size:27px;font-weight:900}' +
    '.web-choice-pop p{margin:0 auto 23px;max-width:340px;color:#aebbd0;font-size:14px;line-height:1.6}' +
    '.web-choice-actions{display:grid;gap:11px}' +
    '.web-choice-actions button{width:100%;min-height:52px;padding:13px 16px;border-radius:14px;font-size:14px;font-weight:900}' +
    '.web-choice-download{background:#ffc42e;color:#1a1300;box-shadow:0 9px 25px #ffc42e2b}' +
    '.web-choice-ads{background:#202c3b;border:1px solid #40536b;color:#fff}' +
    '.web-choice-actions button:focus-visible,.web-choice-close:focus-visible{outline:3px solid #fff;outline-offset:3px}' +
    '@media(max-width:420px){.web-choice-pop{padding:30px 18px 20px}.web-choice-pop h2{font-size:24px}}';
  document.head.appendChild(webChoiceStyle);
  document.body.appendChild(webChoiceModal);
  function finishWebChoice(allow) {
    webChoiceModal.classList.remove('open');
    const resolve = webChoiceResolve;
    webChoiceResolve = null;
    if (resolve) resolve(!!allow);
  }
  function requestWebChoice() {
    if (webChoiceResolve) return Promise.resolve(false);
    return new Promise(resolve => {
      webChoiceResolve = resolve;
      webChoiceModal.classList.add('open');
      setTimeout(() => { const b = $('webChoiceAds'); if (b) b.focus(); }, 30);
    });
  }
  $('webChoiceClose').onclick = () => finishWebChoice(false);
  $('webChoiceAds').onclick = () => finishWebChoice(true);
  $('webChoiceDownload').onclick = () => {
    finishWebChoice(false);
    if (typeof window.deeprowssGo === 'function') window.deeprowssGo('downloads');
    else location.hash = '#downloads';
  };
  webChoiceModal.addEventListener('click', e => {
    if (e.target === webChoiceModal) finishWebChoice(false);
  });
  document.addEventListener('keydown', e => {
    if (!webChoiceResolve) return;
    if (e.key === 'Escape' || e.key === 'Backspace') {
      e.preventDefault(); e.stopPropagation(); finishWebChoice(false);
    }
  }, true);

  window.deeprowssMovieAccess = async function(movie, action) {
    if (showWebChoice && (action || 'play') !== 'download') return await requestWebChoice();
    const title = String((movie && (movie.title || movie.name)) || movie || 'movie').toLowerCase();
    const type = movie && (movie.type === 'tv' || movie.isSeries) ? 'tv' : 'movie';
    const key = type + ':' + title.replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 100);
    const result = await api('/receiver/movie-access', 'POST', {
      device_id: deviceId(), decoder_code: activeUnlock() ? code : '',
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

  // Visitors and non-Premium users can start four distinct TV channels per UTC day.
  // The Worker records each channel atomically; reopening one of today's channels is free.
  window.deeprowssTvAccess = async function(channel) {
    if (showWebChoice) return await requestWebChoice();
    if (!gateOn() || activeUnlock()) return true;
    const name = String(channel && channel.name || channel || 'TV channel').trim();
    const key = String(channel && (channel.id || (name + '|' + (channel.category || '') + '|' + (channel.country || ''))) || name)
      .toLowerCase().replace(/[^a-z0-9|:_-]+/g, '-').slice(0, 120);
    const result = await api('/receiver/tv-access', 'POST', {
      device_id: deviceId(), decoder_code: activeUnlock() ? code : '', channel_key: key
    });
    if (result.ok && result.data.allowed === true) return true;
    openModal();
    const status = $('gateStatus');
    if (status) {
      if (!result.ok) {
        status.textContent = result.status === 0 || result.status === 404 || result.status === 503
          ? 'Free TV access could not be verified. Please try again shortly.'
          : (result.data.error || 'Could not verify TV access. Please try again.');
      } else {
        status.textContent = 'You have used all 4 free TV channels for today. Upgrade to Premium for unlimited live TV. Your free allowance resets at midnight UTC.';
      }
    }
    return false;
  };

  // Movie cards remain browsable; their three-title gate is applied to their action buttons.

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
    signalPremiumState();
  }
  setInterval(() => { if (unlocked) refreshEntitlement(); }, 15000);
  setInterval(loadConfig, 5 * 60 * 1000);
})();
