/* Deeprowss receiver · Fixtures page (website, Windows app, Android TV).
   Lists live and upcoming football matches from fixtures.json (the same file the app uses) and
   refreshes whenever that file changes. Every match card also shows the live ESPN scoreboard
   (score, minute / half-time / full-time) matched by league, team names and kick-off time.
   Tapping a match opens a popup: on deeprowss.pages.dev it can play Stream 1 or Stream 2 in the
   receiver player; elsewhere it sends the visitor to the Deeprowss app or to Smart Decoder. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const ROOT = 'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/';
  const DEFAULT_MIN = 130;
  const REFRESH_MS = 2 * 60 * 1000;
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  let fixtures = [], cfg = {}, league = 'All', loaded = false, failed = false, modalOpen = false, rendered = '';

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
      url: s('url'), altUrl: s('altUrl'), referer: s('referer'), ua: s('ua'),
      altReferer: s('altReferer'), altUa: s('altUa')
    };
  }
  async function load() {
    const [list, conf] = await Promise.all([getJson('fixtures.json'), getJson('app_config.json')]);
    if (conf) cfg = conf;
    if (Array.isArray(list)) { fixtures = list.map(parse).filter(Boolean); loaded = true; failed = false; }
    else if (!loaded) failed = true;
    render(false);
    espnLoad(false);
  }
  const phase = (f, now) => now < f.start ? 'upcoming' : (now < f.start + f.mins * 60000 ? 'live' : 'ended');
  const visible = now => fixtures.filter(f => phase(f, now) !== 'ended')
    .sort((a, b) => (phase(a, now) === 'live' ? 0 : 1) - (phase(b, now) === 'live' ? 0 : 1) || a.start - b.start);

  /* ---------- ESPN scoreboard ----------
     Public (unofficial) ESPN soccer scoreboard: site.api.espn.com/apis/site/v2/sports/soccer/<league>/scoreboard.
     The league name in fixtures.json ("Serie A - Italy") is mapped to an ESPN league code; anything we cannot
     map, or cannot find there, is looked up in ESPN's "all soccer" board. A match is paired with a fixture when
     both team names agree and ESPN's kick-off is within 18 hours of ours. Failures are silent: the card then
     just keeps its normal countdown. */
  const ESPN = 'https://site.api.espn.com/apis/site/v2/sports/soccer/';
  const ESPN_LIVE_MS = 25 * 1000, ESPN_IDLE_MS = 4 * 60 * 1000, ESPN_ALL_MS = 5 * 60 * 1000;
  let espn = new Map(), espnAt = 0, espnAllAt = 0, espnBusy = false;

  const plain = s => String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  const LEAGUES = [
    [/^premier league$/, /england|^$/, 'eng.1'],
    [/^championship$/, /england|^$/, 'eng.2'],
    [/^league one$/, /england|^$/, 'eng.3'],
    [/^league two$/, /england|^$/, 'eng.4'],
    [/^fa cup$/, null, 'eng.fa'],
    [/^(efl|carabao|league) cup$/, null, 'eng.league_cup'],
    [/^la ?liga$|^primera division$/, /spain|^$/, 'esp.1'],
    [/^la ?liga ?2$|^segunda division$/, null, 'esp.2'],
    [/^copa del rey$/, null, 'esp.copa_del_rey'],
    [/^serie a$/, /brazil/, 'bra.1'],
    [/^serie a$/, /italy|^$/, 'ita.1'],
    [/^serie b$/, /italy|^$/, 'ita.2'],
    [/^coppa italia$/, null, 'ita.coppa_italia'],
    [/^bundesliga$/, /germany|^$/, 'ger.1'],
    [/^2\.? ?bundesliga$/, null, 'ger.2'],
    [/^dfb[- ]pokal$/, null, 'ger.dfb_pokal'],
    [/^ligue 1$/, null, 'fra.1'],
    [/^ligue 2$/, null, 'fra.2'],
    [/^coupe de france$/, null, 'fra.coupe_de_france'],
    [/^eredivisie$/, null, 'ned.1'],
    [/^(primeira liga|liga portugal.*)$/, null, 'por.1'],
    [/^(scottish )?premiership$/, null, 'sco.1'],
    [/^super lig$/, null, 'tur.1'],
    [/^(belgian )?pro league$/, null, 'bel.1'],
    [/^(uefa )?champions league$/, null, 'uefa.champions'],
    [/^(uefa )?europa league$/, null, 'uefa.europa'],
    [/^(uefa )?(europa )?conference league$/, null, 'uefa.europa.conf'],
    [/^(mls|major league soccer)$/, null, 'usa.1'],
    [/^liga mx$/, null, 'mex.1'],
    [/^(liga profesional.*|primera division)$/, /argentina/, 'arg.1'],
    [/^saudi pro league$/, null, 'ksa.1']
  ];
  function slugFor(name) {
    const parts = String(name || '').split(/\s+-\s+/), n = plain(parts[0]).trim(), c = plain(parts[1] || '').trim();
    for (const [re, cre, slug] of LEAGUES) if (re.test(n) && (!cre || cre.test(c))) return slug;
    return '';
  }
  const ymd = ms => { const d = new Date(ms); return d.getUTCFullYear() + String(d.getUTCMonth() + 1).padStart(2, '0') + String(d.getUTCDate()).padStart(2, '0'); };

  const STOP = new Set(['fc', 'cf', 'afc', 'ac', 'as', 'sc', 'ssc', 'cd', 'ud', 'sd', 'rc', 'rcd', 'ca', 'the', 'club', 'de', 'del', 'and', 'sv', 'vfb', 'vfl', 'tsg', 'fsv', 'bsc', 'calcio']);
  const toks = s => plain(s).replace(/&/g, ' and ').replace(/[^a-z0-9]+/g, ' ').split(' ').filter(w => w && !STOP.has(w));
  function same(a, names) {
    const A = toks(a); if (!A.length) return false;
    return names.some(n => {
      const B = toks(n); if (!B.length) return false;
      const [s, l] = A.length <= B.length ? [A, B] : [B, A];
      return s.every(w => l.includes(w));
    });
  }
  const namesOf = c => { const t = (c && c.team) || {}; return [t.displayName, t.shortDisplayName, t.name, t.location]; };
  function parseEvent(ev) {
    const comp = ev && ev.competitions && ev.competitions[0];
    if (!comp || !Array.isArray(comp.competitors)) return null;
    const h = comp.competitors.find(c => c.homeAway === 'home'), a = comp.competitors.find(c => c.homeAway === 'away');
    if (!h || !a) return null;
    return { id: ev.id, t: Date.parse(ev.date || comp.date), ev, h, a, hn: namesOf(h), an: namesOf(a) };
  }
  function scoreInfo(e, swapped) {
    const st = e.ev.status || {}, type = st.type || {};
    const H = swapped ? e.a : e.h, A = swapped ? e.h : e.a;
    const num = c => { const v = String(c.score == null ? '' : c.score).trim(); return v === '' ? null : v; };
    const logoOf = c => String((c.team && c.team.logo) || '');
    let state = type.state || 'pre', detail = '', note = '';
    if (/POSTPONED|CANCEL|ABANDON|SUSPEND/i.test(type.name || '')) { state = 'pre'; note = String(type.shortDetail || type.description || 'Postponed'); }
    else if (state === 'in') {
      if (/half/i.test(type.name || type.description || '')) detail = 'Half-time';
      else { const clk = String(st.displayClock || type.shortDetail || '').replace(/'/g, '\u2032').trim(); detail = clk ? 'Live · ' + clk : 'Live now'; }
    } else if (state === 'post') {
      const d = String(type.shortDetail || type.detail || '');
      detail = /pen/i.test(d) ? 'Full time · pens' : (/aet|extra/i.test(d) ? 'Full time · AET' : 'Full time');
    }
    return { state, detail, note, hs: note ? null : num(H), aw: note ? null : num(A), homeLogo: logoOf(H), awayLogo: logoOf(A) };
  }
  function matchAll(list, events) {
    const out = new Map();
    for (const f of list) {
      let best = null, bd = Infinity;
      for (const e of events) {
        if (Number.isNaN(e.t)) continue;
        const d = Math.abs(e.t - f.start);
        if (d > 18 * 3600000 || d >= bd) continue;
        const straight = same(f.home, e.hn) && same(f.away, e.an), swapped = !straight && same(f.home, e.an) && same(f.away, e.hn);
        if (straight || swapped) { best = { e, swapped }; bd = d; }
      }
      if (best) out.set(f.id, scoreInfo(best.e, best.swapped));
    }
    return out;
  }
  async function fetchBoard(slug, dates) {
    try {
      const r = await fetch(ESPN + slug + '/scoreboard?dates=' + dates + '&limit=300', { cache: 'no-store' });
      if (!r.ok) return [];
      const j = await r.json();
      return Array.isArray(j.events) ? j.events : [];
    } catch (_) { return []; }
  }
  async function espnLoad(force) {
    if (espnBusy) return;
    const now = Date.now(), list = visible(now);
    if (!list.length) return;
    const live = list.some(f => phase(f, now) === 'live');
    if (!force && now - espnAt < (live ? ESPN_LIVE_MS : ESPN_IDLE_MS)) return;
    espnBusy = true;
    try {
      const slugs = new Set();
      let loose = false;
      list.forEach(f => { const s = slugFor(f.league); if (s) slugs.add(s); else loose = true; });
      const lo = Math.min(...list.map(f => f.start)) - 864e5;
      const hi = Math.min(Math.max(...list.map(f => f.start)) + 864e5, lo + 14 * 864e5);
      const dates = ymd(lo) + '-' + ymd(hi);
      const seen = new Set(), events = [];
      const take = boards => boards.forEach(b => b.forEach(ev => { if (!ev || seen.has(ev.id)) return; seen.add(ev.id); const p = parseEvent(ev); if (p) events.push(p); }));
      take(await Promise.all([...slugs].slice(0, 14).map(s => fetchBoard(s, dates))));
      let found = matchAll(list, events);
      // Unmapped leagues, or matches missing from their league board: try ESPN's all-soccer board (at most every 5 min).
      if ((loose || list.some(f => !found.has(f.id))) && now - espnAllAt > ESPN_ALL_MS) {
        espnAllAt = now;
        take([await fetchBoard('all', dates)]);
        found = matchAll(list, events);
      }
      if (events.length) espn = found;
      espnAt = now;
    } catch (_) { espnAt = now; }
    finally { espnBusy = false; }
    tick();
  }
  // ESPN data for a fixture, ignoring a "started/finished" state that cannot be right yet.
  const espnFor = (f, now) => {
    const m = espn.get(f.id);
    if (!m) return null;
    if (m.state !== 'pre' && now < f.start - 45 * 60000) return null;
    return m;
  };
  const hasScore = m => !!m && m.state !== 'pre' && m.hs != null && m.aw != null;

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
  // Footer text: ESPN's live status when it has one, otherwise our own countdown.
  function whenText(f, now) {
    const m = espnFor(f, now);
    if (m && m.note) return m.note;
    if (m && m.state === 'in') return m.detail || 'Live now';
    if (m && m.state === 'post') return m.detail || 'Full time';
    return countdown(f, now);
  }
  function logo(v, name, fb) {
    const ini = '<span class="fx-ini">' + esc(name.trim().charAt(0).toUpperCase()) + '</span>';
    let url = '';
    if (/^\d+$/.test(v)) url = 'https://media.api-sports.io/football/teams/' + v + '.png';
    else if (/^https?:\/\//i.test(v)) url = v;
    else if (/^https?:\/\//i.test(fb || '')) url = fb;
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
  .fx-team b{font-weight:700;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .fx-sc{margin-left:auto;flex:none;min-width:24px;padding-left:8px;text-align:right;font-size:24px;font-weight:900;line-height:1;font-variant-numeric:tabular-nums;color:#fff}
  .fx-sc.dim{color:#51647a;font-weight:700}
  .fxcard.live .fx-sc:not(.dim){color:var(--accent2,#6fd6fb)}
  .fx-logo{position:relative;flex:none;width:38px;height:38px;border-radius:50%;display:grid;place-items:center;background:#ffffff10;border:1px solid #ffffff18;overflow:hidden}
  .fx-logo img{position:absolute;inset:0;width:100%;height:100%;padding:5px;object-fit:contain}
  .fx-ini{font-size:15px;font-weight:900;color:#9fb2c7}
  .fx-foot{display:flex;justify-content:space-between;align-items:center;gap:10px;margin-top:12px;padding-top:12px;border-top:1px solid #ffffff12;font-size:13px;color:#aebdce}
  .fx-left{display:flex;align-items:center;gap:8px;min-width:0}
  .fx-when{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .fx-src{flex:none;padding:2px 6px;border-radius:5px;background:#ffffff12;color:#8fa0b5;font-size:9.5px;font-weight:900;letter-spacing:.1em}
  .fxcard.live .fx-foot .fx-when{color:#ff8f93;font-weight:800}
  .fx-watch{flex:none;display:inline-flex;align-items:center;gap:6px;padding:6px 12px;border-radius:999px;background:var(--accent,#1db4ea);color:#03121b;font-size:12px;font-weight:900}
  .fx-empty{padding:60px 18px;text-align:center;line-height:1.7;color:var(--muted,#8fa0b5)}
  .fx-skel{height:150px;border-radius:18px;background:linear-gradient(90deg,#0f1a27,#16253a,#0f1a27);background-size:200% 100%;animation:sh 1.2s infinite}
  .fx-sheet{z-index:90;align-items:center}
  .fx-pop{position:relative;width:min(100%,480px);margin:auto;padding:28px 26px 24px;background:#0d1520;border:1px solid #2c3d52;border-radius:26px;box-shadow:0 30px 90px #000c;animation:up .25s ease both;max-height:94dvh;overflow-y:auto}
  .fx-pop .fx-x{position:absolute;top:10px;right:10px;width:38px;height:38px;padding:0;border-radius:50%;background:#16222f;border:1px solid #2c3d52;color:#fff;font-size:15px}
  .fx-match{display:flex;align-items:center;justify-content:center;gap:14px;margin:4px 0 6px}
  .fx-match .fx-logo{width:52px;height:52px}.fx-match span.vs{font-size:12px;font-weight:900;letter-spacing:.12em;color:#7f90a5}
  .fx-match .fx-big{min-width:78px;text-align:center;font-size:34px;font-weight:900;letter-spacing:.04em;line-height:1;font-variant-numeric:tabular-nums}
  .fx-pop h2{margin:8px 0 4px;text-align:center;font-size:21px;font-weight:800;line-height:1.25}
  .fx-meta{margin:0 0 16px;text-align:center;font-size:13px;color:#8fa0b5}
  .fx-opts{display:grid;gap:10px;margin:0 0 16px}
  .fx-opt{display:flex;gap:13px;align-items:flex-start;padding:13px 14px;border-radius:16px;background:#101b28;border:1px solid #233246}
  .fx-opt .ic{flex:none;width:38px;height:38px;border-radius:12px;display:grid;place-items:center;font-size:19px;background:#1db4ea1f;border:1px solid #1db4ea44}
  .fx-opt b{display:block;font-size:15px;margin-bottom:2px}.fx-opt p{margin:0;font-size:13px;line-height:1.5;color:#aebdce}
  .fx-pop .fx-dl{width:100%;min-height:52px;font-size:16px;margin-bottom:10px}
  .fx-stream-choices{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:12px}
  .fx-stream-choices .fx-dl{margin:0}
  @media(max-width:420px){.fx-stream-choices{grid-template-columns:1fr 1fr}.fx-stream-choices .fx-dl{font-size:15px}}
  .fx-pop .fx-connect{width:100%;min-height:46px}
  .fx-ver{margin-top:12px;text-align:center;font-size:11px;letter-spacing:.08em;color:#7f90a5}
  @media(max-width:600px){#fixturesView .fx-body{padding:4px 14px 40px}.fx-grid{grid-template-columns:1fr}}
  `;
  document.head.appendChild(css);

  /* ---------- match player controls: Switch 1 / Switch 2 + phone layout ----------
     The controls live in index.html / kodi.css; their labels are set by tv.js. On phones kodi.css hides every
     label, which left the two stream buttons blank. Here, for a match (body.fixture-streaming) or a live channel
     (body[data-mode=tv]) on a phone: two rows, big tap targets, "Switch 1 / Switch 2" always labelled and
     highlighted when active, channel zapping and 10-second seek hidden for a match, bar never auto-hides
     (a tap on the video goes to the embedded player, so it could not be brought back). */
  const mm = s => ['body.fixture-streaming', 'body[data-mode=tv]'].map(p => p + ' ' + s).join(',');
  const phone = '@media(max-width:700px),(max-height:480px) and (max-width:1000px)';
  const ctl = document.createElement('style');
  ctl.id = 'fx-player-controls';
  ctl.textContent = `
  .player .controls #mainStream.active,.player .controls #backupStream.active{background:var(--accent);color:var(--ink)}
  .player .controls #mainStream:disabled,.player .controls #backupStream:disabled{opacity:.35}
  body.fixture-streaming .controls .tvonly.nomethod{display:none!important}
  body.fixture-streaming .player .controls #prevCh,body.fixture-streaming .player .controls #nextCh{display:none!important}
  ${phone}{
    body.fixture-streaming .player .controls #rewind,body.fixture-streaming .player .controls #forward,body.fixture-streaming .player .progress{display:none!important}
    ${mm('.player.controls-hidden .player-head')},${mm('.player.controls-hidden .controls')}{opacity:1;pointer-events:auto}
  }
  @media(max-width:700px){
    ${mm('.player .controls')}{left:8px;right:8px;bottom:max(8px,env(safe-area-inset-bottom));transform:none;width:auto;max-width:none;display:flex;flex-wrap:wrap;justify-content:center;gap:6px;padding:8px;border-radius:18px;overflow:visible;background:#0a1119f2}
    ${mm('.player .controls::after')}{content:'';order:1;flex:0 0 100%;height:0;margin-top:-6px}
    ${mm('.player .controls button')}{order:2;flex:1 1 40px;min-width:40px;height:44px;line-height:44px;padding:0 6px;border-radius:12px;background:#ffffff14;font-size:13px;text-align:center}
    ${mm('.player .controls button svg')}{margin:0;width:20px;height:20px;vertical-align:-5px}
    ${mm('.player .controls button .lbl')}{display:none}
    ${mm('.player .controls #mainStream')},${mm('.player .controls #backupStream')}{order:0;flex:1 1 38%;font-size:14px;font-weight:800;border:1px solid #ffffff26}
    ${mm('.player .controls #mainStream .lbl')},${mm('.player .controls #backupStream .lbl')}{display:inline!important}
    ${mm('.player .controls #tvMethod')}{order:0;flex:0 0 52px}
    ${mm('.player-head')}{padding-top:max(8px,env(safe-area-inset-top));padding-bottom:8px;gap:8px}
    ${mm('.player-head .title')}{font-size:15px;line-height:1.25}
  }
  @media(max-height:480px) and (max-width:1000px){
    ${mm('.player .controls')}{left:50%;right:auto;transform:translateX(-50%);width:max-content;max-width:calc(100% - 16px);flex-wrap:nowrap;overflow-x:auto;gap:4px;padding:5px;border-radius:999px;bottom:max(6px,env(safe-area-inset-bottom))}
    ${mm('.player .controls::after')}{display:none}
    ${mm('.player .controls button')}{order:0;flex:none;height:38px;line-height:38px;padding:0 12px;border-radius:999px;font-size:13px}
    ${mm('.player .controls button .lbl')}{display:none}
    ${mm('.player .controls #mainStream .lbl')},${mm('.player .controls #backupStream .lbl')}{display:inline!important}
    ${mm('.player .controls button svg')}{margin:0}
    ${mm('.player .controls #tvMethod')}{flex:none}
    ${mm('.player-head')}{padding-top:max(6px,env(safe-area-inset-top));padding-bottom:6px}
  }
  `;
  document.head.appendChild(ctl);

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
  const scoreCell = (v, on) => '<span class="fx-sc' + (on ? '' : ' dim') + '">' + (on ? esc(v) : '\u2013') + '</span>';
  function cardHtml(f, now) {
    const ph = phase(f, now), m = espnFor(f, now), has = hasScore(m);
    const pill = ph === 'live' || (m && m.state === 'in') ? '● LIVE' : (m && m.state === 'post' ? 'FT' : esc(timeOf(f.start)));
    return '<button type="button" class="fxcard ' + ph + '" data-id="' + esc(f.id) + '" aria-label="' + esc(f.home + ' vs ' + f.away + (has ? ', ' + m.hs + ' to ' + m.aw : '')) + '">' +
      '<div class="fx-top"><span>' + esc(f.league) + '</span><span class="fx-pill">' + pill + '</span></div>' +
      '<div class="fx-team">' + logo(f.homeLogo, f.home, m && m.homeLogo) + '<b>' + esc(f.home) + '</b>' + scoreCell(m && m.hs, has) + '</div>' +
      '<div class="fx-team">' + logo(f.awayLogo, f.away, m && m.awayLogo) + '<b>' + esc(f.away) + '</b>' + scoreCell(m && m.aw, has) + '</div>' +
      '<div class="fx-foot"><span class="fx-left"><span class="fx-when" data-id="' + esc(f.id) + '">' + esc(whenText(f, now)) + '</span>' +
      (m ? '<span class="fx-src" title="Score from ESPN">ESPN</span>' : '') + '</span>' +
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
    const scoreSig = f => { const m = espnFor(f, now); return m ? [m.state, m.hs, m.aw, m.note].join(':') : ''; };
    const sig = [league, names.join('|'), list.map(f => [f.id, f.home, f.away, f.start, f.league, f.homeLogo, f.awayLogo, phase(f, now), scoreSig(f)].join('~')).join(',')].join('#');
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
    const now = Date.now(), byId = new Map(fixtures.map(f => [f.id, f]));
    let changed = false;
    document.querySelectorAll('#fxList .fx-when').forEach(el => {
      const f = byId.get(el.dataset.id); if (!f) return;
      const card = el.closest('.fxcard');
      if (!card || !card.classList.contains(phase(f, now))) { changed = true; return; }
      el.textContent = whenText(f, now);
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
    const m = espnFor(f, now), has = hasScore(m);
    const allowAdPlayback = location.hostname === 'deeprowss.pages.dev' && !!f.url;
    const hasAlt = /^https?:\/\//i.test(f.altUrl || '');
    const watch = !allowAdPlayback ? '' : (hasAlt
      ? '<div class="fx-stream-choices"><button type="button" class="fx-dl" id="fxWatchAds">▶ Stream 1</button><button type="button" class="fx-dl" id="fxWatchAds2">▶ Stream 2</button></div>'
      : '<button type="button" class="fx-dl" id="fxWatchAds">▶ Continue watching with ads</button>');
    modal.innerHTML = '<div class="fx-pop">' +
      '<button type="button" class="fx-x" id="fxX" aria-label="Close">✕</button>' +
      '<div class="fx-match">' + logo(f.homeLogo, f.home, m && m.homeLogo) +
        (has ? '<span class="fx-big">' + esc(m.hs) + ' – ' + esc(m.aw) + '</span>' : '<span class="vs">VS</span>') +
        logo(f.awayLogo, f.away, m && m.awayLogo) + '</div>' +
      '<h2>' + esc(f.home) + ' vs ' + esc(f.away) + '</h2>' +
      '<p class="fx-meta">' + esc(f.league) + ' · ' + (has || live ? esc(whenText(f, now)) : esc(dayLabel(f.start)) + ', ' + esc(timeOf(f.start))) + '</p>' +
      watch +
      '<div class="fx-opts">' +
        '<div class="fx-opt"><span class="ic">📱</span><div><b>Watch on your phone</b><p>Get the Deeprowss app and open this match from Fixtures. Live streams, scores and match analysis are all there.</p></div></div>' +
        '<div class="fx-opt"><span class="ic">📺</span><div><b>Watch on ' + where() + '</b><p>In the app, open <b>Smart Decoder</b>, choose <b>Send to receiver page</b> and scan the QR code under <b>Connect with App</b> here. The match then plays on ' + where() + '.</p></div></div>' +
      '</div>' +
      (url ? '<button type="button" class="fx-dl" id="fxDl">⬇ Download Deeprowss App</button>' : '<p class="fx-meta">The download link is not available right now. Please try again in a moment.</p>') +
      '<button type="button" class="secondary fx-connect" id="fxConnect">Connect with App</button>' +
      (ver ? '<div class="fx-ver">LATEST VERSION ' + esc(ver) + '</div>' : '') + '</div>';
    $('fxX').onclick = closeModal;
    const play = backup => () => { closeModal(); if (window.deeprowssPlayFixture) window.deeprowssPlayFixture(f, backup); else { const s = document.getElementById('playState'); if (s) s.textContent = 'Player is unavailable. Please refresh and try again.'; } };
    const watchAds = $('fxWatchAds'); if (watchAds) watchAds.onclick = play(false);
    const watchAds2 = $('fxWatchAds2'); if (watchAds2) watchAds2.onclick = play(true);
    $('fxConnect').onclick = () => { closeModal(); if (window.deeprowssGo) window.deeprowssGo('connect'); };
    const dl = $('fxDl'); if (dl) dl.onclick = () => openDl(url);
    modal.classList.add('open'); modalOpen = true;
    setTimeout(() => { const el = $('fxWatchAds') || $('fxDl') || $('fxConnect'); if (el) el.focus(); }, 40);
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
    $('fxRefresh').onclick = () => { rendered = ''; load(); espnLoad(true); };
  }
  window.addEventListener('hashchange', () => { if (location.hash === '#fixtures') load(); });
  render(true);
  load();
  setInterval(() => { if (!document.hidden) load(); }, REFRESH_MS);
  setInterval(() => { if (!document.hidden) tick(); }, 30000);
  setInterval(() => { if (!document.hidden && location.hash === '#fixtures') espnLoad(false); }, 20000);
})();
