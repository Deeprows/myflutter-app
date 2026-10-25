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

const alice=await token(),bob=await token({sub:'bob',email:'bob@gmail.com',name:'Bob'}),carol=await token({sub:'carol',email:'carol@gmail.com',name:'Carol'});
for(const bearer of [alice,bob,carol])assert.equal((await call('auth',{body:{mode:'signup',idToken:bearer}})).status,200);
const state=await (await call('state',{bearer:alice})).json(),a=state.id;
const b=(await (await call('state',{bearer:bob})).json()).id,c=(await (await call('state',{bearer:carol})).json()).id;
const social=(path,body,bearer=alice)=>call('social/'+path,{body,bearer});
assert.equal((await call('social/profile')).status,401);
assert.equal((await call('social/profile',{bearer:await token({sub:'unknown'})})).status,403);
let response=await social('profile',{name:'Alpha Fan',bio:'Home of the fans',id:b});assert.equal(response.status,200);
let profile=(await (await social('profile?id='+a)).json()).profile;
assert.equal(profile.name,'Alpha Fan');assert.equal(profile.bio,'Home of the fans');assert.equal(profile.is_me,true);
assert.equal('email' in profile,false);assert.equal('google_sub' in profile,false);assert.equal('photo' in profile,false);
assert.equal((await social('profile',{name:'x',bio:''})).status,400);
assert.equal((await social('profile',{name:'Alpha Fan',bio:'a'.repeat(161)})).status,400);
assert.equal((await social('profile?id=invalid')).status,400);
assert.equal((await social('follow',{id:a,following:true})).status,400);
assert.equal((await social('follow',{id:'f'.repeat(64),following:true})).status,404);
for(let i=0;i<2;i++)assert.equal((await social('follow',{id:b,following:true})).status,200);
profile=(await (await social('profile?id='+b)).json()).profile;
assert.equal(profile.followers,1);assert.equal(profile.followed,1);assert.equal(profile.is_me,false);
let people=await (await social('people?id='+b+'&type=followers')).json();assert.deepEqual(people.people.map(p=>p.id),[a]);assert.equal('email' in people.people[0],false);
people=await (await social('people?id='+a+'&type=following')).json();assert.deepEqual(people.people.map(p=>p.id),[b]);
assert.equal((await social('people?id='+a+'&type=wrong')).status,400);
assert.equal((await social('people?id='+a+'&before=wrong')).status,400);
const postId=crypto.randomUUID(),otherPost=crypto.randomUUID();
sql.prepare('INSERT INTO fan_posts(id,user_id,kind,text,at) VALUES(?,?,?,?,?)').run(postId,b,'banter','<script>alert(1)</script> match talk',Date.now());
sql.prepare('INSERT INTO fan_posts(id,user_id,kind,text,at) VALUES(?,?,?,?,?)').run(otherPost,c,'prediction','A different fan prediction',Date.now());
let feed=await (await call('posts?scope=following',{bearer:alice})).json();assert.deepEqual(feed.posts.map(p=>p.id),[postId]);
feed=await (await call('posts?author='+c,{bearer:alice})).json();assert.deepEqual(feed.posts.map(p=>p.id),[otherPost]);
assert.equal((await call('posts?author=oops',{bearer:alice})).status,400);
for(let i=0;i<2;i++)assert.equal((await social('like',{id:postId,liked:true})).status,200);
let post=(await (await social('post?id='+postId)).json()).post;assert.equal(post.likes,1);assert.equal(post.liked,1);
assert.equal((await social('like',{id:postId,liked:'true'})).status,400);
assert.equal((await social('like',{id:postId,liked:true},bob)).status,200);
post=(await (await social('post?id='+postId)).json()).post;assert.equal(post.likes,2);
assert.equal((await social('like',{id:postId,liked:false})).status,200);
post=(await (await social('post?id='+postId)).json()).post;assert.equal(post.likes,1);assert.equal(post.liked,0);
assert.equal((await social('comment',{id:postId,text:' '})).status,400);
assert.equal((await social('comment',{id:postId,text:'a'.repeat(501)})).status,400);
response=await social('comment',{id:postId,text:'Great prediction!'});assert.equal(response.status,200);const commentId=(await response.json()).id;
assert.equal((await social('comment',{id:postId,text:'Too fast'})).status,429);
let thread=await (await social('comments?id='+postId)).json();assert.equal(thread.comments.length,1);assert.equal(thread.post.comments,1);
assert.equal((await social('comment-delete',{id:commentId},carol)).status,403);
assert.equal((await social('comment-report',{id:commentId},carol)).status,200);
let reports=await (await call('admin/reports',{bearer:'secret'})).json();assert.equal(reports.comment_reports.length,1);
assert.equal((await social('comment-delete',{id:commentId},bob)).status,200,'Post owner moderates comments');
thread=await (await social('comments?id='+postId)).json();assert.equal(thread.comments.length,0);assert.equal(thread.post.comments,0);
sql.prepare('UPDATE fan_users SET last_post=0 WHERE id=?').run(a);
const ownComment=(await (await social('comment',{id:otherPost,text:'My own reply'})).json()).id;
assert.equal((await social('comment-delete',{id:ownComment})).status,200,'Comment author can delete');
// Same-time records use stable ID tie breaks across pages.
for(let i=0;i<35;i++)sql.prepare('INSERT INTO fan_comments(id,post_id,user_id,text,at) VALUES(?,?,?,?,?)').run(crypto.randomUUID(),postId,a,'Comment '+i,1000);
thread=await (await social('comments?id='+postId)).json();assert.equal(thread.comments.length,30);assert.ok(thread.next);
const page2=await (await social('comments?id='+postId+'&before='+encodeURIComponent(thread.next))).json();assert.equal(page2.comments.length,5);
assert.equal(new Set([...thread.comments,...page2.comments].map(c=>c.id)).size,35);
assert.equal((await social('comments?id='+postId+'&before=bad')).status,400);
for(let i=0;i<45;i++){
 const target=(1000+i).toString(16).padStart(64,'0');sql.prepare('INSERT INTO fan_users(id,name) VALUES(?,?)').run(target,'Fan '+i);
 sql.prepare('INSERT INTO fan_follows(follower_id,following_id,at) VALUES(?,?,?)').run(target,b,1000);
}
people=await (await social('people?id='+b)).json();assert.equal(people.people.length,40);assert.ok(people.next);
const people2=await (await social('people?id='+b+'&before='+encodeURIComponent(people.next))).json();assert.equal(people2.people.length,6);
assert.equal(new Set([...people.people,...people2.people].map(p=>p.id)).size,46);
for(let i=0;i<10;i++){
 const key='history-'+i;sql.prepare('INSERT INTO fan_picks VALUES(?,?,?,?,?,?)').run(b,key,'A vs B',1000,i<5?2:0,1);
 sql.prepare('INSERT INTO fan_results VALUES(?,?,?)').run(key,2,1);
}
profile=(await (await social('profile?id='+b)).json()).profile;assert.equal(profile.stats.points,15);assert.equal(profile.stats.exact,5);
assert.equal(profile.achievements.find(x=>x.key==='five-exact').earned,true);assert.equal(profile.achievements.find(x=>x.key==='ten-followers').earned,true);
response=await call('../fan/share/'+postId);assert.equal(response.status,200);const markup=await response.text();assert.ok(markup.includes('&lt;script&gt;'));assert.equal(markup.includes('<script>'),false);
assert.equal((await social('follow',{id:b,following:false})).status,200);
assert.equal((await social('follow',{id:b,following:false})).status,200);
feed=await (await call('posts?scope=following',{bearer:alice})).json();assert.equal(feed.posts.length,0);
const remaining=thread.comments[0].id;
assert.equal((await call('admin/hide-comment',{bearer:'secret',body:{id:remaining}})).status,200);
assert.equal((await call('post/delete',{bearer:bob,body:{id:postId}})).status,200);
for(const path of ['post?id='+postId,'comments?id='+postId])assert.equal((await social(path)).status,404);
assert.equal((await social('like',{id:postId,liked:true})).status,404);
assert.equal((await social('comment',{id:postId,text:'Hidden parent'})).status,404);
assert.equal((await call('../fan/share/'+postId)).status,404);
profile=(await (await social('profile?id='+b)).json()).profile;assert.equal(profile.posts,0);assert.equal(profile.likes_received,0);
// Quotas are enforced before the associated writes.
const hour=Math.floor(Date.now()/3600000);
sql.prepare('INSERT OR REPLACE INTO fan_social_limits VALUES(?,?,?)').run('follow:'+a+':'+hour,120,Date.now()+3600000);
assert.equal((await social('follow',{id:b,following:true})).status,429);
// Legacy install social activity migrates to the verified account atomically.
const legacy='ef'.repeat(32);
assert.equal((await call('profile',{body:{name:'Legacy Social'},bearer:legacy,e:{DB}})).status,200);
const legacyId=sql.prepare('SELECT id FROM fan_users WHERE name=?').get('Legacy Social').id;
sql.prepare('INSERT INTO fan_follows VALUES(?,?,?)').run(legacyId,c,100);
sql.prepare('INSERT INTO fan_follows VALUES(?,?,?)').run(c,legacyId,100);
sql.prepare('INSERT INTO fan_likes VALUES(?,?,?)').run(otherPost,legacyId,100);
const legacyComment=crypto.randomUUID();sql.prepare('INSERT INTO fan_comments(id,post_id,user_id,text,at) VALUES(?,?,?,?,?)').run(legacyComment,otherPost,legacyId,'Legacy reply',100);
assert.equal((await call('auth',{body:{mode:'login',idToken:alice,legacyToken:legacy}})).status,200);
assert.equal(sql.prepare('SELECT user_id FROM fan_comments WHERE id=?').get(legacyComment).user_id,a);
assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM fan_follows WHERE follower_id=? AND following_id=?').get(a,c).n,1);
assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM fan_follows WHERE follower_id=? AND following_id=?').get(c,a).n,1);
assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM fan_likes WHERE post_id=? AND user_id=?').get(otherPost,a).n,1);
assert.equal(sql.prepare('SELECT id FROM fan_users WHERE id=?').get(legacyId),undefined);
console.log('Social: Google identity, public privacy, profile ownership, follows, follower pagination, following/author feeds, idempotent likes, comments, cooldowns, ownership, reports/admin moderation, stable pages, earned achievements, safe shares and hidden-parent access passed.');
