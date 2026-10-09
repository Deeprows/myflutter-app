import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import '../theme/app_theme.dart';
import 'support_browser_screen.dart' show SupportResult;

/// The ad page that opens on the first tap (replaces the hidden "We Need Your
/// Support" overlay).
///
///  1. [AppConfig.supportUrl] loads full screen under a slim bar that says
///     [AppConfig.supportWaitText]. Nothing can close it while it is loading:
///     no close button, and Back is ignored, so the page is never cut off
///     halfway.
///  2. Once the page has FULLY loaded (including redirects) the bar turns into
///     "Ad loaded" with a Resume button and a short countdown
///     ([AppConfig.supportAfterLoadSeconds]). The page can be used meanwhile.
///  3. When the countdown ends, or Resume is tapped, the page closes and the
///     person is back exactly where they were.
///
/// If the person taps something in the page that opens another page, the wait
/// message comes back and that page is allowed to finish loading too.
///
/// Pops [SupportResult.completed] when it was shown, or
/// [SupportResult.failed] when it could not load at all (offline / dead link),
/// so nobody is ever locked out.
class AdSupportScreen extends StatefulWidget {
  final String url;
  const AdSupportScreen({super.key, required this.url});

  @override
  State<AdSupportScreen> createState() => _AdSupportScreenState();
}

enum _Phase { loading, ready, error }

class _AdSupportScreenState extends State<AdSupportScreen> {
  late final WebViewController _wc;

  _Phase _phase = _Phase.loading;
  final ValueNotifier<int> _progress = ValueNotifier<int>(0);
  final ValueNotifier<double> _left = ValueNotifier<double>(0);

  Timer? _settle; // waits a moment to be sure no redirect follows
  Timer? _maxLoad; // safety: a page that never says "finished"
  Timer? _tick;
  DateTime? _end;

  bool _started = false; // the page has begun to load
  bool _everLoaded = false; // some page has finished loading at least once
  bool _forced = false; // max load time reached: stop going back to "loading"
  bool _done = false;

  static const _settleDelay = Duration(milliseconds: 1400);

