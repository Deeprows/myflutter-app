import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import worker,{fanKey,fanEspnFinal,fanApiFinal} from './worker.js';
const now=Date.now(),kickoff=new Date(now-3*3600000).toISOString();
const fixture={id:'psg',home:'Paris Saint-Germain',away:'Lyon',homeLogo:'85',awayLogo:'80',league:'Ligue 1',kickoff};
function event(changes={}) {return {id:'verified-game',date:kickoff,status:{period:2,type:{state:'post',completed:true,name:'STATUS_FULL_TIME'}},competitions:[{competitors:[{homeAway:'home',team:{displayName:'Paris Saint-Germain'},score:'2'},{homeAway:'away',team:{displayName:'Lyon'},score:'0'}]}],...changes};}
assert.equal(fanEspnFinal(fixture,{events:[event()]}).home,2);
assert.equal(fanEspnFinal(fixture,{events:[event(),event({id:'duplicate'})]}),null);
for(const status of [
 {period:2,type:{state:'in',completed:false,name:'STATUS_IN_PROGRESS'}},
 {period:2,type:{state:'post',completed:false,name:'STATUS_FULL_TIME'}},
 {period:2,type:{state:'post',completed:true,name:'STATUS_POSTPONED'}},
 {period:4,type:{state:'post',completed:true,name:'STATUS_FINAL'}},
 {period:2,type:{state:'post',completed:true,name:'STATUS_CANCELED'}},
])assert.equal(fanEspnFinal(fixture,{events:[event({status})]}),null);
assert.equal(fanEspnFinal(fixture,{events:[event({date:new Date(now-48*3600000).toISOString()})]}),null);
assert.equal(fanEspnFinal({...fixture,home:'Paris Saint-Germain Women'},{events:[event()]}),null);
assert.equal(fanEspnFinal({...fixture,league:"Ballon d'Or Awards"},{events:[event()]}),null);
assert.equal(fanEspnFinal(fixture,{events:[event({competitions:[{competitors:{}}]})]}),null);
const bad=event();bad.competitions[0].competitors[0].score='';assert.equal(fanEspnFinal(fixture,{events:[bad]}),null);
assert.equal(fanEspnFinal({...fixture,home:'Lyon',away:'Paris Saint-Germain'},{events:[event()]}).away,2);
const api={response:[{fixture:{id:777,date:kickoff,status:{short:'PEN'}},teams:{home:{id:85},away:{id:80}},score:{fulltime:{home:1,away:1},extratime:{home:2,away:2},penalty:{home:5,away:4}},goals:{home:2,away:2}}]};
assert.equal(fanApiFinal(fixture,api).home,1);assert.equal(fanApiFinal(fixture,{...api,errors:{requests:'quota'}}),null);
const sql=new DatabaseSync(':memory:');
const DB={prepare(query){let args=[];const st={bind(...a){args=a;return st;},async first(){return sql.prepare(query).get(...args)||null;},async all(){return {results:sql.prepare(query).all(...args)};},async run(){return sql.prepare(query).run(...args);}};return st;},async batch(list){const results=[];for(const s of list)results.push(await s.run());return results;}};
const env={DB};let feed=[fixture],events=[event()],offline=false,requests=[];
globalThis.fetch=async url=>{url=String(url);requests.push(url);if(url.includes('fixtures.json'))return new Response(JSON.stringify(feed));if(offline)return new Response('unavailable',{status:503});if(url.includes('site.api.espn.com'))return new Response(JSON.stringify({events}));if(url.includes('v3.football'))return new Response(JSON.stringify(api));throw Error('Unexpected URL');};
const token='ab'.repeat(32),other='cd'.repeat(32);
async function call(path,body,bearer=token){return worker.fetch(new Request('https://worker.test/fan/'+path,{method:body?'POST':'GET',headers:{authorization:'Bearer '+bearer,'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})}),env,{});}
await call('profile',{name:'Exact Fan'});await call('profile',{name:'Wrong Fan'},other);
const id=(await(await call('state')).json()).id,id2=(await(await call('state',null,other)).json()).id,key=fanKey(fixture);
function seed(f,uid=id,market='score',selection=''){sql.prepare('INSERT INTO fan_picks(user_id,match_key,title,kickoff,home,away,market,selection) VALUES(?,?,?,?,?,?,?,?)').run(uid,fanKey(f),`${f.home} vs ${f.away}`,new Date(f.kickoff).getTime(),2,0,market,selection);}
function retry(){sql.prepare('UPDATE fan_result_sync SET next_at=0').run();sql.prepare('UPDATE fan_result_jobs SET checked_at=0').run();}
seed(fixture);seed(fixture,id2,'result','2');
let data=await(await call('state')).json();assert.equal(data.picks[0].result_home,2);assert.equal(data.leaderboard[0].id,id);assert.equal(data.leaderboard[0].points,3);assert.equal(data.leaderboard.find(x=>x.id===id2).lost,1);assert.equal(data.result_sync.settled,1);
const count=requests.length;await call('state');assert.equal(requests.length,count);
const old={...fixture,id:'old',kickoff:new Date(now-27*3600000).toISOString()};seed(old);feed=[];events=[event({date:old.kickoff})];retry();
data=await(await call('state')).json();assert.equal(data.picks.find(p=>p.match_key===fanKey(old)).result_home,2);
const live={...fixture,id:'live'};seed(live);feed=[live];events=[event({status:{period:2,type:{state:'in',completed:false,name:'STATUS_IN_PROGRESS'}}})];retry();requests=[];
await Promise.all([call('state'),call('state',null,other)]);
assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM fan_results WHERE match_key=?').get(fanKey(live)).n,0);assert.equal(requests.filter(u=>u.includes('site.api.espn.com')).length,1);
offline=true;retry();const response=await call('state');assert.equal(response.status,200);data=await response.json();assert.equal(data.result_sync.status,'unavailable');assert.equal(data.picks.find(p=>p.match_key===fanKey(live)).result_home,null);
offline=false;events=[event()];retry();await call('state');assert.equal(sql.prepare('SELECT home FROM fan_results WHERE match_key=?').get(fanKey(live)).home,2);
sql.prepare('UPDATE fan_results SET home=0,away=1 WHERE match_key=?').run(key);await call('state');assert.equal(sql.prepare('SELECT home FROM fan_results WHERE match_key=?').get(key).home,0);
const cup={...fixture,id:'cup'};seed(cup);feed=[cup];events=[event({status:{period:4,type:{state:'post',completed:true,name:'STATUS_FINAL'}}})];env.API_FOOTBALL_KEY='test-key';retry();await call('state');assert.deepEqual({...sql.prepare('SELECT home,away FROM fan_results WHERE match_key=?').get(fanKey(cup))},{home:1,away:1});
const future={...fixture,id:'new',kickoff:new Date(now+3600000).toISOString()};feed=[future];assert.equal((await call('pick',{key:fanKey(future),home:2,away:1})).status,200);assert.equal(JSON.parse(sql.prepare('SELECT fixture_json FROM fan_result_jobs WHERE match_key=?').get(fanKey(future)).fixture_json).homeLogo,'85');
const awards={...future,id:'awards',league:"Ballon d'Or Awards"};feed=[awards];assert.equal((await call('pick',{key:fanKey(awards),home:1,away:0})).status,400);
const scheduled={...fixture,id:'cron'};seed(scheduled);feed=[scheduled];events=[event()];retry();const tasks=[];await worker.scheduled({},env,{waitUntil:p=>tasks.push(p)});await Promise.all(tasks);assert.equal(sql.prepare('SELECT home FROM fan_results WHERE match_key=?').get(fanKey(scheduled)).home,2);
// Reusing a feed ID for a different event cannot retarget an old saved prediction.
const saved={...fixture,id:'saved'};seed(saved);
sql.prepare('INSERT INTO fan_result_jobs(match_key,fixture_json) VALUES(?,?)').run(fanKey(saved),JSON.stringify(saved));
feed=[{...saved,home:'Other Club',away:'Another Club'}];events=[event()];retry();await call('state');
assert.equal(sql.prepare('SELECT home FROM fan_results WHERE match_key=?').get(fanKey(saved)).home,2);
console.log('Auto results: verified finals, 90-minute scoring, exact matching, historical picks, shared leases, outages/retry, saved metadata, ranks, admin overrides and cron passed.');
