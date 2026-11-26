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
    .dr-ad-slot{position:absolute;z-index:5;right:48px;top:110px;width:230px;height:300px;--w:230px;--h:300px;text-shadow:none;transition:width .35s ease,height .35s ease}
    .dr-ad-slot[hidden]{display:none}
    .dr-ad{position:relative;display:block;width:100%;height:100%;overflow:hidden;border-radius:calc(var(--w)*.075);border:1px solid rgba(var(--ar,29,180,234),.4);background:#0a121d;color:#fff;text-decoration:none;cursor:pointer;box-shadow:0 12px 34px #000a,0 0 0 1px #00000040;transition:transform .18s ease,box-shadow .18s ease,border-color .18s ease}
    .dr-ad:hover,.dr-ad:focus-visible{transform:translateY(-2px) scale(1.02);border-color:rgba(var(--ar,29,180,234),.8);box-shadow:0 18px 44px #000b,0 0 28px rgba(var(--ar,29,180,234),.35)}
    .dr-ad:focus-visible,html.tv .dr-ad:focus{outline:4px solid #fff;outline-offset:3px}
    .dr-ad-img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;opacity:0;transition:opacity .6s ease}
    .dr-ad-img.on{opacity:1}
    .dr-ad-tag{position:absolute;z-index:2;left:calc(var(--w)*.045);top:calc(var(--w)*.045);padding:2px calc(var(--w)*.035);border-radius:5px;background:#050a12b3;backdrop-filter:blur(4px);font-weight:800;font-size:max(9px,calc(var(--w)*.045));line-height:1.35;letter-spacing:.18em;color:#cfe9f7;text-transform:uppercase;pointer-events:none}
    .dr-ad-ph{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:calc(var(--w)*.05);padding:calc(var(--w)*.1);text-align:center;background:radial-gradient(130% 80% at 50% 0%,rgba(var(--ar,29,180,234),.28),#0000 65%),linear-gradient(170deg,#0e1b2c,#08111d 75%)}
    .dr-ad-ph::before{content:'';position:absolute;inset:6px;border:1.5px dashed rgba(var(--ar,29,180,234),.45);border-radius:calc(var(--w)*.06);pointer-events:none}
    .dr-ad-ph::after{content:'';position:absolute;top:0;bottom:0;width:calc(var(--w)*.4);left:-80px;background:linear-gradient(100deg,#0000,#ffffff26,#0000);transform:skewX(-18deg);animation:drAdShine 5.5s ease-in-out infinite}
    .dr-ad-ico{flex:none;width:calc(var(--w)*.28);height:calc(var(--w)*.28);border-radius:calc(var(--w)*.08);display:grid;place-items:center;background:linear-gradient(145deg,var(--accent2,#6fd6fb),var(--accent,#0b84b8));box-shadow:0 8px 22px rgba(var(--ar,29,180,234),.45)}
    .dr-ad-ico svg{width:55%;height:55%;fill:none;stroke:var(--ink,#03121b);stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
    .dr-ad-txt{min-width:0;display:flex;flex-direction:column;align-items:center;gap:calc(var(--w)*.03)}
    .dr-ad-txt b{font-size:calc(var(--w)*.088);line-height:1.15;font-weight:900;letter-spacing:.12em;color:#fff}
    .dr-ad-txt small{font-size:calc(var(--w)*.056);line-height:1.3;font-weight:600;letter-spacing:.02em;color:#9fb6c9}
    .dr-ad-go{flex:none;margin-top:calc(var(--w)*.02);padding:calc(var(--w)*.02) calc(var(--w)*.07);border-radius:999px;background:var(--accent,#1db4ea);color:var(--ink,#03121b);font-size:calc(var(--w)*.06);font-weight:900;letter-spacing:.06em;line-height:1.3;transition:transform .18s ease}
    .dr-ad:hover .dr-ad-go,.dr-ad:focus-visible .dr-ad-go{transform:scale(1.06)}
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
    if (url) { const go = $('span', 'dr-ad-go'); go.textContent = 'Advertise with us'; box.appendChild(go); }
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
    /* If an image will not load, try other routes before giving up:
       1) the jsDelivr copy (for GitHub raw links), 2) the Windows app downloading it itself. */
    const mirrorOf = u => { const m = String(u).match(/^https:\/\/raw\.githubusercontent\.com\/([^/]+)\/([^/]+)\/([^/?#]+)\/([^?#]+)/i); return m ? 'https://cdn.jsdelivr.net/gh/' + m[1] + '/' + m[2] + '@' + m[3] + '/' + m[4] : ''; };
    imgs.forEach((im, i) => im.addEventListener('error', () => {
      const orig = safeUrl(ads[i].image_url), step = (im._dwStep || 0) + 1; im._dwStep = step;
      const giveUp = () => { if (!im.isConnected || im._dwDead) return; im._dwDead = true; broken++; im.remove(); if (broken >= ads.length) slot.replaceChildren(placeholder(data)); };
      const desk = window.deeprowssDesktop;
      const viaApp = () => {
        if (desk && typeof desk.fetchImage === 'function' && /^https:/i.test(orig)) {
          Promise.resolve(desk.fetchImage(orig)).then(d => { if (d && im.isConnected) im.src = d; else giveUp(); }).catch(giveUp);
        } else giveUp();
      };
      const mir = mirrorOf(orig);
      if (step === 1 && mir) { im.src = mir; return; }
      if (step <= 2) { viaApp(); return; }
      giveUp();                                        /* never show a broken image */
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

  /* Banner width always equals the width of the time above it. The height is now tall (portrait, about 1.3 x the width),
     limited so it never runs down into the home tiles on shorter screens. */
  function sizeBanner() {
    const slot = document.querySelector('.dr-ad-slot'), t = document.getElementById('clockTime');
    if (!slot || !t || slot.hidden) return;
    const txt = String(t.textContent || '');
    if (!/\d/.test(txt)) return;                        /* clock not filled in yet */
    const rg = document.createRange();
    rg.selectNodeContents(t);                            /* the time text's own box, exactly */
    const w = Math.floor(rg.getBoundingClientRect().width);
    if (w < 90) return;
    /* Sit just under the whole clock block (place, time and date) so the banner never covers the date line. */
    const ht = slot.parentNode, cb = t.parentNode && t.parentNode.getBoundingClientRect ? t.parentNode.getBoundingClientRect() : null;
    if (ht && cb && ht.getBoundingClientRect) slot.style.top = Math.max(60, Math.round(cb.bottom - ht.getBoundingClientRect().top + 16)) + 'px';
    const top = parseFloat(slot.style.top) || parseFloat(window.getComputedStyle(slot).top) || 110;
    const room = Math.round(window.innerHeight * 0.62 - top);
    const h = Math.max(Math.round(w * 0.8), Math.min(Math.round(w * 1.3), room));
    slot.style.width = w + 'px'; slot.style.height = h + 'px';
    slot.style.setProperty('--w', w + 'px'); slot.style.setProperty('--h', h + 'px');
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
  /* Plain GET (no custom headers) so browsers never need a CORS preflight to raw.githubusercontent.com;
     if GitHub is unreachable, the same file is read from the jsDelivr mirror. */
  const MIRROR = 'https://cdn.jsdelivr.net/gh/Deeprows/myflutter-app@main/assets/data/';
  async function getJson(url) {
    const stamp = '?v=' + Date.now();
    try {
      const r = await fetch(url + stamp, { cache: 'no-store' });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return await r.json();
    } catch (e) {
      const name = url.slice(url.lastIndexOf('/') + 1);
      const r2 = await fetch(MIRROR + name + stamp, { cache: 'no-store' });
      if (!r2.ok) throw e;
      return r2.json();
    }
  }
  async function refresh(){
    try { const t=await getJson(TICKER_URL); addTicker(t); } catch(_){}
    try { const n=await getJson(NOTICE_URL); showNotice(n); } catch(_){}
    try { const b=await getJson(BANNER_URL); addBanner(b); try { localStorage.setItem('dr_banner_last', JSON.stringify(b)); } catch(_){} }
    catch(_){
      if(!bannerSig){ let last=null; try { last=JSON.parse(localStorage.getItem('dr_banner_last')||'null'); } catch(_){} addBanner(last||{enabled:true,ads:[]}); }
    }
  }
  refresh(); window.setInterval(refresh,60000);
})();
