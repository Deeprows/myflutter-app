// Node 22+: actual SQLite integration for league, clubs, and tagged posts.
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import worker,{fanWeek} from './worker.js';
const sql=new DatabaseSync(':memory:');
const DB={prepare(query){let args=[];const st={bind(...a){args=a;return st;},async first(){return sql.prepare(query).get(...args)||null;},async all(){return {results:sql.prepare(query).all(...args)};},async run(){return sql.prepare(query).run(...args);}};return st;},async batch(list){sql.exec('BEGIN');try{const result=[];for(const s of list)result.push(await s.run());sql.exec('COMMIT');return result;}catch(e){sql.exec('ROLLBACK');throw e;}}};
const fixtures=[{id:'tag',home:'Club One',away:'Club Two',homeLogo:'40',awayLogo:'33',kickoff:new Date(Date.now()+3600000).toISOString(),url:'https://video.test/embed/match',league:'League'}];
globalThis.fetch=async()=>new Response(JSON.stringify(fixtures));
const env={DB,ADMIN_TOKEN:'admin-secret'},credential='ab'.repeat(32);
async function call(path,body){return worker.fetch(new Request('https://feed.test/fan/'+path,{method:body?'POST':'GET',headers:{authorization:'Bearer '+credential,'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})}),env,{});}
async function admin(path,body,bearer='admin-secret'){
  return worker.fetch(new Request('https://feed.test/fan/admin'+path,{method:body?'POST':'GET',headers:{authorization:'Bearer '+bearer,'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})}),env,{});
}
assert.equal((await call('profile',{name:'Fan One'})).status,200);
let state=await (await call('state')).json();const u1=state.id;
for(const [id,name] of [['u2','Fan Two'],['u3','Fan Three'],['u4','Fan Four']])sql.prepare('INSERT INTO fan_users(id,name) VALUES(?,?)').run(id,name);
const WEEK=fanWeek(),W=WEEK-7*86400000,now=Date.now();
const pick=(user,key,at,market,selection,home=0,away=0)=>sql.prepare('INSERT INTO fan_picks(user_id,match_key,title,kickoff,home,away,market,selection) VALUES(?,?,?,?,?,?,?,?)').run(user,key,key,at,home,away,market,selection);
sql.prepare('INSERT INTO fan_results VALUES(?,?,?)').run('m1',2,0);sql.prepare('INSERT INTO fan_results VALUES(?,?,?)').run('m2',1,1);
pick(u1,'m1',W+1000,'result','1');pick(u1,'m2',W+2000,'result','X');          // 2 points
pick('u2','m1',W+1000,'score','',2,0);pick('u2','m2',W+2000,'result','1');    // exact (3) + miss
pick('u3','m1',W+1000,'result','1');                                          // 1 point
pick('u4','m1',W+1000,'result','2');                                          // 0 points
// a big week-after prediction must not leak into last week's standings
pick('u3','m3',WEEK+1000,'score','',1,0);sql.prepare('INSERT INTO fan_results VALUES(?,?,?)').run('m3',1,0);

// --- the admin page is public HTML with no data; the data routes need the admin secret ---
let r=await worker.fetch(new Request('https://feed.test/fan/admin'),env,{});
assert.equal(r.status,200);assert.match(r.headers.get('content-type'),/text\/html/);assert.match(r.headers.get('content-security-policy'),/connect-src 'self'/);
assert.match(await r.text(),/Weekly winners/);
assert.equal((await admin('/week',null,'wrong')).status,401);
assert.equal((await admin('/week/finalize',{week:W},'wrong')).status,401);

// --- review last week ---
r=await admin('/week');assert.equal(r.status,200);let rep=await r.json();
assert.equal(rep.week,W);assert.equal(rep.ended,true);assert.equal(rep.waiting,0);assert.equal(rep.weeks.length,8);assert.equal(rep.published.length,0);
assert.deepEqual(rep.standings.map(x=>[x.id,x.points]),[['u2',3],[u1,2],['u3',1],['u4',0]],"last week's points only, ranked");
assert.equal((await admin('/week?week='+(W+5000))).status,400,'must be a Monday 00:00 UTC week start');

// --- rules: only finished weeks, and only when results are in (unless forced) ---
assert.equal((await admin('/week/finalize',{week:WEEK})).status,400);
pick('u3','late',W+3000,'result','1');
r=await admin('/week/finalize',{week:W});assert.equal(r.status,409);assert.equal((await r.json()).code,'waiting');
sql.prepare('DELETE FROM fan_picks WHERE match_key=?').run('late');

// --- publish the computed top three ---
r=await admin('/week/finalize',{week:W});assert.equal(r.status,200);
assert.deepEqual((await r.json()).winners.map(x=>[x.rank,x.id,x.points]),[[1,'u2',3],[2,u1,2],[3,'u3',1]]);
state=await (await call('state')).json();
assert.equal(state.winners.length,1);assert.equal(state.winners[0].week,W);
assert.deepEqual(state.winners[0].winners.map(x=>[x.rank,x.name,x.points]),[[1,'Fan Two',3],[2,'Fan One',2],[3,'Fan Three',1]]);
// the running table is untouched by publishing
assert.equal(state.leaderboard.find(x=>x.id==='u3').points,4,'u3: 1 point last week + 3 (exact score) this week, all in the running table');

// --- the admin decides: override the podium (and publish only two) ---
r=await admin('/week/finalize',{week:W,winners:[u1,'u2']});assert.equal(r.status,200);
state=await (await call('state')).json();
assert.deepEqual(state.winners[0].winners.map(x=>[x.rank,x.id]),[[1,u1],[2,'u2']],'overridden order replaces the old podium');
for(const winners of [[],['u1','u1'],['nobody-here'],['a','b','c','d'],'u2',[5]])assert.equal((await admin('/week/finalize',{week:W,winners})).status,400,JSON.stringify(winners));

// --- more weeks stack up; unpublish removes one ---
sql.prepare('INSERT INTO fan_week_winners(week,rank,user_id,name,points,played,won,finalized_at) VALUES(?,?,?,?,?,?,?,?)').run(W-7*86400000,1,'u4','Fan Four',9,5,3,now);
state=await (await call('state')).json();assert.deepEqual(state.winners.map(x=>x.week),[W,W-7*86400000],'newest week first');
assert.equal((await admin('/week/unpublish',{week:W})).status,200);
state=await (await call('state')).json();assert.deepEqual(state.winners.map(x=>x.week),[W-7*86400000]);
console.log('Weekly winners: admin review, ended-week and results rules, computed and overridden top three, running table unaffected, app state, unpublish and admin-page security passed.');
