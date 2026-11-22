/* Deeprowss receiver · Fixtures page (website, Windows app, Android TV).
   Lists live and upcoming football matches from fixtures.json (the same file the app uses) and
   refreshes whenever that file changes. Match streams are never played here: tapping a match
   opens a popup that sends the visitor to the Deeprowss app, or to Smart Decoder to cast it
   to this screen. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const ROOT = 'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/';
  const DEFAULT_MIN = 130;
  const REFRESH_MS = 2 * 60 * 1000;
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  let fixtures = [], cfg = {}, league = 'All', loaded = false, failed = false, modalOpen = false, rendered = '';\n  const scores = new Map(); let scoreBusy = false; const SCORE_POLL_MS = 45000;

  /* ---------- data ---------- */
  async function getJson(name) {
    for (const u of [ROOT + name, 'data/' + name, '../data/' + name]) {
      try {
        const r = await fetch(u + '?_f=' + Date.now(), { cache: 'no-store' });
        if (r.ok) return await r.json();
      } catch (_) {}
    }
    return null;
  }
  function parse(raw) {
    if (!raw || typeof raw !== 'object') return null;
    const s = k => String(raw[k] == null ? '' : raw[k]).trim();
    let k = s('kickoff');
    // A time with no zone is read as Nigeria time (+01:00), exactly like the app.
    if (k && !/(Z|[+-]\d{2}:?\d{2})$/i.test(k) && /[T ]/.test(k)) k += '+01:00';
    const t = Date.parse(k);
    if (!s('home') || !s('away') || Number.isNaN(t)) return null;
    return {
      id: s('id') || s('home') + '-' + s('away') + '-' + s('kickoff'),
      home: s('home'), away: s('away'), homeLogo: s('homeLogo'), awayLogo: s('awayLogo'),
      league: s('league') || 'Football', start: t, mins: parseInt(s('duration'), 10) || DEFAULT_MIN,
      url: s('url'), altUrl: s('altUrl'), referer: s('referer'), ua: s('ua'), scoreLeague: s('scoreLeague')
    };
  }
  async function load() {
    const [list, conf] = await Promise.all([getJson('fixtures.json'), getJson('app_config.json')]);
    if (conf) cfg = conf;
    if (Array.isArray(list)) { fixtures = list.map(parse).filter(Boolean); loaded = true; failed = false; }
    else if (!loaded) failed = true;
    render(false);
  }
  const phase = (f, now) => now < f.start ? 'upcoming' : (now < f.start + f.mins * 60000 ? 'live' : 'ended');
  // ESPN scoreboard: same public feed and 45-second refresh cadence as the Deeprowss app.
  const scoreNorm = value => String(value || '').toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, ' ').trim().split(/\\s+/).filter(x => x && !['fc','cf','afc','sc','ac','as','ssc','cd','ud','fk','sk','bk','club','the','sv'].includes(x))
    .map(x => ({man:'manchester',utd:'united',spurs:'tottenham',wolves:'wolverhampton',atleti:'atletico',intl:'international',st:'saint',nottm:'nottingham',notts:'nottingham'}[x] || x));
  const teamMatch = (fixture, candidates) => {
    const a = scoreNorm(fixture); if (!a.length) return false;
    return candidates.some(name => {
      const b = scoreNorm(name); if (!b.length) return false;
      const short = a.length <= b.length ? a : b, long = a.length <= b.length ? b : a;
      if (short.every(x => long.some(y => x === y || (x.length >= 3 && y.startsWith(x)) || (y.length >= 3 && x.startsWith(y))))) {
        return !long.some(x => ['women','u17','u18','u19','u20','u21','u23','reserves'].includes(x) && !short.includes(x));
      }
      return false;
    });
  };
  function scoreTargets(now) { return fixtures.filter(f => now - f.start <= 12*3600000 && f.start - now <= 30*60000); }
  function utcDate(ms) { const d = new Date(ms); return d.getUTCFullYear()+String(d.getUTCMonth()+1).padStart(2,'0')+String(d.getUTCDate()).padStart(2,'0'); }
  async function scoreEvents(url, date) {
    try {
      const u = new URL(url); u.searchParams.set('dates', date);
      const r = await fetch(u.href, {cache:'no-store'}); if (!r.ok) return [];
      const json = await r.json(), out = [];
      for (const e of (json.events || [])) {
        const comp = e.competitions && e.competitions[0]; if (!comp) continue;
        const list = comp.competitors || [];
        const home = list.find(c => c.homeAway === 'home'), away = list.find(c => c.homeAway === 'away');
        if (!home || !away) continue;
        const status = comp.status || e.status || {}, type = status.type || {};
        const state = String(type.state || '');
        const statusName = String(type.name || '').toUpperCase();
        if (!['in','post'].includes(state) || /POSTPON|CANCEL|ABANDON|FORFEIT|SUSPEND|DELAY/.test(statusName)) continue;
        const teamNames = c => { const t = c.team || {}; return ['displayName','shortDisplayName','name','location','abbreviation'].map(k=>t[k]).filter(Boolean); };
        const dc = String(status.displayClock || '').trim(), sd = String(type.shortDetail || '').trim();
        const clock = state === 'in' ? (statusName.includes('HALF') && !statusName.includes('FIRST') && !statusName.includes('SECOND') ? 'HT' : (dc && dc !== "0'" ? dc : sd)) : (sd || 'FT');
        out.push({homeNames:teamNames(home),awayNames:teamNames(away),home:Number(home.score)||0,away:Number(away.score)||0,state,clock,date:Date.parse(e.date || comp.date || '')});
      }
      return out;
    } catch (_) { return []; }
  }
  async function refreshScores() {
    const config = cfg.scores || {};
    if (scoreBusy || config.enabled === false) return;
    const targets = scoreTargets(Date.now()); if (!targets.length) return;
    scoreBusy = true;
    try {
      const base = String(config.url || 'https://site.api.espn.com/apis/site/v2/sports/soccer/all/scoreboard');
      const dates = new Set(); targets.forEach(f => { const d = new Date(f.start).getTime(); dates.add(utcDate(d)); dates.add(utcDate(d-86400000)); });
      const events = []; for (const date of dates) events.push(...await scoreEvents(base,date));
      const found = new Map();
      const findScore = (f, rows) => {
        let best = null, bestGap = Infinity;
        for (const e of rows) {
          const straight = teamMatch(f.home,e.homeNames) && teamMatch(f.away,e.awayNames);
          const flipped = !straight && teamMatch(f.home,e.awayNames) && teamMatch(f.away,e.homeNames);
          if (!straight && !flipped) continue;
          const gap = Number.isFinite(e.date) ? Math.abs(e.date-f.start) : 0;
          if (gap > 8*3600000 || gap >= bestGap) continue;
          bestGap=gap; best={home:flipped?e.away:e.home,away:flipped?e.home:e.away,clock:e.clock,live:e.state==='in',finished:e.state==='post'};
        }
        return best;
      };
      targets.forEach(f => { const s=findScore(f,events); if(s)found.set(f.id,s); });
      if (base.includes('/all/')) for (const f of targets) {
        if (found.has(f.id) || !f.scoreLeague) continue;
        const url=base.replace('/all/','/'+f.scoreLeague+'/'), more=[];
        for (const date of [utcDate(f.start),utcDate(f.start-86400000)]) more.push(...await scoreEvents(url,date));
        const s=findScore(f,more); if(s)found.set(f.id,s);
      }
      let changed=false; for(const [id,s] of found){if(JSON.stringify(scores.get(id))!==JSON.stringify(s)){scores.set(id,s);changed=true;}}
      if(changed){render(true);}
    } finally { scoreBusy=false; }
  }
  const visible = now => fixtures.filter(f => phase(f, now) !== 'ended')
    .sort((a, b) => (phase(a, now) === 'live' ? 0 : 1) - (phase(b, now) === 'live' ? 0 : 1) || a.start - b.start);

  /* ---------- formatting ---------- */
  const timeOf = ms => new Date(ms).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  function dayKey(ms) { const d = new Date(ms); return d.getFullYear() + '-' + d.getMonth() + '-' + d.getDate(); }
  function dayLabel(ms) {
    const now = Date.now(), d = new Date(ms);
    if (dayKey(ms) === dayKey(now)) return 'Today';
    if (dayKey(ms) === dayKey(now + 86400000)) return 'Tomorrow';
    return d.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' });
  }
  function countdown(f, now) {
    const ph = phase(f, now);
    if (ph === 'live') { const m = Math.max(1, Math.floor((now - f.start) / 60000)); return 'Live now · ' + m + '\u2032'; }
    const mins = Math.max(0, Math.round((f.start - now) / 60000));
    if (mins < 1) return 'Starting now';
    if (mins < 60) return 'Starts in ' + mins + ' min';
    if (mins < 24 * 60) return 'Starts in ' + Math.floor(mins / 60) + 'h ' + String(mins % 60).padStart(2, '0') + 'm';
    return timeOf(f.start);
  }
  function logo(v, name) {
    const ini = '<span class="fx-ini">' + esc(name.trim().charAt(0).toUpperCase()) + '</span>';
    let url = '';
    if (/^\d+$/.test(v)) url = 'https://media.api-sports.io/football/teams/' + v + '.png';
    else if (/^https?:\/\//i.test(v)) url = v;
    return '<span class="fx-logo">' + ini + (url ? '<img loading="lazy" decoding="async" referrerpolicy="no-referrer" alt="" src="' + esc(url) + '">' : '') + '</span>';
  }

  /* ---------- styles ---------- */
  const css = document.createElement('style');
  css.textContent = `
  .tiles{grid-template-columns:repeat(4,minmax(0,1fr));max-width:1380px}
  @media(max-width:1100px) and (min-width:821px){.tiles .tile small{font-size:13px}.tile b{font-size:24px}}
  @media(max-width:820px){.tiles{grid-template-columns:1fr;gap:10px}.tile{height:78px}.tile svg{top:16px;width:42px;height:42px}.fx-badge{top:50%;right:14px;transform:translateY(-50%)}}
  .fx-badge{position:absolute;right:18px;top:18px;display:none;align-items:center;gap:7px;padding:5px 11px;border-radius:999px;background:#e5484d;color:#fff;font-size:11px;font-weight:900;letter-spacing:.12em}
  .fx-badge.on{display:inline-flex}.fx-badge i{width:7px;height:7px;border-radius:50%;background:#fff;animation:fxp 1.2s infinite}
  @keyframes fxp{50%{opacity:.25}}
  #fixturesView .fx-body{max-width:1400px;margin:0 auto;padding:6px 20px 46px}
  .fx-sub{margin:0 0 4px;padding:4px 2px 0;font-size:15px;color:var(--muted,#8fa0b5)}
  .fx-chips{display:flex;gap:10px;overflow-x:auto;padding:12px 0 6px;scrollbar-width:none}.fx-chips::-webkit-scrollbar{display:none}
  .fx-day{display:flex;align-items:baseline;gap:12px;margin:22px 2px 12px}
  .fx-day h3{margin:0;font-size:22px;font-weight:700}.fx-day span{font-size:13px;color:var(--muted,#8fa0b5);letter-spacing:.06em}
  .fx-day.live h3{color:#ff6b6f}
  .fx-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(310px,1fr));gap:14px}
  .fxcard{position:relative;display:block;width:100%;padding:16px 18px;text-align:left;color:#fff;background:linear-gradient(160deg,#142233f2,#0b131df2);border:1px solid #2c3d52;border-radius:18px;transition:transform .15s,border-color .15s,box-shadow .15s}
  .fxcard:hover,.fxcard:focus-visible{transform:translateY(-4px);border-color:var(--accent,#1db4ea);box-shadow:0 0 0 2px var(--accent,#1db4ea),0 18px 44px #000a;outline:none}
  .fxcard.live{border-color:#e5484d99}
  .fx-top{display:flex;justify-content:space-between;align-items:center;gap:10px;margin-bottom:12px;font-size:11px;font-weight:800;letter-spacing:.1em;text-transform:uppercase;color:var(--accent2,#6fd6fb)}
  .fx-top span:first-child{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-width:0}
  .fx-pill{flex:none;padding:4px 10px;border-radius:999px;background:#ffffff14;color:#e9f0f7;letter-spacing:.06em}
  .fxcard.live .fx-pill{background:#e5484d;color:#fff}
  .fx-team{display:flex;align-items:center;gap:12px;padding:5px 0;font-size:18px;font-weight:700;line-height:1.2}
  .fx-team b{font-weight:700;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}\n  .fx-score{display:flex;align-items:center;justify-content:center;gap:9px;margin:2px 0 3px;color:#fff;font-variant-numeric:tabular-nums}.fx-score b{font-size:17px;font-weight:950;letter-spacing:.04em}.fx-score>span:last-child{font-size:11px;font-weight:800;color:#ff8f93}.fx-score-brand{font-size:9px;font-weight:950;letter-spacing:.1em;color:#9fb2c7;padding:3px 5px;border:1px solid #ffffff20;border-radius:5px}
  .fx-logo{position:relative;flex:none;width:38px;height:38px;border-radius:50%;display:grid;place-items:center;background:#ffffff10;border:1px solid #ffffff18;overflow:hidden}
  .fx-logo img{position:absolute;inset:0;width:100%;height:100%;padding:5px;object-fit:contain}
  .fx-ini{font-size:15px;font-weight:900;color:#9fb2c7}
  .fx-foot{display:flex;justify-content:space-between;align-items:center;gap:10px;margin-top:12px;padding-top:12px;border-top:1px solid #ffffff12;font-size:13px;color:#aebdce}
  .fxcard.live .fx-foot .fx-when{color:#ff8f93;font-weight:800}
  .fx-watch{flex:none;display:inline-flex;align-items:center;gap:6px;padding:6px 12px;border-radius:999px;background:var(--accent,#1db4ea);color:#03121b;font-size:12px;font-weight:900}
  .fx-empty{padding:60px 18px;text-align:center;line-height:1.7;color:var(--muted,#8fa0b5)}
  .fx-skel{height:150px;border-radius:18px;background:linear-gradient(90deg,#0f1a27,#16253a,#0f1a27);background-size:200% 100%;animation:sh 1.2s infinite}
  .fx-sheet{z-index:90;align-items:center}
  .fx-pop{position:relative;width:min(100%,480px);margin:auto;padding:28px 26px 24px;background:#0d1520;border:1px solid #2c3d52;border-radius:26px;box-shadow:0 30px 90px #000c;animation:up .25s ease both;max-height:94dvh;overflow-y:auto}
  .fx-pop .fx-x{position:absolute;top:10px;right:10px;width:38px;height:38px;padding:0;border-radius:50%;background:#16222f;border:1px solid #2c3d52;color:#fff;font-size:15px}
  .fx-match{display:flex;align-items:center;justify-content:center;gap:14px;margin:4px 0 6px}
  .fx-match .fx-logo{width:52px;height:52px}.fx-match span.vs{font-size:12px;font-weight:900;letter-spacing:.12em;color:#7f90a5}
  .fx-pop h2{margin:8px 0 4px;text-align:center;font-size:21px;font-weight:800;line-height:1.25}
  .fx-meta{margin:0 0 16px;text-align:center;font-size:13px;color:#8fa0b5}
  .fx-opts{display:grid;gap:10px;margin:0 0 16px}
  .fx-opt{display:flex;gap:13px;align-items:flex-start;padding:13px 14px;border-radius:16px;background:#101b28;border:1px solid #233246}
  .fx-opt .ic{flex:none;width:38px;height:38px;border-radius:12px;display:grid;place-items:center;font-size:19px;background:#1db4ea1f;border:1px solid #1db4ea44}
  .fx-opt b{display:block;font-size:15px;margin-bottom:2px}.fx-opt p{margin:0;font-size:13px;line-height:1.5;color:#aebdce}
  .fx-pop .fx-dl{width:100%;min-height:52px;font-size:16px;margin-bottom:10px}
  .fx-stream-choices{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:12px}
  .fx-stream-choices .fx-dl{margin:0}
  @media(max-width:420px){.fx-stream-choices{grid-template-columns:1fr}}
  .fx-pop .fx-connect{width:100%;min-height:46px}
  .fx-ver{margin-top:12px;text-align:center;font-size:11px;letter-spacing:.08em;color:#7f90a5}
  @media(max-width:600px){#fixturesView .fx-body{padding:4px 14px 40px}.fx-grid{grid-template-columns:1fr}}
  `;
  document.head.appendChild(css);

  /* ---------- home tile ---------- */
  function addTile() {
    const nav = document.querySelector('#landing .tiles');
    if (!nav || $('goFixtures')) return;
    const b = document.createElement('button');
    b.type = 'button'; b.className = 'tile'; b.id = 'goFixtures'; b.dataset.go = 'fixtures';
    b.innerHTML = '<svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="17" rx="2"/><path d="M3 9h18M8 2v4M16 2v4M8 14h3M13 14h3M8 18h3"/></svg>' +
      '<span class="fx-badge" id="fxBadge"><i></i><span id="fxBadgeTxt">LIVE</span></span>' +
      '<b>Fixtures</b><small>Upcoming live football matches</small>';
    b.addEventListener('click', () => { if (window.deeprowssGo) window.deeprowssGo('fixtures'); else location.hash = 'fixtures'; });
    const connect = $('goConnect');
    nav.insertBefore(b, connect || null); // Movies, TV Channels, Fixtures, Connect with App
  }

  /* ---------- page ---------- */
  function leagues(list) { return ['All', ...Array.from(new Set(list.map(f => f.league))).sort()]; }
  function cardHtml(f, now) {
    const ph = phase(f, now);
    return '<button type="button" class="fxcard ' + ph + '" data-id="' + esc(f.id) + '" aria-label="' + esc(f.home + ' vs ' + f.away) + '">' +
      '<div class="fx-top"><span>' + esc(f.league) + '</span><span class="fx-pill">' + (ph === 'live' ? '● LIVE' : esc(timeOf(f.start))) + '</span></div>' +
      '<div class="fx-team">' + logo(f.homeLogo, f.home) + '<b>' + esc(f.home) + '</b></div>' +
      (scores.has(f.id) ? '<div class="fx-score"><span class="fx-score-brand">ESPN</span><b>' + scores.get(f.id).home + ' - ' + scores.get(f.id).away + '</b><span>' + esc(scores.get(f.id).clock) + '</span></div>' : '') +
      '<div class="fx-team">' + logo(f.awayLogo, f.away) + '<b>' + esc(f.away) + '</b></div>' +
      '<div class="fx-foot"><span class="fx-when" data-s="' + f.start + '" data-e="' + (f.start + f.mins * 60000) + '">' + esc(countdown(f, now)) + '</span>' +
      '<span class="fx-watch">▶ Watch</span></div></button>';
  }
  function render(force) {
    const root = $('fxList'); if (!root) return;
    const now = Date.now(), all = visible(now);
    const live = all.filter(f => phase(f, now) === 'live').length;
    const badge = $('fxBadge');
    if (badge) { badge.classList.toggle('on', live > 0); $('fxBadgeTxt').textContent = live + ' LIVE'; }
    const names = leagues(all);
    if (!names.includes(league)) league = 'All';
    const list = league === 'All' ? all : all.filter(f => f.league === league);
    const sig = [league, names.join('|'), list.map(f => [f.id, f.home, f.away, f.start, f.league, f.homeLogo, f.awayLogo, scores.has(f.id) ? JSON.stringify(scores.get(f.id)) : '', phase(f, now)].join('~')).join(',')].join('#');
    if (!force && sig === rendered) return;
    rendered = sig;

    const chips = $('fxChips');
    chips.innerHTML = names.length > 2 ? names.map(n => '<button type="button" class="chip' + (n === league ? ' on' : '') + '" data-l="' + esc(n) + '">' + esc(n) + '</button>').join('') : '';
    $('fxCount').textContent = all.length ? all.length + (all.length === 1 ? ' match' : ' matches') + (live ? ' · ' + live + ' live now' : '') : '';

    if (!loaded) { root.innerHTML = failed ? '<div class="fx-empty">Could not load fixtures.<br>Check your connection and press refresh.</div>' : '<div class="fx-grid"><div class="fx-skel"></div><div class="fx-skel"></div><div class="fx-skel"></div></div>'; return; }
    if (!list.length) { root.innerHTML = '<div class="fx-empty">No live or upcoming matches right now.<br>New fixtures appear here as soon as they are added.</div>'; return; }

    const groups = [], liveList = list.filter(f => phase(f, now) === 'live');
    if (liveList.length) groups.push({ cls: 'live', title: 'Live now', sub: liveList.length + (liveList.length === 1 ? ' match' : ' matches'), items: liveList });
    const byDay = new Map();
    list.filter(f => phase(f, now) === 'upcoming').forEach(f => { const k = dayKey(f.start); if (!byDay.has(k)) byDay.set(k, { cls: '', title: dayLabel(f.start), sub: '', items: [] }); byDay.get(k).items.push(f); });
    byDay.forEach(g => { g.sub = g.items.length + (g.items.length === 1 ? ' match' : ' matches'); groups.push(g); });
    root.innerHTML = groups.map(g => '<div class="fx-day ' + g.cls + '"><h3>' + esc(g.title) + '</h3><span>' + esc(g.sub) + '</span></div><div class="fx-grid">' + g.items.map(f => cardHtml(f, now)).join('') + '</div>').join('');
  }
  function tick() {
    const now = Date.now();
    let changed = false;
    document.querySelectorAll('#fxList .fx-when').forEach(el => {
      const s = Number(el.dataset.s), e = Number(el.dataset.e), ph = now < s ? 'upcoming' : (now < e ? 'live' : 'ended');
      const card = el.closest('.fxcard');
      if (!card.classList.contains(ph)) { changed = true; return; }
      el.textContent = countdown({ start: s, mins: (e - s) / 60000 }, now);
    });
    if (changed) render(true); else render(false);
  }

  /* ---------- popup ---------- */
  const modal = document.createElement('div');
  modal.className = 'sheet fx-sheet'; modal.id = 'fxModal';
  modal.setAttribute('role', 'dialog'); modal.setAttribute('aria-modal', 'true'); modal.setAttribute('aria-label', 'Watch this match');
  const appUrl = () => {
    const u = (cfg.update && cfg.update.apkUrl) || (cfg.share && cfg.share.link) || '';
    try { const x = new URL(u); return /^https?:$/.test(x.protocol) ? x.href : ''; } catch (_) { return ''; }
  };
  const openDl = u => { if (window.deeprowssDesktop && window.deeprowssDesktop.openDownload) window.deeprowssDesktop.openDownload(u); else window.open(u, '_blank', 'noopener'); };
  const where = () => window.deeprowssDesktop ? 'this Windows app' : 'this screen';
  function openModal(f) {
    const url = appUrl(), ver = cfg.update && cfg.update.version, now = Date.now(), live = phase(f, now) === 'live';
    const allowAdPlayback = location.hostname === 'deeprowss.pages.dev' && !!f.url;
    modal.innerHTML = '<div class="fx-pop">' +
      '<button type="button" class="fx-x" id="fxX" aria-label="Close">✕</button>' +
      '<div class="fx-match">' + logo(f.homeLogo, f.home) + '<span class="vs">VS</span>' + logo(f.awayLogo, f.away) + '</div>' +
      '<h2>' + esc(f.home) + ' vs ' + esc(f.away) + '</h2>' +
      '<p class="fx-meta">' + esc(f.league) + ' · ' + (live ? 'Live now' : esc(dayLabel(f.start)) + ', ' + esc(timeOf(f.start))) + '</p>' +
      (allowAdPlayback ? '<button type="button" class="fx-dl" id="fxWatchAds">▶ Continue watching with ads</button>' : '') +
      '<div class="fx-opts">' +
        '<div class="fx-opt"><span class="ic">📱</span><div><b>Watch on your phone</b><p>Get the Deeprowss app and open this match from Fixtures. Live streams, scores and match analysis are all there.</p></div></div>' +
        '<div class="fx-opt"><span class="ic">📺</span><div><b>Watch on ' + where() + '</b><p>In the app, open <b>Smart Decoder</b>, choose <b>Send to receiver page</b> and scan the QR code under <b>Connect with App</b> here. The match then plays on ' + where() + '.</p></div></div>' +
      '</div>' +
      (url ? '<button type="button" class="fx-dl" id="fxDl">⬇ Download Deeprowss App</button>' : '<p class="fx-meta">The download link is not available right now. Please try again in a moment.</p>') +
      '<button type="button" class="secondary fx-connect" id="fxConnect">Connect with App</button>' +
      (ver ? '<div class="fx-ver">LATEST VERSION ' + esc(ver) + '</div>' : '') + '</div>';
    $('fxX').onclick = closeModal;
    const watchAds = $('fxWatchAds'); if (watchAds) watchAds.onclick = () => { closeModal(); if (window.deeprowssPlayFixture) window.deeprowssPlayFixture(f, false); else { const s = document.getElementById('playState'); if (s) s.textContent = 'Player is unavailable. Please refresh and try again.'; } };
    $('fxConnect').onclick = () => { closeModal(); if (window.deeprowssGo) window.deeprowssGo('connect'); };
    const dl = $('fxDl'); if (dl) dl.onclick = () => openDl(url);
    modal.classList.add('open'); modalOpen = true;
    setTimeout(() => { const el = $('fxDl') || $('fxConnect'); if (el) el.focus(); }, 40);
  }
  function closeModal() { modal.classList.remove('open'); modalOpen = false; }
  modal.addEventListener('click', e => { if (e.target === modal) closeModal(); });
  document.addEventListener('keydown', e => {
    if (!modalOpen) return;
    if (e.key === 'Escape' || e.key === 'Backspace') { e.preventDefault(); e.stopPropagation(); closeModal(); }
  }, true);
  const prevBack = window.deeprowssHandleBack;
  window.deeprowssHandleBack = () => { if (modalOpen) { closeModal(); return true; } return prevBack ? prevBack() : false; };

  /* ---------- start ---------- */
  addTile();
  document.body.appendChild(modal);
  const list = $('fxList');
  if (list) {
    list.addEventListener('click', e => {
      const c = e.target.closest('.fxcard'); if (!c) return;
      const f = fixtures.find(x => x.id === c.dataset.id); if (f) openModal(f);
    });
    $('fxChips').addEventListener('click', e => {
      const b = e.target.closest('[data-l]'); if (!b) return;
      league = b.dataset.l; render(true);
    });
    $('fxRefresh').onclick = () => { rendered = ''; load(); };
  }
  window.addEventListener('hashchange', () => { if (location.hash === '#fixtures') load(); });
  render(true);
  load();\n  refreshScores();\n  setInterval(() => { if (!document.hidden) load(); }, REFRESH_MS);\n  setInterval(() => { if (!document.hidden) refreshScores(); }, SCORE_POLL_MS);
  setInterval(() => { if (!document.hidden) tick(); }, 30000);
})();
