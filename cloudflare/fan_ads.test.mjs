// Run with Node 22+: node cloudflare/fan_ads.test.mjs
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import worker from './worker.js';
const sql = new DatabaseSync(':memory:');
const DB = {
  prepare(query) {
    let args=[];
    const stmt={
      bind(...v){args=v;return stmt;},
      async first(){return sql.prepare(query).get(...args) || null;},
      async all(){return {results:sql.prepare(query).all(...args)};},
      async run(){return sql.prepare(query).run(...args);},
    };
    return stmt;
  },
  async batch(list){for(const s of list) await s.run();return [];},
};
globalThis.fetch=async()=>new Response('[]');
const env={DB,ADMIN_TOKEN:'admin-secret'};
const admin='ab'.repeat(32), fan='cd'.repeat(32);
async function call(path,body,cred=admin){
  return worker.fetch(new Request('https://feed.test/fan/'+path,{
    method:body?'POST':'GET',headers:{authorization:'Bearer '+cred,'content-type':'application/json'},
    ...(body?{body:JSON.stringify(body)}:{}),
  }),env,{});
}
async function post(text,cred,extra={}){
  const form=new FormData();form.set('kind','banter');form.set('text',text);
  for(const [k,v] of Object.entries(extra))form.set(k,v);
  return worker.fetch(new Request('https://feed.test/fan/post',{method:'POST',headers:{authorization:'Bearer '+cred},body:form}),env,{});
}
const wait=()=>new Promise(r=>setTimeout(r,10));
assert.equal((await call('profile',{name:'Deeprowss Admin'},admin)).status,200);
assert.equal((await call('profile',{name:'Regular Fan'},fan)).status,200);
const adminId=(await (await call('social/profile',null,admin)).json()).profile.id;
// Not admin yet: nobody can publish ads, pin, or take the reserved handle.
assert.equal((await post('Buy now',admin,{is_ad:'1'})).status,403);
assert.equal((await call('social/handle',{handle:'DeeprowssAdmin'},admin)).status,400);
// Link the admin's Google account email (deeprows@gmail.com).
sql.prepare('INSERT INTO fan_accounts(id,google_sub,email,name,photo,created_at) VALUES(?,?,?,?,?,?)').run(adminId,'sub-1','Deeprows@Gmail.com','Deeprowss Admin','',Date.now());
assert.equal((await call('social/handle',{handle:'DeeprowssAdmin'},admin)).status,200);
assert.equal((await call('social/handle',{handle:'DeeprowssAdmin'},fan)).status,400);
let feed=await (await call('posts',null,admin)).json();
assert.equal(feed.is_admin,true);
assert.equal((await (await call('posts',null,fan)).json()).is_admin,false);
// Regular user cannot post an ad even by sending the field.
assert.equal((await post('Fake ad',fan,{is_ad:'1'})).status,403);
// Admin publishes an ad: it carries is_ad, stays out of the normal list and shows in `ads`.
assert.equal((await post('Advertise with Deeprowss',admin,{is_ad:'1'})).status,200);
await wait();sql.prepare('UPDATE fan_users SET last_post=0').run();
assert.equal((await post('Normal gist',fan)).status,200);
feed=await (await call('posts',null,fan)).json();
assert.equal(feed.posts.length,1);assert.equal(feed.posts[0].text,'Normal gist');
assert.equal(feed.ads.length,1);assert.equal(feed.ads[0].is_ad,1);assert.equal(feed.ads[0].handle,'DeeprowssAdmin');
// Pinning is admin only, with a day limit; pinned posts come back as `pinned` with a flag.
const postId=feed.posts[0].id;
assert.equal((await call('post/pin',{id:postId,pinned:true,days:7},fan)).status,403);
assert.equal((await call('post/pin',{id:postId,pinned:true,days:400},admin)).status,400);
assert.equal((await call('post/pin',{id:postId,pinned:true,days:7},admin)).status,200);
feed=await (await call('posts',null,fan)).json();
assert.equal(feed.pinned.length,1);assert.equal(feed.pinned[0].id,postId);assert.equal(feed.pinned[0].pinned,1);
// An expired pin disappears; unpin clears it.
sql.prepare('UPDATE fan_posts SET pin_until=? WHERE id=?').run(Date.now()-1000,postId);
assert.equal((await (await call('posts',null,fan)).json()).pinned.length,0);
assert.equal((await call('post/pin',{id:postId,pinned:true,days:0},admin)).status,200);
assert.equal((await (await call('posts',null,fan)).json()).pinned.length,1);
assert.equal((await call('post/pin',{id:postId,pinned:false},admin)).status,200);
assert.equal((await (await call('posts',null,fan)).json()).pinned.length,0);
console.log('Fan ads and pins: admin-only ads, ad slot feed, sponsored pinning, expiry and reserved handle passed.');
