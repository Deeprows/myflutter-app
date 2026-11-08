// Run: node --no-warnings cloudflare/subscription_account.test.mjs   (Node 22+)
// Premium belongs to the logged-in Gmail account, never to the phone.
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import worker from './worker.js';

const sql=new DatabaseSync(':memory:');
const DB={prepare(query){let args=[];const st={bind(...a){args=a;return st;},
  async first(){return sql.prepare(query).get(...args)||null;},
  async all(){return {results:sql.prepare(query).all(...args)};},
  async run(){return sql.prepare(query).run(...args);}};return st;},
  async batch(list){sql.exec('BEGIN');try{const r=[];for(const s of list)r.push(await s.run());sql.exec('COMMIT');return r;}catch(e){sql.exec('ROLLBACK');throw e;}}};
const keys=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const jwk=await crypto.subtle.exportKey('jwk',keys.publicKey);jwk.kid='k1';
const store=new Map();
globalThis.caches={default:{match:async r=>{const x=store.get(r.url);return x?x.clone():undefined;},put:async(r,x)=>{store.set(r.url,x);}}};
const txs=new Map();let initBody=null;
globalThis.fetch=async(url,opts={})=>{
  const u=String(url);
  if(u==='https://www.googleapis.com/oauth2/v3/certs')return new Response(JSON.stringify({keys:[jwk]}),{headers:{'cache-control':'public,max-age=3600'}});
  if(u.includes('open.er-api.com'))return new Response(JSON.stringify({rates:{USD:0.00065}}));
  if(u.endsWith('/transaction/initialize')){
    initBody=JSON.parse(opts.body);
    txs.set(initBody.reference,{status:'success',reference:initBody.reference,currency:'NGN',amount:initBody.amount,customer:{email:initBody.email},metadata:initBody.metadata});
    return new Response(JSON.stringify({status:true,data:{authorization_url:'https://checkout.paystack.com/x',reference:initBody.reference}}));
  }
  const m=/\/transaction\/verify\/(.+)$/.exec(u);
  if(m){const t=txs.get(decodeURIComponent(m[1]));return new Response(JSON.stringify(t?{status:true,data:t}:{status:false}),{status:t?200:404});}
  return new Response('[]');
};
const env={DB,GOOGLE_WEB_CLIENT_ID:'web-client.apps.googleusercontent.com',PAYSTACK_SECRET_KEY:'sk_test',ADMIN_TOKEN:'adm'};
const now=Math.floor(Date.now()/1000);
async function token(sub,email){
  const enc=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
  const body=enc({alg:'RS256',kid:jwk.kid})+'.'+enc({iss:'https://accounts.google.com',aud:env.GOOGLE_WEB_CLIENT_ID,sub,email,email_verified:true,name:sub,iat:now,exp:now+3600});
  const sig=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',keys.privateKey,new TextEncoder().encode(body));
  return body+'.'+Buffer.from(sig).toString('base64url');
}
const alice=await token('alice-sub','alice@gmail.com'),bob=await token('bob-sub','bob@gmail.com');
const call=(path,{body,bearer,install}={})=>worker.fetch(new Request('https://feed.test'+path,{method:body?'POST':'GET',
  headers:{'content-type':'application/json',...(bearer?{authorization:'Bearer '+bearer}:{}),...(install?{'x-install-id':install}:{})},
  ...(body?{body:JSON.stringify(body)}:{})}),env,{waitUntil(){}});
const json=async r=>r.json();

// Register both Gmails.
const aliceId=(await json(await call('/fan/auth',{body:{mode:'signup',idToken:alice}}))).user.id;
const bobId=(await json(await call('/fan/auth',{body:{mode:'signup',idToken:bob}}))).user.id;
assert.notEqual(aliceId,bobId);

// The old bug: a phone that paid before accounts existed (install id + Alice's e-mail).
const PHONE='a1b2c3d4e5f60718293a4b5c6d7e8f90';
assert.equal((await call('/sub/status?install='+PHONE)).status,401,'no Gmail login = no premium answer');
await call('/sub/status',{bearer:bob});
sql.prepare("INSERT INTO subs(install_id,email,expires_at,source,updated_at) VALUES(?,?,?,?,?)").run(PHONE,'alice@gmail.com',Date.now()+20*86400000,'paystack',Date.now());
// Leaked copy from the old code on Bob's fan profile.
sql.prepare('UPDATE fan_users SET premium_until=? WHERE id=?').run(Date.now()+20*86400000,bobId);

// Bob logs in on the same phone: he must NOT get Alice's premium.
let j=await json(await call('/sub/status',{bearer:bob,install:PHONE}));
assert.equal(j.active,false,'another Gmail on the same phone gets nothing');
assert.equal(sql.prepare('SELECT expires_at FROM subs WHERE install_id=?').get(PHONE).expires_at>Date.now(),true,'Bob must not use up the old purchase');

// Bob cannot ask about Alice's id either.
j=await json(await call('/sub/status?install='+aliceId,{bearer:bob}));
assert.equal(j.active,false);

// Fan Zone side: no blue tick / editing for Bob, and his leaked copy is cleared.
j=await json(await call('/fan/premium/status',{bearer:bob,install:PHONE}));
assert.equal(j.premium,false);
assert.equal(sql.prepare('SELECT premium_until FROM fan_users WHERE id=?').get(bobId).premium_until,0);

// Alice (the Gmail that paid) gets it, once.
j=await json(await call('/sub/status',{bearer:alice,install:PHONE}));
assert.equal(j.active,true);
assert.equal(sql.prepare('SELECT expires_at FROM subs WHERE install_id=?').get(PHONE).expires_at,0,'old phone row is switched off');
j=await json(await call('/sub/status',{bearer:bob,install:PHONE}));
assert.equal(j.active,false);
j=await json(await call('/fan/premium/status',{bearer:alice,install:PHONE}));
assert.equal(j.premium,true);

// Paying while logged in: the Gmail account is the owner, whatever e-mail was typed.
let r=await call('/sub/start',{bearer:bob,body:{install_id:aliceId,email:'typed@example.com',recurring:false}});
assert.equal(r.status,200);
assert.equal(initBody.email,'bob@gmail.com');
assert.equal(initBody.metadata.install_id,bobId);
const ref=(await json(r)).reference;
j=await json(await call('/sub/verify?reference='+ref));
assert.equal(j.active,true);
j=await json(await call('/sub/status',{bearer:bob}));
assert.equal(j.active,true);
j=await json(await call('/fan/premium/status',{bearer:bob}));
assert.equal(j.premium,true);

// Logging out / a third Gmail: nothing.
const carol=await token('carol-sub','carol@gmail.com');
j=await json(await call('/sub/status',{bearer:carol,install:PHONE}));
assert.equal(j.active,false);
assert.equal((await call('/sub/status',{bearer:'junk'})).status,401);

// Restore moves the time to the account (the old holder loses it).
txs.set('OLDREF',{status:'success',reference:'OLDREF',currency:'NGN',amount:200000,customer:{email:'bob@gmail.com'},metadata:{}});
r=await call('/sub/restore',{bearer:carol,body:{email:'bob@gmail.com',reference:'OLDREF'}});
j=await json(r);assert.equal(j.active,true);
assert.equal((await json(await call('/sub/status',{bearer:bob}))).active,false,'moved away from Bob');
assert.equal((await json(await call('/sub/status',{bearer:carol}))).active,true);
console.log('Account-bound premium: no sharing between Gmails on one phone, spoof-proof ids, legacy hand-over, leak cleanup and restore passed.');
