// Node 22+: actual SQLite integration for league, clubs, and tagged posts.
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import worker,{fanKey,fanWeek} from './worker.js';
const sql=new DatabaseSync(':memory:');
const DB={prepare(query){let args=[];const st={bind(...a){args=a;return st;},async first(){return sql.prepare(query).get(...args)||null;},async all(){return {results:sql.prepare(query).all(...args)};},async run(){return sql.prepare(query).run(...args);}};return st;},async batch(list){sql.exec('BEGIN');try{const result=[];for(const s of list)result.push(await s.run());sql.exec('COMMIT');return result;}catch(e){sql.exec('ROLLBACK');throw e;}}};
const fixtures=[{id:'tag',home:'Club One',away:'Club Two',homeLogo:'40',awayLogo:'33',kickoff:new Date(Date.now()+3600000).toISOString(),url:'https://video.test/embed/match',league:'League'}];
globalThis.fetch=async()=>new Response(JSON.stringify(fixtures));
const env={DB},credential='ab'.repeat(32);
async function call(path,body){return worker.fetch(new Request('https://feed.test/fan/'+path,{method:body?'POST':'GET',headers:{authorization:'Bearer '+credential,'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})}),env,{});}
assert.equal((await call('profile',{name:'Fan One'})).status,200);
let state=await (await call('state')).json(),id=state.id;
assert.equal(state.leaderboard.length,1);assert.equal(state.leaderboard[0].played,0);
// New registrations appear before making a prediction, including beyond the first page.
for(let i=0;i<105;i++){
 const uid=(i+1).toString(16).padStart(64,'0');
 sql.prepare('INSERT INTO fan_accounts VALUES(?,?,?,?,?,?)').run(uid,'sub-'+i,'private'+i+'@gmail.com','Registered '+i,'',Date.now());
 sql.prepare('INSERT INTO fan_users(id,name) VALUES(?,?)').run(uid,'Registered '+i);
}
state=await (await call('state')).json();assert.equal(state.leaderboard.length,50);assert.equal(state.board_next,50);
const all=[...state.leaderboard];let next=state.board_next;
while(next!==null){const p=await(await call('leaderboard?offset='+next)).json();all.push(...p.leaderboard);next=p.board_next;}
assert.equal(all.length,106);assert.equal(new Set(all.map(x=>x.id)).size,106);assert.ok(all.every(x=>x.points===0));
assert.equal((await call('leaderboard?offset=-1')).status,400);
assert.equal((await call('leaderboard?offset=foo')).status,400);
// Correctness, failures, void totals and late result correction update the table.
const week=fanWeek(),kickoff=week+1000;
for(const [key,market,selection] of [['win','result','1'],['lose','result','2'],['push','totals','over_1']]) {
 sql.prepare('INSERT INTO fan_picks(user_id,match_key,title,kickoff,home,away,market,selection) VALUES(?,?,?,?,?,?,?,?)').run(id,key,key,kickoff,0,0,market,selection);
 sql.prepare('INSERT INTO fan_results VALUES(?,?,?)').run(key,1,0);
}
state=await (await call('state')).json();let row=state.leaderboard.find(x=>x.id===id);
assert.equal(row.points,1);assert.equal(row.played,2);assert.equal(row.won,1);assert.equal(row.lost,1);assert.equal(state.leaderboard[0].id,id);
sql.prepare('UPDATE fan_results SET home=0,away=1 WHERE match_key=?').run('win');
state=await (await call('state')).json();
let board=[...state.leaderboard];next=state.board_next;
while(next!==null){const p=await(await call('leaderboard?offset='+next)).json();board.push(...p.leaderboard);next=p.board_next;}
row=board.find(x=>x.id===id);assert.equal(row.points,0);assert.equal(row.lost,2);assert.equal(board.at(-1).id,id,'Failures move fan below equal zero-point newcomers');
// Clubs persist privately by owner and are public profile fields; existing bio/location retained.
assert.equal((await call('social/profile',{name:'Profile Name',bio:'hello',location:'Lagos',club_name:'Liverpool',club_logo:'40'})).status,200);
let profile=(await(await call('social/profile')).json()).profile;
assert.equal(profile.club_name,'Liverpool');assert.equal(profile.club_logo,'40');assert.equal(profile.location,'Lagos');
assert.ok(!JSON.stringify(profile).includes('@gmail.com'));
assert.equal((await call('social/profile',{name:'Profile Name',bio:'hello',club_name:'bad',club_logo:'https://evil.test/a'})).status,400);
assert.equal((await call('social/profile',{name:'Profile Name',bio:'hello',club_name:'<bad>',club_logo:'40'})).status,400);
assert.equal((await call('social/profile',{name:'Changed Name',bio:'new bio'})).status,200);
profile=(await(await call('social/profile')).json()).profile;assert.equal(profile.club_name,'Liverpool','Old app updates preserve club');
assert.equal((await call('social/profile',{name:'Changed Name',bio:'new bio',club_name:'',club_logo:''})).status,200);
assert.equal((await(await call('social/profile')).json()).profile.club_logo,'');
assert.equal((await call('social/profile',{name:'Changed Name',bio:'new bio',club_name:'My local club',club_logo:''})).status,200,'Custom clubs use an uploaded cover');
// Authoritative tagged match snapshot survives fixture removal; malformed tags never publish.
async function publish(key){const form=new FormData();form.set('kind','banter');form.set('text','Match talk https://youtu.be/efzxdQeODpU');form.set('match_key',key);return worker.fetch(new Request('https://feed.test/fan/post',{method:'POST',headers:{authorization:'Bearer '+credential},body:form}),env,{});}
assert.equal((await publish('fake')).status,400);
let response=await publish(fanKey(fixtures[0]));assert.equal(response.status,200);const postId=(await response.json()).id;
let post=(await(await call('social/post?id='+postId)).json()).post;
assert.equal(JSON.parse(post.match_json).home,'Club One');assert.equal(JSON.parse(post.match_json).url,fixtures[0].url);
fixtures.length=0;
post=(await(await call('posts')).json()).posts[0];assert.equal(JSON.parse(post.match_json).id,'tag');assert.equal(post.name,'Changed Name');
console.log('Experience: all-member league pagination, success/failure/push ranking, result corrections, club validation/persistence/privacy, and authoritative tagged posts passed.');
