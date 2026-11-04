import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import worker,{fanKey} from './worker.js';
const now=Date.now(),kickoff=new Date(now-3*3600000).toISOString();
const fixture={id:'ncl',home:'Newcastle United',away:'Everton',league:'Premier League',kickoff};
const sql=new DatabaseSync(':memory:');
const DB={prepare(query){let args=[];const st={bind(...a){args=a;return st;},async first(){return sql.prepare(query).get(...args)||null;},async all(){return {results:sql.prepare(query).all(...args)};},async run(){return sql.prepare(query).run(...args);}};return st;},async batch(list){const results=[];for(const s of list)results.push(await s.run());return results;}};
const env={DB};
// ESPN and the other providers are unreachable from the server: only the apps' reports can settle the match.
globalThis.fetch=async url=>{url=String(url);if(url.includes('fixtures.json'))return new Response(JSON.stringify([fixture]));return new Response('unavailable',{status:503});};
const tokens=['ab','cd','ef'].map(x=>x.repeat(32));
async function call(path,body,bearer=tokens[0]){return worker.fetch(new Request('https://worker.test/fan/'+path,{method:body?'POST':'GET',headers:{authorization:'Bearer '+bearer,'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})}),env,{});}
const ids=[];
for(const [i,t] of tokens.entries()){await call('profile',{name:'Fan Number '+i},t);ids.push((await(await call('state',null,t)).json()).id);}
const key=fanKey(fixture);
sql.prepare('INSERT INTO fan_picks(user_id,match_key,title,kickoff,home,away,market,selection) VALUES(?,?,?,?,?,?,?,?)').run(ids[0],key,'Newcastle United vs Everton',new Date(kickoff).getTime(),2,1,'score','');
sql.prepare('INSERT INTO fan_picks(user_id,match_key,title,kickoff,home,away,market,selection) VALUES(?,?,?,?,?,?,?,?)').run(ids[1],key,'Newcastle United vs Everton',new Date(kickoff).getTime(),0,0,'result','1');
const report=async(i,home,away,k=key)=>(await(await call('result-report',{key:k,home,away},tokens[i])).json());
const settled=()=>sql.prepare('SELECT home,away FROM fan_results WHERE match_key=?').get(key);
// A match nobody predicted is ignored.
assert.equal((await report(0,1,0,'nobody|1')).status,'ignored');
// One report is not enough (default quorum 2).
let r=await report(0,2,1);assert.equal(r.status,'recorded');assert.equal(settled(),undefined);
// The same person cannot confirm their own report.
r=await report(0,2,1);assert.equal(r.status,'recorded');assert.equal(settled(),undefined);
// A conflicting report blocks settlement (no clear majority).
r=await report(1,0,0);assert.equal(r.status,'recorded');assert.equal(settled(),undefined);
// A second matching report settles it, and the points reach the ranks table.
r=await report(2,2,1);assert.equal(r.status,'settled');assert.deepEqual({...settled()},{home:2,away:1});
const state=await(await call('state')).json();
assert.equal(state.picks[0].result_home,2);assert.equal(state.leaderboard.find(x=>x.id===ids[0]).points,3);
// Settled results can no longer be changed by later reports.
assert.equal((await report(1,5,5)).status,'settled');assert.deepEqual({...settled()},{home:2,away:1});
// Too early: a match that has just started cannot be reported as finished.
const live={...fixture,id:'live',kickoff:new Date(now-30*60000).toISOString()};
sql.prepare('INSERT INTO fan_picks(user_id,match_key,title,kickoff,home,away,market,selection) VALUES(?,?,?,?,?,?,?,?)').run(ids[0],fanKey(live),'A vs B',new Date(live.kickoff).getTime(),1,0,'score','');
assert.equal((await report(0,1,0,fanKey(live))).status,'too_early');
console.log('ok');
