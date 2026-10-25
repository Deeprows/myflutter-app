// Node 22+: node cloudflare/fan_auth.test.mjs
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import worker,{verifyFanGoogleToken} from './worker.js';
const sql=new DatabaseSync(':memory:');
const DB={prepare(query){let args=[];const st={bind(...a){args=a;return st;},
  async first(){return sql.prepare(query).get(...args)||null;},
  async all(){return {results:sql.prepare(query).all(...args)};},
  async run(){return sql.prepare(query).run(...args);}};return st;},
  async batch(list){sql.exec('BEGIN');try{const result=[];for(const s of list)result.push(await s.run());sql.exec('COMMIT');return result;}catch(e){sql.exec('ROLLBACK');throw e;}}};
const keys=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const jwk=await crypto.subtle.exportKey('jwk',keys.publicKey);jwk.kid='test-google-key';
let keyFetches=0;
globalThis.fetch=async(url)=>{
  if(String(url)==='https://www.googleapis.com/oauth2/v3/certs'){
    keyFetches++;return new Response(JSON.stringify({keys:[jwk]}),{headers:{'cache-control':'public,max-age=3600'}});
  }
  return new Response('[]');
};
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
const alice=await token(),bob=await token({sub:'bob-google-id',email:'bob@gmail.com',name:'Bob'});
assert.equal((await verifyFanGoogleToken(alice,env)).email,'alice@gmail.com');
for(const invalid of [{aud:'wrong-client'},{iss:'https://evil.test'},{exp:now-1},{iat:now+500},
  {email_verified:false},{email:'alice@untrusted.test'},{sub:''}]){
  assert.equal(await verifyFanGoogleToken(await token(invalid),env),null);
}
const forged=alice.split('.');forged[1]=Buffer.from(JSON.stringify({sub:'forged'})).toString('base64url');
assert.equal(await verifyFanGoogleToken(forged.join('.'),env),null);
const signature=alice.split('.');signature[2]='AAAA';assert.equal(await verifyFanGoogleToken(signature.join('.'),env),null);
assert.equal(keyFetches,1,'Google keys are cached between verifications');
assert.equal((await call('auth',{body:{mode:'signup',idToken:alice},e:{DB}})).status,503);
assert.equal((await call('auth',{body:{mode:'login',idToken:alice}})).status,404);
assert.equal((await call('state',{bearer:alice})).status,403,'Verified but unregistered accounts are blocked');
// Seed an actual device profile through the legacy API before enabling OAuth.
const legacy='ab'.repeat(32);
assert.equal((await call('profile',{e:{DB},bearer:legacy,body:{name:'Legacy Nickname'}})).status,200);
const legacyId=sql.prepare('SELECT id FROM fan_users WHERE name=?').get('Legacy Nickname').id;
sql.prepare('INSERT INTO fan_picks(user_id,match_key,title,kickoff,home,away) VALUES(?,?,?,?,?,?)').run(legacyId,'old-match','Old Home vs Old Away',Date.now()+100000,2,1);
sql.prepare('INSERT INTO fan_messages(id,room,user_id,text,at) VALUES(?,?,?,?,?)').run('legacy-message','lounge',legacyId,'Old comment',Date.now());
sql.prepare('INSERT INTO fan_posts(id,user_id,kind,text,at) VALUES(?,?,?,?,?)').run('legacy-post',legacyId,'prediction','Old prediction',Date.now());
let response=await call('auth',{body:{mode:'signup',idToken:alice,legacyToken:legacy}});
assert.equal(response.status,200);const account=(await response.json()).user;
assert.equal(account.email,'alice@gmail.com');assert.notEqual(account.id,legacyId);
assert.equal(sql.prepare('SELECT id FROM fan_users WHERE id=?').get(legacyId),undefined);
let state=await (await call('state',{bearer:alice})).json();
assert.equal(state.id,account.id);assert.equal(state.name,'Legacy Nickname');assert.equal(state.picks.length,1);
assert.equal(sql.prepare('SELECT user_id FROM fan_posts WHERE id=?').get('legacy-post').user_id,account.id);
assert.equal(sql.prepare('SELECT user_id FROM fan_messages WHERE id=?').get('legacy-message').user_id,account.id);
assert.equal((await call('state',{bearer:legacy})).status,401,'Old install credentials cannot access account-protected data');
assert.equal((await call('auth',{body:{mode:'signup',idToken:alice}})).status,409);
assert.equal((await call('auth',{body:{mode:'login',idToken:alice}})).status,200);
assert.equal((await call('auth',{body:{mode:'signup',idToken:bob,legacyToken:legacy}})).status,200);
const bobState=await (await call('state',{bearer:bob})).json();
assert.notEqual(bobState.id,account.id);assert.equal(bobState.picks.length,0);
assert.equal(sql.prepare('SELECT account_id FROM fan_legacy_claims WHERE legacy_id=?').get(legacyId).account_id,account.id);
const aliceNewToken=await token({iat:now+1,exp:now+3601});
state=await (await call('state',{bearer:aliceNewToken})).json();assert.equal(state.id,account.id);assert.equal(state.picks.length,1,'A new device/token resolves to the same account data');
assert.equal((await call('auth',{body:{mode:'signup',idToken:'not-a-token'}})).status,401);
assert.equal((await call('admin/matches',{bearer:'secret'})).status,200,'Existing admin token still works');
console.log('Google auth: JWT signature/audience/issuer/expiry/Gmail checks, key caching, signup/login, duplicate prevention, account isolation, cross-token persistence and legacy migration passed.');
