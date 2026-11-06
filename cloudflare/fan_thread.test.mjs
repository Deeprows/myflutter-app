// Node 22+: node cloudflare/fan_thread.test.mjs
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

const alice=await token(),bob=await token({sub:'bob',email:'bob@gmail.com',name:'Bob'}),carol=await token({sub:'carol',email:'carol@gmail.com',name:'Carol'});
for(const bearer of [alice,bob,carol])assert.equal((await call('auth',{body:{mode:'signup',idToken:bearer}})).status,200);
const state=await (await call('state',{bearer:alice})).json(),a=state.id;
const b=(await (await call('state',{bearer:bob})).json()).id,c=(await (await call('state',{bearer:carol})).json()).id;

const social=(path,body,bearer=alice)=>call('social/'+path,{body,bearer});
const objects=new Map();
const media={
  async put(key,bytes,opts){objects.set(key,{bytes,type:opts.httpMetadata.contentType});return {};},
  async get(key){const v=objects.get(key);return v?{body:v.bytes,writeHttpMetadata(h){h.set('content-type',v.type);}}:null;},
  async delete(key){objects.delete(key);},
};
const mediaEnv={...env,FAN_MEDIA:media};
const cooldown=()=>sql.prepare('UPDATE fan_users SET last_post=0').run();
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jN2kAAAAASUVORK5CYII=','base64');
const gif=Buffer.from('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7','base64');
async function multipart(path,fields,bearer=alice,e=mediaEnv){
  const form=new FormData();
  for(const [k,v] of Object.entries(fields)){if(v instanceof Buffer)form.set(k,new Blob([v]),'f');else form.set(k,v);}
  return worker.fetch(new Request('https://feed.test/fan/'+path,{method:'POST',headers:{authorization:'Bearer '+bearer},body:form}),e,{});
}
for(const bearer of [alice,bob]){await social('profile',{name:bearer===alice?'Alpha Fan':'Beta Fan',bio:''},bearer);}
cooldown();
let response=await multipart('post',{kind:'banter',text:'Chelsea were class today'},alice);assert.equal(response.status,200);
const postId=(await response.json()).id;

// ---- Views: one per fan, counted for everyone ----
assert.equal((await social('view',{id:postId},bob)).status,200);
assert.equal((await social('view',{id:postId},bob)).status,200);
assert.equal((await social('view',{id:postId},alice)).status,200);
assert.equal((await social('view',{id:'bad'},bob)).status,400);
let post=(await (await social('post?id='+postId)).json()).post;
assert.equal(post.views,2);assert.equal(post.reposts,0);assert.equal(post.reposted,0);

// ---- Replies to comments, with image / GIF ----
cooldown();
response=await multipart('social/comment',{id:postId,text:'First!'},bob);assert.equal(response.status,200);
const first=(await response.json()).id;
cooldown();
response=await multipart('social/comment',{id:postId,parent_id:first,text:'Nice one',image:png},alice);assert.equal(response.status,200);
const reply=(await response.json()).id;
cooldown();
response=await multipart('social/comment',{id:postId,parent_id:reply,text:'',image:gif},bob);assert.equal(response.status,200);
const nested=(await response.json()).id;
cooldown();
assert.equal((await multipart('social/comment',{id:postId,parent_id:reply,text:'',},bob)).status,400);
assert.equal((await multipart('social/comment',{id:postId,parent_id:'not-a-comment',text:'x'},bob)).status,400);
cooldown();
assert.equal((await multipart('social/comment',{id:postId,parent_id:'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',text:'x'},bob)).status,404);
cooldown();
assert.equal((await multipart('social/comment',{id:postId,text:'bad',image:Buffer.from('<svg onload=1>')},bob)).status,400);
assert.equal((await multipart('social/comment',{id:postId,text:'no r2',image:png},bob,env)).status,503);
let data=await (await call('social/comments?id='+postId,{bearer:alice})).json();
const byId=Object.fromEntries(data.comments.map(c=>[c.id,c]));
assert.equal(data.comments.length,3);
assert.equal(byId[first].root_id,'');assert.equal(byId[reply].root_id,first);assert.equal(byId[nested].root_id,first,'replies to replies stay in the same thread');
assert.equal(byId[reply].parent_id,first);assert.equal(byId[nested].parent_id,reply);
assert.equal(byId[nested].reply_to_name,'Alpha Fan');assert.equal(byId[nested].has_image,1);assert.equal(byId[first].has_image,0);
let img=await call('comment-image/'+reply,{bearer:alice,e:mediaEnv});assert.equal(img.status,200);assert.equal(img.headers.get('content-type'),'image/png');
img=await call('comment-image/'+nested,{bearer:alice,e:mediaEnv});assert.equal(img.headers.get('content-type'),'image/gif');
assert.equal((await call('comment-image/'+first,{bearer:alice,e:mediaEnv})).status,404);
// Comment likes
assert.equal((await social('comment-like',{id:reply,liked:true},bob)).status,200);
assert.equal((await social('comment-like',{id:reply,liked:true},bob)).status,200);
assert.equal((await social('comment-like',{id:reply,liked:'yes'},bob)).status,400);
data=await (await call('social/comments?id='+postId,{bearer:bob})).json();
const liked=data.comments.find(c=>c.id===reply);assert.equal(liked.likes,1);assert.equal(liked.liked,1);
// Deleting a reply removes its image
assert.equal((await call('social/comment-delete',{body:{id:reply},bearer:alice,e:mediaEnv})).status,200);
assert.equal(objects.has('fan-comments/'+reply),false);
post=(await (await social('post?id='+postId)).json()).post;assert.equal(post.comments,2);
// Plain-JSON comments keep working for older app versions
cooldown();assert.equal((await social('comment',{id:postId,text:'old client'},bob)).status,200);

