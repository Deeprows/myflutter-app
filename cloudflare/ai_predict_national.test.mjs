// Node 22+: node cloudflare/ai_predict_national.test.mjs
// National teams (Nations League etc.) need results from the international competitions, not the 48-day club scan.
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
const DAY=86400000,ago=d=>new Date(Date.now()-d*DAY).toISOString();
const T={tr:['465','Türkiye'],be:['459','Belgium'],al:['200','Albania'],fi:['300','Finland']};
const game=(id,d,h,a,hs,as)=>({id,date:ago(d),competitions:[{status:{period:2,type:{name:'STATUS_FULL_TIME',state:'post',completed:true}},competitors:[
  {homeAway:'home',score:String(hs),team:{id:h[0],displayName:h[1],location:h[1]}},{homeAway:'away',score:String(as),team:{id:a[0],displayName:a[1],location:a[1]}}]}]});
// Matches are 30-250 days old: far outside the old 48-day window.
const BY_SLUG={'uefa.nations':[game('1',60,T.tr,T.be,1,1),game('2',30,T.be,T.tr,2,0),game('3',200,T.al,T.fi,0,0)],
  'fifa.friendly':[game('4',120,T.tr,['1','Wales'],2,1),game('5',250,T.fi,T.al,1,0),game('6',150,T.al,['2','Malta'],3,0)],
  'fifa.worldq.uefa':[game('7',90,['3','Georgia'],T.tr,1,3),game('8',100,T.al,['4','Serbia'],0,1),game('9',70,T.fi,['5','Greece'],2,2),game('10',80,T.be,['6','Wales'],2,0),game('11',95,['7','Austria'],T.be,1,1)]};
let calls=0;
const KICK=new Date(Date.now()+3*DAY).toISOString();
const FEED=[{id:'9',home:'Czechia',away:'Spain',league:'UEFA Nations League - League A',kickoff:KICK,homeLogo:'770',awayLogo:'9'}];
T.cz=['468','Czechia'];T.es=['164','Spain'];
BY_SLUG['uefa.nations'].push(game('21',40,T.cz,['8','Ukraine'],1,0),game('22',55,['9','Albania'],T.cz,0,2),game('23',75,T.es,['10','Serbia'],3,0),game('24',50,T.cz,T.es,0,1));
BY_SLUG['fifa.friendly'].push(game('25',110,T.es,['11','Egypt'],2,1),game('26',130,T.cz,['12','Poland'],1,1),game('27',160,['13','Italy'],T.es,0,0));
let apiFootballCalls=0;
globalThis.fetch=async(url)=>{const u=String(url);
  if(u.endsWith('/fixtures.json'))return new Response(JSON.stringify(FEED));
  if(u.includes('api-football') || u.includes('api-sports')){apiFootballCalls++;return new Response(JSON.stringify({errors:{plan:'Free plans do not have access to this season, try from 2022 to 2024.'},response:[]}));}
  if(u==='https://www.googleapis.com/oauth2/v3/certs')return new Response(JSON.stringify({keys:[jwk]}),{headers:{'cache-control':'public,max-age=3600'}});
  if(u.startsWith('https://site.api.espn.com/')) {
    const slug=u.split('/soccer/')[1].split('/')[0];calls++;
    if(slug==='all')return new Response(JSON.stringify({events:[]}));
    if(u.includes('/teams?'))return new Response(JSON.stringify({sports:[{leagues:[{teams:slug==='eng.1'?[{team:{id:'359',displayName:'Arsenal',shortDisplayName:'Arsenal',name:'Arsenal',location:'Arsenal',abbreviation:'ARS'}}]:[]}]}]}));
    if(u.includes('/scoreboard?')) {
      if(!BY_SLUG[slug]&&slug!=='uefa.euroq')return new Response('{}',{status:404});
      const m=/dates=(\d{8})-(\d{8})/.exec(u),f=Date.UTC(+m[1].slice(0,4),+m[1].slice(4,6)-1,+m[1].slice(6)),t=Date.UTC(+m[2].slice(0,4),+m[2].slice(4,6)-1,+m[2].slice(6))+DAY;
      return new Response(JSON.stringify({events:(BY_SLUG[slug]||[]).filter(e=>Date.parse(e.date)>=f&&Date.parse(e.date)<t)}));
    }
  }
  return new Response('[]');};
env.AI={async run(){return {response:'Lean based on recent results; uncertain.'};}};
const alice=await token();assert.equal((await call('auth',{body:{mode:'signup',idToken:alice}})).status,200);
// Typed national-team matchup (name aliases: "Turkey" is "Türkiye" on ESPN)
let r=await call('ai-predict',{body:{custom:{home:'Turkey',away:'Belgium'}},bearer:alice});
const out=await r.json();assert.equal(r.status,200,JSON.stringify(out));
assert.ok(out.home.played>=3&&out.away.played>=3,'both national sides have form');
// Literal local spelling must also bypass the domestic-club lookup path.
r=await call('ai-predict',{body:{custom:{home:'Türkiye',away:'Belgium'}},bearer:alice});
const outTr=await r.json();assert.equal(r.status,200,JSON.stringify(outTr));
assert.ok(outTr.home.played>=3&&outTr.away.played>=3,'Türkiye spelling uses national-team form');
// Strict names: Albania must not pick up Northern Ireland-style partial matches or other teams' games
r=await call('ai-predict',{body:{custom:{home:'Albania',away:'Finland'}},bearer:alice});
const o2=await r.json();assert.equal(r.status,200,JSON.stringify(o2));
assert.ok(o2.home.played>=3&&o2.away.played>=3);
assert.equal(o2.home.teamId,'espn:national');
// API-Football refuses (plan error) for a fixture that HAS team IDs: ESPN must take over.
env.API_FOOTBALL_KEY='k';
r=await call('ai-predict',{body:{key:'9|'+new Date(KICK).getTime()},bearer:alice});
const o3=await r.json();assert.equal(r.status,200,JSON.stringify(o3));
assert.ok(apiFootballCalls>0,'API-Football was tried first');
assert.match(o3.dataSource||'',/ESPN/);assert.ok(o3.home.played>=3&&o3.away.played>=3);
console.log('AI national: Türkiye vs Belgium and Albania vs Finland get form from international competitions; ESPN calls',calls);
