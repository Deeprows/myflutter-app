import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../services/ad_shield.dart';
import '../config.dart';
import '../models/fan_post_link.dart';
import '../services/player_html.dart';
import '../services/stream_resolver.dart';
import '../theme/app_theme.dart';

/// A lightweight play card. In the feed, tapping it opens the post (like a
/// Twitter timeline); inside the post, the video plays right there.
class FanPostVideo extends StatefulWidget {
  final String url;
  final bool inline;

  /// When set, tapping the preview calls this (e.g. open the post) instead of
  /// starting playback.
  final VoidCallback? onTapPreview;

  /// Start playing as soon as the card is shown (used on the post page).
  final bool autoPlay;
  const FanPostVideo({
    super.key,
    required this.url,
    required this.inline,
    this.onTapPreview,
    this.autoPlay = false,
  });
  @override
  State<FanPostVideo> createState() => _FanPostVideoState();
}

class _FanPostVideoState extends State<FanPostVideo>
    with WidgetsBindingObserver {
  WebViewController? _controller;
  OverlayEntry? _fullscreenEntry;
  VoidCallback? _fullscreenHidden;
  final Set<String> _allowedSites = {};
  DateTime _startedAt = DateTime.now();
  bool _settled = false;
  static const _redirectGate = Duration(seconds: 5);
  bool _loading = false, _failed = false;
  String get _url => fanVideoUrl(widget.url);

  String? get _youtubeThumbnail {
    final uri = Uri.tryParse(_url);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (!host.contains('youtube.com') && host != 'youtu.be') return null;
    String? id;
    if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
      id = uri.pathSegments.first;
    } else if (uri.pathSegments.length > 1 &&
        ['embed', 'shorts', 'live'].contains(uri.pathSegments.first)) {
      id = uri.pathSegments[1];
    } else {
      id = uri.queryParameters['v'];
    }
    if (id == null || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
      return null;
    }
    return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller == null) _play();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.of(context)) _stop();
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _showFullscreen(Widget child, void Function() onHidden) {
    if (!mounted || _fullscreenEntry != null) return;
    _fullscreenHidden = onHidden;
    _fullscreenEntry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: Material(
          color: Colors.black,
          child: SafeArea(
            left: false, right: false, top: false, bottom: false,
            child: SizedBox.expand(child: child),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_fullscreenEntry!);
    unawaited(SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  }

  void _hideFullscreen() {
    final entry = _fullscreenEntry;
    if (entry == null) return;
    _fullscreenEntry = null;
    _fullscreenHidden = null;
    entry.remove();
    entry.dispose();
    unawaited(_restoreSystemUi());
  }

  void _backFromFullscreen() {
    _fullscreenHidden?.call();
    _hideFullscreen();
  }

  NavigationDecision _navigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'about' || scheme == 'data' || scheme == 'blob') {
      return NavigationDecision.navigate;
    }
    if (scheme != 'http' && scheme != 'https') return NavigationDecision.prevent;
    if (!request.isMainFrame) {
      return AdShield.isAdSubframe(request.url)
          ? NavigationDecision.prevent : NavigationDecision.navigate;
    }
    if (AdShield.isAdUrl(request.url)) return NavigationDecision.prevent;
    final host = uri.host.toLowerCase();
    final isYoutube = host == 'youtube.com' || host.endsWith('.youtube.com') ||
        host == 'youtu.be' || host.endsWith('.youtu.be');
    if (isYoutube && !uri.path.startsWith('/embed/')) {
      String? id;
      if (host == 'youtu.be' || host.endsWith('.youtu.be')) {
        id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      } else {
        id = uri.queryParameters['v'];
        if ((id == null || id.isEmpty) && uri.pathSegments.length > 1 &&
            ['shorts', 'live'].contains(uri.pathSegments.first)) id = uri.pathSegments[1];
      }
      if (id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
        unawaited(_controller?.loadRequest(Uri.https(
          'www.youtube-nocookie.com', '/embed/$id',
          const {'autoplay':'1','playsinline':'1','rel':'0','controls':'1'},
        )) ?? Future<void>.value());
      }
      return NavigationDecision.prevent;
    }
    final site = _siteOf(host);
    if (!_settled && DateTime.now().difference(_startedAt) < _redirectGate) {
      _allowedSites.add(site);
      return NavigationDecision.navigate;
    }
    if (_allowedSites.contains(site) ||
        site == _siteOf(Uri.parse(AppConfig.playerOrigin).host)) {
      return NavigationDecision.navigate;
    }
    // Drop top-level ad/affiliate hand-offs. Embedded media frames remain allowed.
    return NavigationDecision.prevent;
  }

  String _siteOf(String host) {
    final parts = host.toLowerCase().split('.');
    return parts.length < 2 ? host.toLowerCase() : parts.sublist(parts.length - 2).join('.');
  }

  void _stop() {
    _backFromFullscreen();
    final c = _controller;
    if (c != null) {
      _controller = null;
      unawaited(c.loadHtmlString('<html></html>').catchError((Object _) {}));
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backFromFullscreen();
    unawaited(_restoreSystemUi());
    final c = _controller;
    if (c != null)
      unawaited(c.loadHtmlString('<html></html>').catchError((Object _) {}));
    super.dispose();
  }

  Future<void> _play() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final stream = StreamResolver.resolve(_url);
    final initialUri = Uri.tryParse(_url);
    _startedAt = DateTime.now();
    _settled = false;
    _allowedSites
      ..clear()
      ..add(_siteOf(initialUri?.host ?? ''));
    final c = WebViewController();
    c
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            c.runJavaScript(AdShield.adShieldJs).catchError((_) {});
          },
          onPageFinished: (_) {
            _settled = true;
            c.runJavaScript(AdShield.adShieldJs).catchError((_) {});
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted)
              setState(() {
                _failed = true;
                _loading = false;
              });
          },
          onNavigationRequest: _navigation,
        ),
      );
    if (!mounted) return;
    setState(() => _controller = c);
    final platform = c.platform;
    if (platform is AndroidWebViewController) {
      unawaited(platform.setMediaPlaybackRequiresUserGesture(false));
      platform.setCustomWidgetCallbacks(
        onShowCustomWidget: _showFullscreen,
        onHideCustomWidget: _hideFullscreen,
      );
    }
    try {
      final youtubeId = _youtubeId(initialUri);
      if (youtubeId != null) {
        await c.loadHtmlString(
          '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"></head><body style="margin:0;background:#000"><iframe src="https://www.youtube-nocookie.com/embed/$youtubeId?autoplay=1&playsinline=1&rel=0&controls=1" style="position:fixed;inset:0;width:100%;height:100%;border:0" allow="autoplay; encrypted-media; fullscreen; picture-in-picture" allowfullscreen></iframe></body></html>',
          baseUrl: 'https://www.youtube-nocookie.com',
        );
      } else if (stream.usesHtmlPlayer) {
        await c.loadHtmlString(
          buildPlayerHtml(stream, lowQuality: false),
          baseUrl: 'https://deeprowss.com',
        );
      } else if (Uri.parse(_url).host == 'www.youtube.com' &&
          Uri.parse(_url).path.startsWith('/embed/')) {
        final src = const HtmlEscape(HtmlEscapeMode.attribute).convert(_url);
        await c.loadHtmlString(
          '<html><meta name="viewport" content="width=device-width,initial-scale=1"><body style="margin:0;background:black"><iframe src="$src" style="border:0;width:100%;height:100%" allow="autoplay; encrypted-media; fullscreen; picture-in-picture" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>',
          baseUrl: 'https://deeprowss.com',
        );
      } else {
        await c.loadRequest(Uri.parse(_url));
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _failed = true;
          _loading = false;
        });
    }
  }

  String? _youtubeId(Uri? uri) {
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (!(host == 'youtube.com' || host.endsWith('.youtube.com') || host == 'youtu.be')) return null;
    String? id;
    if (host == 'youtu.be') {
      id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    } else if (uri.pathSegments.length > 1 && ['embed','shorts','live'].contains(uri.pathSegments.first)) {
      id = uri.pathSegments[1];
    } else {
      id = uri.queryParameters['v'];
    }
    return id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ? id : null;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _fullscreenEntry == null,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _fullscreenEntry != null) _backFromFullscreen();
    },
    child: Container(
    margin: const EdgeInsets.only(top: 10),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.black,
      border: Border.all(color: Ui.line),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: _controller != null && !_failed
              ? Stack(
                  children: [
                    WebViewWidget(controller: _controller!),
                    if (_loading) const LinearProgressIndicator(),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton.filled(
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _stop,
                        tooltip: 'Stop video',
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ),
                  ],
                )
              : InkWell(
                  onTap: widget.onTapPreview ?? _play,
                  child: Stack(
                    fit: StackFit.expand,
                    alignment: Alignment.center,
                    children: [
                      if (_youtubeThumbnail != null)
                        Image.network(
                          _youtubeThumbnail!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Color(0xFF171A20),
                          ),
                        )
                      else
                        const ColoredBox(color: Color(0xFF171A20)),
                      const ColoredBox(color: Color(0x55000000)),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.play_circle_fill_rounded,
                              size: 58,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _failed ? 'Retry video' : 'Play video',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                shadows: [Shadow(blurRadius: 5, color: Colors.black)],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );
}
