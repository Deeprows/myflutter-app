// Node 22+: node cloudflare/ai_predict_national_youth.test.mjs
// A national team's form must never include its U17/U20 side's games (ESPN gives both the same location name).
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
// ESPN names a youth side like its country: displayName "Nigeria U17" but location "Nigeria".
const team=(id,name,loc)=>({id,displayName:name,shortDisplayName:name,name,location:loc||name});
const NG=team('657','Nigeria'),TZ=team('2699','Tanzania'),NG17=team('9001','Nigeria U17','Nigeria'),TZ17=team('9002','Tanzania U17','Tanzania');
const game=(id,d,h,a,hs,as)=>({id,date:ago(d),competitions:[{status:{period:2,type:{name:'STATUS_FULL_TIME',state:'post',completed:true}},competitors:[
  {homeAway:'home',score:String(hs),team:h},{homeAway:'away',score:String(as),team:a}]}]});
const slugsAsked=new Set();
const BY_SLUG={
  'caf.nations':[game('1',60,NG,team('1','Benin'),2,1),game('2',50,team('2','Rwanda'),NG,0,1),game('3',40,NG,TZ,1,1)],
  'caf.nations_qual':[game('4',30,NG,team('3','Libya'),3,0),game('5',20,team('4','Zimbabwe'),NG,1,1),game('6',70,TZ,team('5','Uganda'),1,0),game('7',45,TZ,team('6','Chad'),2,0),game('8',35,team('7','Mali'),TZ,2,2)],
  // The U17 team's games (these used to be read as Nigeria's form):
  'fifa.friendly':[game('11',5,NG17,team('8','Japan U17'),2,1),game('12',8,team('9','Brazil U17'),NG17,1,3),game('13',12,NG17,team('10','Venezuela U17'),1,0),
    game('14',15,TZ17,team('11','Mexico U17'),0,2),game('15',18,NG17,team('12','North Korea U17'),3,1)]};
const KICK=new Date(Date.now()+3*DAY).toISOString();
const FEED=[{id:'9',home:'Nigeria',away:'Tanzania',league:'International Friendly',kickoff:KICK,homeLogo:'657',awayLogo:'2699'}];
globalThis.fetch=async(url)=>{const u=String(url);
  if(u.endsWith('/fixtures.json'))return new Response(JSON.stringify(FEED));
  if(u==='https://www.googleapis.com/oauth2/v3/certs')return new Response(JSON.stringify({keys:[jwk]}),{headers:{'cache-control':'public,max-age=3600'}});
  if(u.startsWith('https://site.api.espn.com/')) {
    const slug=u.split('/soccer/')[1].split('/')[0];slugsAsked.add(slug);
    if(slug==='all')return new Response(JSON.stringify({events:[]}));
    if(u.includes('/teams?'))return new Response(JSON.stringify({sports:[{leagues:[{teams:slug==='eng.1'?[{team:{id:'359',displayName:'Arsenal',shortDisplayName:'Arsenal',name:'Arsenal',location:'Arsenal',abbreviation:'ARS'}}]:[]}]}]}));
    if(u.includes('/scoreboard?')) {
      if(!BY_SLUG[slug])return new Response('{}',{status:404});
      const m=/dates=(\d{8})-(\d{8})/.exec(u),f=Date.UTC(+m[1].slice(0,4),+m[1].slice(4,6)-1,+m[1].slice(6)),t=Date.UTC(+m[2].slice(0,4),+m[2].slice(4,6)-1,+m[2].slice(6))+DAY;
      return new Response(JSON.stringify({events:(BY_SLUG[slug]||[]).filter(e=>Date.parse(e.date)>=f&&Date.parse(e.date)<t)}));
    }
  }
  return new Response('[]');};
env.AI={async run(){return {response:'Lean based on recent results; uncertain.'};}};
const alice=await token();assert.equal((await call('auth',{body:{mode:'signup',idToken:alice}})).status,200);
// Typed matchup: the senior sides.
let r=await call('ai-predict',{body:{custom:{home:'Nigeria',away:'Tanzania'}},bearer:alice});
const out=await r.json();assert.equal(r.status,200,JSON.stringify(out));
const opp=f=>(f.matches||[]).map(m=>m.opponent);
assert.ok(out.home.played>=3,'Nigeria has form');
assert.ok(!opp(out.home).some(n=>/U-?\d\d/i.test(n)),'Nigeria form has no youth games: '+opp(out.home));
assert.ok(!opp(out.away).some(n=>/U-?\d\d/i.test(n)),'Tanzania form has no youth games: '+opp(out.away));
assert.ok(opp(out.home).includes('Benin') || opp(out.home).includes('Libya'),'Nigeria form comes from Africa Cup of Nations games');
assert.ok(slugsAsked.has('caf.nations') && slugsAsked.has('caf.nations_qual'),'African competitions are read first');
assert.ok(!slugsAsked.has('uefa.nations'),'African sides do not read the UEFA lists');
// ESPN feed match with team ids (the match in the app): same result.
r=await call('ai-predict',{body:{ext:'9'},bearer:alice});
// A youth side asked for by name still gets its own (youth) games only.
r=await call('ai-predict',{body:{custom:{home:'Nigeria U17',away:'Tanzania U17'}},bearer:alice});
const y=await r.json();
if(r.status===200){assert.ok(!opp(y.home).includes('Benin'),'U17 form has no senior games');}
console.log('AI national youth: Nigeria / Tanzania senior form excludes U17 games; AFCON competitions read first');
