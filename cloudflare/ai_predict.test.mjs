// Node 22+: node cloudflare/fan_auth.test.mjs
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import worker,{verifyFanGoogleToken} from './worker.js';
const sql=new DatabaseSync(':memory:');
const DB={prepare(query){let args=[];const st={bind(...a){args=a;return st;},
  async first(){return sql.prepare(query).get(...args)||null;},
  async all(){return {results:sql.prepare(query).all(...args)};},
  async run(){return /RETURNING/i.test(query) ? {results:sql.prepare(query).all(...args)} : sql.prepare(query).run(...args);}};return st;},
  async batch(list){sql.exec('BEGIN');try{const result=[];for(const s of list)result.push(await s.run());sql.exec('COMMIT');return result;}catch(e){sql.exec('ROLLBACK');throw e;}}};
const keys=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const jwk=await crypto.subtle.exportKey('jwk',keys.publicKey);jwk.kid='test-google-key';
let keyFetches=0;
const kickoff=new Date(Date.now()+3600000).toISOString();
const fixture={id:'ai-fixture',home:'Home FC',away:'Away FC',league:'Test League',kickoff};
globalThis.fetch=async(url)=>{
  if(String(url)==='https://www.googleapis.com/oauth2/v3/certs'){
    keyFetches++;return new Response(JSON.stringify({keys:[jwk]}),{headers:{'cache-control':'public,max-age=3600'}});
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

const alice=await token();
assert.equal((await call('auth',{body:{mode:'signup',idToken:alice}})).status,200);
let runs=0;
env.AI={async run(model,input){
  runs++;assert.equal(model,'@cf/meta/llama-3.1-8b-instruct-fp8');
  assert.match(input.messages[0].content,/no live data/);
  const details=JSON.parse(input.messages[1].content);
  assert.equal(details.fixture.home,'Home FC');assert.equal(details.userProvidedStats,stats);
  return {response:'Tentative home lean based on unverified supplied form. No guaranteed result.'};
}};
const stats='Home won 3 of last 5; Away won 1 of last 5. User-supplied data.';
const body={key:fixture.id+'|'+new Date(kickoff).getTime(),stats};
assert.equal((await call('ai-predict',{body})).status,401);
assert.equal((await call('ai-predict',{body,bearer:await token({sub:'unknown'})})).status,403);
assert.equal((await call('ai-predict',{body,bearer:alice,e:{...env,AI:undefined}})).status,503);
assert.equal((await call('ai-predict',{bearer:alice})).status,405);
assert.equal((await call('ai-predict',{body:{...body,stats:'short'},bearer:alice})).status,400);
assert.equal((await call('ai-predict',{body:{...body,stats:'x'.repeat(2501)},bearer:alice})).status,400);
assert.equal((await call('ai-predict',{body:{...body,stats:'x'.repeat(5000)},bearer:alice})).status,413);
assert.equal((await call('ai-predict',{body:{...body,key:'unknown'},bearer:alice})).status,404);
fixture.kickoff=new Date(Date.now()-1000).toISOString();
assert.equal((await call('ai-predict',{body:{...body,key:fixture.id+'|'+new Date(fixture.kickoff).getTime()},bearer:alice})).status,400);
fixture.kickoff=kickoff;
assert.equal(runs,0,'Invalid/unauthorized requests never invoke AI');
const response=await call('ai-predict',{body,bearer:alice});assert.equal(response.status,200);
const result=await response.json();assert.match(result.analysis,/Tentative home lean/);assert.match(result.dataSource,/no live data/);
for(let i=1;i<10;i++)assert.equal((await call('ai-predict',{body,bearer:alice})).status,200);
assert.equal((await call('ai-predict',{body,bearer:alice})).status,429);assert.equal(runs,10);
assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM fan_picks').get().n,0,'AI never submits competition picks');
sql.exec('DELETE FROM fan_ai_limits');
env.AI={async run(){throw new Error('Test provider failure');}};
assert.equal((await call('ai-predict',{body,bearer:alice})).status,503);
sql.exec('DELETE FROM fan_ai_limits');env.AI={async run(){return {response:''};}};
assert.equal((await call('ai-predict',{body,bearer:alice})).status,502);
sql.exec('DELETE FROM fan_ai_limits');
const id=sql.prepare('SELECT id FROM fan_accounts LIMIT 1').get().id;
sql.prepare('INSERT INTO fan_ai_limits VALUES(?,?,?)').run('day:'+id+':'+Math.floor(Date.now()/86400000),50,Date.now()+86400000);
assert.equal((await call('ai-predict',{body,bearer:alice})).status,429,'Daily quota survives hourly resets');
console.log('AI Predict: registered Gmail access, binding, input validation, upcoming fixtures, prompt data boundaries, inference response, hourly/daily limits, provider errors and no competition side effects passed.');
