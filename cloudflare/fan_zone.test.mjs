// Run with Node 22+: node cloudflare/fan_zone.test.mjs
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import worker, {fanKey,fanWeek,fanPoints,fanImageType} from './worker.js';
const sql = new DatabaseSync(':memory:');
const DB = {
  prepare(query) {
    let args=[];
    const stmt={
      bind(...values){args=values;return stmt;},
      async first(){return sql.prepare(query).get(...args) || null;},
      async all(){return {results:sql.prepare(query).all(...args)};},
      async run(){return sql.prepare(query).run(...args);},
    };
    return stmt;
  },
  async batch(statements){for(const s of statements) await s.run();return [];},
};
const now=Date.now();
const fixtures=[{id:'1',home:'Home',away:'Away',kickoff:new Date(now+3600000).toISOString()}];
globalThis.fetch=async()=>new Response(JSON.stringify(fixtures));
const env={DB,ADMIN_TOKEN:'admin-secret'};
const token='ab'.repeat(32), other='cd'.repeat(32);
async function call(path,body,credential=token,customEnv=env){
  return worker.fetch(new Request('https://feed.test/fan/'+path,{
    method:body ? 'POST':'GET',headers:{authorization:'Bearer '+credential,'content-type':'application/json'},
    ...(body?{body:JSON.stringify(body)}:{}),
  }),customEnv,{});
}
assert.equal(fanPoints(2,1,2,1),3);
assert.equal(fanPoints(3,1,2,1),1);
assert.equal(fanPoints(1,1,0,0),1);
assert.equal(fanPoints(0,1,2,1),0);
assert.equal(new Date(fanWeek(new Date('2026-10-25T23:59:00Z'))).toISOString(),'2026-10-19T00:00:00.000Z');
assert.equal((await call('state',null,token,{})).status,503);
assert.equal((await call('state',null,'invalid')).status,401);
assert.equal((await call('pick',{key:fanKey(fixtures[0]),home:2,away:1})).status,403);
assert.equal((await call('profile',{name:'Fan One'})).status,200);
assert.equal((await call('profile',{name:'Fan Two'},other)).status,200);
const key=fanKey(fixtures[0]);
assert.equal((await call('admin/matches',null,'admin-secret')).status,200);
assert.equal((await call('pick',{key,home:2,away:1})).status,200);
assert.equal((await call('pick',{key,home:3,away:1})).status,200);
assert.equal((await call('pick',{key,home:2,away:1},other)).status,200);
assert.equal((await call('pick',{key,home:-1,away:1})).status,400);
assert.equal((await call('pick',{key:'fake',home:1,away:0})).status,400);
assert.equal((await call('pick',{key,home:1.5,away:0})).status,400);
const adminMatches=await (await call('admin/matches',null,'admin-secret')).json();
assert.equal(adminMatches.matches[0].match_key,key);
assert.equal(adminMatches.matches[0].picks,2);
let data=await (await call('state')).json();
assert.equal(data.picks.length,1);assert.equal(data.picks[0].home,3);
assert.equal(data.leaderboard.length,0);
assert.equal((await call('admin/result',{key,home:2,away:1})).status,401);
assert.equal((await call('admin/result',{key,home:2,away:1},'admin-secret')).status,400);
fixtures[0].kickoff=new Date(now-1000).toISOString();
const startedKey=fanKey(fixtures[0]);
assert.equal((await call('pick',{key:startedKey,home:1,away:0})).status,409);
// Preserve a historical fixture with the exact original key; simulate kickoff.
sql.prepare('UPDATE fan_picks SET kickoff=?').run(now-1000);
assert.equal((await call('pick',{key:startedKey,home:8,away:0})).status,409);
assert.equal((await call('admin/result',{key,home:2,away:1},'admin-secret')).status,200);
data=await (await call('state')).json();
assert.equal(data.leaderboard[0].name,'Fan Two');assert.equal(data.leaderboard[0].points,3);
assert.equal(data.leaderboard[1].points,1);
assert.equal((await call('admin/result',{key,home:3,away:1},'admin-secret')).status,200);
data=await (await call('state')).json();assert.equal(data.leaderboard[0].name,'Fan One');
assert.equal((await call('message',{room:'lounge',text:'Hello fans!'})).status,200);
assert.equal((await call('message',{room:'lounge',text:'Spam'})).status,429);
assert.equal((await call('message',{room:'unknown',text:'Hi'},other)).status,400);
let messages=await (await call('messages?room=lounge')).json();
assert.equal(messages.messages.length,1);
const messageId=messages.messages[0].id;
assert.equal((await call('report',{id:messageId},other)).status,200);
assert.equal((await call('report',{id:messageId},other)).status,200);
assert.equal((await call('admin/reports',null,'admin-secret')).status,200);
assert.equal((await call('admin/hide',{id:messageId},'admin-secret')).status,200);
messages=await (await call('messages?room=lounge')).json();assert.equal(messages.messages.length,0);
assert.equal((await call('report',{id:'missing'},other)).status,404);
assert.equal((await call('profile',{name:'<invalid>'})).status,400);
console.log('Fan Zone: scoring, weekly boundaries, identity, picks, cutoff, rankings, result correction, rate limit, reports and moderation passed.');


