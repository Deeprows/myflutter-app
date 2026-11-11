// Node 22+: node cloudflare/fan_auth.test.mjs
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import worker,{verifyFanGoogleToken} from './worker.js';
const sql=new DatabaseSync(':memory:');
const DB={prepare(query){let args=[];const st={bind(...a){args=a;return st;},
  async first(){return sql.prepare(query).get(...args)||null;},
  async all(){return {results:sql.prepare(query).all(...args)};},
  async run(){return /RETURNING/i.test(query)?{results:sql.prepare(query).all(...args)}:sql.prepare(query).run(...args);}};return st;},
  async batch(list){sql.exec('BEGIN');try{const result=[];for(const s of list)result.push(await s.run());sql.exec('COMMIT');return result;}catch(e){sql.exec('ROLLBACK');throw e;}}};
const keys=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const jwk=await crypto.subtle.exportKey('jwk',keys.publicKey);jwk.kid='test-google-key';
let keyFetches=0,providerCalls=0,providerFailure=false,smallSample=false,providerError=null,espnEnabled=false,espnCalls=0,espnLimited=false;
const fixture={id:'auto',home:'Home FC',away:'Away FC',homeLogo:'66',awayLogo:'50',league:'Serie A',kickoff:new Date(Date.now()+3600000).toISOString()};
function history(id) {
  return Array.from({length:smallSample?2:5},(_,i)=>({fixture:{id:Number(id)*100+i,date:new Date(Date.now()-(i+1)*86400000).toISOString(),status:{short:i===0?'AET':'FT'}},teams:{home:{id:Number(id),name:'Team '+id},away:{id:777,name:'Opponent'}},goals:{home:3,away:1},score:{fulltime:{home:i===0?1:2,away:1}}}));
}
const env={DB,GOOGLE_WEB_CLIENT_ID:'web-client.apps.googleusercontent.com',ADMIN_TOKEN:'secret'};
const now=Math.floor(Date.now()/1000);
async function token(changes={}){
  const enc=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
  const payload={iss:'https://accounts.google.com',aud:env.GOOGLE_WEB_CLIENT_ID,sub:'alice-google-id',
    email:'alice@gmail.com',email_verified:true,name:'Alice',iat:now,exp:now+3600,...changes};
  const body=enc({alg:'RS256',kid:jwk.kid})+'.'+enc(payload);
  const signature=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',keys.privateKey,new TextEncoder().encode(body));
  return body+'.'+Buffer.from(signature).toString('base64url');
}
async function call(path,{body,bearer,e=env}={}){
  return worker.fetch(new Request('https://feed.test/fan/'+path,{method:body?'POST':'GET',
    headers:{'content-type':'application/json',...(bearer?{authorization:'Bearer '+bearer}:{})},
    ...(body?{body:JSON.stringify(body)}:{})}),e,{});
}

const FUTURE=new Date(Date.now()+2*86400000).toISOString();
let scoreboardCalls=0,teamsCalls=0,scheduleCalls=0;
const TEAMS={'eng.1':[['359','Arsenal','Arsenal','ARS'],['363','Chelsea','Chelsea','CHE'],['382','Manchester City','Manchester City','MCI'],['360','Manchester United','Manchester United','MUN'],['341','Leeds United','Leeds','LEE']],
  'eng.w.1':[['9363','Chelsea','Chelsea','CHE'],['9341','Leeds','Leeds','LEE']],
  'esp.1':[['86','Real Madrid','Real Madrid','RMA'],['89','Real Sociedad','Real Sociedad','RSO']],
  'tur.1':[['432','Fenerbahçe','Fenerbahçe','FEN'],['436','Galatasaray','Galatasaray','GAL']],
  'ger.1':[['131','Bayern Munich','Bayern Munich','BAY'],['132','Bayer Leverkusen','Bayer Leverkusen','LEV']],
  'ita.3':[['701','Lecce','Lecce','LEC']]};
