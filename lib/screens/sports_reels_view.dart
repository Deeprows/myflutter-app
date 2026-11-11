import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
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
  // Hidden when the reels tab is covered (another tab/page is on top).
  bool _tabVisible = true;
  ValueListenable<bool>? _tickerMode;
  final _timers = <Timer>[];

  bool get _canPlay => widget.active && _appVisible && _tabVisible;

  void _onTickerMode() {
    final visible = _tickerMode?.value ?? true;
    if (visible == _tabVisible) return;
    _tabVisible = visible;
    if (_canPlay) {
      _start();
      _resume();
    } else {
      _pause();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = TickerMode.getNotifier(context);
    if (!identical(notifier, _tickerMode)) {
      _tickerMode?.removeListener(_onTickerMode);
      _tickerMode = notifier..addListener(_onTickerMode);
    }
    _onTickerMode();
  }

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
      if (_canPlay) {
        _start();
        _resume();
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
    } else if (_canPlay) {
      _resume();
    }
  }

  void _start() {
    if (_web != null || !_canPlay) return;
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
            // YouTube's own Shorts page is shown as-is (its like, comment,
            // share and subscribe buttons work with the user's YouTube
            // login). We only trim the page chrome and start playback with
            // sound.
            await _hideYoutubeUi();
            await _playWithSound();
            _timers
              ..forEach((t) => t.cancel())
              ..clear();
            for (final ms in const [700, 1800, 3500]) {
              _timers.add(Timer(Duration(milliseconds: ms), _playWithSound));
            }
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
            // Keep YouTube/Google sign-in, comments and media requests in this
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

  /// Trims only the page chrome around the Short (YouTube logo/search bar,
  /// bottom tab bar, "open in app" banners) and removes the unmute button.
  /// The Short's like / comment / share / subscribe buttons stay untouched.
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
            ytm-mobile-topbar-renderer, ytm-pivot-bar-renderer,
            ytm-reel-player-header-renderer, .reel-player-header-container,
            ytm-upsell-dialog-renderer, ytm-mealbar-promo-renderer,
            .ytp-unmute, .ytp-unmute-inner, .ytp-unmute-text,
            [class*="unmute"], button[aria-label*="mute" i]
            { display: none !important; }
            body, html { background: #000 !important; }
          `;
          document.head.appendChild(s);
        })();
      ''');
    } catch (_) {}
  }

  /// Plays the reel with sound. Falls back to muted playback only if the
  /// WebView refuses sound autoplay, so the video never sits frozen.
  Future<void> _playWithSound() async {
    final controller = _web;
    if (controller == null || !_canPlay) return;
    try {
      await controller.runJavaScript('''
        (function () {
          document.querySelectorAll('video').forEach((video) => {
            video.playsInline = true;
            video.muted = false;
            video.volume = 1;
            const r = video.play();
            if (r && r.catch) {
              r.catch(() => {
                video.muted = true;
                const m = video.play();
                if (m && m.catch) m.catch(() => {});
              });
            }
          });
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _pause() async {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
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
    await _playWithSound();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickerMode?.removeListener(_onTickerMode);
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
      ],
    );
  }
}
