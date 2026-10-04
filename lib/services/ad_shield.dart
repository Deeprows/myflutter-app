/// Best-effort ad suppression for pages loaded in a WebView (embed players,
/// stream pages, download pages). A WebView can't filter network requests, so
/// this works in two ways:
///  * [isAdUrl]: known ad-network hosts/paths are refused in the navigation
///    delegate (also for iframes and sub-frames).
///  * [adShieldJs]: a script that removes pop-ups, click-catching overlays and
///    banner / video / gif ad blocks while never touching the real player.
class AdShield {
  static final _adHosts = RegExp(
    r'(^|\.)('
    r'doubleclick\.net|googlesyndication\.com|googleadservices\.com|'
    r'adservice\.google\.[a-z.]+|adnxs\.com|adsterra\.com|'
    r'propellerads\.com|popads\.net|popcash\.net|popunder\.net|'
    r'exoclick\.com|exosrv\.com|juicyads\.com|trafficjunky\.net|'
    r'clickadu\.com|hilltopads\.net|adcash\.com|revcontent\.com|'
    r'taboola\.com|outbrain\.com|mgid\.com|criteo\.com|'
    r'pubmatic\.com|rubiconproject\.com|openx\.net|adform\.net|'
    r'onclickads\.net|onclkds\.com|profitablecpmrate\.com|'
    r'highperformanceformat\.com|effectivegatecpm\.com|'
    r'adsco\.re|a-ads\.com|ad-maven\.com|admaven\.com|'
    r'monetag\.com|richpush\.co|pushwoosh\.com|'
    r'yllix\.com|ero-advertising\.com|bidvertiser\.com|'
    r'tsyndicate\.com|trafmag\.com|syndication\.exdynsrv\.com|'
    r'ads\.[a-z0-9-]+\.[a-z.]+|adserver\.[a-z0-9-]+\.[a-z.]+'
    r')$',
    caseSensitive: false,
  );

  static final _adPath = RegExp(
    r'/(ads?|adserver|advert|banner|popunder|popup|pop-under)[/_.-]|[?&](ad|ads|adid)=',
    caseSensitive: false,
  );