globalThis.fetch=async(url)=>{
  const u=String(url);
  if(u==='https://www.googleapis.com/oauth2/v3/certs')return new Response(JSON.stringify({keys:[jwk]}),{headers:{'cache-control':'public,max-age=3600'}});
  if(u.startsWith('https://site.api.espn.com/')) {
    const slug=u.split('/soccer/')[1].split('/')[0];
    if(u.includes('/scoreboard?')) {
      scoreboardCalls++;
      if(slug==='esp.1')return new Response('{}',{status:404});
      if(slug==='uefa.champions') {
        const e={id:'8001',date:FUTURE,competitions:[{status:{type:{state:'pre',name:'STATUS_SCHEDULED'}},competitors:[{homeAway:'home',team:{id:'86',displayName:'Real Madrid'}},{homeAway:'away',team:{id:'359',displayName:'Arsenal'}}]}]};
        return new Response(JSON.stringify({events:[e]}));
      }
      if(slug==='eng.w.1')return new Response(JSON.stringify({events:[{id:'9901',date:FUTURE,competitions:[{status:{type:{state:'pre',name:'STATUS_SCHEDULED'}},competitors:[{homeAway:'home',team:{id:'9363',displayName:'Chelsea'}},{homeAway:'away',team:{id:'9341',displayName:'Leeds'}}]}]}]}));
      if(slug!=='eng.1')return new Response(JSON.stringify({events:[]}));
      const mk=(id,state,name,date,h,a)=>({id,date,competitions:[{status:{type:{state,name}},competitors:[{homeAway:'home',team:{id:h[0],displayName:h[1],logo:'https://a.espncdn.com/i/teamlogos/soccer/500/'+h[0]+'.png'}},{homeAway:'away',team:{id:a[0],displayName:a[1],logo:'https://evil.example/x.png'}}]}]});
      return new Response(JSON.stringify({events:[
        mk('7001','pre','STATUS_SCHEDULED',FUTURE,TEAMS['eng.1'][0],TEAMS['eng.1'][1]),
        mk('7002','post','STATUS_FULL_TIME',FUTURE,TEAMS['eng.1'][2],TEAMS['eng.1'][3]),
        mk('7003','pre','STATUS_POSTPONED',FUTURE,TEAMS['eng.1'][2],TEAMS['eng.1'][3]),
        mk('7004','pre','STATUS_SCHEDULED',new Date(Date.now()-3600000).toISOString(),TEAMS['eng.1'][2],TEAMS['eng.1'][3])]}));
    }
    if(u.includes('/teams?')) {
      teamsCalls++;
      const teams=(TEAMS[slug]||[]).map(([id,displayName,name,abbreviation])=>({team:{id,displayName,shortDisplayName:name,name,location:name,abbreviation,logos:[{href:'https://a.espncdn.com/i/teamlogos/soccer/500/'+id+'.png'}]}}));
      return new Response(JSON.stringify({sports:[{leagues:[{teams}]}]}));
    }
    const m=/\/teams\/(\d+)\/schedule/.exec(u);
    if(m) {
      scheduleCalls++;
      return new Response(JSON.stringify({events:Array.from({length:5},(_,i)=>({id:m[1]+'-'+i,date:new Date(Date.now()-(i+1)*86400000).toISOString(),status:{period:2,type:{name:'STATUS_FULL_TIME',state:'post',completed:true}},competitions:[{competitors:[{homeAway:'home',team:{id:m[1],displayName:'Club'},score:{value:2}},{homeAway:'away',team:{id:'999',displayName:'Opponent'},score:{value:1}}]}]}))}));
    }
  }
  return new Response(JSON.stringify([]));
};
// ---- TheSportsDB mock: the free search + last-5-events endpoints ----
const espnFetch=globalThis.fetch;
const tsdbCalls=[];
const DAY=86400000;
const evt=(i,home,away,hs,as,hid,aid,status='Match Finished')=>({strSport:'Soccer',strStatus:status,strTimestamp:new Date(Date.now()-(i+1)*3*DAY).toISOString().slice(0,19),idHomeTeam:hid,idAwayTeam:aid,strHomeTeam:home,strAwayTeam:away,intHomeScore:String(hs),intAwayScore:String(as)});
const TSDB={
  // Only the proper spelling with ø is stored, exactly like the real site.
  'brøndby':{teams:[{idTeam:'100',strTeam:'Brøndby',strAlternate:'Brøndby IF, Brondby IF',strSport:'Soccer',strGender:'Male',strBadge:'https://r2.thesportsdb.com/images/media/team/badge/bif.png',strDescriptionEN:'x'.repeat(5000)}]},
  'rosenborg':{teams:[{idTeam:'101',strTeam:'Rosenborg',strAlternate:'Rosenborg BK',strSport:'Soccer',strGender:'Male',strBadge:'https://r2.thesportsdb.com/images/media/team/badge/rbk.png'}]},
  'brann':{teams:[{idTeam:'102',strTeam:'Brann',strAlternate:'SK Brann',strSport:'Soccer',strGender:'Male'}]},
  'czarni sosnowiec':{teams:[{idTeam:'103',strTeam:'Czarni Sosnowiec',strAlternate:'',strSport:'Soccer',strGender:'Male'}]},
  'preussen munster':{teams:[{idTeam:'104',strTeam:'Preußen Münster',strAlternate:'SC Preußen Münster',strSport:'Soccer',strGender:'Male'},{idTeam:'105',strTeam:'Preußen Münster II',strAlternate:'',strSport:'Soccer',strGender:'Male'}]},
  'lecco':{teams:[{idTeam:'106',strTeam:'Lecco',strAlternate:'',strSport:'Soccer',strGender:'Male'}]},
  'thin fc':{teams:[{idTeam:'107',strTeam:'Thin FC',strAlternate:'',strSport:'Soccer',strGender:'Male'}]},
  'ambig':{teams:[{idTeam:'108',strTeam:'Ambig Rovers',strSport:'Soccer',strGender:'Male'},{idTeam:'109',strTeam:'Ambig Athletic',strSport:'Soccer',strGender:'Male'}]}
};
const LAST={
  '100':[0,1,2,3,4].map(i=>evt(i,i%2?'Brøndby':'Odense',i%2?'Aalborg':'Brøndby',2,1,i%2?'100':'200',i%2?'300':'100')),
  '101':[0,1,2,3,4].map(i=>evt(i,'Rosenborg','Molde',1,1,'101','400')),
  '102':[0,1,2,3,4].map(i=>evt(i,'Viking','Brann',0,2,'500','102')),
  '103':[0,1,2,3,4].map(i=>evt(i,'Czarni Sosnowiec','Other',3,0,'103','600')),
  '104':[0,1,2,3,4].map(i=>evt(i,'Preußen Münster','Other',1,0,'104','700')),
  '105':[evt(0,'Preußen Münster II','Other',1,0,'105','700')],
  '106':[0,1,2,3,4].map(i=>evt(i,'Lecco','Other',1,0,'106','700')),
  '107':[evt(0,'Thin FC','Other',1,0,'107','700'),evt(1,'Other','Thin FC',1,0,'700','107','Not Started')]
};
let tsdbDown=false;
globalThis.fetch=async(url,o)=>{
  const u=String(url);
  if(u.startsWith('https://www.thesportsdb.com/')) {
    tsdbCalls.push(decodeURIComponent(u.split('/json/3/')[1] || u));
    if(tsdbDown)return new Response('down',{status:503});
    const m=/searchteams\.php\?t=(.*)$/.exec(u);
    if(m){const q=decodeURIComponent(m[1]).toLowerCase();return new Response(JSON.stringify(TSDB[q] || {teams:null}));}
    const l=/eventslast\.php\?id=(\d+)/.exec(u);
    if(l)return new Response(JSON.stringify({results:LAST[l[1]] || null}));
    return new Response(JSON.stringify({events:[]}));
  }
  return espnFetch(url,o);
};
let runs=0,lastPrompt=null;
env.AI={async run(model,input){runs++;lastPrompt=JSON.parse(input.messages[1].content);return {response:'Lean based on the fetched recent results; uncertain outcome.'};}};
const alice=await token();assert.equal((await call('auth',{body:{mode:'signup',idToken:alice}})).status,200);
const ask=async(home,away,extra={})=>{const r=await call('ai-predict',{body:{custom:{home,away,...extra}},bearer:alice});return {status:r.status,body:await r.json()};};

