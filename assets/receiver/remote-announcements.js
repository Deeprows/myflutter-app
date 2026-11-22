/* Receiver-only remote ticker and notice. Shared by URL receiver, Windows EXE and Android TV receiver. */
(() => {
  'use strict';
  const BASE = 'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/';
  const TICKER_URL = BASE + 'receiver_ticker.json';
  const NOTICE_URL = BASE + 'receiver_notice.json';
  const $ = (tag, cls) => { const n = document.createElement(tag); if (cls) n.className = cls; return n; };
  const css = document.createElement('style');
  css.textContent = `
    .dr-remote-ticker{position:relative;z-index:5;display:flex;align-items:center;justify-content:center;overflow:hidden;width:min(100% - 48px,1100px);margin:4px auto 0;height:30px;border:1px solid #ffffff16;border-radius:999px;background:#080d16d9;color:#e8f4ff}
    .dr-remote-ticker[hidden]{display:none}.dr-ticker-track{display:flex;white-space:nowrap;will-change:transform;animation:drTickerScroll var(--dr-speed,36s) linear infinite}
    .dr-ticker-track span{padding:0 42px;font-size:13px;font-weight:700;letter-spacing:.02em}
    @keyframes drTickerScroll{from{transform:translateX(100%)}to{transform:translateX(-100%)}}
    .dr-notice-backdrop{position:fixed;inset:0;z-index:99999;display:grid;place-items:center;padding:20px;background:#000b;backdrop-filter:blur(8px)}
    .dr-notice-card{width:min(560px,94vw);padding:24px;border:1px solid #ffffff26;border-radius:18px;background:#111a27;color:#f5f7fb;box-shadow:0 24px 90px #000b}
    .dr-notice-card h2{margin:0 0 12px;font-size:clamp(20px,3vw,28px)}.dr-notice-card p{white-space:pre-wrap;line-height:1.65;color:#d5deea}
    .dr-notice-actions{display:flex;justify-content:flex-end;gap:10px;flex-wrap:wrap}.dr-notice-actions a,.dr-notice-actions button{border:0;border-radius:9px;padding:11px 16px;font-weight:800;text-decoration:none;background:#e11d48;color:white;cursor:pointer}.dr-notice-actions button{background:#263449;color:white}
    html.tv .dr-remote-ticker{height:40px;margin-top:8px}html.tv .dr-ticker-track span{font-size:18px}
    @media(max-width:600px){.dr-remote-ticker{width:calc(100% - 24px);margin-top:2px;height:27px}.dr-ticker-track span{font-size:11px;padding:0 28px}}
    @media(prefers-reduced-motion:reduce){.dr-ticker-track{animation:none;white-space:normal;text-align:center}}
  `;
  document.head.appendChild(css);

  let soundReady = false, lastNoticeId = '';
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
      if (homeTop) homeTop.insertAdjacentElement('afterend',el);
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
  function showNotice(n) {
    if (!n || n.enabled !== true || !n.message) return;
    if (n.expires && Date.parse(n.expires) && Date.now() > Date.parse(n.expires)) return;
    const id = String(n.id || n.updated_at || n.title || n.message);
    if (id === lastNoticeId) return;
    lastNoticeId = id;
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
  }
  refresh(); window.setInterval(refresh,60000);
})();
