import assert from 'node:assert/strict';
import {fanEspnFinal} from './worker.js';
const now=Date.now(),kickoff=new Date(now-3*3600000).toISOString();
const team=(name,score,extra={})=>({team:{displayName:name},score:String(score),...extra});
const game=(home,away,{status,date=kickoff,id='g1'}={})=>({id,date,status:status||{period:2,type:{state:'post',completed:true,name:'STATUS_FULL_TIME'}},competitions:[{competitors:[{homeAway:'home',...home},{homeAway:'away',...away}]}]});
const fx=(home,away,changes={})=>({id:'x',home,away,league:'Serie A',kickoff,...changes});

// Names that differ between the app's feed and ESPN now settle.
assert.deepEqual({...fanEspnFinal(fx('Torino','Como 1907'),{events:[game(team('Torino',1),team('Como',2))]})},{home:1,away:2,source:'ESPN',eventId:'g1'},'Como 1907 = Como');
assert.equal(fanEspnFinal(fx('AS Roma','Cagliari'),{events:[game(team('Roma',3),team('Cagliari',0))]}).home,3);
assert.equal(fanEspnFinal(fx('Al Nassr','Al Kholood'),{events:[game(team('Al Nassr',4),team('Al-Kholood',1))]}).away,1);
assert.equal(fanEspnFinal(fx('Mainz 05','Union Berlin'),{events:[game(team('Mainz',2),team('Union Berlin',2))]}).home,2);
assert.equal(fanEspnFinal(fx('Newcastle United','Brighton & Hove Albion'),{events:[game(team('Newcastle',1),team('Brighton',0))]}).home,1);

// ...but similar names never attach the wrong game.
assert.equal(fanEspnFinal(fx('Manchester City','Chelsea'),{events:[game(team('Manchester United',1),team('Chelsea',0))]}),null,'City is not United');
assert.equal(fanEspnFinal(fx('Inter Milan','Roma'),{events:[game(team('Inter Miami',1),team('Roma',0))]}),null);
assert.equal(fanEspnFinal(fx('Paris Saint-Germain','Lyon'),{events:[game(team('Paris Saint-Germain Women',1),team('Lyon',0))]}),null,"women's side");
assert.equal(fanEspnFinal(fx('Arsenal','Chelsea'),{events:[game(team('Arsenal U21',1),team('Chelsea U21',0))]}),null,'youth side');

// A kick-off that differs a few hours still settles; two days away does not.
assert.equal(fanEspnFinal(fx('Torino','Como'),{events:[game(team('Torino',1),team('Como',0),{date:new Date(now-9*3600000).toISOString()})]}).home,1);
assert.equal(fanEspnFinal(fx('Torino','Como'),{events:[game(team('Torino',1),team('Como',0),{date:new Date(now-48*3600000).toISOString()})]}),null);
// Two games with the same pair stay pending (ambiguous).
assert.equal(fanEspnFinal(fx('Torino','Como'),{events:[game(team('Torino',1),team('Como',0)),game(team('Torino',2),team('Como',2),{id:'g2'})]}),null);

// Cup ties: extra time / penalties settle on the 90-minute score (two half line-scores), never the full total.
const half=(a,b,c=0,d=0)=>({linescores:[{value:a},{value:b},{value:c},{value:d}]});
const pens={period:4,type:{state:'post',completed:true,name:'STATUS_FINAL_PEN'}};
let r=fanEspnFinal(fx('Fleetwood Town','Arsenal',{league:'EFL Cup'}),{events:[game({team:{displayName:'Fleetwood Town'},score:'1',...half(0,1)},{team:{displayName:'Arsenal'},score:'1',...half(1,0)},{status:pens})]});
assert.deepEqual({home:r.home,away:r.away},{home:1,away:1});
const aet={period:4,type:{state:'post',completed:true,name:'STATUS_FINAL_AET'}};
r=fanEspnFinal(fx('Fleetwood Town','Arsenal'),{events:[game({team:{displayName:'Fleetwood Town'},score:'3',...half(1,1,1,0)},{team:{displayName:'Arsenal'},score:'2',...half(1,1,0,0)},{status:aet})]});
assert.deepEqual({home:r.home,away:r.away},{home:2,away:2},'extra-time goals are not counted');
assert.equal(fanEspnFinal(fx('Fleetwood Town','Arsenal'),{events:[game(team('Fleetwood Town',1),team('Arsenal',1),{status:pens})]}),null,'no line-scores: stays pending');
assert.equal(fanEspnFinal(fx('Fleetwood Town','Arsenal'),{events:[game({team:{displayName:'Fleetwood Town'},score:'1',linescores:[{value:1}]},{team:{displayName:'Arsenal'},score:'1',linescores:[{value:1}]},{status:pens})]}),null,'incomplete line-scores');
console.log('Result matching: club-name variants, wrong-team protection, kick-off tolerance, extra-time/penalty 90-minute scores passed.');
