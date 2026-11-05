import '../utils/l10n.dart';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../theme/app_theme.dart';
import '../utils/l10n.dart';

/// An in-app YouTube player for trailers supplied by TMDB.
/// This keeps the user inside DamiMovies instead of launching a browser/app.
class TrailerPlayerScreen extends StatefulWidget {
  final String title;
  final String youtubeKey;
  final String poster;

  const TrailerPlayerScreen({
    super.key,
    required this.title,
    required this.youtubeKey,
    this.poster = '',
  });

  @override
  State<TrailerPlayerScreen> createState() => _TrailerPlayerScreenState();
}

class _TrailerPlayerScreenState extends State<TrailerPlayerScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;
  int _progress = 0;
  Widget? _fullscreenWidget;
  void Function()? _fullscreenHidden;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _failed = false;
              _progress = 0;
            });
          },
          onProgress: (progress) {
            if (mounted)
              setState(() => _progress = progress.clamp(0, 100).toInt());
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _progress = 100;
            });
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _loading = false;
                _failed = true;
              });
            }
          },
          // Keep YouTube redirects inside this in-app web player.
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            // Keep every trailer and any YouTube navigation inside this WebView.
            // Convert ordinary YouTube watch links to the embedded player rather
            // than allowing a browser/app hand-off.
            final scheme0 = uri.scheme.toLowerCase();
            if (scheme0 == 'about' || scheme0 == 'data')
              return NavigationDecision.navigate;
            if (!request.isMainFrame) {
              return scheme0 == 'https' || scheme0 == 'http'
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            }
            final host = uri.host.toLowerCase();
            final isYouTube = host == 'youtube.com' ||
                host.endsWith('.youtube.com') ||
                host == 'youtu.be' ||
                host.endsWith('.youtu.be');
            if (isYouTube && !uri.path.startsWith('/embed/')) {
              String? videoId;
              if (host == 'youtu.be' || host.endsWith('.youtu.be')) {
                videoId =
                    uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
              } else {
                videoId = uri.queryParameters['v'];
              }
              if (videoId != null && videoId.isNotEmpty) {
                unawaited(_controller.loadRequest(Uri.https(
                  'www.youtube-nocookie.com',
                  '/embed/$videoId',
                  const {
                    'autoplay': '1',
                    'playsinline': '1',
                    'rel': '0',
                    'controls': '1',
                    'modestbranding': '1',
                  },
                )));
                return NavigationDecision.prevent;
              }
            }

            final scheme = uri.scheme.toLowerCase();
            return scheme == 'https' || scheme == 'http'
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      unawaited(platform.setMediaPlaybackRequiresUserGesture(false));
      platform.setCustomWidgetCallbacks(
        onShowCustomWidget: _showFullscreen,
        onHideCustomWidget: _hideFullscreen,
      );
    }
    unawaited(_loadTrailer());
  }

  Future<void> _loadTrailer() async {
    final key = widget.youtubeKey.trim();
    if (key.isEmpty) {
      if (mounted)
        setState(() {
          _loading = false;
          _failed = true;
        });
      return;
    }
    if (mounted)
      setState(() {
        _loading = true;
        _failed = false;
      });
    final safeKey = key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    try {
      await _controller.loadHtmlString(
        _autoplayHtml(safeKey),
        baseUrl: 'https://www.youtube-nocookie.com',
      );
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _failed = true;
        });
    }
  }

  /// Wraps the YouTube player so the trailer starts by itself as soon as it is
  /// ready. If the WebView refuses autoplay with sound, it retries muted and
  /// then keeps nudging playback until it actually starts.
  String _autoplayHtml(String id) => '''
<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{position:absolute;inset:0;width:100%;height:100%}</style>
</head><body>
<div id="p"></div>
<script>
var player, tries = 0, started = false;
var tag = document.createElement('script');
tag.src = 'https://www.youtube.com/iframe_api';
document.head.appendChild(tag);
function onYouTubeIframeAPIReady() {
  player = new YT.Player('p', {
    videoId: '$id',
    host: 'https://www.youtube-nocookie.com',
    playerVars: {autoplay: 1, playsinline: 1, rel: 0, controls: 1, modestbranding: 1, origin: location.origin},
    events: {
      onReady: function(e) { e.target.playVideo(); },
      onAutoplayBlocked: function() { player.mute(); player.playVideo(); },
      onStateChange: function(e) {
        if (e.data === 1) { started = true; }
        if ((e.data === -1 || e.data === 5) && !started) { setTimeout(nudge, 400); }
      }
    }
  });
}
function nudge() {
  if (started || !player || tries > 6) return;
  tries++;
  if (tries > 2) { try { player.mute(); } catch (_) {} }
  try { player.playVideo(); } catch (_) {}
  setTimeout(nudge, 700);
}
</script>
</body></html>
''';

  void _showFullscreen(Widget child, void Function() onHidden) {
    if (!mounted) return;
    setState(() {
      _fullscreenWidget = child;
      _fullscreenHidden = onHidden;
    });
    unawaited(SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]));
    unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  }

  void _hideFullscreen() {
    if (!mounted) return;
    setState(() {
      _fullscreenWidget = null;
      _fullscreenHidden = null;
    });
    unawaited(
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }

  Future<void> _reload() async {
    try {
      await _controller.reload();
    } catch (_) {
      await _loadTrailer();
    }
  }

  Future<void> _back() async {
    if (_fullscreenWidget != null) {
      _fullscreenHidden?.call();
      _hideFullscreen();
      return;
    }
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    unawaited(
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _fullscreenWidget == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fullscreenWidget != null) _back();
      },
      child: Scaffold(
        backgroundColor: Ui.bg,
        appBar: _fullscreenWidget != null
            ? null
            : AppBar(
                backgroundColor: Ui.bg,
                title: Text(widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                leading: IconButton(
                    onPressed: _back, icon: Icon(Icons.arrow_back_rounded)),
                actions: [
                  IconButton(
                      tooltip: 'Reload trailer',
                      onPressed: _reload,
                      icon: Icon(Icons.refresh_rounded)),
                ],
              ),
        body: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      WebViewWidget(controller: _controller),
                      if (_loading)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: .72),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Ui.red),
                                SizedBox(height: 12),
                                Text(
                                    'Loading trailer… ${_progress.clamp(0, 100)}%',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      if (_failed)
                        ColoredBox(
                          color: Colors.black,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.wifi_off_rounded,
                                      color: Colors.white54, size: 36),
                                  SizedBox(height: 10),
                                  Text('This trailer could not be loaded.'.tr,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white70)),
                                  SizedBox(height: 10),
                                  FilledButton.icon(
                                    onPressed: _loadTrailer,
                                    icon: Icon(Icons.refresh_rounded),
                                    label: Text('Try again'.tr),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                                color: Ui.red,
                                borderRadius: BorderRadius.circular(6)),
                            child: Text('TRAILER'.tr,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1)),
                          ),
                          SizedBox(width: 9),
                          Icon(Icons.ondemand_video_rounded,
                              color: Colors.white54, size: 18),
                          SizedBox(width: 5),
                          Text('Playing in DamiMovies'.tr,
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                      SizedBox(height: 12),
                      Text(widget.title,
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              height: 1.12)),
                      SizedBox(height: 12),
                      if (widget.poster.startsWith('http'))
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: widget.poster,
                            height: 130,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      SizedBox(height: 14),
                      Text(
                        'Trailer video provided by YouTube. Use the player controls to pause, seek or enter fullscreen.',
                        style: TextStyle(
                            color: Colors.white54, height: 1.45, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_fullscreenWidget != null)
              Positioned.fill(
                  child: ColoredBox(
                      color: Colors.black, child: _fullscreenWidget!)),
          ],
        ),
      ),
    );
  }
}
