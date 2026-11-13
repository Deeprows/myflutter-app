// Node 22+: node cloudflare/fan_prediction_history.test.mjs
// Public prediction history: only SETTLED picks of a fan are visible to others.
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import worker from './worker.js';
const sql=new DatabaseSync(':memory:');
const DB={prepare(query){let args=[];const st={bind(...a){args=a;return st;},
  async first(){return sql.prepare(query).get(...args)||null;},
  async all(){return {results:sql.prepare(query).all(...args)};},
  async run(){return sql.prepare(query).run(...args);}};return st;},
  async batch(list){sql.exec('BEGIN');try{const result=[];for(const s of list)result.push(await s.run());sql.exec('COMMIT');return result;}catch(e){sql.exec('ROLLBACK');throw e;}}};
const keys=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const jwk=await crypto.subtle.exportKey('jwk',keys.publicKey);jwk.kid='test-google-key';
globalThis.fetch=async(url)=>String(url)==='https://www.googleapis.com/oauth2/v3/certs'
  ?new Response(JSON.stringify({keys:[jwk]}),{headers:{'cache-control':'public,max-age=3600'}}):new Response('[]');
const env={DB,GOOGLE_WEB_CLIENT_ID:'web-client.apps.googleusercontent.com',ADMIN_TOKEN:'secret'};
const now=Math.floor(Date.now()/1000);
async function token(changes={}){
  const enc=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
  const payload={iss:'https://accounts.google.com',aud:env.GOOGLE_WEB_CLIENT_ID,sub:'alice-google-id',
    email:'alice@gmail.com',email_verified:true,name:'Alice',iat:now,exp:now+3600,...changes};
  const body=enc({alg:'RS256',kid:jwk.kid})+'.'+enc(payload);
  const sig=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',keys.privateKey,new TextEncoder().encode(body));
  return body+'.'+Buffer.from(sig).toString('base64url');
}
const call=(path,bearer)=>worker.fetch(new Request('https://feed.test/fan/'+path,{headers:bearer?{authorization:'Bearer '+bearer}:{}}),env,{});
const post=(path,body,bearer)=>worker.fetch(new Request('https://feed.test/fan/'+path,{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+bearer},body:JSON.stringify(body)}),env,{});

const alice=await token(),bob=await token({sub:'bob',email:'bob@gmail.com',name:'Bob'});
for(const t of [alice,bob])assert.equal((await post('auth',{mode:'signup',idToken:t},t)).status,200);
const a=(await (await call('state',alice)).json()).id,b=(await (await call('state',bob)).json()).id;

// Alice has one settled pick (exact), one settled miss and one pending pick.
const ins=sql.prepare('INSERT INTO fan_picks(user_id,match_key,title,kickoff,home,away,market,selection) VALUES(?,?,?,?,?,?,?,?)');
ins.run(a,'m1|1000','Alpha vs Beta',1000,2,1,'score','');
ins.run(a,'m2|2000','Gamma vs Delta',2000,1,0,'result','1');
ins.run(a,'m3|9999999999999','Future vs Pending',9999999999999,3,3,'score','');
sql.prepare('INSERT INTO fan_results(match_key,home,away) VALUES(?,?,?)').run('m1|1000',2,1);
sql.prepare('INSERT INTO fan_results(match_key,home,away) VALUES(?,?,?)').run('m2|2000',0,2);

assert.equal((await call('social/predictions')).status,401);
assert.equal((await call('social/predictions?id=invalid',bob)).status,400);
assert.equal((await call('social/predictions?id='+'0'.repeat(64),bob)).status,404);

// Bob views Alice: settled only, newest first, pending hidden.
const res=await call('social/predictions?id='+a,bob);assert.equal(res.status,200);
const data=await res.json();
assert.equal(data.id,a);assert.equal(data.name,'Alice');
assert.deepEqual(data.picks.map(p=>p.match_key),['m2|2000','m1|1000']);
assert.equal(data.picks.some(p=>p.match_key.startsWith('m3')),false,'pending pick must stay private');
assert.equal(data.picks[1].result_home,2);assert.equal(data.picks[1].home,2);
for(const p of data.picks){assert.equal('user_id' in p,false);}

// Own history works without an id; someone with no picks gets an empty list.
assert.equal((await (await call('social/predictions',alice)).json()).picks.length,2);
assert.deepEqual((await (await call('social/predictions?id='+b,alice)).json()).picks,[]);

// Banned fans are not listed.
sql.prepare('INSERT INTO fan_bans(user_id,reason,banned_at) VALUES(?,?,?)').run(a,'test',Date.now());
assert.equal((await call('social/predictions?id='+a,bob)).status,404);
console.log('fan_prediction_history ok');
