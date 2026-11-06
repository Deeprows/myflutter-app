// Node 22+: node cloudflare/fan_notifications.test.mjs
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
const pkcs8=Buffer.from(await crypto.subtle.exportKey('pkcs8',keys.privateKey)).toString('base64');
const pem=`-----BEGIN PRIVATE KEY-----\n${pkcs8.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;
const fcm=[];
globalThis.fetch=async(url,init)=>{
  url=String(url);
  if(url==='https://www.googleapis.com/oauth2/v3/certs')return new Response(JSON.stringify({keys:[jwk]}),{headers:{'cache-control':'public,max-age=3600'}});
  if(url==='https://oauth2.googleapis.com/token')return new Response(JSON.stringify({access_token:'fcm-access',expires_in:3600}));
  if(url.startsWith('https://fcm.googleapis.com/v1/projects/demo-project/messages:send')) {
    const message=JSON.parse(init.body).message;fcm.push(message);
    return message.token==='gone-device-token-0000000'?new Response('{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}',{status:404}):new Response('{}');
  }
  return new Response('[]');
};
const env={DB,GOOGLE_WEB_CLIENT_ID:'web-client.apps.googleusercontent.com',ADMIN_TOKEN:'secret'};
const pending=[];const ctx={waitUntil:p=>pending.push(p)};
const flush=async()=>{await Promise.all(pending.splice(0));};
const now=Math.floor(Date.now()/1000);
async function token(changes={}){
  const enc=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
  const payload={iss:'https://accounts.google.com',aud:env.GOOGLE_WEB_CLIENT_ID,sub:'alice-google-id',email:'alice@gmail.com',email_verified:true,name:'Alice',iat:now,exp:now+3600,...changes};
  const body=enc({alg:'RS256',kid:jwk.kid})+'.'+enc(payload);
  const signature=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',keys.privateKey,new TextEncoder().encode(body));
  return body+'.'+Buffer.from(signature).toString('base64url');
}
async function call(path,{body,bearer,e=env}={}){
  return worker.fetch(new Request('https://feed.test/fan/'+path,{method:body?'POST':'GET',
    headers:{'content-type':'application/json',...(bearer?{authorization:'Bearer '+bearer}:{})},
    ...(body?{body:JSON.stringify(body)}:{})}),e,ctx);
}
const alice=await token(),bob=await token({sub:'bob',email:'bob@gmail.com',name:'Bob'});
for(const bearer of [alice,bob])assert.equal((await call('auth',{body:{mode:'signup',idToken:bearer}})).status,200);
const a=(await (await call('state',{bearer:alice})).json()).id,b=(await (await call('state',{bearer:bob})).json()).id;
const social=(path,body,bearer=alice)=>call('social/'+path,{body,bearer});
assert.equal((await social('profile',{name:'Alpha Fan',bio:''})).status,200);
assert.equal((await social('profile',{name:'Bravo Fan',bio:''},bob)).status,200);
const postId=crypto.randomUUID(),ownPost=crypto.randomUUID();
sql.prepare('INSERT INTO fan_posts(id,user_id,kind,text,at) VALUES(?,?,?,?,?)').run(postId,b,'banter','Bob post',Date.now());
sql.prepare('INSERT INTO fan_posts(id,user_id,kind,text,at) VALUES(?,?,?,?,?)').run(ownPost,a,'banter','Alice post',Date.now());

// Nothing yet.
let inbox=await (await social('notifications',undefined,bob)).json();
assert.deepEqual(inbox.notifications,[]);assert.equal(inbox.unread,0);

// Follow, like, comment -> three notifications for Bob.
assert.equal((await social('follow',{id:b,following:true})).status,200);
assert.equal((await social('like',{id:postId,liked:true})).status,200);
assert.equal((await social('comment',{id:postId,text:'  Great   match!  '})).status,200);
// Repeats never notify twice (follow toggling, unlike + like).
await social('follow',{id:b,following:false});await social('follow',{id:b,following:true});
await social('like',{id:postId,liked:false});await social('like',{id:postId,liked:true});
// Self activity never notifies.
await social('like',{id:ownPost,liked:true});
inbox=await (await social('notifications',undefined,bob)).json();
assert.equal(inbox.notifications.length,3);assert.equal(inbox.unread,3);
assert.deepEqual(inbox.notifications.map(n=>n.kind).sort(),['comment','follow','like']);
const comment=inbox.notifications.find(n=>n.kind==='comment');
assert.equal(comment.actor_name,'Alpha Fan');assert.equal(comment.post_id,postId);assert.equal(comment.text,'Great   match!');
assert.equal(inbox.notifications.find(n=>n.kind==='follow').actor_id,a);
// Alice (the actor) has nothing.
assert.equal((await (await social('notifications',undefined,alice)).json()).notifications.length,0);

// Mark as read.
await new Promise(r=>setTimeout(r,5));
assert.equal((await social('notifications-read',{},bob)).status,200);
assert.equal((await (await social('notifications',undefined,bob)).json()).unread,0);

// Devices + push.
assert.equal((await social('device',{token:'short'},bob)).status,400);
assert.equal((await social('device',{token:'device-token-for-bob-0000000'},bob)).status,200);
assert.equal((await social('device',{token:'gone-device-token-0000000'},bob)).status,200);
const pushEnv={...env,FIREBASE_SERVICE_ACCOUNT:JSON.stringify({client_email:'svc@demo-project.iam.gserviceaccount.com',private_key:pem,project_id:'demo-project'})};
const carol=await token({sub:'carol',email:'carol@gmail.com',name:'Carol'});
assert.equal((await call('auth',{body:{mode:'signup',idToken:carol}})).status,200);
assert.equal((await call('social/profile',{body:{name:'Charlie Fan',bio:''},bearer:carol})).status,200);
const res=await call('social/like',{body:{id:postId,liked:true},bearer:carol,e:pushEnv});assert.equal(res.status,200);
await flush();
assert.equal(fcm.length,2);
const sent=fcm.find(m=>m.token==='device-token-for-bob-0000000');
assert.equal(sent.notification.title,'New like');assert.equal(sent.notification.body,'Charlie Fan liked your post');
assert.equal(sent.data.type,'social');assert.equal(sent.data.kind,'like');assert.equal(sent.data.postId,postId);assert.ok(sent.data.nid);
assert.equal(sent.android.notification.channel_id,'social');
// The expired device was removed after FCM said UNREGISTERED.
assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM fan_devices').get().n,1);
// Signing the device out stops pushes.
assert.equal((await social('device',{token:'device-token-for-bob-0000000',enabled:false},bob)).status,200);
assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM fan_devices').get().n,0);
console.log('Social notifications: follow/like/comment inbox, de-duplication, self-actions, read marker, device registration and FCM push passed.');
