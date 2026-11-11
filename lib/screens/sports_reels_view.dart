import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import '../services/sports_reels_service.dart';
import '../theme/app_theme.dart';
import 'browser_screen.dart';

/// Full-height vertical sports reels, built from the same config-driven setup
/// as the Deeprowss browser's Reels (YouTube Shorts, Dailymotion, PeerTube,
/// RSS and your own videos, with tabs per category and a "Near You" tab).
///
/// YouTube reels use the same mobile Shorts page as the in-app browser, rather
/// than YouTube's restricted embed player. Other sources play in their own
/// embed player. Only the visible reel is allowed to play.
class SportsReelsView extends StatefulWidget {
  /// False while another tab or section is on top: every reel stops.
  final bool active;
  const SportsReelsView({super.key, this.active = true});

  @override
  State<SportsReelsView> createState() => _SportsReelsViewState();
}

class _SportsReelsViewState extends State<SportsReelsView>
    with WidgetsBindingObserver {
  final _page = PageController();
  SportsReelsFeed? _feed;
  // A newer download waiting for the person to tap "New reels".
  SportsReelsFeed? _pending;
  String _tab = 'all';
  bool _loading = false, _failed = false;
  // True while a reel shows a YouTube sign-in (or any non-Shorts) page: the
  // reel list is frozen so scrolling the page never changes the reel.
  bool _locked = false;
  int _index = 0;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // Keep the reels moving: look for new videos every few minutes while this
    // tab is on screen. The feed itself is cached for 5 minutes.
    _refresh = Timer.periodic(const Duration(minutes: 3), (_) => _checkFresh());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _page.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkFresh();
  }

  Future<void> _load({bool force = false}) async {
    if (_loading) return;
    if (!force && _feed != null) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final feed = await SportsReelsService.load(force: force);
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _pending = null;
        _locked = false;
        if (!feed.tabs.contains(_tab)) _tab = 'all';
        _index = 0;
      });
      if (_page.hasClients) _page.jumpToPage(0);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Quietly looks for newer reels. Never swaps the list under a playing
  /// reel: a "New reels" chip is shown instead.
  Future<void> _checkFresh() async {
    if (!mounted || _loading || _feed == null) return;
    if (!widget.active ||
        !TickerMode.getValue(context) ||
        !SportsReelsService.isStale) {
      return;
    }
    try {
      final feed = await SportsReelsService.load();
      if (!mounted || identical(feed, _feed)) return;
      if (feed.signature(_tab) != _feed!.signature(_tab)) {
        setState(() => _pending = feed);
      } else {
        _feed = feed;
      }
    } catch (_) {}
  }

  void _applyPending() {
    final feed = _pending;
    if (feed == null) return;
    setState(() {
      _feed = feed;
      _pending = null;
      _locked = false;
      if (!feed.tabs.contains(_tab)) _tab = 'all';
      _index = 0;
    });
    if (_page.hasClients) _page.jumpToPage(0);
  }

  void _pick(String tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _index = 0;
      _locked = false;
    });
    if (_page.hasClients) _page.jumpToPage(0);
  }

  void _setLocked(bool v) {
    if (!mounted || _locked == v) return;
    setState(() => _locked = v);
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    final items = feed?.forTab(_tab) ?? const <SportsReel>[];
    final tabs = feed?.tabs ?? const <String>[];
    return Column(
      children: [
        if (!_locked && feed != null && feed.enabled && tabs.length > 2)
          SizedBox(
            height: 46,
            child: Row(
              children: [
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    children: [
                      for (final t in tabs)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(feed.label(t)),
                            selected: _tab == t,
                            onSelected: (_) => _pick(t),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh reels',
                  icon: Icon(Icons.refresh, color: Ui.muted),
                  onPressed: _loading ? null : () => _load(force: true),
                ),
              ],
            ),
          ),
        Expanded(
          child: items.isNotEmpty
              ? Stack(
                  children: [
                    PageView.builder(
                      controller: _page,
                      scrollDirection: Axis.vertical,
                      // Frozen while a sign-in page is open.
                      physics: _locked
                          ? const NeverScrollableScrollPhysics()
                          : const PageScrollPhysics(),
                      itemCount: items.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (_, i) => _ReelPage(
                        // Keep the state tied to the reel, not its active flag.
                        key: ValueKey(items[i].id),
                        reel: items[i],
                        active: i == _index,
                        viewActive: widget.active,
                        onInteractive: _setLocked,
                      ),
                    ),
                    if (_pending != null && !_locked)
                      Positioned(
                        top: 10,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: ActionChip(
                            avatar: const Icon(Icons.arrow_upward_rounded,
                                size: 16),
                            label: const Text('New reels'),
                            onPressed: _applyPending,
                          ),
                        ),
                      ),
                  ],
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
                                feed != null && !feed.enabled
                                    ? 'Reels are switched off right now.'
                                    : _failed
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

  /// The whole Reels view is on screen (not covered by another tab).
  final bool viewActive;

  /// Tells the list when this reel is showing a page that must be scrolled
  /// (YouTube sign-in, consent...), so the list stops reacting to swipes.
  final ValueChanged<bool>? onInteractive;

  const _ReelPage({
    super.key,
    required this.reel,
    required this.active,
    this.viewActive = true,
    this.onInteractive,
  });

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> with WidgetsBindingObserver {
  // The WebView exists only while this reel may play. When it must stop it is
  // blanked and thrown away (so nothing can keep playing in the background)
  // and a fresh one is made when the reel comes back.
  WebViewController? _web;
  bool _ready = false;
  bool _error = false;
  bool _appVisible = true;
  // Unknown (null) until the first dependency pass: a reel built while its
  // tab is hidden must not start.
  bool? _tabVisible;
  // Showing a sign-in / non-Shorts page instead of the Shorts player.
  bool _interactive = false;
  ValueListenable<bool>? _tickerMode;
  final _timers = <Timer>[];

  bool get _canPlay =>
      widget.active &&
      widget.viewActive &&
      _appVisible &&
      (_tabVisible ?? false);

  /// True for the Shorts player page itself.
  static bool _isReelUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return true;
    if (u.scheme != 'http' && u.scheme != 'https') return true;
    final host = u.host.toLowerCase();
    if (!(host == 'youtube.com' || host.endsWith('.youtube.com'))) return false;
    return u.path.startsWith('/shorts') || u.path.startsWith('/watch');
  }

  void _setInteractive(bool v) {
    if (_interactive == v) return;
    if (mounted) setState(() => _interactive = v);
    if (widget.active) widget.onInteractive?.call(v);
  }

  void _onUrl(String url) {
    if (!widget.reel.isYouTube || _web == null) return;
    _setInteractive(!_isReelUrl(url));
  }

  void _onTickerMode() {
    final visible = _tickerMode?.value ?? true;
    if (visible == _tabVisible) return;
    _tabVisible = visible;
    // Never rebuild in the middle of the framework's own build.
    scheduleMicrotask(() {
      if (mounted) _sync();
    });
  }

  /// Plays when the reel is the visible one, otherwise stops it for good.
  void _sync() {
    if (_canPlay) {
      if (_web == null) {
        _start();
      } else {
        unawaited(_playWithSound());
      }
    } else {
      _stop();
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
    final visible = notifier.value;
    if (visible != _tabVisible) {
      _tabVisible = visible;
      // First pass (or a change): decide now, before anything can play.
      if (_canPlay) {
        if (_web == null) _start();
      } else {
        _stop(rebuild: false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Playback is decided in didChangeDependencies, once it is known whether
    // this reel's tab is actually on screen.
  }

  @override
  void didUpdateWidget(covariant _ReelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.viewActive != widget.viewActive) {
      if (!widget.active && _interactive) {
        _interactive = false;
      }
      _sync();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _appVisible = true;
        _sync();
      case AppLifecycleState.inactive:
        // Notification shade, permission dialog...: just pause.
        _softPause();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _appVisible = false;
        _sync();
    }
  }

  void _start() {
    if (_web != null || !_canPlay) return;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(AppConfig.userAgent)
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            _onUrl(url);
            setState(() {
              _ready = false;
              _error = false;
            });
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) _onUrl(url);
          },
          onPageFinished: (url) async {
            if (!mounted || _web == null) return;
            setState(() => _ready = true);
            // Embed players (Dailymotion, PeerTube, own videos) run inside
            // their own frame: nothing to trim, they start themselves.
            if (!widget.reel.isYouTube) return;
            _onUrl(url);
            if (_interactive) {
              // Sign-in / consent page: make it fit the screen and leave it
              // alone (no trimming, no autoplay).
              await _fitPage();
              return;
            }
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
    if (mounted) setState(() {});
    // Load the same Shorts URL used by the working in-app browser. Do not use
    // /embed/: embedded videos can be rejected by the channel (error 152-4).
    _open(controller);
  }

  void _open(WebViewController controller) {
    final r = widget.reel;
    if (r.isYouTube) {
      controller.loadRequest(Uri.parse(r.watchUrl));
    } else {
      // The base address tells Dailymotion & co. which site is embedding.
      controller.loadHtmlString(_embedPage(r.embedUrl!),
          baseUrl: 'https://deeprows.github.io/');
    }
  }

  static bool _isFile(String url) {
    final path = url.split('?').first.toLowerCase();
    return path.endsWith('.mp4') ||
        path.endsWith('.webm') ||
        path.endsWith('.m3u8') ||
        path.endsWith('.ogg');
  }

  /// Full-screen page holding the video: a <video> for direct files, an
  /// iframe for player pages (same page the Deeprowss browser builds).
  static String _embedPage(String raw) {
    final url = raw.replaceAll('"', '%22');
    final referrer = url.contains('dailymotion.com')
        ? 'no-referrer-when-downgrade'
        : 'strict-origin-when-cross-origin';
    final inner = _isFile(url)
        ? '<video src="$url" controls autoplay playsinline></video>'
        : '<iframe src="$url" allow="autoplay; encrypted-media; '
            'picture-in-picture; fullscreen" allowfullscreen '
            'referrerpolicy="$referrer"></iframe>';
    return '<!DOCTYPE html><html><head>'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<style>html,body{margin:0;padding:0;width:100%;height:100%;'
        'background:#000;overflow:hidden}iframe,video{position:absolute;'
        'top:0;left:0;width:100%;height:100%;border:0;background:#000}'
        '</style></head><body>$inner</body></html>';
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

  /// Makes a sign-in / consent page fit the screen: the right viewport, no
  /// sideways overflow, and room under the last button so "Continue" can be
  /// scrolled clear of the phone's navigation bar.
  Future<void> _fitPage() async {
    final controller = _web;
    if (controller == null) return;
    try {
      await controller.runJavaScript('''
        (function () {
          let m = document.querySelector('meta[name=viewport]');
          if (!m) {
            m = document.createElement('meta');
            m.name = 'viewport';
            document.head.appendChild(m);
          }
          m.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
          if (document.getElementById('dp-fit')) return;
          const s = document.createElement('style');
          s.id = 'dp-fit';
          s.textContent = `
            html, body { max-width: 100vw !important; overflow-x: hidden !important; }
            body { padding-bottom: 120px !important; box-sizing: border-box; }
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
    if (controller == null ||
        !_canPlay ||
        _interactive ||
        !widget.reel.isYouTube) {
      return;
    }
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

  void _cancelTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  /// Pauses without tearing the page down (short interruptions).
  Future<void> _softPause() async {
    _cancelTimers();
    final controller = _web;
    if (controller == null) return;
    try {
      await controller.runJavaScript('''
        document.querySelectorAll('video').forEach((video) => video.pause());
      ''');
    } catch (_) {}
  }

  /// Stops the reel completely: pauses it, blanks the page (so no sound can
  /// leak out of a hidden tab) and lets go of the WebView.
  void _stop({bool rebuild = true}) {
    _cancelTimers();
    final controller = _web;
    final wasInteractive = _interactive;
    _web = null;
    _ready = false;
    _interactive = false;
    if (controller != null) {
      unawaited(() async {
        try {
          await controller.runJavaScript(
              "document.querySelectorAll('video,audio').forEach((m) => m.pause());");
        } catch (_) {}
        try {
          await controller.loadRequest(Uri.parse('about:blank'));
        } catch (_) {}
      }());
    }
    if (wasInteractive) {
      // Never tell the list while the framework is building or disposing.
      final notify = widget.onInteractive;
      scheduleMicrotask(() => notify?.call(false));
    }
    if (rebuild && mounted) setState(() {});
  }

  /// Leaves the sign-in page and goes back to the reel.
  void _backToReel() {
    final controller = _web;
    if (controller == null) return;
    _setInteractive(false);
    setState(() {
      _ready = false;
      _error = false;
    });
    controller.loadRequest(Uri.parse(widget.reel.watchUrl));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickerMode?.removeListener(_onTickerMode);
    _stop(rebuild: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reel;
    final showWeb = _web != null && widget.active && _canPlay;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (showWeb)
          // One WebView, always in the same place in the tree. On a sign-in
          // page it is moved below a small bar and kept clear of the phone's
          // navigation bar, and it takes every touch itself so scrolling the
          // page never scrolls the reels.
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                top: _interactive ? 48 : 0,
                bottom: _interactive ? bottom + 8 : 0,
              ),
              child: WebViewWidget(
                controller: _web!,
                gestureRecognizers: _interactive
                    ? <Factory<OneSequenceGestureRecognizer>>{
                        Factory<OneSequenceGestureRecognizer>(
                          () => EagerGestureRecognizer(),
                        ),
                      }
                    : const <Factory<OneSequenceGestureRecognizer>>{},
              ),
            ),
          )
        else
          CachedNetworkImage(
            imageUrl: r.thumb,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        if (showWeb && _interactive)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 48,
            child: Material(
              color: Colors.black,
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _backToReel,
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                    label: const Text('Back to reels',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        if (!r.isYouTube)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xB3000000), Color(0x00000000)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      r.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.ago.isEmpty ? r.channel : '${r.channel} \u00B7 ${r.ago}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (showWeb && !_ready && !_error)
          const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          ),
        if (showWeb && _error)
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
