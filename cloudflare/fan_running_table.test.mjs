// Node 22+: actual SQLite integration for league, clubs, and tagged posts.
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import worker from './worker.js';
const sql=new DatabaseSync(':memory:');
const DB={prepare(query){let args=[];const st={bind(...a){args=a;return st;},async first(){return sql.prepare(query).get(...args)||null;},async all(){return {results:sql.prepare(query).all(...args)};},async run(){return sql.prepare(query).run(...args);}};return st;},async batch(list){sql.exec('BEGIN');try{const result=[];for(const s of list)result.push(await s.run());sql.exec('COMMIT');return result;}catch(e){sql.exec('ROLLBACK');throw e;}}};
const fixtures=[{id:'tag',home:'Club One',away:'Club Two',homeLogo:'40',awayLogo:'33',kickoff:new Date(Date.now()+3600000).toISOString(),url:'https://video.test/embed/match',league:'League'}];
globalThis.fetch=async()=>new Response(JSON.stringify(fixtures));
const env={DB},credential='ab'.repeat(32);
async function call(path,body){return worker.fetch(new Request('https://feed.test/fan/'+path,{method:body?'POST':'GET',headers:{authorization:'Bearer '+credential,'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})}),env,{});}
assert.equal((await call('profile',{name:'Fan One'})).status,200);
let state=await (await call('state')).json();const id=state.id;
const DAY=86400000,now=Date.now();
const add=(key,kickoffAt,market,selection,result)=>{
  sql.prepare('INSERT INTO fan_picks(user_id,match_key,title,kickoff,home,away,market,selection) VALUES(?,?,?,?,?,?,?,?)').run(id,key,key,kickoffAt,0,0,market,selection);
  if(result)sql.prepare('INSERT INTO fan_results VALUES(?,?,?)').run(key,result[0],result[1]);
};
// Predictions for matches from this week, last week and two months ago all count once their match has ended.
add('today',now-5*3600000,'result','1',[2,0]);
add('lastweek',now-9*DAY,'result','1',[3,1]);
add('old',now-60*DAY,'result','2',[0,1]);
add('wrong',now-20*DAY,'result','1',[0,2]);
add('unfinished',now-3600000,'result','1',null);
state=await (await call('state')).json();
let row=state.leaderboard.find(x=>x.id===id);
assert.equal(row.points,3,'three correct outcomes at 1 point each, regardless of week');
assert.equal(row.played,4);assert.equal(row.won,3);assert.equal(row.lost,1);
// The moment a result is saved the points move; no weekly/monthly wait.
sql.prepare('INSERT INTO fan_results VALUES(?,?,?)').run('unfinished',1,0);
state=await (await call('state')).json();row=state.leaderboard.find(x=>x.id===id);
assert.equal(row.points,4);assert.equal(row.played,5);
// An exact score is worth 3 points, even for an older match.
sql.prepare('INSERT INTO fan_picks(user_id,match_key,title,kickoff,home,away,market,selection) VALUES(?,?,?,?,?,?,?,?)').run(id,'exact','exact',now-45*DAY,2,1,'score','');
sql.prepare('INSERT INTO fan_results VALUES(?,?,?)').run('exact',2,1);
state=await (await call('state')).json();row=state.leaderboard.find(x=>x.id===id);
assert.equal(row.points,7);assert.equal(row.played,6);
console.log('Running league table: predictions count from day one, across weeks, immediately after each result.');
