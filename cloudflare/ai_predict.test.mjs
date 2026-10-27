// Node 22+: node cloudflare/fan_auth.test.mjs
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import worker,{verifyFanGoogleToken} from './worker.js';
const sql=new DatabaseSync(':memory:');
const DB={prepare(query){let args=[];const st={bind(...a){args=a;return st;},
  async first(){return sql.prepare(query).get(...args)||null;},
  async all(){return {results:sql.prepare(query).all(...args)};},
  async run(){return /RETURNING/i.test(query)?{results:sql.prepare(query).all(...args)}:sql.prepare(query).run(...args);}};return st;},
  async batch(list){sql.exec('BEGIN');try{const result=[];for(const s of list)result.push(await s.run());sql.exec('COMMIT');return result;}catch(e){sql.exec('ROLLBACK');throw e;}}};
const keys=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const jwk=await crypto.subtle.exportKey('jwk',keys.publicKey);jwk.kid='test-google-key';
let keyFetches=0,providerCalls=0,providerFailure=false,smallSample=false,providerError=null,espnEnabled=false,espnCalls=0,espnLimited=false;
const fixture={id:'auto',home:'Home FC',away:'Away FC',homeLogo:'66',awayLogo:'50',league:'Serie A',kickoff:new Date(Date.now()+3600000).toISOString()};
function history(id) {
  return Array.from({length:smallSample?2:5},(_,i)=>({fixture:{id:Number(id)*100+i,date:new Date(Date.now()-(i+1)*86400000).toISOString(),status:{short:i===0?'AET':'FT'}},teams:{home:{id:Number(id),name:'Team '+id},away:{id:777,name:'Opponent'}},goals:{home:3,away:1},score:{fulltime:{home:i===0?1:2,away:1}}}));
}
globalThis.fetch=async(url)=>{
  if(String(url)==='https://www.googleapis.com/oauth2/v3/certs'){
    keyFetches++;return new Response(JSON.stringify({keys:[jwk]}),{headers:{'cache-control':'public,max-age=3600'}});
  }
  if(String(url).startsWith('https://v3.football.api-sports.io/fixtures?')) {
    const q=new URL(url).searchParams;assert.equal(q.has('last'),false);assert.equal(q.has('next'),false);assert.match(q.get('season'),/^\d{4}$/);assert.match(q.get('from'),/^\d{4}-\d{2}-\d{2}$/);
    providerCalls++;if(providerError)return new Response(JSON.stringify({errors:providerError,response:[]}));if(providerFailure)return new Response('{}',{status:403});
    return new Response(JSON.stringify({errors:[],response:history(new URL(url).searchParams.get('team'))}));
  }
  if(String(url).startsWith('https://site.api.espn.com/') && espnEnabled) {
    espnCalls++;
    if(String(url).includes('/teams?'))return new Response(JSON.stringify({sports:[{leagues:[{teams:[{team:{id:'101',displayName:'Home FC'}},{team:{id:'202',displayName:'Away FC'}}]}]}]}));
    const id=String(url).includes('/101/')?'101':'202';
    return new Response(JSON.stringify({events:Array.from({length:espnLimited?2:5},(_,i)=>({id:id+'-'+i,date:new Date(Date.now()-(i+1)*86400000).toISOString(),status:{period:2,type:{name:'STATUS_FULL_TIME',state:'post',completed:true}},competitions:[{competitors:[{homeAway:'home',team:{id,displayName:'Verified Club'},score:{value:2}},{homeAway:'away',team:{id:'999',displayName:'Opponent'},score:{value:1}}]}]}))}));
  }
  return new Response(JSON.stringify([fixture]));
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

const alice=await token();assert.equal((await call('auth',{body:{mode:'signup',idToken:alice}})).status,200);
const body={key:fixture.id+'|'+Date.parse(fixture.kickoff)};
let runs=0;
env.API_FOOTBALL_KEY='test-secret';env.AI={async run(model,input){
 runs++;assert.equal(model,'@cf/meta/llama-3.1-8b-instruct-fp8');
 const data=JSON.parse(input.messages[1].content);
 assert.equal(data.home.played,5);assert.equal(data.away.played,5);
 assert.equal(data.home.matches[0].goalsFor,1,'AET uses 90-minute score');
 assert.equal(data.home.matches[0].result,'D');
 assert.equal(data.home.goalsFor,9);assert.equal(data.home.goalsAgainst,5);
 assert.equal('userProvidedStats' in data,false);assert.equal(JSON.stringify(data).includes('invented-user-data'),false);
 return {response:'Home lean based on the fetched recent results; uncertain outcome.'};
}};
assert.equal((await call('ai-predict',{body})).status,401);
assert.equal((await call('ai-predict',{body,bearer:await token({sub:'unknown'})})).status,403);
assert.equal((await call('ai-predict',{body,bearer:alice,e:{...env,AI:undefined}})).status,503);
assert.equal((await call('ai-predict',{body,bearer:alice,e:{...env,API_FOOTBALL_KEY:undefined}})).status,503);
assert.equal((await call('ai-predict',{bearer:alice})).status,405);
assert.equal((await call('ai-predict',{body:{key:'missing'},bearer:alice})).status,404);
const savedLogo=fixture.homeLogo;fixture.homeLogo='';assert.equal((await call('ai-predict',{body,bearer:alice})).status,422);fixture.homeLogo=savedLogo;
let response=await call('ai-predict',{body:{...body,stats:'invented-user-data'},bearer:alice});assert.equal(response.status,200);
const result=await response.json();assert.match(result.dataSource,/API-Football/);assert.equal(result.home.matches.length,5);assert.equal(JSON.stringify(result).includes('test-secret'),false);
assert.equal(providerCalls,2);
for(let i=1;i<10;i++)assert.equal((await call('ai-predict',{body,bearer:alice})).status,200);
assert.equal(providerCalls,2,'Server cache reuses recent results');
assert.equal((await call('ai-predict',{body,bearer:alice})).status,429);assert.equal(runs,10);
assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM fan_picks').get().n,0,'AI does not submit user picks');
sql.exec('DELETE FROM fan_ai_limits; DELETE FROM fan_form_cache');providerFailure=true;
assert.equal((await call('ai-predict',{body,bearer:alice})).status,503);
sql.exec('DELETE FROM fan_ai_limits; DELETE FROM fan_form_cache');providerFailure=false;smallSample=true;
assert.equal((await call('ai-predict',{body,bearer:alice})).status,422);assert.equal(runs,10,'Insufficient results never invent an analysis');
console.log('Automatic AI: verified access, binding/key setup, real server-sourced results, 90-minute scores, sample checks, cache, quotas, user-input exclusion and provider errors passed.');

// Rejected provider plans use real normalized ESPN data; API-Sports IDs are not reused as ESPN IDs.
sql.exec('DELETE FROM fan_ai_limits; DELETE FROM fan_form_cache; DELETE FROM fan_espn_form_cache; DELETE FROM fan_social_limits');
smallSample=false;providerError={plan:'Free plan does not allow this query'};espnEnabled=true;
env.AI={async run(model,input){runs++;const data=JSON.parse(input.messages[1].content);assert.equal(data.home.source,'ESPN');assert.equal(data.home.teamId,'espn:101');assert.equal(data.away.teamId,'espn:202');assert.equal(data.home.played,5);assert.equal(data.home.goalsFor,10);assert.equal(data.home.goalsAgainst,5);return {response:'Analysis from verified ESPN recent results.'};}};
response=await call('ai-predict',{body,bearer:alice});assert.equal(response.status,200);let fallback=await response.json();assert.equal(fallback.dataSource,'ESPN');assert.equal(fallback.home.played,5);assert.equal(espnCalls,3,'Shared team lookup and two schedules');
const used=espnCalls;await call('ai-predict',{body,bearer:alice});assert.equal(espnCalls,used,'ESPN forms are cached');
// When neither source is usable, report a specific cause and do not consume model-call quota.
for(const [errors,code] of [[{token:'Invalid key'},'provider_auth'],[{requests:'Daily quota exceeded'},'provider_quota'],[{plan:'Season unavailable with this plan'},'provider_plan']]) {
 sql.exec('DELETE FROM fan_ai_limits; DELETE FROM fan_form_cache; DELETE FROM fan_espn_form_cache');espnEnabled=false;providerError=errors;
 response=await call('ai-predict',{body,bearer:alice});assert.equal(response.status,503);const failure=await response.json();assert.equal(failure.code,code);assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM fan_ai_limits').get().n,0);assert.ok(!JSON.stringify(failure).includes('test-secret'));
}
console.log('AI provider fix: date/season queries, duplicate exclusion, ESPN fallback and caching, source attribution, actionable auth/plan/quota errors and model-quota accounting passed.');

sql.exec('DELETE FROM fan_ai_limits; DELETE FROM fan_form_cache; DELETE FROM fan_espn_form_cache');
providerError={plan:'Season not available'};espnEnabled=true;espnLimited=true;
const before=runs;response=await call('ai-predict',{body,bearer:alice});assert.equal(response.status,422);assert.equal(runs,before,'Incomplete fallback data never generates analysis');
assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM fan_ai_limits').get().n,0);
console.log('Insufficient fallback results leave AI model quota untouched.');
