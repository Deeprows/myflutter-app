// Run with Node 22+: node cloudflare/fan_handles.test.mjs
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
const a='ab'.repeat(32), b='cd'.repeat(32);
async function call(path,body,cred=a){
  return worker.fetch(new Request('https://feed.test/fan/'+path,{
    method:body?'POST':'GET',headers:{authorization:'Bearer '+cred,'content-type':'application/json'},
    ...(body?{body:JSON.stringify(body)}:{}),
  }),env,{});
}
assert.equal((await call('profile',{name:'Alice'},a)).status,200);
assert.equal((await call('profile',{name:'Bobby'},b)).status,200);
// default handle, then custom
let p=await (await call('social/profile')).json();
const aId=p.profile.id,bId=(await (await call('social/profile',null,b)).json()).profile.id;
assert.equal(p.profile.handle,'fan_'+aId.slice(0,12));
assert.equal((await call('social/handle',{handle:'ab'})).status,400);
assert.equal((await call('social/handle',{handle:'bad name'})).status,400);
assert.equal((await call('social/handle',{handle:'fan_'+bId.slice(0,12)})).status,400);
assert.equal((await call('social/handle',{handle:'Alice_FC'})).status,200);
assert.equal((await call('social/handle',{handle:'alice_fc'},b)).status,409);
// Rename is locked for 60 days after the first username is set.
let locked=await call('social/handle',{handle:'Other_One'});
assert.equal(locked.status,429);
assert.ok((await locked.json()).next_change_at>Date.now()+59*86400000);
// Look-alikes of another fan's username are refused.
assert.equal((await call('social/handle',{handle:'alicefc'},b)).status,409);
assert.equal((await call('social/handle',{handle:'A1ice_FC'},b)).status,409);
assert.equal((await call('social/handle',{handle:'Deeprowss_Admin'},b)).status,400);
p=await (await call('social/profile')).json();
assert.equal(p.profile.handle,'Alice_FC');
// look up by handle (any case), old default no longer resolves
p=await (await call('social/profile?handle=alice_fc',null,b)).json();
assert.equal(p.profile.id,aId);
assert.equal((await call('social/profile?handle=fan_'+aId.slice(0,12),null,b)).status,404);
assert.equal((await call('social/profile?handle=fan_'+bId.slice(0,12),null,a)).status,200);
// mention suggestions
let m=await (await call('social/mentions?q=ali',null,b)).json();
assert.equal(m.users.length,1);assert.equal(m.users[0].handle,'Alice_FC');
m=await (await call('social/mentions?q=',null,b)).json();
assert.ok(m.users.length>=2);
// posts expose the handle and mentions notify
const form=new FormData();form.set('kind','banter');form.set('text','Hey @Alice_FC and @fan_'+bId.slice(0,12)+' and @nobody');
const res=await worker.fetch(new Request('https://feed.test/fan/post',{method:'POST',headers:{authorization:'Bearer '+b},body:form}),env,{});
assert.equal(res.status,200);
const posts=await (await call('posts',null,a)).json();
assert.equal(posts.posts[0].handle,'fan_'+bId.slice(0,12));
const notes=await (await call('social/notifications',null,a)).json();
assert.ok(notes.notifications.some(n=>n.kind==='mention'));
const own=await (await call('social/notifications',null,b)).json();
assert.ok(!own.notifications.some(n=>n.kind==='mention'));
// After 60 days the owner can rename; the old name is held for them, not free to copy.
sql.prepare('UPDATE fan_handles SET changed_at=? WHERE user_id=?').run(Date.now()-61*86400000,aId);
assert.equal((await call('social/handle',{handle:'Alice_Pro'})).status,200);
assert.equal((await call('social/handle',{handle:'Alice_FC'},b)).status,409);
// Nicknames cannot copy another fan's username or nickname.
assert.equal((await call('social/profile',{name:'Alice_Pro',bio:''},b)).status,409);
assert.equal((await call('social/profile',{name:'Admin',bio:''},b)).status,409);
console.log('Fan handles and @mentions: custom username, uniqueness, lookup, suggestions and mention notifications passed.');
