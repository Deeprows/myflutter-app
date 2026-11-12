import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../services/ad_shield.dart';
import '../services/dailymotion_check.dart';
import '../config.dart';
import '../models/fan_post_link.dart';
import '../services/embed_info.dart';
import '../services/player_html.dart';
import '../services/stream_resolver.dart';
import '../screens/browser_screen.dart' show openExternally;
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

  /// Dailymotion says this video cannot be embedded (owner turned it off,
  /// private or removed): show a clear message instead of "Forbidden".
  bool _dmBlocked = false;

  /// True while the WebView shows a page we built ourselves (our HTML5 player
  /// for m3u8/mp4/mpd, or an embed iframe). Such a page has no reason to
  /// navigate anywhere, so every top-level hop to another site is an ad.
  bool _htmlMode = false;

  /// Width of the video box, so Facebook's plugin is asked for a size that fits.
  double _boxW = 360;

  Future<void> _loadHtml(WebViewController c, String html, {String? baseUrl}) {
    _htmlMode = true;
    return c.loadHtmlString(html, baseUrl: baseUrl);
  }

  /// Same page origin the match page uses for streams (plain-http streams get
  /// an http origin so they are not blocked as mixed content).
  String _streamBase(String streamUrl) {
    if (streamUrl.toLowerCase().startsWith('http://')) {
      return AppConfig.playerOrigin.replaceFirst('https://', 'http://');
    }
    return AppConfig.playerOrigin;
  }
  String get _url => fanVideoUrl(widget.url);

  // Shape of the video box (width / height). Starts from a guess based on the
  // link (Shorts / TikTok / Reels are portrait) and follows the real video once
  // the player can measure it. [_manualRatio] wins when the viewer picks a shape.
  late EmbedInfo _info = embedInfoFor(widget.url);
  late double _ratio = _info.ratio;
  double? _manualRatio;
  String? _tiktokThumb;

  static const _shapes = [kLandscape, 1.0, kPortrait];

  void _cycleShape() {
    final cur = _manualRatio ?? _ratio;
    var nearest = 0;
    for (var i = 1; i < _shapes.length; i++) {
      if ((_shapes[i] - cur).abs() < (_shapes[nearest] - cur).abs()) nearest = i;
    }
    setState(() => _manualRatio = _shapes[(nearest + 1) % _shapes.length]);
  }

  void _onMeasured(String message) {
    if (_manualRatio != null) return;
    final parts = message.split('x');
    if (parts.length != 2) return;
    final w = double.tryParse(parts[0]), h = double.tryParse(parts[1]);
    if (w == null || h == null || w <= 0 || h <= 0) return;
    final r = (w / h).clamp(0.4, 2.4).toDouble();
    if ((r - _ratio).abs() > 0.02 && mounted) setState(() => _ratio = r);
  }

  String _iframeHtml(String src) {
    final safe = const HtmlEscape(HtmlEscapeMode.attribute).convert(src);
    return '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"></head><body style="margin:0;background:#000"><iframe src="$safe" style="position:fixed;inset:0;width:100%;height:100%;border:0" allow="autoplay; encrypted-media; fullscreen; picture-in-picture; clipboard-write" allowfullscreen scrolling="no"></iframe></body></html>';
  }

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
    if (_info.kind == EmbedKind.tiktok) {
      tiktokThumbnail(widget.url).then((t) {
        if (mounted && t != null) setState(() => _tiktokThumb = t);
      });
    }
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
    // Our own player / iframe page never needs to leave itself: any top-level
    // jump to another site (ad redirect, "open in browser") is dropped.
    if (_htmlMode) {
      final ytEmbed = (host == 'youtube-nocookie.com' || host == 'www.youtube-nocookie.com' ||
              host == 'www.youtube.com') &&
          uri.path.startsWith('/embed/');
      return ytEmbed ? NavigationDecision.navigate : NavigationDecision.prevent;
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

  /// 0 = app player origin, 1 = same origin but no Referer, 2 = stream's own
  /// origin (see the match player page).
  int _attempt = 0;

  /// Embed pages: 0 = iframe on a page presenting as the player origin,
  /// 1 = direct with that origin as Referer, 2 = direct, no Referer.
  /// Tapping "Retry video" after a failure tries the next one.
  int _embedMode = 0;

  void _playTap() {
    if (_failed) _embedMode = (_embedMode + 1) % 3;
    _play();
  }

  bool get _ownOrigin => _attempt >= 2;

  String _streamOrigin(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return AppConfig.playerOrigin;
    return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}/';
  }

  Future<void> _play({int attempt = 0}) async {
    _attempt = attempt;
    setState(() {
      _loading = true;
      _failed = false;
      _dmBlocked = false;
    });
    var stream = StreamResolver.resolve(_url);
    final initialUri = Uri.tryParse(_url);
    _startedAt = DateTime.now();
    _settled = false;
    _htmlMode = false;
    _allowedSites
      ..clear()
      ..add(_siteOf(initialUri?.host ?? ''));
    final c = WebViewController();
    c
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('FanSize', onMessageReceived: (m) => _onMeasured(m.message))
      ..addJavaScriptChannel('DwPlayer', onMessageReceived: (m) {
        if (m.message == 'fail' && _attempt < 2 && mounted) {
          _play(attempt: _attempt + 1);
        }
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            c.runJavaScript(AdShield.adShieldJs).catchError((_) {});
          },
          onProgress: (_) {
            // Like the match page: keep sweeping pop-ups / click-catchers
            // while an embed page is loading (our own player page needs none).
            if (!_htmlMode) c.runJavaScript(AdShield.adShieldJs).catchError((_) {});
          },
          onPageFinished: (_) {
            _settled = true;
            c.runJavaScript(AdShield.adShieldJs).catchError((_) {});
            c.runJavaScript(embedSizeJs).catchError((_) {});
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
      final cookies = WebViewCookieManager().platform;
      if (cookies is AndroidWebViewCookieManager) {
        unawaited(cookies.setAcceptThirdPartyCookies(platform, true));
      }
    }
    try {
      // Browser-like agent (no "wv"): TikTok and Facebook serve their full
      // players to it instead of an "open the app" page.
      await c.setUserAgent(AppConfig.userAgent);
      if (_info.kind == EmbedKind.tiktok) {
        final id = await resolveTikTokId(_url);
        if (!mounted || _controller != c) return;
        if (id != null) {
          await _loadHtml(c, 
            _iframeHtml(tiktokEmbedUrl(id)),
            baseUrl: AppConfig.embedOrigin,
          );
          return;
        }
      } else if (_info.kind == EmbedKind.facebook && initialUri != null) {
        final fbUrl = await resolveFacebookUrl(_url);
        if (!mounted || _controller != c) return;
        await _loadHtml(c,
          _iframeHtml(facebookEmbedUrl(fbUrl, width: _boxW.round().clamp(220, 734))),
          baseUrl: AppConfig.embedOrigin,
        );
        return;
      } else if (_info.kind == EmbedKind.vimeo && initialUri != null) {
        final id = _vimeoId(initialUri);
        if (id == null) throw FormatException('Invalid Vimeo video URL');
        await _loadHtml(c, 
          _iframeHtml('https://player.vimeo.com/video/$id?autoplay=1&title=0&byline=0&portrait=0'),
          baseUrl: AppConfig.embedOrigin,
        );
        return;
      } else if (_info.kind == EmbedKind.dailymotion && initialUri != null) {
        final id = _dailymotionId(initialUri);
        if (id == null) throw FormatException('Invalid Dailymotion video URL');
        if (await DailymotionCheck.check(id) == DailymotionEmbed.blocked) {
          if (!mounted || _controller != c) return;
          setState(() {
            _dmBlocked = true;
            _failed = true;
            _loading = false;
          });
          return;
        }
        if (!mounted || _controller != c) return;
        await _loadHtml(c,
          _iframeHtml(DailymotionCheck.playerUrl(id)),
          baseUrl: AppConfig.embedOrigin,
        );
        return;
      }
      if (_attempt == 0 &&
          stream.kind == StreamKind.embed &&
          _youtubeId(initialUri) == null &&
          _info.kind == EmbedKind.generic) {
        // Direct link without a file extension: ask the server what it is.
        final k = await StreamResolver.sniff(stream.url);
        if (!mounted || _controller != c) return;
        if (k != null) stream = ResolvedStream(stream.url, k);
      }
      final youtubeId = _youtubeId(initialUri);
      if (youtubeId != null) {
        await _loadHtml(c, 
          '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"></head><body style="margin:0;background:#000"><iframe src="https://www.youtube-nocookie.com/embed/$youtubeId?autoplay=1&playsinline=1&rel=0&controls=1" style="position:fixed;inset:0;width:100%;height:100%;border:0" allow="autoplay; encrypted-media; fullscreen; picture-in-picture" allowfullscreen></iframe></body></html>',
          baseUrl: 'https://www.youtube-nocookie.com',
        );
      } else if (stream.usesHtmlPlayer) {
        await c.setUserAgent(AppConfig.userAgent);
        await _loadHtml(c,
          buildPlayerHtml(stream, lowQuality: false, noReferrer: _attempt == 1),
          baseUrl: _ownOrigin ? _streamOrigin(stream.url) : _streamBase(stream.url),
        );
      } else if (Uri.parse(_url).host == 'www.youtube.com' &&
          Uri.parse(_url).path.startsWith('/embed/')) {
        final src = const HtmlEscape(HtmlEscapeMode.attribute).convert(_url);
        await _loadHtml(c, 
          '<html><meta name="viewport" content="width=device-width,initial-scale=1"><body style="margin:0;background:black"><iframe src="$src" style="border:0;width:100%;height:100%" allow="autoplay; encrypted-media; fullscreen; picture-in-picture" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>',
          baseUrl: AppConfig.embedOrigin,
        );
      } else {
        // Embed page: same desktop-like agent as the match page's player.
        await c.setUserAgent(AppConfig.userAgent);
        final target = stream.kind == StreamKind.invalid ? _url : stream.url;
        if (_embedMode == 0 && stream.kind == StreamKind.embed) {
          final src = const HtmlEscape(HtmlEscapeMode.attribute).convert(target);
          await _loadHtml(c,
            '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"></head><body style="margin:0;background:#000"><iframe src="$src" style="position:fixed;inset:0;width:100%;height:100%;border:0" allow="autoplay; encrypted-media; fullscreen; picture-in-picture" allowfullscreen></iframe></body></html>',
            baseUrl: _streamBase(target),
          );
        } else {
          _htmlMode = false;
          if (_embedMode == 1 && stream.kind == StreamKind.embed) {
            await c.loadRequest(Uri.parse(target),
                headers: {'Referer': _streamBase(target)});
          } else {
            await c.loadRequest(Uri.parse(target));
          }
        }
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _failed = true;
          _loading = false;
        });
    }
  }


  String? _vimeoId(Uri? uri) {
    if (uri == null) return null;
    final match = RegExp(r'/(?:video/)?(\d{6,})').firstMatch(uri.path);
    return match?.group(1);
  }

  String? _dailymotionId(Uri? uri) => DailymotionCheck.idFrom(uri);

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

  String get _playLabel {
    if (_failed) return 'Retry video';
    switch (_info.kind) {
      case EmbedKind.tiktok:
        return 'Play TikTok';
      case EmbedKind.facebook:
        return 'Play Facebook video';
      case EmbedKind.vimeo:
        return 'Play Vimeo video';
      case EmbedKind.dailymotion:
        return 'Play Dailymotion video';
      case EmbedKind.filemoon:
        return 'Play Filemoon video';
      case EmbedKind.hls:
        return 'Play HLS stream';
      case EmbedKind.direct:
        return 'Play video';
      default:
        return 'Play video';
    }
  }

  Widget _blockedCard() => ColoredBox(
    color: const Color(0xFF171A20),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block_rounded, color: Colors.white70, size: 34),
            const SizedBox(height: 8),
            const Text(
              'The owner of this Dailymotion video does not allow it to be '
              'played outside Dailymotion.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => openExternally(widget.url),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open on Dailymotion'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _preview() {
    if (_dmBlocked) return _blockedCard();
    final thumb = _youtubeThumbnail ?? _tiktokThumb;
    return InkWell(
      onTap: widget.onTapPreview ?? _playTap,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          if (thumb != null)
            Image.network(
              thumb,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFF171A20)),
            )
          else
            Image.asset(
              'assets/themes/cr7.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFF171A20)),
            ),
          const ColoredBox(color: Color(0x66000000)),
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
                  _playLabel,
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
    );
  }

  Widget _player() => Stack(
    children: [
      WebViewWidget(controller: _controller!),
      if (_loading) const LinearProgressIndicator(),
      Positioned(
        top: 4,
        right: 4,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_info.kind == EmbedKind.tiktok ||
                _info.kind == EmbedKind.facebook ||
                _info.kind == EmbedKind.dailymotion) ...[
              // Some TikTok / Facebook videos refuse to be embedded (private,
              // region-locked, owner turned embedding off): open the original.
              IconButton.filled(
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => openExternally(widget.url),
                tooltip: 'Open original',
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
              ),
              const SizedBox(width: 4),
            ],
            IconButton.filled(
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              onPressed: _cycleShape,
              tooltip: 'Change video shape',
              icon: const Icon(Icons.aspect_ratio_rounded, size: 18),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              onPressed: _stop,
              tooltip: 'Stop video',
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // In the feed keep tall (portrait) videos from taking over the screen;
    // on the post page they can use most of it.
    final maxFraction = widget.onTapPreview != null ? 0.55 : 0.78;
    return PopScope(
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
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth.isFinite ? box.maxWidth : screen.width;
            _boxW = w;
            final maxH = math.max(w * 0.5, screen.height * maxFraction);
            final h = (w / (_manualRatio ?? _ratio)).clamp(w * 0.45, maxH).toDouble();
            return AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: w,
                height: h,
                child: _controller != null && !_failed ? _player() : _preview(),
              ),
            );
          },
        ),
      ),
    );
  }
}
