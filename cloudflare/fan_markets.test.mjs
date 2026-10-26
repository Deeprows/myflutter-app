// Run with Node 22+: node cloudflare/fan_zone.test.mjs
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import worker, {fanKey,fanWeek,fanPoints,fanImageType,validFanMarket,fanPredictionPoints} from './worker.js';
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

assert.equal((await call('profile',{name:'Markets Fan'})).status,200);
const key=fanKey(fixtures[0]),id=(await (await call('state')).json()).id;
const choices=[['score',''],...['1','X','2'].map(s=>['result',s]),...['1X','X2','12'].map(s=>['double_chance',s]),...['yes','no'].map(s=>['btts',s]),...['0.5','1','1.5','2','2.5','3','3.5','4.5'].flatMap(n=>[['totals','over_'+n],['totals','under_'+n]])];
for(const [market,selection] of choices){
 assert.ok(validFanMarket(market,selection));
 assert.equal((await call('pick',{key,market,selection,home:2,away:1})).status,200);
 const state=await (await call('state')).json();assert.equal(state.picks.length,1);assert.equal(state.picks[0].market,market);assert.equal(state.picks[0].selection,selection);
}
for(const bad of [{market:'result',selection:'3'},{market:'totals',selection:'over_999'},{market:'btts',selection:'maybe'},{market:'fake',selection:''}])assert.equal((await call('pick',{key,...bad})).status,400);
assert.equal((await call('pick',{key,home:2,away:1})).status,200,'Old exact-score client is compatible');
sql.prepare('UPDATE fan_picks SET kickoff=?').run(Date.now()-1000);
for(const [market,selection] of choices){
 sql.prepare('UPDATE fan_picks SET market=?,selection=?,home=2,away=1').run(market,selection);
 for(let home=0;home<=5;home++)for(let away=0;away<=5;away++){
  sql.prepare('INSERT INTO fan_results VALUES(?,?,?) ON CONFLICT(match_key) DO UPDATE SET home=excluded.home,away=excluded.away').run(key,home,away);
  const expected=fanPredictionPoints({market,selection,home:2,away:1},home,away);
  const state=await (await call('state')).json();
  if(expected===null)assert.equal(state.leaderboard.length,0,'Push excludes this pick from ranking count');
  else {assert.equal(state.leaderboard[0].points,expected,`${market}/${selection} @ ${home}-${away}`);assert.equal(state.leaderboard[0].played,1);}
 }
}
assert.equal(fanPredictionPoints({market:'totals',selection:'over_1'},0,1),null);
assert.equal(fanPredictionPoints({market:'totals',selection:'over_1'},2,0),1);
assert.equal(fanPredictionPoints({market:'totals',selection:'over_2.5'},1,1),0);
assert.equal(fanPredictionPoints({market:'totals',selection:'over_2.5'},2,1),1);
fixtures[0].kickoff=new Date(Date.now()-1000).toISOString();
assert.equal((await call('pick',{key:fanKey(fixtures[0]),market:'result',selection:'1'})).status,409);
console.log('Markets: validation, one choice per match, legacy score compatibility, all selections/results, JS/SQL parity, 90-minute totals, whole-goal pushes and kickoff locks passed.');
