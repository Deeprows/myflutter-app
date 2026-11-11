import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import '../services/auth_service.dart';
import '../services/sports_reels_service.dart';
import '../theme/app_theme.dart';
import 'browser_screen.dart';

/// Full-height vertical sports reels. Each reel uses the same mobile YouTube
/// Shorts page as the in-app browser, rather than YouTube's restricted embed
/// player. Only the visible reel is allowed to play.
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
                    // Keep the state tied to the reel, not its active flag.
                    // This lets it pause/resume without rebuilding its WebView.
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
  bool _error = false;
  bool _appVisible = true;
  bool _liked = false, _likeBusy = false;
  static const _likedKey = 'liked_reel_ids_v1';

  Future<void> _loadLiked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mine = prefs.getStringList(_likedKey) ?? const <String>[];
      if (mounted && mine.contains(widget.reel.id)) setState(() => _liked = true);
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    final msg = ScaffoldMessenger.of(context);
    final want = !_liked;
    setState(() {
      _liked = want; // instant feedback
      _likeBusy = true;
    });
    final error = await SportsReelsService.setLike(widget.reel.id, want);
    if (!mounted) return;
    if (error != null) {
      setState(() => _liked = !want);
      msg.showSnackBar(SnackBar(content: Text(error)));
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final ids = (prefs.getStringList(_likedKey) ?? <String>[]).toList();
        want ? ids.add(widget.reel.id) : ids.remove(widget.reel.id);
        await prefs.setStringList(_likedKey, ids.toSet().toList());
      } catch (_) {}
    }
    if (mounted) setState(() => _likeBusy = false);
  }

  Widget _action(IconData icon, String label, VoidCallback onTap,
      {Color color = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 32, shadows: const [
            Shadow(blurRadius: 8, color: Colors.black87)
          ]),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black87)])),
        ]),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadLiked();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant _ReelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active && _appVisible) {
        _start();
      } else {
        _pause();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    _appVisible = visible;
    if (!visible) {
      _pause();
    } else if (widget.active) {
      _resume();
    }
  }

  void _start() {
    if (_web != null || !widget.active || !_appVisible) return;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(AppConfig.userAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _ready = false;
              _error = false;
            });
          },
          onPageFinished: (_) async {
            if (!mounted) return;
            setState(() => _ready = true);
            // YouTube's mobile Shorts page owns its player UI. Nudge its video
            // element to begin muted playback when autoplay is permitted.
            await _hideYoutubeUi();
            await _playMuted();
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted) {
              setState(() => _error = true);
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme == 'about' ||
                uri.scheme == 'data' ||
                uri.scheme == 'blob') {
              return NavigationDecision.navigate;
            }
            // Liking is done by the app with the user's Gmail, so never let
            // the page open YouTube/Google sign-in screens.
            if (uri.host == 'accounts.google.com' ||
                uri.path.contains('/signin') ||
                uri.path.contains('ServiceLogin')) {
              return NavigationDecision.prevent;
            }
            // Keep YouTube's own navigation and media/CDN requests in this
            // WebView. Never launch an external app from a reel.
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      );

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      unawaited(platform.setMediaPlaybackRequiresUserGesture(false));
    }

    _web = controller;
    _ready = false;
    _error = false;
    // Load the same Shorts URL used by the working in-app browser. Do not use
    // /embed/: embedded videos can be rejected by the channel (error 152-4).
    controller.loadRequest(Uri.parse(widget.reel.watchUrl));
  }

  /// Hides YouTube's own title, channel, buttons and sign-in prompts; the app
  /// draws one clean overlay on top instead (no repeated text).
  Future<void> _hideYoutubeUi() async {
    final controller = _web;
    if (controller == null) return;
    try {
      await controller.runJavaScript('''
        (function () {
          if (document.getElementById('dp-clean')) return;
          const s = document.createElement('style');
          s.id = 'dp-clean';
          s.textContent = `
            ytm-reel-player-overlay-renderer,
            ytm-reel-player-header-renderer,
            ytm-shorts-lockup-view-model,
            ytm-shorts-lockup-view-model-v2,
            shorts-video-metadata, .reel-player-overlay-actions,
            .reel-player-header-container, ytm-mobile-topbar-renderer,
            ytm-pivot-bar-renderer, ytm-bottom-sheet-renderer,
            .mobile-topbar-header, c3-overlay, tp-yt-paper-dialog,
            ytm-promoted-sparkles-web-renderer,
            [class*="player-controls-bottom"], [class*="mealbar"]
            { display: none !important; }
            body, html { background: #000 !important; }
          `;
          document.head.appendChild(s);
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _playMuted() async {
    final controller = _web;
    if (controller == null || !widget.active || !_appVisible) return;
    try {
      await controller.runJavaScript('''
        (function () {
          const videos = document.querySelectorAll('video');
          videos.forEach((video) => {
            video.muted = true;
            video.playsInline = true;
            const result = video.play();
            if (result && result.catch) result.catch(() => {});
          });
        })();
      ''');
    } catch (_) {
      // YouTube may still be initializing its player; its own autoplay logic
      // will retry when the Shorts page is ready.
    }
  }

  Future<void> _pause() async {
    final controller = _web;
    if (controller == null) return;
    try {
      await controller.runJavaScript('''
        document.querySelectorAll('video').forEach((video) => video.pause());
      ''');
    } catch (_) {}
  }

  Future<void> _resume() async {
    if (_web == null) return;
    await _playMuted();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pause();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reel;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (_web != null && widget.active)
          WebViewWidget(controller: _web!)
        else
          CachedNetworkImage(
            imageUrl: r.thumb,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        if (widget.active && !_ready && !_error)
          const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          ),
        if (widget.active && _error)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, color: Colors.white70, size: 38),
                const SizedBox(height: 10),
                const Text(
                  'This reel could not be loaded.',
                  style: TextStyle(color: Colors.white),
                ),
                TextButton.icon(
                  onPressed: () =>
                      openInApp(context, r.watchUrl, title: r.channel),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Retry in video browser'),
                ),
              ],
            ),
          ),
        // One clean overlay (YouTube's own title/buttons are hidden).
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              height: 150,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 76,
          bottom: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                r.channel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                r.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black87)]),
              ),
            ],
          ),
        ),
        Positioned(
          right: 8,
          bottom: 10,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _action(
                _liked ? Icons.favorite : Icons.favorite_border,
                _liked ? 'Liked' : 'Like',
                _toggleLike,
                color: _liked ? const Color(0xFFFF3B5C) : Colors.white,
              ),
              _action(Icons.ios_share, 'Share', () async {
                try {
                  await Share.share('${r.title}\n${r.watchUrl}');
                } catch (_) {}
              }),
              _action(Icons.open_in_new, 'Open',
                  () => openInApp(context, r.watchUrl, title: r.channel)),
            ],
          ),
        ),
      ],
    );
  }
}