// 1. The screenshot cases ---------------------------------------------------
// "Brondby" (no ø) is found, and shown under its real name; SK Brann resolves by its short name.
let x=await ask('Brondby','Rosenborg');
assert.equal(x.status,200,JSON.stringify(x.body));assert.equal(x.body.fixture.home,'Brøndby');assert.equal(x.body.fixture.away,'Rosenborg');
assert.equal(x.body.home.played,5);assert.match(x.body.dataSource,/TheSportsDB/);assert.match(x.body.fixture.homeLogo,/thesportsdb\.com/);
assert.equal(x.body.home.matches[0].venue,'home'.length?x.body.home.matches[0].venue:'');
for(const m of x.body.home.matches)assert.ok(['home','away'].includes(m.venue));
x=await ask('Czarni Sosnowiec','SK Brann');
assert.equal(x.status,200,JSON.stringify(x.body));assert.equal(x.body.fixture.away,'Brann');assert.equal(x.body.away.matches[0].venue,'away');
assert.equal(x.body.away.matches[0].goalsFor,2,'goals are read from the club\'s own side');
// The misspelt club "Feberbache" is corrected to Fenerbahçe from ESPN's list; Real Sociedad is unaffected.
x=await ask('Feberbache','Real Sociedad');
assert.equal(x.status,200,JSON.stringify(x.body));assert.equal(x.body.fixture.home,'Fenerbahçe');assert.equal(x.body.home.teamId,'espn:432');assert.equal(x.body.fixture.away,'Real Sociedad');
// "Preußen Münster II" and "SC Wiedenbrück 2000": a reserve side with too little history says so plainly; an unknown club is not guessed.
x=await ask('SC Wiedenbrück 2000','Preußen Münster II');
assert.equal(x.status,422);assert.match(x.body.error,/(?:No team found|Could not verify completed recent results)/i);
assert.doesNotMatch(x.body.error,/AI is temporarily unavailable/);
x=await ask('Thin FC','Rosenborg');
assert.equal(x.status,200,JSON.stringify(x.body));assert.equal(x.body.home.played,1);assert.equal(x.body.sampleQuality.level,'limited');assert.match(lastPrompt.sampleNotice,/1 match/,'one-match form is clearly labelled as preliminary');

