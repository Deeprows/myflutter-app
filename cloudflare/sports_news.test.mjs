import assert from 'node:assert/strict';
import worker,{parseSportsNewsRss} from './worker.js';
const now=Date.now(),source={name:'BBC Sport',hosts:['bbc.co.uk','bbc.com']};
function item(title='Sports &amp; goals',link='https://www.bbc.com/sport/a',date=now-60000,image='https://ichef.bbci.co.uk/news/abc.jpg') {return `<item><title><![CDATA[${title}]]></title><link>${link}</link><pubDate>${new Date(date).toUTCString()}</pubDate><media:thumbnail url="${image}"/></item>`;}
function rss(items){return '<?xml version="1.0"?><rss><channel>'+items+'</channel></rss>';}
let parsed=parseSportsNewsRss(rss(item()),source,now);assert.equal(parsed.length,1);assert.equal(parsed[0].title,'Sports & goals');assert.equal(parsed[0].source,'BBC Sport');assert.ok(parsed[0].image.startsWith('https://ichef.'));
assert.equal(parseSportsNewsRss(rss(item('&#x1F3C6; Win &#39;now&#39;')),source,now)[0].title,"🏆 Win 'now'");
for(const url of ['javascript:alert(1)','https://bbc.com.evil.test/a','https://user:pass@bbc.com/a','https://evil.test/sport'])assert.equal(parseSportsNewsRss(rss(item('test',url)),source,now).length,0);
assert.equal(parseSportsNewsRss(rss(item('old',undefined,now-8*86400000)),source,now).length,0);
assert.equal(parseSportsNewsRss(rss(item('future',undefined,now+3600000)),source,now).length,0);
assert.equal(parseSportsNewsRss(rss(item().replace(/<pubDate>.*?<\/pubDate>/,'')),source,now).length,0);
assert.equal(parseSportsNewsRss(rss(item('test',undefined,undefined,'https://tracker.test/photo')),source,now)[0].image,null);
assert.equal(parseSportsNewsRss('x'.repeat(550001),source,now).length,0);
assert.equal(parseSportsNewsRss(rss(item('<b>Title</b><script>bad()</script>')),source,now)[0].title,'Title');
let calls=[],offline=false,skyDown=false;
globalThis.fetch=async url=>{calls.push(String(url));if(offline || skyDown && String(url).includes('skysports'))return new Response('down',{status:503});
 const sky=String(url).includes('skysports');
 return new Response(rss(sky?item('Newest story','https://www.skysports.com/football/news/1',now-30000,'https://e0.365dm.com/img.jpg')+item('Sports &amp; goals','https://www.skysports.com/football/news/2',now-120000):item()),{headers:{'content-type':'text/xml'}});};
const env={};const call=(category='all',e=env,method='GET')=>worker.fetch(new Request('https://worker.test/sports-news?category='+category,{method}),e,{});
let response=await call();assert.equal(response.status,200);let data=await response.json();assert.equal(data.items.length,2);assert.equal(data.items[0].title,'Newest story');assert.equal(data.items[1].source,'BBC Sport');assert.equal(calls.length,2);
await call();assert.equal(calls.length,2,'Fresh cache avoids repeated publisher requests');
assert.equal((await call('invalid')).status,400);assert.equal((await call('all',env,'POST')).status,405);
calls=[];await Promise.all([call('football'),call('football')]);assert.equal(calls.length,2,'Concurrent requests share a fetch');
calls=[];await call('cricket');assert.equal(calls.length,1);assert.ok(calls[0].includes('/cricket/rss.xml'));
skyDown=true;data=await(await call('all',{})).json();assert.equal(data.partial,true);assert.equal(data.items.length,1);skyDown=false;
const originalNow=Date.now;
try{Date.now=()=>now+6*60000;offline=true;data=await(await call()).json();assert.equal(data.stale,true);assert.equal(data.items.length,2);
 data=await(await call('all',{})).json();assert.equal(data.unavailable,true);assert.equal(data.items.length,0);
}finally{Date.now=originalNow;}
console.log('Sports news: RSS parsing, actual dates, source attribution, URL/image validation, deduplication, ordering, categories, caching, concurrency, partial feeds and stale fallback passed.');