// ---- Repost / quote ----
assert.equal((await social('repost',{id:postId,reposted:'yes'},bob)).status,400);
response=await social('repost',{id:postId,reposted:true},bob);assert.equal(response.status,200);
assert.equal((await response.json()).reposts,1);
assert.equal((await (await social('repost',{id:postId,reposted:true},bob)).json()).reposts,1,'idempotent');
post=(await (await social('post?id='+postId,undefined,bob)).json()).post;
assert.equal(post.reposts,1);assert.equal(post.reposted,1);
let feed=(await (await call('posts',{bearer:alice})).json()).posts;
const repost=feed.find(p=>p.kind==='repost');
assert.ok(repost);assert.equal(repost.quote_of,postId);assert.equal(repost.q_name,'Alpha Fan');assert.equal(repost.q_text,'Chelsea were class today');
// Reposting the repost reposts the original (no chains)
assert.equal((await (await social('repost',{id:repost.id,reposted:true},alice)).json()).id,postId);
// Quote
cooldown();
response=await multipart('post',{kind:'banter',text:'Agreed, top class',quote_of:postId},bob);assert.equal(response.status,200);
const quote=(await response.json()).id;
cooldown();assert.equal((await multipart('post',{kind:'banter',text:'',quote_of:postId},bob)).status,400);
cooldown();assert.equal((await multipart('post',{kind:'banter',text:'x',quote_of:'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'},bob)).status,404);
feed=(await (await call('posts',{bearer:alice})).json()).posts;
assert.equal(feed.find(p=>p.id===quote).q_name,'Alpha Fan');
post=(await (await social('post?id='+postId)).json()).post;assert.equal(post.reposts,3);
// Undo repost
assert.equal((await (await social('repost',{id:postId,reposted:false},bob)).json()).reposts,2);
post=(await (await social('post?id='+postId,undefined,bob)).json()).post;assert.equal(post.reposted,0);
// Deleting the original leaves the quote readable but without the original
assert.equal((await call('post/delete',{body:{id:postId},bearer:alice})).status,200);
feed=(await (await call('posts',{bearer:alice})).json()).posts;
assert.equal(feed.find(p=>p.id===quote).q_name,null);
// Notifications
const kinds=(await (await call('social/notifications',{bearer:alice})).json()).notifications.map(n=>n.kind);
for(const k of ['comment','repost','quote'])assert.ok(kinds.includes(k),k);
const bobKinds=(await (await call('social/notifications',{bearer:bob})).json()).notifications.map(n=>n.kind);
assert.ok(bobKinds.includes('reply'),'the author of the parent comment is told about the reply');
console.log('Thread: views, replies to comments with image/GIF, nested threads, comment likes, reposts, quotes and cleanup passed.');
