/* Receiver-only remote ticker and notice. Shared by URL receiver, Windows EXE and Android TV receiver. */
(() => {
  'use strict';
  const BASE = 'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/';
  const TICKER_URL = BASE + 'receiver_ticker.json';
  const NOTICE_URL = BASE + 'receiver_notice.json';
  const BANNER_URL = BASE + 'receiver_banner.json';
  const $ = (tag, cls) => { const n = document.createElement(tag); if (cls) n.className = cls; return n; };
  const css = document.createElement('style');
  css.textContent = `
    .dr-remote-ticker{position:absolute;z-index:5;left:50%;top:50%;transform:translate(-50%,-50%);display:flex;align-items:center;justify-content:center;overflow:hidden;width:min(48vw,720px);margin:0;height:30px;border:1px solid #ffffff16;border-radius:999px;background:#080d16d9;color:#e8f4ff}
    .dr-remote-ticker[hidden]{display:none}.dr-ticker-track{display:flex;white-space:nowrap;will-change:transform;animation:drTickerScroll var(--dr-speed,36s) linear infinite}
    .dr-ticker-track span{padding:0 42px;font-size:13px;font-weight:700;letter-spacing:.02em}
    @keyframes drTickerScroll{from{transform:translateX(100%)}to{transform:translateX(-100%)}}
    .dr-notice-backdrop{position:fixed;inset:0;z-index:99999;display:grid;place-items:center;padding:20px;background:#000b;backdrop-filter:blur(8px)}
    .dr-notice-card{width:min(560px,94vw);padding:24px;border:1px solid #ffffff26;border-radius:18px;background:#111a27;color:#f5f7fb;box-shadow:0 24px 90px #000b}
    .dr-notice-card h2{margin:0 0 12px;font-size:clamp(20px,3vw,28px)}.dr-notice-card p{white-space:pre-wrap;line-height:1.65;color:#d5deea}
    .dr-notice-actions{display:flex;justify-content:flex-end;gap:10px;flex-wrap:wrap}.dr-notice-actions a,.dr-notice-actions button{border:0;border-radius:9px;padding:11px 16px;font-weight:800;text-decoration:none;background:#e11d48;color:white;cursor:pointer}.dr-notice-actions button{background:#263449;color:white}
    html.tv .dr-remote-ticker{height:40px;width:min(48vw,900px)}html.tv .dr-ticker-track span{font-size:18px}
    @media(max-width:600px){.dr-remote-ticker{left:12px;top:76px;transform:none;width:calc(100% - 24px);height:27px}.dr-ticker-track span{font-size:11px;padding:0 28px}}
    @media(prefers-reduced-motion:reduce){.dr-ticker-track{animation:none;white-space:normal;text-align:center}}
    .dr-ad-slot{position:absolute;z-index:5;right:48px;top:110px;width:230px;height:51px;--h:51px;text-shadow:none;transition:width .35s ease,height .35s ease}
    .dr-ad-slot[hidden]{display:none}
    .dr-ad{position:relative;display:block;width:100%;height:100%;overflow:hidden;border-radius:calc(var(--h)*.22);border:1px solid #6fd6fb40;background:#0a121d;color:#fff;text-decoration:none;cursor:pointer;box-shadow:0 10px 30px #0009,0 0 0 1px #00000040;transition:transform .18s ease,box-shadow .18s ease,border-color .18s ease}
    .dr-ad:hover,.dr-ad:focus-visible{transform:translateY(-2px) scale(1.03);border-color:#6fd6fbcc;box-shadow:0 16px 38px #000b,0 0 26px #1db4ea55}
    .dr-ad:focus-visible,html.tv .dr-ad:focus{outline:4px solid #fff;outline-offset:3px}
    .dr-ad-img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;opacity:0;transition:opacity .6s ease}
    .dr-ad-img.on{opacity:1}
    .dr-ad-tag{position:absolute;z-index:2;left:calc(var(--h)*.1);top:calc(var(--h)*.09);padding:1px calc(var(--h)*.1);border-radius:5px;background:#050a12b3;backdrop-filter:blur(4px);font-weight:800;font-size:max(8px,calc(var(--h)*.14));line-height:1.35;letter-spacing:.18em;color:#cfe9f7;text-transform:uppercase;pointer-events:none}
    .dr-ad-ph{position:absolute;inset:0;display:flex;align-items:center;gap:calc(var(--h)*.18);padding:0 calc(var(--h)*.2) 0 calc(var(--h)*.16);background:radial-gradient(120% 160% at 0% 0%,#1db4ea38,#0000 60%),linear-gradient(120deg,#0e1b2c,#08111d 70%)}
    .dr-ad-ph::before{content:'';position:absolute;inset:4px;border:1.5px dashed #6fd6fb66;border-radius:calc(var(--h)*.16);pointer-events:none}
    .dr-ad-ph::after{content:'';position:absolute;top:0;bottom:0;width:calc(var(--h)*.9);left:-80px;background:linear-gradient(100deg,#0000,#ffffff26,#0000);transform:skewX(-18deg);animation:drAdShine 5.5s ease-in-out infinite}
    .dr-ad-ico{flex:none;width:calc(var(--h)*.6);height:calc(var(--h)*.6);border-radius:calc(var(--h)*.18);display:grid;place-items:center;background:linear-gradient(145deg,#6fd6fb,#0b84b8);box-shadow:0 6px 18px #1db4ea66}
    .dr-ad-ico svg{width:55%;height:55%;fill:none;stroke:#03121b;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
    .dr-ad-txt{min-width:0;flex:1;display:flex;flex-direction:column;gap:calc(var(--h)*.05);text-align:left}
    .dr-ad-txt b{font-size:calc(var(--h)*.23);line-height:1.1;font-weight:900;letter-spacing:.16em;color:#fff;white-space:nowrap}
    .dr-ad-txt small{font-size:calc(var(--h)*.16);line-height:1.2;font-weight:600;letter-spacing:.03em;color:#9fb6c9;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .dr-ad-go{margin-left:auto;flex:none;font-size:calc(var(--h)*.4);line-height:1;color:#6fd6fb;transition:transform .18s ease}
    .dr-ad:hover .dr-ad-go,.dr-ad:focus-visible .dr-ad-go{transform:translateX(3px)}
    @keyframes drAdShine{0%,55%{left:-80px}100%{left:110%}}
    @media(max-width:820px){.dr-ad-slot{display:none}}
    @media(prefers-reduced-motion:reduce){.dr-ad-ph::after{animation:none;display:none}.dr-ad,.dr-ad-img{transition:none}}
  `;
  document.head.appendChild(css);

  let soundReady = false, lastNoticeId = '';
  try { lastNoticeId = localStorage.getItem('dr_receiver_notice_seen') || ''; } catch (_) {}
  const enableSound = () => { soundReady = true; };
  ['pointerdown','keydown','touchstart'].forEach(ev => window.addEventListener(ev, enableSound, {once:true,passive:true}));
  function beep() {
    if (!soundReady) return;
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return;
      const ctx = new Ctx(), osc = ctx.createOscillator(), gain = ctx.createGain();
      osc.type = 'sine'; osc.frequency.value = 880; gain.gain.setValueAtTime(.0001,ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(.12,ctx.currentTime+.025);
      gain.gain.exponentialRampToValueAtTime(.0001,ctx.currentTime+.32);
      osc.connect(gain); gain.connect(ctx.destination); osc.start(); osc.stop(ctx.currentTime+.34);
      osc.onended = () => ctx.close();
    } catch (_) {}
  }
  function addTicker(data) {
    let el = document.querySelector('.dr-remote-ticker');
    if (!el) {
      el = $('div','dr-remote-ticker');
      const homeTop = document.querySelector('.home-top');
      if (homeTop) homeTop.appendChild(el);
      else document.body.prepend(el);
    }
    const items = Array.isArray(data.items) ? data.items.map(x=>String(x||'').trim()).filter(Boolean) : [];
    el.hidden = data.enabled === false || !items.length;
    if (el.hidden) return;
    const track = $('div','dr-ticker-track');
    track.style.setProperty('--dr-speed', Math.max(12,Number(data.speed)||36)+'s');
    const line = items.join('   •   ');
    for(let i=0;i<2;i++){const span=$('span');span.textContent=line;track.appendChild(span);}
    el.replaceChildren(track);
  }

  /* ---------- Advert banner (under the clock) ---------- */
  let bannerSig = '', bannerTimer = 0;
  const MEGAPHONE = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 11v2a1 1 0 0 0 1 1h2l5 4V6L6 10H4a1 1 0 0 0-1 1z"/><path d="M15.5 8.5a5 5 0 0 1 0 7"/><path d="M18.5 5.5a9 9 0 0 1 0 13"/></svg>';
  function safeUrl(u) {
    const v = String(u || '').trim();
    return /^(https?:\/\/|mailto:)/i.test(v) ? v : '';
  }
  function notExpired(x) {
    if (!x || !x.expires) return true;
    const e = /^\d{4}-\d{2}-\d{2}$/.test(String(x.expires)) ? Date.parse(String(x.expires) + 'T23:59:59') : Date.parse(x.expires);
    return !Number.isFinite(e) || Date.now() <= e;
  }
  function openAd(url, ev) {
    try {
      if (window.DeeprowssTv && typeof window.DeeprowssTv.openAd === 'function') { ev.preventDefault(); window.DeeprowssTv.openAd(url); return; }
      if (window.deeprowssDesktop && typeof window.deeprowssDesktop.openAd === 'function') { ev.preventDefault(); window.deeprowssDesktop.openAd(url); return; }
    } catch (_) {}
    /* Browser / LG webOS / Tizen: the anchor's own target=_blank handles it. */
  }
  function placeholder(data) {
    const url = safeUrl(data.placeholder_url);
    const a = $(url ? 'a' : 'div', 'dr-ad');
    if (url) { a.href = url; a.target = '_blank'; a.rel = 'noopener noreferrer'; a.addEventListener('click', ev => openAd(url, ev)); }
    a.setAttribute('aria-label', (data.placeholder_text || 'Advert here') + (url ? ' - advertise with us' : ''));
    const box = $('div', 'dr-ad-ph');
    const ico = $('span', 'dr-ad-ico'); ico.innerHTML = MEGAPHONE;
    const txt = $('span', 'dr-ad-txt');
    const b = $('b'); b.textContent = String(data.placeholder_text || 'Advert here').toUpperCase();
    const sm = $('small'); sm.textContent = data.placeholder_sub || 'Your banner could be here';
    txt.append(b, sm); box.append(ico, txt);
    if (url) { const go = $('span', 'dr-ad-go'); go.textContent = '\u203a'; box.appendChild(go); }
    a.appendChild(box);
    return a;
  }
  function addBanner(data) {
    const homeTop = document.querySelector('.home-top');
    if (!homeTop) return;
    let slot = document.querySelector('.dr-ad-slot');
    if (data && data.enabled === false) { if (slot) slot.hidden = true; bannerSig = 'off'; return; }
    const sig = JSON.stringify(data || {});
    if (slot && sig === bannerSig) return;           /* unchanged: keep rotation running */
    bannerSig = sig;
    window.clearInterval(bannerTimer);
    if (!slot) { slot = $('div', 'dr-ad-slot'); homeTop.appendChild(slot); }
    slot.hidden = false; sizeBanner();
    const ads = (Array.isArray(data && data.ads) ? data.ads : [])
      .filter(x => x && safeUrl(x.image_url) && notExpired(x));
    if (!ads.length) { slot.replaceChildren(placeholder(data || {})); return; }

    const first = ads[0], link = safeUrl(first.url);
    const a = $(link ? 'a' : 'div', 'dr-ad');
    const tag = $('span', 'dr-ad-tag'); tag.textContent = data.label || 'Ad';
    const imgs = ads.map((x, i) => {
      const im = $('img', 'dr-ad-img' + (i === 0 ? ' on' : ''));
      im.alt = x.alt || 'Advertisement'; im.decoding = 'async'; im.referrerPolicy = 'no-referrer';
      im.draggable = false; im.src = safeUrl(x.image_url);
      return im;
    });
    let cur = 0, broken = 0;
    const setLink = () => {
      const x = ads[cur], u = safeUrl(x.url);
      if (u) { a.href = u; a.target = '_blank'; a.rel = 'noopener noreferrer sponsored'; } else { a.removeAttribute('href'); }
      a.setAttribute('aria-label', x.alt || 'Advertisement');
    };
    a.addEventListener('click', ev => { const u = safeUrl(ads[cur].url); if (u) openAd(u, ev); else ev.preventDefault(); });
    imgs.forEach(im => im.addEventListener('error', () => {
      broken++; im.remove();                           /* never show a broken image */
      if (broken >= ads.length) slot.replaceChildren(placeholder(data));
    }));
    a.append(...imgs, tag); setLink();
    slot.replaceChildren(a);
    if (ads.length > 1) {
      const secs = Math.max(4, Number(data.rotate_seconds) || 8);
      bannerTimer = window.setInterval(() => {
        const live = imgs.filter(im => im.isConnected);
        if (live.length < 2) return;
        const from = imgs[cur]; let n = cur;
        do { n = (n + 1) % imgs.length; } while (!imgs[n].isConnected);
        from.classList.remove('on'); imgs[n].classList.add('on'); cur = n; setLink();
      }, secs * 1000);
    }
  }

  /* Banner width always equals the width of the time above it (never longer), height follows a 4.5:1 ratio. */
  function sizeBanner() {
    const slot = document.querySelector('.dr-ad-slot'), t = document.getElementById('clockTime');
    if (!slot || !t || slot.hidden) return;
    const txt = String(t.textContent || '');
    if (!/\d/.test(txt)) return;                        /* clock not filled in yet */
    const rg = document.createRange();
    rg.selectNodeContents(t);                            /* the time text's own box, exactly */
    const w = Math.floor(rg.getBoundingClientRect().width);
    if (w < 90) return;
    const h = Math.max(34, Math.round(w / 4.5));
    slot.style.width = w + 'px'; slot.style.height = h + 'px'; slot.style.setProperty('--h', h + 'px');
    const ct = t.parentNode && t.parentNode.getBoundingClientRect ? t.parentNode.getBoundingClientRect() : null;
    if (ct && ct.right) slot.style.right = Math.max(0, Math.round(window.innerWidth - ct.right)) + 'px';
  }
  window.addEventListener('resize', sizeBanner);
  window.setInterval(sizeBanner, 2500);
  function showNotice(n) {
    if (!n || n.enabled !== true || !n.message || n.popup === false) return;
    if (n.expires) {
      const expiry = /^\d{4}-\d{2}-\d{2}$/.test(String(n.expires))
        ? Date.parse(String(n.expires) + 'T23:59:59') : Date.parse(n.expires);
      if (Number.isFinite(expiry) && Date.now() > expiry) return;
    }
    const id = String(n.id || n.updated_at || n.title || n.message);
    if (id === lastNoticeId) return;
    lastNoticeId = id;
    try { localStorage.setItem('dr_receiver_notice_seen', id); } catch (_) {}
    if (n.beep !== false) beep();
    const back = $('div','dr-notice-backdrop'), card=$('section','dr-notice-card');
    const h=$('h2');h.textContent=n.title||'Deeprowss Notice';
    const p=$('p');p.textContent=n.message;
    const actions=$('div','dr-notice-actions');
    const close=$('button');close.type='button';close.textContent=n.ok_text||'Close';close.onclick=()=>back.remove();actions.appendChild(close);
    if(n.button_url){const a=$('a');a.href=n.button_url;a.target='_blank';a.rel='noopener';a.textContent=n.button_text||'Open';actions.appendChild(a);}
    card.append(h,p,actions);back.appendChild(card);document.body.appendChild(back);
    if ('Notification' in window && Notification.permission === 'granted' && document.hidden) {
      try { new Notification(n.title||'Deeprowss Notice',{body:n.message,tag:id}); } catch (_) {}
    }
  }
  async function getJson(url) {
    const r=await fetch(url+'?v='+Date.now(),{cache:'no-store',headers:{'Cache-Control':'no-cache'}});
    if(!r.ok) throw new Error('HTTP '+r.status);return r.json();
  }
  async function refresh(){
    try { const t=await getJson(TICKER_URL); addTicker(t); } catch(_){}
    try { const n=await getJson(NOTICE_URL); showNotice(n); } catch(_){}
    try { const b=await getJson(BANNER_URL); addBanner(b); } catch(_){ if(!bannerSig) addBanner({enabled:true,ads:[]}); }
  }
  refresh(); window.setInterval(refresh,60000);
})();
