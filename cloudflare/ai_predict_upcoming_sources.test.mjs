// Node 22+: node cloudflare/ai_predict_upcoming_sources.test.mjs
// Extra upcoming-match networks (football-data.org, API-Football, BBC Sport, Flashscore): top leagues only, deduplicated, mapped to ESPN clubs.
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import worker from './worker.js';
const sql=new DatabaseSync(':memory:');
const DB={prepare(query){let args=[];const st={bind(...a){args=a;return st;},
  async first(){return sql.prepare(query).get(...args)||null;},
  async all(){return {results:sql.prepare(query).all(...args)};},
  async run(){return /RETURNING/i.test(query)?{results:sql.prepare(query).all(...args)}:sql.prepare(query).run(...args);}};return st;},
  async batch(list){const r=[];for(const s of list)r.push(await s.run());return r;}};
const keys=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const jwk=await crypto.subtle.exportKey('jwk',keys.publicKey);jwk.kid='k';
const env={DB,GOOGLE_WEB_CLIENT_ID:'web-client.apps.googleusercontent.com',ADMIN_TOKEN:'secret'};
const now=Math.floor(Date.now()/1000);
async function token(){const enc=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
  const body=enc({alg:'RS256',kid:jwk.kid})+'.'+enc({iss:'https://accounts.google.com',aud:env.GOOGLE_WEB_CLIENT_ID,sub:'g1',email:'a@gmail.com',email_verified:true,name:'A',iat:now,exp:now+3600});
  const sig=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',keys.privateKey,new TextEncoder().encode(body));return body+'.'+Buffer.from(sig).toString('base64url');}
const call=(path,{body,bearer}={})=>worker.fetch(new Request('https://feed.test/fan/'+path,{method:body?'POST':'GET',headers:{'content-type':'application/json',...(bearer?{authorization:'Bearer '+bearer}:{})},...(body?{body:JSON.stringify(body)}:{})}),env,{});
const DAY=86400000,at=d=>new Date(Date.now()+d*DAY).toISOString();
const CONFIG={data:{upcoming:{topLeaguesOnly:false,leagues:['eng.1','sco.1','esp.1','ita.1','ger.1'],sources:[
  {id:'espn',enabled:true},{id:'espn_all',enabled:true},{id:'footballdata',enabled:true},{id:'apifootball',enabled:true},
  {id:'bbc',enabled:true},{id:'flashscore',enabled:true},{id:'tsdb',enabled:false},{id:'nonsense',enabled:true}]}}};
const TEAMS={'eng.1':[['359','Arsenal','Arsenal'],['382','Manchester City','Man City'],['363','Chelsea','Chelsea']],'sco.1':[['256','Celtic','Celtic'],['257','Rangers','Rangers']]};
const seen=new Set();let tsdbCalls=0;
globalThis.fetch=async(url)=>{const u=String(url);
  if(u.includes('raw.githubusercontent.com'))return new Response(JSON.stringify(CONFIG));
  if(u.endsWith('/fixtures.json'))return new Response('[]');
  if(u==='https://www.googleapis.com/oauth2/v3/certs')return new Response(JSON.stringify({keys:[jwk]}),{headers:{'cache-control':'public,max-age=3600'}});
  if(u.startsWith('https://site.api.espn.com/')) {
    const slug=u.split('/soccer/')[1].split('/')[0];
    if(u.includes('/teams?'))return new Response(JSON.stringify({sports:[{leagues:[{teams:(TEAMS[slug]||[]).map(([id,n,s])=>({team:{id,displayName:n,shortDisplayName:s,name:n,location:n,logos:[{href:`https://a.espncdn.com/i/teamlogos/soccer/500/${id}.png`}]}}))}]}]}));
    return new Response('{}',{status:503}); // ESPN fixtures are down: only the extra networks can fill the list
  }
  if(u.includes('thesportsdb.com')){tsdbCalls++;return new Response('{}',{status:500});}
  if(u.startsWith('https://api.football-data.org/')){seen.add('fd');
    assert.equal(new URL(u).searchParams.get('competitions'),'PL,PD,SA,BL1','Scottish league is not on football-data.org');
    return new Response(JSON.stringify({matches:[
      {id:501,utcDate:at(2),status:'TIMED',homeTeam:{name:'Arsenal FC'},awayTeam:{name:'Manchester City FC'},competition:{code:'PL'}},
      {id:502,utcDate:at(2),status:'TIMED',homeTeam:{name:'Paris Saint-Germain FC'},awayTeam:{name:'Olympique Lyonnais'},competition:{code:'FL1'}},
      {id:503,utcDate:at(1),status:'FINISHED',homeTeam:{name:'Chelsea FC'},awayTeam:{name:'Arsenal FC'},competition:{code:'PL'}}]}));}
  if(u.startsWith('https://v3.football.api-sports.io/')){seen.add('af');return new Response(JSON.stringify({errors:{plan:'Free plans do not have access to this season'},response:[]}));}
  if(u.startsWith('https://web-cdn.api.bbci.co.uk/')){seen.add('bbc');
    const premier=u.includes('premier-league');
    return new Response(JSON.stringify(premier?{data:{eventGroups:[{secondaryGroups:[{events:[
      {id:'EFBO1',status:'PRE_MATCH',home:{fullName:'Chelsea'},away:{fullName:'Arsenal'},date:{iso:at(3)}},
      {id:'EFBO2',status:'FULL_TIME',home:{fullName:'Chelsea'},away:{fullName:'Everton'},date:{iso:at(-1)}}]}]}]}}:{data:{eventGroups:[]}}));}
  if(u.startsWith('https://d.flashscore.com/')){seen.add('fs');assert.ok(u.endsWith('_en_1'));
    const ts=Math.floor(Date.parse(at(4))/1000);
    return new Response(`ZA÷SCOTLAND: Premiership¬ZEE÷x¬~AA÷abc12345¬AD÷${ts}¬AB÷1¬AE÷Hearts¬AF÷Hibernian¬~ZA÷FRANCE: Ligue 1¬~AA÷zzz¬AD÷${ts}¬AB÷1¬AE÷Nice¬AF÷Metz¬~`);}
  return new Response('[]');};
env.AI={async run(){return {response:'ok'};}};env.FOOTBALL_DATA_KEY='fd-test';env.API_FOOTBALL_KEY='af-test';
const alice=await token();assert.equal((await call('auth',{body:{mode:'signup',idToken:alice}})).status,200);
// Free users get 3 analyses a day; these tests run many, so make the test user premium.
sql.exec("CREATE TABLE IF NOT EXISTS subs (install_id TEXT PRIMARY KEY, email TEXT, expires_at INTEGER NOT NULL DEFAULT 0, source TEXT, updated_at INTEGER NOT NULL DEFAULT 0)");
for(const u of sql.prepare('SELECT id FROM fan_users').all())sql.prepare("INSERT OR REPLACE INTO subs(install_id,email,expires_at,source,updated_at) VALUES(?,?,?,?,?)").run(u.id,'alice@gmail.com',Date.now()+30*86400000,'test',Date.now());
let r=await call('ai-predict/top-matches',{bearer:alice});
const out=await r.json();assert.equal(r.status,200,JSON.stringify(out));
const names=out.matches.map(m=>`${m.home} v ${m.away} [${m.league}]`).sort();
assert.deepEqual(names,[
  'Arsenal v Manchester City [Premier League]','Chelsea v Arsenal [Premier League]','Hearts v Hibernian [Scottish Premiership]'
],JSON.stringify(names));
for(const k of ['fd','af','bbc','fs'])assert.ok(seen.has(k),'source called: '+k);
assert.equal(tsdbCalls,0,'TheSportsDB is switched off in the JSON');
const arsenal=out.matches.find(m=>m.home==='Arsenal');
assert.ok(/espncdn\.com/.test(arsenal.homeLogo),'club crest comes from the ESPN team list');
assert.ok(out.matches.every(m=>!('source' in m) && !('homeId' in m)),'internal fields are not sent to the app');
assert.deepEqual(out.sources,{fd:1,bbc:1,fs:1},JSON.stringify(out.sources));
// A match from these networks can be found again when it is picked or analysed (looked up in the top-league list).
const hearts=out.matches.find(m=>m.home==='Hearts');
r=await call('ai-predict',{body:{ext:hearts.id},bearer:alice});
assert.notEqual(r.status,404,'listed match is found again: '+JSON.stringify(await r.clone().json().catch(()=>null)));
console.log('ai_predict_upcoming_sources ok:',names.length,'matches');