// 2. Safety: close spellings must not turn one real club into another -----------
x=await ask('Lecco','Rosenborg');
assert.equal(x.status,200,JSON.stringify(x.body));assert.equal(x.body.fixture.home,'Lecco','Lecco (own result) is not "corrected" to Lecce');
assert.equal(x.body.home.teamId,'tsdb:106');
// Two clubs in ESPN at the same distance: suggest, never pick
x=await ask('Bayerm Munich','Arsenal');
assert.equal(x.status,200,'single nearest club is corrected');assert.equal(x.body.fixture.home,'Bayern Munich');
// Short names have to be exact
x=await ask('Lecca','Arsenal');
assert.equal(x.status,422);assert.match(x.body.error,/No team found|Could not verify completed recent results/i);
// A different club with an ambiguous name is not guessed
x=await ask('Ambig','Arsenal');
assert.equal(x.status,422);

// 3. Cheap lookup first: the heavy all-soccer scan is not used when the precise lookup works ----
const seen=[];const f0=globalThis.fetch;globalThis.fetch=async(u,o)=>{seen.push(String(u));return f0(u,o);};
await ask('Rosenborg','Arsenal');
assert.ok(!seen.some(u=>/espn\.com.*scoreboard\?dates=/.test(u)),'no ESPN scan for a club the name lookup resolved: '+seen.length+' requests');
assert.ok(seen.length<=8,'few requests: '+seen.length);
globalThis.fetch=f0;
// Cached: asking again makes no new TSDB request
const n=tsdbCalls.length;await ask('Rosenborg','Arsenal');assert.equal(tsdbCalls.length,n,'TheSportsDB answers are cached');