  static bool isAdUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    if (_adHosts.hasMatch(uri.host)) return true;
    // Only treat path hints as ads on sub-frames of third-party hosts; the
    // caller decides whether that applies.
    return false;
  }

  /// Looser check used only for sub-frames / sub-resources.
  static bool isAdSubframe(String url) =>
      isAdUrl(url) || _adPath.hasMatch(Uri.tryParse(url)?.path ?? '');

  /// Injected after every page start / finish. Safe to run repeatedly.
  static const adShieldJs = r"""
(function(){
  try{
    if(window.__dwShield){window.__dwShield();return}
    var BAD=/(doubleclick|googlesyndication|googleadservices|adnxs|adsterra|propeller|popads|popcash|exoclick|exosrv|juicyads|trafficjunky|clickadu|hilltopads|adcash|taboola|outbrain|mgid|criteo|onclickads|onclkds|profitablecpmrate|highperformanceformat|effectivegatecpm|a-ads|admaven|ad-maven|monetag|richpush|bidvertiser|tsyndicate|exdynsrv|\/ads?[\/_.-]|adserver|banner|popunder)/i;
    var SEL='[id^="ad-"],[id^="ad_"],[id$="-ad"],[id$="_ad"],[id*="advert" i],[id*="banner" i],'+
            '[class^="ad-"],[class^="ad_"],[class*=" ad-"],[class*=" ad_"],[class*="advert" i],[class*="banner" i],'+
            '[class*="popup" i],[class*="popunder" i],[class*="sponsor" i],[class*="overlay" i],'+
            'ins.adsbygoogle,[data-ad],[data-ad-slot],[data-adsbygoogle-status]';
    function hasPlayer(el){
      if(!el||el.nodeType!==1)return false;
      var t=el.tagName;
      if(t==='VIDEO'||t==='AUDIO')return true;
      return !!(el.querySelector&&el.querySelector('video,audio'));
    }
    function isPlayerFrame(f){
      // the biggest iframe on the page is the real player, never remove it
      var r=f.getBoundingClientRect();
      return r.width*r.height>=0.35*innerWidth*innerHeight;
    }
    function kill(el){try{el.style.setProperty('display','none','important');el.remove()}catch(e){}}
    function sweep(){
      try{
        // 1. ad iframes / scripts / images / gifs / videos from ad hosts
        var list=document.querySelectorAll('iframe,img,video,source,embed,object,script,a,link');
        for(var i=0;i<list.length;i++){
          var n=list[i];
          var u=n.src||n.href||n.getAttribute('data-src')||'';
          if(!u||!BAD.test(u))continue;
          if(n.tagName==='VIDEO'&&hasPlayer(n)&&!BAD.test(n.currentSrc||u))continue;
          if(n.tagName==='IFRAME'&&isPlayerFrame(n)&&!/doubleclick|googlesyndication|adsterra|popads|exoclick/i.test(u))continue;
          kill(n);
        }
        // 2. class / id based ad containers (never ones holding the player)
        var c=document.querySelectorAll(SEL);
        for(var j=0;j<c.length;j++){
          var e=c[j];
          if(hasPlayer(e)||e.contains(document.activeElement))continue;
          var r=e.getBoundingClientRect();
          // skip huge containers (page wrappers) - only ad-sized blocks
          if(r.width*r.height>0.6*innerWidth*innerHeight&&!/fixed|absolute|sticky/.test(getComputedStyle(e).position))continue;
          kill(e);
        }
        // 3. fixed / absolute floating layers: banners, gif/video ads and
        //    invisible click-catchers sitting above the player
        var all=document.body?document.body.getElementsByTagName('*'):[];
        for(var k=0;k<all.length&&k<2500;k++){
          var x=all[k];
          if(x.tagName==='VIDEO'||x.tagName==='AUDIO'||x.tagName==='SCRIPT'||x.tagName==='STYLE')continue;
          var cs=getComputedStyle(x);
          if(cs.position!=='fixed'&&cs.position!=='absolute'&&cs.position!=='sticky')continue;
          var z=parseInt(cs.zIndex,10);
          if(!(z>=100))continue;
          if(hasPlayer(x))continue;
          if(x.closest&&x.closest('video,[class*="jw"],[class*="vjs"],[class*="plyr"],[class*="player" i],[id*="player" i]'))continue;
          var b=x.getBoundingClientRect();
          if(b.width<30||b.height<20)continue;
          var big=b.width>=0.6*innerWidth&&b.height>=0.6*innerHeight;
          var media=x.tagName==='IMG'||x.tagName==='IFRAME'||x.querySelector('img,iframe,video[muted]');
          var hasText=(x.innerText||'').trim().length>0;
          // click-catcher: large, transparent/empty, above the player
          if(big&&!hasText&&!x.querySelector('button,input,svg')){kill(x);continue}
          // floating banner / gif / video ad
          if(media&&!big){kill(x);continue}
        }
      }catch(e){}
    }
    window.__dwShield=sweep;
    // pop-ups, new tabs, redirects triggered by scripts
    window.open=function(){return null};
    try{window.alert=function(){};window.confirm=function(){return false}}catch(e){}
    document.addEventListener('click',function(ev){
      var a=ev.target&&ev.target.closest?ev.target.closest('a[target=_blank],a[target=_new]'):null;
      if(a){ev.preventDefault();ev.stopPropagation()}
    },true);
    // hide leftovers instantly via CSS, then clean the DOM
    var st=document.createElement('style');
    st.textContent='ins.adsbygoogle,[id^="google_ads"],[id^="div-gpt-ad"],iframe[src*="doubleclick"],iframe[src*="googlesyndication"],iframe[src*="adsterra"],iframe[src*="popads"],iframe[src*="exoclick"]{display:none!important}';
    (document.head||document.documentElement).appendChild(st);
    sweep();
    var t=null;
    new MutationObserver(function(){if(t)return;t=setTimeout(function(){t=null;sweep()},250)})
      .observe(document.documentElement,{childList:true,subtree:true});
    setInterval(sweep,2000);
  }catch(e){}
})();""";
}
