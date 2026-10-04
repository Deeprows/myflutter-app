import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import '../services/pip_service.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import '../services/ad_shield.dart';
import '../services/player_html.dart';
import '../services/settings_service.dart';
import '../services/stream_resolver.dart';
import '../theme/app_theme.dart';
import '../widgets/live_dot.dart';
import 'browser_screen.dart' show siteOf;

/// WebView based player. Plays:
///  * m3u8 (hls.js), mpd (dash.js) and direct video files through a built-in
///    HTML5 player page,
///  * anything else (embed pages, iframes, player links) as a normal web page.
class PlayerScreen extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String url;
  final String? altUrl;
  final bool isLive;

  const PlayerScreen({
    super.key,
    required this.title,
    required this.url,
    this.subtitle,
    this.altUrl,
    this.isLive = false,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final WebViewController _wc;
  final GlobalKey _videoKey = GlobalKey();

  late final List<String> _sources = [
    widget.url,
    if (widget.altUrl != null &&
        widget.altUrl!.trim().isNotEmpty &&
        widget.altUrl!.trim() != widget.url.trim())
      widget.altUrl!,
  ];
  int _srcIdx = 0;

  bool _error = false;
  bool _settled = false;
  bool _landscape = false;
  String _initialHost = '';

  // Pop-up / redirect blocking. Cross-site hops are only trusted during the
  // first load (short links, embed redirects); after that, the page may not
  // send the player to another website by itself.
  DateTime _startedAt = DateTime.now();
  final Set<String> _allowedSites = {};
  static const _gateWindow = Duration(seconds: 5);
  bool _pipEnabled = false;

  Widget? _fullscreenWidget;
  VoidCallback? _fullscreenHidden;

  ResolvedStream get _stream => StreamResolver.resolve(_sources[_srcIdx]);

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(AppConfig.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => _killPopups(),
        onProgress: (_) => _killPopups(),
        onPageFinished: (_) {
          _settled = true;
          _killPopups();
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) {
            setState(() => _error = true);
          }
        },
        onNavigationRequest: _onNavigation,
      ));

    final p = _wc.platform;
    if (p is AndroidWebViewController) {
      p.setMediaPlaybackRequiresUserGesture(false);
      p.setCustomWidgetCallbacks(
        onShowCustomWidget: _showFullscreen,
        onHideCustomWidget: _hideFullscreen,
      );
      final cookies = WebViewCookieManager().platform;
      if (cookies is AndroidWebViewCookieManager) {
        cookies.setAcceptThirdPartyCookies(p, true);
      }
    }

    Settings.floatingPlayer().then((v) {
      if (mounted) setState(() => _pipEnabled = v);
    });
    _start();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------------------------------------------------------- loading

  Future<void> _start() async {
    final s = _stream;
    setState(() {
      _error = false;
      _settled = false;
    });
    if (s.kind == StreamKind.invalid) {
      setState(() => _error = true);
      return;
    }
    _initialHost = Uri.tryParse(s.url)?.host ?? '';
    _startedAt = DateTime.now();
    _allowedSites
      ..clear()
      ..add(siteOf(_initialHost));
    try {
      if (s.usesHtmlPlayer) {
        final low = await Settings.forceLowQuality();
        await _wc.loadHtmlString(
          buildPlayerHtml(s, lowQuality: low),
          baseUrl: AppConfig.playerOrigin,
        );
      } else {
        await _wc.loadRequest(Uri.parse(s.url));
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  bool get _gateOpen =>
      !_settled && DateTime.now().difference(_startedAt) < _gateWindow;

  /// Keeps ad redirects out. Frames and sub-resources (what embeds are made
  /// of) are never affected. Top-level navigation to another website is only
  /// trusted while the first page is loading; afterwards it is blocked and a
  /// snackbar offers ALLOW in case the redirect was legitimate.
  NavigationDecision _onNavigation(NavigationRequest r) {
    if (!r.isMainFrame) {
      // Frames/sub-resources stay allowed (embeds are made of them), except
      // known ad networks.
      return AdShield.isAdSubframe(r.url)
          ? NavigationDecision.prevent
          : NavigationDecision.navigate;
    }
    final uri = Uri.tryParse(r.url);
    if (uri == null) return NavigationDecision.prevent;
    if (AdShield.isAdUrl(r.url)) return NavigationDecision.prevent;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'about' || scheme == 'data' || scheme == 'blob') {
      return NavigationDecision.navigate;
    }
    // intent://, market://, custom app schemes: never leave the app.
    if (scheme != 'http' && scheme != 'https') {
      return NavigationDecision.prevent;
    }
    final site = siteOf(uri.host);
    if (_gateOpen) {
      _allowedSites.add(site);
      return NavigationDecision.navigate;
    }
    if (_allowedSites.contains(site) ||
        site == siteOf(Uri.parse(AppConfig.playerOrigin).host)) {
      return NavigationDecision.navigate;
    }
    _noteBlocked(uri);
    return NavigationDecision.prevent;
  }

  /// Blocked redirects are dropped silently (no notification).
  void _noteBlocked(Uri uri) {}

  /// Neutralises pop-ups opened by the page itself and by transparent
  /// click-catcher overlays (window.open / target=_blank links).
  void _killPopups() {
    if (_stream.usesHtmlPlayer) return; // our own page has no ads
    _wc.runJavaScript(AdShield.adShieldJs).catchError((_) {});
  }

  // ------------------------------------------------------------- fullscreen

  Future<void> _applyOrientation({required bool landscape}) async {
    if (landscape) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _showFullscreen(Widget widget, void Function() onHidden) {
    if (!mounted) return;
    setState(() {
      _fullscreenWidget = widget;
      _fullscreenHidden = onHidden;
    });
    _applyOrientation(landscape: true);
  }

  void _hideFullscreen() {
    if (!mounted) return;
    setState(() {
      _fullscreenWidget = null;
      _fullscreenHidden = null;
    });
    _applyOrientation(landscape: _landscape);
  }

  void _toggleLandscape() {
    setState(() => _landscape = !_landscape);
    _applyOrientation(landscape: _landscape);
  }

  // ---------------------------------------------------------------- actions

  void _switchSource() {
    setState(() => _srcIdx = (_srcIdx + 1) % _sources.length);
    _start();
  }

  Future<void> _enterPip() async {
    try {
      if (await PipService.isAvailable() && await PipService.enter()) return;
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Floating player is not supported here')));
  }

  /// Opens Android's "Cast screen" panel so the stream (including web embeds)
  /// can be mirrored to a TV or Chromecast.
  Future<void> _cast() async {
    const actions = [
      'android.settings.CAST_SETTINGS',
      'android.settings.WIFI_DISPLAY_SETTINGS',
    ];
    for (final a in actions) {
      try {
        await AndroidIntent(action: a).launch();
        return;
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Open "Cast" or "Smart View" from your phone\'s quick settings')));
  }

  void _onBack() {
    if (_fullscreenWidget != null) {
      _fullscreenHidden?.call();
      _hideFullscreen();
    } else if (_landscape) {
      _toggleLandscape();
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final fs = _fullscreenWidget != null;
    final immersive = _landscape || fs;

    final video = ColoredBox(
      key: _videoKey,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _wc),
          if (_error) _ErrorOverlay(
            hasAlt: _sources.length > 1,
            invalid: _stream.kind == StreamKind.invalid,
            onRetry: _start,
            onAlt: _switchSource,
          ),
        ],
      ),
    );

    return PopScope(
      canPop: !immersive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: immersive ? Colors.black : Ui.bg,
        body: Stack(
          children: [
            if (immersive)
              Positioned.fill(child: video)
            else
              _portraitBody(video),
            if (_landscape && !fs) ...[
              Positioned(
                left: 12,
                top: 12,
                child: _RoundButton(
                    icon: Icons.arrow_back_rounded, onTap: _onBack),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: _RoundButton(
                    icon: Icons.screen_rotation_rounded,
                    onTap: _toggleLandscape),
              ),
            ],
            if (fs)
              Positioned.fill(
                child: ColoredBox(color: Colors.black, child: _fullscreenWidget),
              ),
          ],
        ),
      ),
    );
  }

  Widget _portraitBody(Widget video) {
    final s = _stream;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: 'Cast to screen',
                  onPressed: _cast,
                  icon: const Icon(Icons.cast_rounded),
                ),
                if (_pipEnabled)
                  IconButton(
                    tooltip: 'Floating player',
                    onPressed: _enterPip,
                    icon: const Icon(Icons.picture_in_picture_alt_rounded),
                  ),
                if (widget.isLive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: Ui.red, borderRadius: BorderRadius.circular(99)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LiveDot(size: 6),
                        SizedBox(width: 6),
                        Text('LIVE',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          AspectRatio(aspectRatio: 16 / 9, child: video),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Text(widget.title,
                    style: const TextStyle(
                        fontSize: 20,
                        height: 1.2,
                        fontWeight: FontWeight.w900)),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(widget.subtitle!,
                      style: TextStyle(
                          color: Ui.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Chip(icon: Icons.play_circle_outline_rounded, label: s.label),
                    if (_sources.length > 1)
                      _Chip(
                          icon: Icons.layers_outlined,
                          label: 'Stream ${_srcIdx + 1} of ${_sources.length}'),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _Action(
                          icon: Icons.refresh_rounded,
                          label: 'Reload',
                          onTap: _start),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Action(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Switch',
                          enabled: _sources.length > 1,
                          onTap: _switchSource),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Action(
                          icon: Icons.screen_rotation_rounded,
                          label: 'Rotate',
                          onTap: _toggleLandscape),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Ui.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Ui.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: Ui.muted),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Stream not loading? Tap Reload, or Switch to try the '
                          'backup source. Pop-ups, redirects and on-screen ads are blocked '
                          'automatically.',
                          style: TextStyle(
                              color: Ui.muted, fontSize: 12.5, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  final bool hasAlt;
  final bool invalid;
  final VoidCallback onRetry;
  final VoidCallback onAlt;
  const _ErrorOverlay({
    required this.hasAlt,
    required this.invalid,
    required this.onRetry,
    required this.onAlt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: .88),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: Ui.redSoft, size: 34),
          const SizedBox(height: 8),
          Text(
            invalid ? 'This link can\'t be played' : 'Couldn\'t load the stream',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onRetry,
                style: FilledButton.styleFrom(backgroundColor: Ui.red),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
              if (hasAlt)
                OutlinedButton.icon(
                  onPressed: onAlt,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Other source'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Ui.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Ui.muted),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Ui.muted)),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : .4,
      child: Material(
        color: Ui.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Ui.line),
            ),
            child: Column(
              children: [
                Icon(icon, size: 22, color: Colors.white),
                const SizedBox(height: 6),
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