// 4. When TheSportsDB is down the old ESPN scan still runs and reports clearly ---------
tsdbDown=true;sql.exec("DELETE FROM fan_espn_form_cache WHERE cache_key LIKE 'tsdb:%'");
x=await ask('Rosenborg','Arsenal');
assert.equal(x.status,422);assert.match(x.body.error,/No team found|unavailable|fewer|Could not verify completed recent results/i);
tsdbDown=false;
// Women's matches keep to women's teams
x=await ask('Chelsea','Leeds',{gender:'women'});assert.equal(x.status,200);assert.equal(x.body.gender,'women');


// 6. League names: the all-soccer feed lists competitions once ("leagues") and tags events by uid --------------
{
  const FUT=new Date(Date.now()+3*86400000).toISOString();
  const ev=(id,uid,h,a)=>({id,uid,date:FUT,competitions:[{status:{type:{state:'pre',name:'STATUS_SCHEDULED'}},competitors:[{homeAway:'home',team:{id:String(id)+'1',displayName:h}},{homeAway:'away',team:{id:String(id)+'2',displayName:a}}]}]});
  const prev=globalThis.fetch;
  globalThis.fetch=async(u,o)=>{
    if(String(u).includes('/soccer/all/scoreboard'))return new Response(JSON.stringify({leagues:[{id:'700',uid:'s:600~l:700',name:'Danish Superliga'},{id:'701',uid:'s:600~l:701',name:'AFC Challenge'}],events:[ev('5001','s:600~l:700~e:5001','Brondby IF','Aalborg BK'),ev('5002','s:600~l:701~e:5002','Alpha','Beta'),ev('5003','s:600~l:999~e:5003','Gamma','Delta'),Object.assign(ev('5004','x','Eps','Zeta'),{leagueName:'Direct League'})]}));
    return prev(u,o);
  };
  sql.exec("DELETE FROM fan_espn_form_cache WHERE cache_key LIKE 'ai-%'");
  const r=await call('ai-predict/matches?fresh=1',{bearer:alice});const list=(await r.json()).matches;
  const by=h=>list.find(m=>m.home===h);
  assert.equal(by('Brondby IF').league,'Danish Superliga');assert.equal(by('Alpha').league,'AFC Challenge');
  assert.equal(by('Eps').league,'Direct League');assert.equal(by('Gamma').league,'Other leagues','unknown stays generic, never wrong');
  globalThis.fetch=prev;
  // Typed matchups name their league when both clubs share one.
  x=await ask('Arsenal','Chelsea');assert.equal(x.status,200);assert.equal(x.body.fixture.league,'Premier League');
  x=await ask('Real Madrid','Arsenal');assert.equal(x.status,200);assert.equal(x.body.fixture.league,'Your matchup');
}
console.log('AI league names: ESPN all-soccer events get their competition name; typed matches show a shared league.');

// 5. Name normalisation -------------------------------------------------------------
const mod=await import('./worker.js');
console.log('AI typo tolerance: Brondby, SK Brann, Feberbache, Czarni Sosnowiec, reserve sides, Lecco/Lecce safety, request budget and caching passed.');
