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

  function signalPremiumState() {
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
    code = n; unlocked = true; codeExpiry = Number(result.expires_at || 0); serverOffset = Number(result.now || Date.now()) - Date.now(); signalPremiumState();
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
    '.gate-plans,.gate-methods{display:flex;gap:8px;margin:10px 0;flex-wrap:wrap}',
    '.gate-methods .gate-choice{flex:1 1 21%}',
    '.gate-choice{flex:1;min-width:0;padding:11px 8px;border:1px solid #33465c;border-radius:12px;background:#101c2a;color:#dbe7f3;text-align:center;font-weight:800;cursor:pointer}',
    '.gate-choice.active{border-color:#f3c76b;background:#f3c76b18;color:#ffe2a0}',
    '.gate-choice small{display:block;margin-top:4px;font-size:11px;color:#9aabc0;font-weight:600}',
    '.gate-plan-select{box-sizing:border-box;width:100%;padding:12px;border:1px solid #33465c;border-radius:10px;background:#060a10;color:#fff;font-size:14px;margin:4px 0 10px}',
    '.gate-field{display:block;margin:12px 0 6px;font-size:12px;font-weight:800;color:#dceaf6}',
    '.gate-pop input[type=email],.gate-pop input[type=text]{box-sizing:border-box;width:100%;min-width:0;padding:12px;border:1px solid #33465c;border-radius:10px;background:#060a10;color:#fff;font-size:15px}',
    '.gate-toggle{display:flex;align-items:center;gap:8px;margin:10px 0;color:#b8c7d8;font-size:12px}',
    '.gate-pay{width:100%;min-height:48px;margin-top:8px;border:0;border-radius:13px;background:linear-gradient(110deg,#f3c76b,#d99a32);color:#201707;font-size:15px;font-weight:900;cursor:pointer}',
    '.gate-pay:disabled{opacity:.45;cursor:not-allowed}',
    '.gate-verify{width:100%;min-height:42px;margin-top:8px;border:1px solid #52667d;border-radius:12px;background:#172536;color:#e6f0fa;font-weight:800;cursor:pointer}',
    '.gate-status{min-height:18px;margin:8px 0;font-size:12px;line-height:1.4;color:#a9bad0}',
    '.gate-substatus{margin:14px 0;padding:14px;border:1px solid #35533f;border-radius:14px;background:#0c1c16}',
    '.gate-substatus .status-head{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:9px;color:#f2f7f4;font-weight:900}',
    '.gate-substatus .status-pill{padding:5px 9px;border-radius:20px;background:#1b9b5528;color:#7be8a4;font-size:10px;font-weight:900}',
    '.gate-substatus .status-pill.expired{background:#ef444422;color:#fca5a5}',
    '.gate-substatus .status-days{font-size:25px;font-weight:900;color:#86efac;line-height:1.2}',
    '.gate-substatus .status-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:12px}',
    '.gate-substatus .status-item{min-width:0;padding:9px;border-radius:9px;background:#ffffff08}',
    '.gate-substatus .status-item small{display:block;color:#9eafa5;font-size:10px;margin-bottom:4px}',
    '.gate-substatus .status-item b{display:block;color:#edf7f0;font-size:12px;overflow-wrap:anywhere}',
    '.gate-substatus .status-note{margin:10px 0 0;color:#aabbb0;font-size:11px;line-height:1.45}',
    '.gate-helpline{margin-top:16px;padding:12px;border:1px solid #24563b;border-radius:12px;background:#0c2118;color:#d6f6e3;font-size:13px}',
    '.gate-helpline a{display:inline-block;margin-left:5px;color:#86efac;font-weight:900;text-decoration:underline}',
    '.gate-paystack{display:flex;align-items:center;justify-content:space-between;gap:10px;margin:12px 0;padding:10px 12px;border:1px solid #34485e;border-radius:12px;background:#101c2a;color:#dceaf6;font-size:12px;font-weight:800}',
    '.gate-coming{padding:5px 9px;border-radius:20px;background:#f59e0b22;color:#fbbf24;font-size:10px;font-weight:900;white-space:nowrap}',
    '.gate-account{margin:12px 0;padding:13px;border:1px solid #34485e;border-radius:13px;background:#080f18}',
    '.gate-account-row{display:flex;align-items:flex-start;gap:8px;margin:7px 0;font-size:12px}',
    '.gate-account-row span{width:92px;flex:none;color:#9aabc0}',
    '.gate-account-row b{min-width:0;flex:1;overflow-wrap:anywhere;color:#fff}',
    '.gate-copy{padding:4px 8px;border:1px solid #52667d;border-radius:8px;background:#172536;color:#e6f0fa;font-size:11px;font-weight:800}',
    '.gate-action{width:100%;min-height:44px;margin-top:9px;border:0;border-radius:12px;background:#25d366;color:#fff;font-weight:900}',
    '.gate-check{width:100%;min-height:42px;margin-top:8px;border:1px solid #52667d;border-radius:12px;background:#172536;color:#e6f0fa;font-weight:800}',
    '.gate-code{margin-top:12px;padding:12px;border:1px solid #2c3d52;border-radius:12px;background:#080f18}',
    '.gate-code button{margin-top:8px}',
    '@media(max-width:860px){.home-top{flex-wrap:wrap;gap:12px}.gate-box{order:3;flex:1 1 100%;margin:0}.gate-features{grid-template-columns:1fr 1fr}}'
  ].join('');
  document.head.appendChild(css);
  // Preserve the receiver's mobile layout: the decoder entry stays hidden on
  // the pages.dev phone homepage, while channel taps still open the gate.
  css.textContent += '\n#landing .gate-box{display:none!important}';

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
      rows.map((r, i) => '<div class="gate-account-row"><span>' + escapeHtml(r[0]) + '</span><b>' + escapeHtml(r[1]) + '</b>' +
        (i === rows.length - 1 ? '<button type="button" class="gate-copy" data-copy="' + escapeHtml(r[1]) + '">Copy</button>' : '') +
        '</div>').join('') +
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
  function manualHelpUrl() {
    const base = String(paymentConfig.receipt_whatsapp || 'https://wa.me/2347041629630');
    const msg = 'Hello Deeprowss, I need help with Premium. Receiver ID: ' + deviceId();
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
    const label = active ? 'ACTIVE' : 'INACTIVE';
    return '<section class="gate-substatus" id="gateSubStatus">' +
      '<div class="status-head"><span>My subscription</span><span class="status-pill ' + (active ? '' : 'expired') + '">' + label + '</span></div>' +
      (active
        ? '<div class="status-days">' + remaining + ' day' + (remaining === 1 ? '' : 's') + ' remaining</div>'
        : '<div class="status-days" style="color:#fca5a5">No active Premium</div>') +
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
  }
  function modalMarkup() {
    return '<div class="gate-pop">' +
      '<button type="button" class="gate-x" id="gateX" aria-label="Close">✕</button>' +
      '<h2>Deeprowss Premium</h2>' +
      '<p>Unlock unlimited movies and series, Play, Alternate player, Downloads and Smart Decoder. Visitors can watch 3 movie titles free.</p>' +
      '<ul class="gate-features"><li>✓ No pop-ups</li><li>✓ Stream without interruptions</li><li>✓ Unlimited movies and downloads</li><li>✓ Smart Decoder access</li></ul>' +
      statusPanelMarkup(!!(unlocked && (!codeExpiry || Date.now() + serverOffset < codeExpiry)), codeExpiry, code) +
      '<div class="gate-code"><label class="gate-field" for="gateModalCode">Already have a Decoder number from the Deeprowss App?</label><input id="gateModalCode" type="text" inputmode="numeric" maxlength="12" placeholder="000 000 0000"><button type="button" class="gate-verify" id="gateModalUnlock">Unlock with Decoder number</button></div>' +
      '<label class="gate-field" for="gateCurrency">Pricing currency</label>' +
      '<select id="gateCurrency" class="gate-plan-select">' +
        '<option value="auto"' + (selectedCurrency === 'auto' ? ' selected' : '') + '>Automatic (device region)</option>' +
        '<option value="NGN"' + (selectedCurrency === 'NGN' ? ' selected' : '') + '>Nigeria · NGN</option>' +
        '<option value="EGP"' + (selectedCurrency === 'EGP' ? ' selected' : '') + '>Egypt · EGP</option>' +
        '<option value="USD"' + (selectedCurrency === 'USD' ? ' selected' : '') + '>United States · USD</option>' +
        '<option value="GBP"' + (selectedCurrency === 'GBP' ? ' selected' : '') + '>United Kingdom · GBP</option>' +
        '<option value="GHS"' + (selectedCurrency === 'GHS' ? ' selected' : '') + '>Ghana · GHS</option>' +
        '<option value="ZAR"' + (selectedCurrency === 'ZAR' ? ' selected' : '') + '>South Africa · ZAR</option>' +
        '<option value="KES"' + (selectedCurrency === 'KES' ? ' selected' : '') + '>Kenya · KES</option>' +
        '<option value="UGX"' + (selectedCurrency === 'UGX' ? ' selected' : '') + '>Uganda · UGX</option>' +
        '<option value="TZS"' + (selectedCurrency === 'TZS' ? ' selected' : '') + '>Tanzania · TZS</option>' +
        '<option value="AED"' + (selectedCurrency === 'AED' ? ' selected' : '') + '>UAE · AED</option>' +
        '<option value="SAR"' + (selectedCurrency === 'SAR' ? ' selected' : '') + '>Saudi Arabia · SAR</option>' +
        '<option value="INR"' + (selectedCurrency === 'INR' ? ' selected' : '') + '>India · INR</option>' +
        '<option value="CAD"' + (selectedCurrency === 'CAD' ? ' selected' : '') + '>Canada · CAD</option>' +
        '<option value="AUD"' + (selectedCurrency === 'AUD' ? ' selected' : '') + '>Australia · AUD</option>' +
      '</select>' +
      '<label class="gate-field" for="gatePlan">Choose Premium duration (' + escapeHtml(pricingCurrency) + ')</label>' +
      '<select id="gatePlan" class="gate-plan-select">' +
        plans.map(p => '<option value="' + Number(p.days) + '"' + (Number(p.days) === selectedDays ? ' selected' : '') + '>' +
          escapeHtml(planLabel(p)) + ' · ' + escapeHtml((p.local_display ? p.local_display + ' · ' : '') + p.ngn_display + (p.usd_display ? ' · ' + p.usd_display : '')) + '</option>').join('') +
      '</select>' +
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
      '<div class="gate-helpline">WhatsApp helpline: <a href="' + escapeHtml(manualHelpUrl()) + '" target="_blank" rel="noopener noreferrer">+234 704 162 9630</a></div>' +
    '</div>';
  }
  function bindModal() {
    $('gateX').onclick = closeModal;
    const help = modal.querySelector('.gate-helpline a');
    if (help) help.onclick = e => { e.preventDefault(); openExternal(help.href); };
    const currencySelect = $('gateCurrency');
    currencySelect.onchange = () => {
      selectedCurrency = currencySelect.value || 'auto';
      loadPlans(selectedCurrency === 'auto' ? currencyForLocale() : selectedCurrency, true);
    };
    const planSelect = $('gatePlan');
    planSelect.onchange = () => { selectedDays = Number(planSelect.value) || 30; fillModal(); };
    modal.querySelectorAll('[data-manual]').forEach(b => b.addEventListener('click', () => { manualMethod = b.dataset.manual; fillModal(); }));
    modal.querySelectorAll('[data-copy]').forEach(b => b.addEventListener('click', () => copyManualValue(b.dataset.copy || '')));
    $('gateReceipt').onclick = () => openExternal(manualReceiptUrl());
    $('gateCheck').onclick = checkManualActivation;
    const statusRefresh = $('gateRefreshStatus');
    if (statusRefresh) statusRefresh.onclick = refreshStatusPanel;
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
  window.deeprowssMovieAccess = async function(movie, action) {
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

  // Keep the Decoder-number gate for live TV channels. Movie cards themselves
  // remain browsable; the three-title gate is applied to their action buttons.
  document.addEventListener('click', e => {
    if (!gateOn()) return;
    const t = e.target && e.target.closest ? e.target : null;
    if (!t || t.closest('#gateModal') || t.closest('.rm,.fav,[data-fav]')) return;
    if (!t.closest('.ch') || activeUnlock()) return;
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
    signalPremiumState();
  }
  setInterval(() => { if (unlocked) refreshEntitlement(); }, 15000);
  setInterval(loadConfig, 5 * 60 * 1000);
})();