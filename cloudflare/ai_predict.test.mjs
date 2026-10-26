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
let keyFetches=0,providerCalls=0,providerFailure=false,smallSample=false;
const fixture={id:'auto',home:'Home FC',away:'Away FC',homeLogo:'66',awayLogo:'50',kickoff:new Date(Date.now()+3600000).toISOString()};
function history(id) {
  return Array.from({length:smallSample?2:5},(_,i)=>({fixture:{id:Number(id)*100+i,date:new Date(Date.now()-(i+1)*86400000).toISOString(),status:{short:i===0?'AET':'FT'}},teams:{home:{id:Number(id),name:'Team '+id},away:{id:777,name:'Opponent'}},goals:{home:3,away:1},score:{fulltime:{home:i===0?1:2,away:1}}}));
}
globalThis.fetch=async(url)=>{
  if(String(url)==='https://www.googleapis.com/oauth2/v3/certs'){
    keyFetches++;return new Response(JSON.stringify({keys:[jwk]}),{headers:{'cache-control':'public,max-age=3600'}});
  }
  if(String(url).startsWith('https://v3.football.api-sports.io/fixtures?')) {
    providerCalls++;if(providerFailure)return new Response('{}',{status:403});
    return new Response(JSON.stringify({errors:[],response:history(new URL(url).searchParams.get('team'))}));
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
