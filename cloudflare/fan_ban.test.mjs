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

// ---- Admin ban / unban ----
const alice=await token(),bob=await token({sub:'bob',email:'bob@gmail.com',name:'Bob'});
for(const bearer of [alice,bob])assert.equal((await call('auth',{body:{mode:'signup',idToken:bearer}})).status,200);
const a=(await (await call('state',{bearer:alice})).json()).id;
const b=(await (await call('state',{bearer:bob})).json()).id;
const admin=(path,body)=>worker.fetch(new Request('https://feed.test/fan/admin/'+path,{method:body?'POST':'GET',
  headers:{'content-type':'application/json',authorization:'Bearer secret'},...(body?{body:JSON.stringify(body)}:{})}),env,{});

// Bob has content that breaks the rules.
const postId=crypto.randomUUID(),commentId=crypto.randomUUID(),messageId=crypto.randomUUID();
sql.prepare('INSERT INTO fan_posts(id,user_id,kind,text,at) VALUES(?,?,?,?,?)').run(postId,b,'banter','rule-breaking post',Date.now());
sql.prepare('INSERT INTO fan_comments(id,post_id,user_id,text,at) VALUES(?,?,?,?,?)').run(commentId,postId,b,'rule-breaking comment',Date.now());
sql.prepare('INSERT INTO fan_messages(id,room,user_id,text,at) VALUES(?,?,?,?,?)').run(messageId,'lounge',b,'rule-breaking chat',Date.now());
assert.equal((await (await call('posts',{bearer:alice})).json()).posts.length,1);

// Only the admin token may ban.
assert.equal((await call('admin/ban',{body:{id:b},bearer:alice})).status,401);
assert.equal((await worker.fetch(new Request('https://feed.test/fan/admin/ban',{method:'POST',body:'{}'}),env,{})).status,401);
assert.equal((await admin('ban',{id:'nope'})).status,400);
assert.equal((await admin('ban',{id:'f'.repeat(64)})).status,404);

// The admin can find Bob by name or email.
let users=(await (await admin('users?q=bob')).json()).users;
assert.deepEqual(users.map(u=>u.id),[b]);assert.equal(users[0].posts,1);assert.equal(users[0].banned,false);
assert.equal((await (await admin('users?q=bob@gmail')).json()).users.length,1);

// Ban with content removal.
assert.equal((await admin('ban',{id:b,reason:'Harassment',removeContent:true})).status,200);
users=(await (await admin('users?q=bob')).json()).users;
assert.equal(users[0].banned,true);assert.equal(users[0].ban_reason,'Harassment');assert.equal(users[0].posts,0);

// Banned fan is locked out everywhere, with the reason.
for(const [path,body] of [['state'],['posts'],['message',{text:'hi',room:'lounge'}],['social/profile'],['post',{kind:'banter',text:'hello'}]]) {
  const res=await call(path,{bearer:bob,body});assert.equal(res.status,403,path);
  const data=await res.json();assert.equal(data.banned,true);assert.match(data.error,/Harassment/);
}
let res=await call('auth',{body:{mode:'login',idToken:bob}});assert.equal(res.status,403);assert.equal((await res.json()).banned,true);

// Content is gone for everyone else; profile, leaderboard are hidden.
assert.equal((await (await call('posts',{bearer:alice})).json()).posts.length,0);
assert.equal((await (await call('messages?room=lounge',{bearer:alice})).json()).messages.length,0);
assert.equal((await call('social/profile?id='+b,{bearer:alice})).status,404);
assert.equal((await (await call('leaderboard',{bearer:alice})).json()).leaderboard.some(r=>r.id===b),false);
const reports=await (await admin('reports')).json();assert.ok(Array.isArray(reports.post_reports));

// Other fans are unaffected.
assert.equal((await call('state',{bearer:alice})).status,200);
assert.equal((await call('message',{bearer:alice,body:{text:'still here',room:'lounge'}})).status,200);

// Unban restores access; removed content stays removed.
assert.equal((await admin('unban',{id:b})).status,200);
assert.equal((await call('state',{bearer:bob})).status,200);
assert.equal((await call('auth',{body:{mode:'login',idToken:bob}})).status,200);
assert.equal(sql.prepare('SELECT hidden FROM fan_posts WHERE id=?').get(postId).hidden,1);

// Ban without removing content keeps it visible.
sql.prepare('INSERT INTO fan_posts(id,user_id,kind,text,at) VALUES(?,?,?,?,?)').run(crypto.randomUUID(),b,'banter','kept post',Date.now());
assert.equal((await admin('ban',{id:b,reason:'',removeContent:false})).status,200);
assert.equal(sql.prepare("SELECT COUNT(*) AS n FROM fan_posts WHERE user_id=? AND hidden=0").get(b).n,1);
assert.equal((await (await call('state',{bearer:bob})).json()).error.includes('Reason'),false);
console.log('fan_ban.test.mjs passed');