// Community posts: real SQLite plus an in-memory R2 stand-in.
const objects=new Map();
const media={
  async put(key,bytes,opts){objects.set(key,{bytes,type:opts.httpMetadata.contentType});return {};},
  async get(key){const value=objects.get(key);return value ? {
    body:value.bytes,writeHttpMetadata(headers){headers.set('content-type',value.type);}
  }:null;},
  async delete(key){objects.delete(key);},
};
const postEnv={...env,FAN_MEDIA:media};
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jN2kAAAAASUVORK5CYII=','base64');
assert.equal(fanImageType(png),'image/png');
const jpegHeader=Uint8Array.from([255,216,255,192,0,17,8,0,10,0,10,3,1,17,0,2,17,0,3,17,0,255,217]);
assert.equal(fanImageType(jpegHeader),'image/jpeg');
assert.equal(fanImageType(Buffer.from('<svg onload="alert(1)"></svg>')),null);
const oversizedDimensions=Buffer.from(png);oversizedDimensions.writeUInt32BE(9000,16);
assert.equal(fanImageType(oversizedDimensions),null);
async function publish({kind='prediction',text='Home to win 2–1',image=null,credential=token,e=postEnv}={}) {
  const form=new FormData();form.set('kind',kind);form.set('text',text);
  if(image)form.set('image',new Blob([image]),'slip.png');
  return worker.fetch(new Request('https://feed.test/fan/post',{
    method:'POST',headers:{authorization:'Bearer '+credential},body:form,
  }),e,{});
}
function resetCooldown(){sql.prepare('UPDATE fan_users SET last_post=0').run();}
resetCooldown();
assert.equal((await publish({kind:'prediction',text:'Away win',e:env})).status,200);
assert.equal((await publish({kind:'banter',text:'More'})).status,429);
resetCooldown();
assert.equal((await publish({kind:'betslip',text:'My picks'})).status,400);
assert.equal((await publish({kind:'prediction',text:''})).status,400);
assert.equal((await publish({kind:'betslip',image:png,e:env})).status,503);
assert.equal((await publish({kind:'betslip',image:Buffer.from('not an image')})).status,400);
assert.equal((await publish({kind:'betslip',image:oversizedDimensions})).status,400);
assert.equal((await publish({kind:'betslip',image:new Uint8Array(4*1024*1024+1)})).status,413);
assert.equal((await publish({text:'x'.repeat(1001)})).status,400);
assert.equal((await publish({credential:'ef'.repeat(32)})).status,403);
const published=await publish({kind:'betslip',text:'My weekend picks',image:png});
assert.equal(published.status,200);
const postId=(await published.json()).id;
assert.equal(objects.size,1);
let posts=await (await call('posts',null,other,postEnv)).json();
assert.equal(posts.posts.length,2);assert.equal(posts.uploads_enabled,true);
assert.equal(posts.posts.find(p=>p.id===postId).has_image,1);
assert.equal(posts.posts.find(p=>p.id===postId).text,'My weekend picks');
let filtered=await (await call('posts?kind=betslip',null,other,postEnv)).json();
assert.equal(filtered.posts.length,1);
assert.equal((await call('posts?kind=unknown')).status,400);
let image=await worker.fetch(new Request('https://feed.test/fan/image/'+postId),postEnv,{});
assert.equal(image.status,200);assert.equal(image.headers.get('content-type'),'image/png');
assert.equal(image.headers.get('x-content-type-options'),'nosniff');
assert.equal(image.headers.get('cache-control'),'no-store');
assert.deepEqual(Buffer.from(await image.arrayBuffer()),png);
assert.equal((await call('post/delete',{id:postId},other,postEnv)).status,403);
assert.equal((await call('post/report',{id:postId},other,postEnv)).status,200);
assert.equal((await call('post/report',{id:postId},other,postEnv)).status,200);
let reports=await (await call('admin/reports',null,'admin-secret',postEnv)).json();
assert.equal(reports.post_reports.length,1);assert.equal(reports.post_reports[0].reports,1);
assert.equal((await call('admin/hide-post',{id:postId},'admin-secret',postEnv)).status,200);
assert.equal(objects.size,0);
image=await worker.fetch(new Request('https://feed.test/fan/image/'+postId),postEnv,{});
assert.equal(image.status,404);
resetCooldown();
const own=await (await publish({kind:'banter',text:'Hello from the feed'})).json();
assert.equal((await call('post/delete',{id:own.id},token,postEnv)).status,200);
assert.equal((await call('post/report',{id:own.id},other,postEnv)).status,404);
// Equal timestamps must paginate without skipping or duplicating posts.
const userId=posts.id;
const insert=sql.prepare('INSERT INTO fan_posts(id,user_id,kind,text,at) VALUES(?,?,?,?,?)');
for(let i=0;i<85;i++)insert.run(crypto.randomUUID(),userId,'banter','Page '+i,Date.now()+100000);
const page1=await (await call('posts?kind=banter',null,token,postEnv)).json();
assert.equal(page1.posts.length,40);assert.ok(page1.next);
const page2=await (await call('posts?kind=banter&before='+encodeURIComponent(page1.next),null,token,postEnv)).json();
assert.equal(page2.posts.length,40);assert.ok(page2.next);
const page3=await (await call('posts?kind=banter&before='+encodeURIComponent(page2.next),null,token,postEnv)).json();
assert.equal(page3.posts.length,5);assert.equal(page3.next,null);
assert.equal(new Set([...page1.posts,...page2.posts,...page3.posts].map(p=>p.id)).size,85);
console.log('Community feed: text/photo publishing, image validation/limits, R2 serving, filters, permissions, cooldown, reports, hide/delete and stable pagination passed.');