  @override
  void initState() {
    super.initState();
    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Ui.bg)
      ..setUserAgent(AppConfig.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) => _route(r.url),
        onPageStarted: (_) {
          _started = true;
          _makeClickable();
          _backToLoading();
        },
        onProgress: (p) {
          _progress.value = p;
          if (p >= 100) _scheduleSettle();
        },
        onPageFinished: (_) {
          _started = true;
          _makeClickable();
          _scheduleSettle();
        },
        onWebResourceError: (e) {
          // Only a failure of the page itself with nothing shown yet counts.
          if (e.isForMainFrame == true && !_everLoaded && mounted) {
            _fail();
          }
        },
      ));

    final p = _wc.platform;
    if (p is AndroidWebViewController) {
      final cookies = WebViewCookieManager().platform;
      if (cookies is AndroidWebViewCookieManager) {
        cookies.setAcceptThirdPartyCookies(p, true);
      }
    }
    _wc.loadRequest(Uri.parse(widget.url));

    _armMaxLoad();
  }

  /// Safety net: a page that is still loading after
  /// [AppConfig.supportMaxLoadSeconds] is treated as loaded (if it showed
  /// anything) so it can never hold the person for ever.
  void _armMaxLoad() {
    _maxLoad?.cancel();
    _maxLoad = Timer(Duration(seconds: AppConfig.supportMaxLoadSeconds), () {
      if (_done || !mounted || _phase == _Phase.error) return;
      _forced = true;
      if (_phase == _Phase.loading) {
        if (_started) {
          _markLoaded();
        } else {
          _fail();
        }
      }
    });
  }

  // ------------------------------------------------------------ loading

  void _backToLoading() {
    _settle?.cancel();
    if (_forced || _done || !mounted) return;
    if (_phase == _Phase.ready) {
      // The person opened another page from the ad: let it load fully too.
      _stopCountdown();
      _progress.value = 0;
      _armMaxLoad();
      setState(() => _phase = _Phase.loading);
    }
  }

  void _scheduleSettle() {
    if (_done || !mounted || _phase == _Phase.error) return;
    _settle?.cancel();
    _settle = Timer(_settleDelay, _markLoaded);
  }

  void _markLoaded() {
    if (_done || !mounted || _phase == _Phase.error) return;
    _everLoaded = true;
    _maxLoad?.cancel();
    if (_phase == _Phase.ready && _tick != null) return;
    setState(() => _phase = _Phase.ready);
    _startCountdown();
  }

  void _startCountdown() {
    _stopCountdown();
    final secs = AppConfig.supportAfterLoadSeconds;
    _end = DateTime.now().add(Duration(seconds: secs));
    _left.value = secs.toDouble();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (t) {
      final ms = _end!.difference(DateTime.now()).inMilliseconds;
      if (ms <= 0) {
        t.cancel();
        _finish();
      } else {
        _left.value = ms / 1000;
      }
    });
  }

  void _stopCountdown() {
    _tick?.cancel();
    _tick = null;
    _end = null;
  }

  void _fail() {
    if (_done || !mounted) return;
    _stopCountdown();
    _settle?.cancel();
    setState(() => _phase = _Phase.error);
  }

  // ------------------------------------------------------------- closing

  /// Resume tapped, or the countdown ended: back to what the person was doing.
  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(SupportResult.completed);
  }

  /// The page could not load at all: let the person through.
  void _continueAnyway() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(SupportResult.failed);
  }

  void _retry() {
    _started = false;
    _everLoaded = false;
    _forced = false;
    _progress.value = 0;
    setState(() => _phase = _Phase.loading);
    _armMaxLoad();
    _wc.loadRequest(Uri.parse(widget.url));
  }

  @override
  void dispose() {
    _settle?.cancel();
    _maxLoad?.cancel();
    _tick?.cancel();
    _progress.dispose();
    _left.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------- web page

  /// Links that ask for a new tab / window would otherwise do nothing inside
  /// the app, so open them in this same page.
  static const _clickFix = '''
(function(){
  if (window.__spFix) return; window.__spFix = true;
  window.open = function(u){ if (u) { location.href = u; } return window; };
  document.addEventListener('click', function(e){
    var a = e.target && e.target.closest ? e.target.closest('a[target]') : null;
    if (a && a.target !== '_self') { a.target = '_self'; }
  }, true);
})();
''';

  void _makeClickable() {
    try {
      _wc.runJavaScript(_clickFix);
    } catch (_) {}
  }

  /// Web links go through. App links (intent://, market://) are turned into
  /// their web page so tapping them still goes somewhere; the rest is ignored.
  NavigationDecision _route(String url) {
    final uri = Uri.tryParse(url);
    final scheme = uri?.scheme.toLowerCase() ?? '';
    if (scheme == 'http' ||
        scheme == 'https' ||
        scheme == 'about' ||
        scheme == 'data' ||
        scheme == 'blob') {
      return NavigationDecision.navigate;
    }
    String? web;
    if (scheme == 'intent') {
      final fb = RegExp(r'S\.browser_fallback_url=([^;]+)').firstMatch(url);
      if (fb != null) {
        web = Uri.decodeComponent(fb.group(1)!);
      } else {
        final sch = RegExp(r'scheme=(https?);').firstMatch(url)?.group(1);
        final body = url.substring('intent://'.length).split('#Intent').first;
        if (sch != null && body.isNotEmpty) web = '$sch://$body';
      }
    } else if (scheme == 'market') {
      final id = uri?.queryParameters['id'];
      if (id != null && id.isNotEmpty) {
        web = 'https://play.google.com/store/apps/details?id=$id';
      }
    }
    final target = web == null ? null : Uri.tryParse(web);
    if (target != null && (target.scheme == 'http' || target.scheme == 'https')) {
      _wc.loadRequest(target);
    }
    return NavigationDecision.prevent;
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back is ignored while the page is loading, so it is never cut off.
      // Once loaded, Back = Resume. If it could not load, Back lets you in.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_phase == _Phase.ready) _finish();
        if (_phase == _Phase.error) _continueAnyway();
      },
      child: Scaffold(
        backgroundColor: Ui.bg,
        body: SafeArea(
          child: Column(
            children: [
              _bar(),
              Expanded(
                child: _phase == _Phase.error
                    ? _ErrorView(onRetry: _retry, onContinue: _continueAnyway)
                    : WebViewWidget(controller: _wc),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar() {
    final loading = _phase != _Phase.ready;
    return Container(
      color: Ui.panel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
            child: Row(
              children: [
                if (loading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Ui.red),
                  )
                else
                  Icon(Icons.check_circle_rounded, size: 18, color: Ui.red),
                const SizedBox(width: 10),
                Expanded(
                  child: loading
                      ? Text(
                          AppConfig.supportWaitText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w800),
                        )
                      : ValueListenableBuilder<double>(
                          valueListenable: _left,
                          builder: (_, v, _) => Text(
                            'Ad loaded · back in ${v.ceil()}s',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                ),
                if (!loading)
                  FilledButton(
                    onPressed: _finish,
                    style: FilledButton.styleFrom(
                      backgroundColor: Ui.red,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('Resume',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: _progress,
            builder: (_, p, _) => LinearProgressIndicator(
              minHeight: 3,
              value: loading ? (p <= 0 ? null : p / 100) : 1,
              backgroundColor: Ui.line,
              valueColor: AlwaysStoppedAnimation(Ui.red),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onContinue;
  const _ErrorView({required this.onRetry, required this.onContinue});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 44, color: Ui.dim),
              const SizedBox(height: 12),
              const Text('The ad page could not load',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Check your internet connection, or continue without it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Ui.muted, fontSize: 13)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                children: [
                  FilledButton(onPressed: onRetry, child: const Text('Retry')),
                  OutlinedButton(
                      onPressed: onContinue, child: const Text('Continue')),
                ],
              ),
            ],
          ),
        ),
      );
}
