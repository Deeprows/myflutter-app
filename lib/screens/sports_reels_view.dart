import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../services/sports_reels_service.dart';
import '../theme/app_theme.dart';
import 'browser_screen.dart';

/// Full-height vertical reels (swipe up for the next one) built from trending
/// sports Shorts. Only the reel on screen has a live player.
class SportsReelsView extends StatefulWidget {
  const SportsReelsView({super.key});
  @override
  State<SportsReelsView> createState() => _SportsReelsViewState();
}

class _SportsReelsViewState extends State<SportsReelsView> {
  static const _chips = [
    ('all', 'Trending'),
    ('football', 'Football'),
    ('cricket', 'Cricket'),
    ('f1', 'F1'),
    ('other', 'More sports'),
  ];
  final _page = PageController();
  final _feeds = <String, SportsReelsFeed>{};
  String _cat = 'all';
  bool _loading = false, _failed = false;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    if (_loading || (!force && _feeds.containsKey(_cat))) return;
    final cat = _cat;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final feed = await SportsReelsService.load(cat);
      if (mounted) setState(() => _feeds[cat] = feed);
    } catch (_) {
      if (mounted && _cat == cat) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pick(String cat) {
    if (cat == _cat) return;
    setState(() {
      _cat = cat;
      _index = 0;
    });
    if (_page.hasClients) _page.jumpToPage(0);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _feeds[_cat]?.items ?? const <SportsReel>[];
    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            children: [
              for (final c in _chips)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c.$2),
                    selected: _cat == c.$1,
                    onSelected: (_) => _pick(c.$1),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: items.isNotEmpty
              ? PageView.builder(
                  controller: _page,
                  scrollDirection: Axis.vertical,
                  itemCount: items.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => _ReelPage(
                    key: ValueKey(items[i].id),
                    reel: items[i],
                    active: i == _index,
                  ),
                )
              : Center(
                  child: _loading
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_circle_outline,
                                  size: 48, color: Ui.dim),
                              const SizedBox(height: 12),
                              Text(
                                _failed
                                    ? 'Could not load reels. Check your connection.'
                                    : 'No trending reels right now.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Ui.muted),
                              ),
                              TextButton(
                                onPressed: () => _load(force: true),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                ),
        ),
      ],
    );
  }
}

class _ReelPage extends StatefulWidget {
  final SportsReel reel;
  final bool active;
  const _ReelPage({super.key, required this.reel, required this.active});
  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> with WidgetsBindingObserver {
  WebViewController? _web;
  bool _ready = false;
  bool _failed = false;
  bool _starting = false;
  bool _appResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant _ReelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active && _appResumed) {
        _start();
      } else {
        _stop();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (!_appResumed) {
      _stop();
    } else if (widget.active) {
      _start();
    }
  }

  Future<void> _start() async {
    if (!mounted || !widget.active || !_appResumed || _starting || _web != null) return;
    _starting = true;
    setState(() {
      _ready = false;
      _failed = false;
    });
    try {
      final id = widget.reel.id;
      final html = '''<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<meta name="referrer" content="origin">
<style>
html,body,#player{margin:0;width:100%;height:100%;background:#000;overflow:hidden}
iframe{position:absolute;inset:0;width:100%;height:100%;border:0}
</style></head><body><div id="player"></div>
<script>
var player;
function notify(value){try{ReelPlayer.postMessage(value)}catch(e){}}
function onYouTubeIframeAPIReady(){
  player=new YT.Player('player',{
    width:'100%',height:'100%',videoId:'$id',
    playerVars:{autoplay:1,playsinline:1,controls:0,rel:0,modestbranding:1,
      fs:0,iv_load_policy:3,disablekb:1,origin:'https://www.youtube.com'},
    events:{
      onReady:function(e){notify('ready');e.target.mute();e.target.playVideo();},
      onStateChange:function(e){if(e.data===1)notify('playing');},
      onError:function(e){notify('error:'+e.data);}
    }
  });
}
function stopReel(){try{if(player&&player.pauseVideo)player.pauseVideo()}catch(e){}}
</script>
<script src="https://www.youtube.com/iframe_api"></script>
</body></html>''';
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Colors.black);
      await controller.addJavaScriptChannel('ReelPlayer', onMessageReceived: (message) {
        if (!mounted) return;
        final value = message.message;
        if (value == 'ready' || value == 'playing') {
          setState(() { _ready = true; _failed = false; });
        } else if (value.startsWith('error:')) {
          setState(() { _failed = true; _ready = false; });
        }
      });
      await controller.setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted && widget.active && !_failed) {
            // The iframe API reports readiness separately; this only confirms
            // that the HTML shell has loaded.
          }
        },
        onWebResourceError: (error) {
          if (mounted && widget.active && error.isForMainFrame == true) {
            setState(() => _failed = true);
          }
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          if (uri.scheme == 'about' || uri.host == 'www.youtube.com' ||
              uri.host == 'youtube.com' || uri.host == 'www.youtube-nocookie.com' ||
              uri.host == 'youtube-nocookie.com' || uri.host.endsWith('googlevideo.com') ||
              uri.host.endsWith('ytimg.com') || uri.host.endsWith('youtube.com')) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
      ));
      final platform = controller.platform;
      if (platform is AndroidWebViewController) {
        await platform.setMediaPlaybackRequiresUserGesture(false);
        final cookies = WebViewCookieManager().platform;
        if (cookies is AndroidWebViewCookieManager) {
          await cookies.setAcceptThirdPartyCookies(platform, true);
        }
      }
      if (!mounted || !widget.active || !_appResumed) {
        _starting = false;
        return;
      }
      _web = controller;
      await controller.loadHtmlString(html, baseUrl: 'https://www.youtube.com/');
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _starting = false;
    }
  }

  Future<void> _stop() async {
    final controller = _web;
    _web = null;
    if (mounted) setState(() { _ready = false; });
    if (controller != null) {
      try {
        await controller.runJavaScript('stopReel();');
        await controller.loadRequest(Uri.parse('about:blank'));
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _web;
    if (controller != null) {
      controller.runJavaScript('stopReel();').catchError((_) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reel;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (_web != null && !_failed)
          WebViewWidget(controller: _web!),
        if (!_ready && !_failed)
          const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
        if (_failed)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_circle_outline, color: Colors.white70, size: 52),
                  const SizedBox(height: 12),
                  const Text('This video cannot play inside the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => openInApp(context, r.watchUrl, title: r.channel),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Watch on YouTube'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54)),
                  ),
                  TextButton(onPressed: () { _web = null; _start(); },
                    child: const Text('Retry', style: TextStyle(color: Colors.white70))),
                ],
              ),
            ),
          ),
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 28, 8, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xCC000000)]),
            ),
            child: Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(r.channel, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              )),
              IconButton(tooltip: 'Open on YouTube',
                icon: const Icon(Icons.open_in_new, color: Colors.white),
                onPressed: () => openInApp(context, r.watchUrl, title: r.channel)),
              IconButton(tooltip: 'Share',
                icon: const Icon(Icons.ios_share, color: Colors.white),
                onPressed: () async {
                  try { await Share.share('${r.title}\n${r.watchUrl}'); } catch (_) {}
                }),
            ]),
          ),
        ),
      ],
    );
  }
}
