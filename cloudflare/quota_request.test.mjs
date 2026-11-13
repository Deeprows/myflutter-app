// Node 22+: node cloudflare/quota_request.test.mjs
// Extra AI quota: WhatsApp request -> admin grant / revoke, on a database created BEFORE the contact column existed.
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import worker from './worker.js';
const sql=new DatabaseSync(':memory:');
const DB={prepare(query){let args=[];const st={bind(...a){args=a;return st;},
  async first(){return sql.prepare(query).get(...args)||null;},
  async all(){return {results:sql.prepare(query).all(...args)};},
  async run(){return /RETURNING/i.test(query)?{results:sql.prepare(query).all(...args)}:sql.prepare(query).run(...args);}};return st;},
  async batch(list){sql.exec('BEGIN');try{const r=[];for(const s of list)r.push(await s.run());sql.exec('COMMIT');return r;}catch(e){sql.exec('ROLLBACK');throw e;}}};
// Old deployment: a quota table with an older layout (no user_name, note or contact) and one existing row.
sql.exec("CREATE TABLE fan_ai_quota_requests (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, amount INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'pending', created_at INTEGER NOT NULL)");
sql.prepare("INSERT INTO fan_ai_quota_requests(id,user_id,amount,status,created_at) VALUES('old1','someone-else',10,'rejected',1)").run();
const keys=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const jwk=await crypto.subtle.exportKey('jwk',keys.publicKey);jwk.kid='k';
const env={DB,GOOGLE_WEB_CLIENT_ID:'web-client.apps.googleusercontent.com',ADMIN_TOKEN:'secret'};
const now=Math.floor(Date.now()/1000);
async function idToken(){const enc=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
  const body=enc({alg:'RS256',kid:jwk.kid})+'.'+enc({iss:'https://accounts.google.com',aud:env.GOOGLE_WEB_CLIENT_ID,sub:'alice-google-id',email:'alice@gmail.com',email_verified:true,name:'Alice',iat:now,exp:now+3600});
  const sig=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',keys.privateKey,new TextEncoder().encode(body));return body+'.'+Buffer.from(sig).toString('base64url');}
globalThis.fetch=async(u)=>{u=String(u);if(u==='https://www.googleapis.com/oauth2/v3/certs')return new Response(JSON.stringify({keys:[jwk]}),{headers:{'cache-control':'public,max-age=3600'}});return new Response('{}',{status:404});};
const bearer=await idToken();
const call=(path,body)=>worker.fetch(new Request('https://feed.test/fan/'+path,{method:body?'POST':'GET',headers:{'content-type':'application/json',authorization:'Bearer '+bearer},...(body?{body:JSON.stringify(body)}:{})}),env,{});
const admin=(fields)=>{const f=new FormData();f.set('token','secret');for(const [k,v] of Object.entries(fields))f.set(k,String(v));return worker.fetch(new Request('https://feed.test/sub/admin',{method:'POST',body:f}),env,{});};
assert.equal((await call('auth',{mode:'signup',idToken:bearer})).status,200);
const uid=sql.prepare('SELECT id FROM fan_users').get().id;
sql.exec("CREATE TABLE IF NOT EXISTS subs (install_id TEXT PRIMARY KEY, email TEXT, expires_at INTEGER NOT NULL DEFAULT 0, source TEXT, updated_at INTEGER NOT NULL DEFAULT 0)");
sql.prepare("INSERT OR REPLACE INTO subs(install_id,email,expires_at,source,updated_at) VALUES(?,?,?,?,?)").run(uid,'alice@gmail.com',Date.now()+30*86400000,'test',Date.now());
// Not exhausted yet: no card, no request.
let st=await (await call('ai-quota/status')).json();
assert.equal(st.exhausted,false);assert.equal(st.daily_limit,35);assert.deepEqual(st.amounts,[10,20,50]);
assert.equal((await call('ai-quota/request',{amount:10,contact:'+234 801 234 5678'})).status,403);
// 35 analyses used today.
sql.prepare("INSERT INTO fan_ai_limits(bucket,count,expires) VALUES(?,?,?)").run(`day:${uid}:${Math.floor(Date.now()/86400000)}`,35,(Math.floor(Date.now()/86400000)+1)*86400000);
st=await (await call('ai-quota/status')).json();assert.equal(st.exhausted,true);
assert.equal((await call('ai-quota/request',{amount:10})).status,400,'WhatsApp number is required');
assert.equal((await call('ai-quota/request',{amount:7,contact:'+234 801 234 5678'})).status,400);
const ok=await call('ai-quota/request',{amount:20,contact:'+234 801 234 5678'});
assert.equal(ok.status,200,await ok.clone().text());
assert.equal((await call('ai-quota/request',{amount:20,contact:'+234 801 234 5678'})).status,409);
// Admin page lists it with a WhatsApp link, then grants.
let page=await (await worker.fetch(new Request('https://feed.test/sub/admin?token=secret'),env,{})).text();
assert.match(page,/AI quota requests \(1\)/);assert.match(page,/https:\/\/wa\.me\/2348012345678/);
const reqId=sql.prepare('SELECT id FROM fan_ai_quota_requests').get().id;
assert.equal((await admin({action:'quota_grant',quota_id:reqId,granted:25})).status,200);
st=await (await call('ai-quota/status')).json();assert.equal(st.remaining,25);assert.equal(st.pending,null);
page=await (await worker.fetch(new Request('https://feed.test/sub/admin?token=secret'),env,{})).text();
assert.match(page,/Extra quota in use/);assert.match(page,/<b>25<\/b> unused/);
// Revoke part, then the rest.
await admin({action:'quota_revoke',user_id:uid,remove:5});
st=await (await call('ai-quota/status')).json();assert.equal(st.remaining,20);
await admin({action:'quota_revoke',user_id:uid});
st=await (await call('ai-quota/status')).json();assert.equal(st.remaining,0);
// A second request can be dismissed.
assert.equal((await call('ai-quota/request',{amount:10,contact:'0801 234 5678'})).status,200);
const id2=sql.prepare("SELECT id FROM fan_ai_quota_requests WHERE status='pending'").get().id;
await admin({action:'quota_reject',quota_id:id2});
assert.equal(sql.prepare("SELECT status FROM fan_ai_quota_requests WHERE id=?").get(id2).status,'rejected');
assert.equal(sql.prepare("SELECT status FROM fan_ai_quota_requests WHERE id='old1'").get().status,'rejected','old rows are kept');
console.log('quota request / grant / revoke tests passed');
