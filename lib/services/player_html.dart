import 'dart:convert';

import 'stream_resolver.dart';

/// Self-contained HTML5 player page for m3u8 (hls.js), mpd (dash.js) and
/// plain video files. Loaded into the WebView via loadHtmlString.
///
/// [noReferrer] asks the page not to send any Referer with the stream
/// requests. Many hosts block foreign referers but accept an empty one, so it
/// is the second attempt after the normal player origin.
String buildPlayerHtml(ResolvedStream s,
    {bool lowQuality = false, bool noReferrer = false}) {
  final url = jsonEncode(s.url).replaceAll('</', r'<\/');
  final kind = jsonEncode(s.kind.name);
  return _template
      .replaceAll('__META__',
          noReferrer ? '<meta name="referrer" content="no-referrer">' : '')
      .replaceAll('__URL__', url)
      .replaceAll('__KIND__', kind)
      .replaceAll('__LOW__', lowQuality ? 'true' : 'false');
}

const _template = r'''<!DOCTYPE html>
<html><head><meta charset="utf-8">
__META__
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
html,body{margin:0;height:100%;background:#000;overflow:hidden;font-family:Roboto,Arial,sans-serif}
video{position:absolute;left:0;top:0;width:100%;height:100%;background:#000;object-fit:contain}
#spin{position:absolute;left:50%;top:50%;width:34px;height:34px;margin:-17px 0 0 -17px;border:3px solid rgba(255,255,255,.2);border-top-color:#ff1744;border-radius:50%;animation:s .8s linear infinite;pointer-events:none}
@keyframes s{to{transform:rotate(360deg)}}
#msg{position:absolute;left:0;top:0;right:0;bottom:0;display:none;align-items:center;justify-content:center;flex-direction:column;color:#fff;text-align:center;padding:24px;background:rgba(0,0,0,.82);font-size:14px;line-height:1.45}
#msg b{font-size:16px;margin-bottom:6px}
#msg small{color:#aeb6c3}
</style></head><body>
<video id="v" controls autoplay playsinline preload="auto"></video>
<div id="spin"></div>
<div id="msg"><b>Couldn't play this stream</b><small id="why">The link may be offline, geo-blocked or protected.</small></div>
<script>
(function(){
var URL_=__URL__, KIND=__KIND__, LOW=__LOW__;
var v=document.getElementById('v'), spin=document.getElementById('spin'),
    msg=document.getElementById('msg'), why=document.getElementById('why');
function hideSpin(){spin.style.display='none'}
var LAST='';
function fail(t){hideSpin(); if(!t&&LAST)t=LAST; if(t) why.textContent=t; msg.style.display='flex';
  try{DwPlayer.postMessage('fail')}catch(e){}}
var started=false, WD=null, recoveries=0;
function markStarted(){started=true; if(WD){clearTimeout(WD);WD=null}}
['loadedmetadata','loadeddata','canplay','playing'].forEach(function(n){v.addEventListener(n,markStarted)});
// Nothing arrived at all (silent block / dead link): report it so the app
// can retry with another origin instead of leaving a black screen.
WD=setTimeout(function(){ if(!started) fail('No data received - the host may be blocking this app or is offline.') },16000);
v.addEventListener('playing',function(){hideSpin();msg.style.display='none'});
// Direct files that freeze mid-way: reload at the same position.
var lastT=-1, still=0;
setInterval(function(){
  if(KIND==='hls'||KIND==='dash'||!started||v.paused||v.ended){still=0;return}
  if(Math.abs(v.currentTime-lastT)<0.05){ still++ } else { still=0 }
  lastT=v.currentTime;
  if(still>=3 && recoveries<4 && isFinite(v.duration)){
    recoveries++; still=0; var t=v.currentTime;
    v.addEventListener('loadedmetadata',function(){try{v.currentTime=t}catch(e){} tryPlay()},{once:true});
    v.src=URL_; v.load();
  }
},3000);
v.addEventListener('waiting',function(){spin.style.display='block'});
v.addEventListener('canplay',hideSpin);
function tryPlay(){var p=v.play(); if(p&&p.catch)p.catch(function(){hideSpin()})}
function native(){
  v.addEventListener('error',function(){fail()},{once:true});
  v.src=URL_; v.load(); tryPlay();
}
function loadScript(list,ok,bad){
  var i=0;
  (function next(){
    if(i>=list.length){bad();return}
    var s=document.createElement('script');
    s.src=list[i++]; s.onload=ok; s.onerror=next;
    document.head.appendChild(s);
  })();
}
function startHls(){
  if(!(window.Hls&&Hls.isSupported())){native();return}
  var h=new Hls({enableWorker:true,lowLatencyMode:true,maxBufferLength:30,startLevel:LOW?0:-1});
  var net=0, med=0;
  h.on(Hls.Events.MANIFEST_PARSED,function(){if(LOW){h.autoLevelCapping=0;h.currentLevel=0}tryPlay()});
  h.on(Hls.Events.ERROR,function(e,d){
    if(!d.fatal)return;
    LAST='Stream error: '+(d.details||'unknown')+(d.response&&d.response.code?' (HTTP '+d.response.code+')':(d.type===Hls.ErrorTypes.NETWORK_ERROR?' (blocked, offline or CORS)':''));
    if(d.type===Hls.ErrorTypes.NETWORK_ERROR&&net++<3){h.startLoad();return}
    if(d.type===Hls.ErrorTypes.MEDIA_ERROR&&med++<2){h.recoverMediaError();return}
    h.destroy(); native();
  });
  h.loadSource(URL_); h.attachMedia(v);
}
function startDash(){
  if(!window.dashjs){native();return}
  var p=dashjs.MediaPlayer().create();
  p.on('error',function(){fail()});
  p.initialize(v,URL_,true);
}
if(KIND==='hls'){
  loadScript(['https://cdn.jsdelivr.net/npm/hls.js@1.5.17/dist/hls.min.js',
              'https://cdnjs.cloudflare.com/ajax/libs/hls.js/1.5.17/hls.min.js'],startHls,native);
}else if(KIND==='dash'){
  loadScript(['https://cdn.jsdelivr.net/npm/dashjs@4.7.4/dist/dash.all.min.js',
              'https://cdnjs.cloudflare.com/ajax/libs/dashjs/4.7.4/dash.all.min.js'],startDash,native);
}else{
  native();
}
})();
</script></body></html>''';
