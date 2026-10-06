import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import '../theme/app_theme.dart';

/// How the support page ended.
enum SupportResult {
  /// Stayed for the full time; it closed by itself.
  completed,

  /// Closed by the person before the time was up.
  closed,

  /// The page could not be loaded (offline, dead link).
  failed,
}

/// In-app browser for the support page. It closes by itself after
/// [seconds] and pops [SupportResult.completed].
///
/// The countdown starts when the page has loaded (or after a short fallback
/// if the page never reports "loaded"), so a slow page doesn't eat the time.
class SupportBrowserScreen extends StatefulWidget {
  final String url;
  final int seconds;
  const SupportBrowserScreen({
    super.key,
    required this.url,
    required this.seconds,
  });

  @override
  State<SupportBrowserScreen> createState() => _SupportBrowserScreenState();
}

class _SupportBrowserScreenState extends State<SupportBrowserScreen> {
  late final WebViewController _wc;
  final ValueNotifier<double> _left = ValueNotifier<double>(-1); // secs; -1 = loading
  Timer? _tick;
  Timer? _fallback;
  bool _error = false;
  bool _done = false;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Ui.bg)
      ..setUserAgent(AppConfig.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          final scheme = Uri.tryParse(r.url)?.scheme.toLowerCase() ?? '';
          // Stay inside the app: no intent://, market://, tel: ...
          if (scheme == 'http' ||
              scheme == 'https' ||
              scheme == 'about' ||
              scheme == 'data' ||
              scheme == 'blob') {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
        onPageStarted: (_) {
          if (mounted && _error) setState(() => _error = false);
        },
        onPageFinished: (_) => _startCountdown(),
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted && _end == null) {
            setState(() => _error = true);
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

    // Some pages never fire "finished" (endless trackers): start anyway.
    _fallback = Timer(const Duration(seconds: 8), () {
      if (!_error) _startCountdown();
    });
  }

  void _startCountdown() {
    if (_end != null || _done || !mounted || _error) return;
    _fallback?.cancel();
    _end = DateTime.now().add(Duration(seconds: widget.seconds));
    _left.value = widget.seconds.toDouble();
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

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(SupportResult.completed);
  }

  void _closeEarly() {
    if (_done) return;
    _done = true;
    Navigator.of(context)
        .pop(_error ? SupportResult.failed : SupportResult.closed);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _fallback?.cancel();
    _left.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.seconds.toDouble();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeEarly();
      },
      child: Scaffold(
        backgroundColor: Ui.bg,
        body: SafeArea(
          child: Column(
            children: [
              // ---- slim top bar with the countdown --------------------------
              Container(
                color: Ui.panel,
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Close',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close_rounded, color: Ui.muted),
                          onPressed: _closeEarly,
                        ),
                        Icon(Icons.favorite_rounded, size: 16, color: Ui.red),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Thank you for supporting Deeprowss',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                        ValueListenableBuilder<double>(
                          valueListenable: _left,
                          builder: (_, v, _) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Ui.red.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Ui.red.withValues(alpha: .45)),
                            ),
                            child: Text(
                              v < 0 ? 'Loading…' : 'Closing in ${v.ceil()}s',
                              style: TextStyle(
                                  color: Ui.redSoft,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: _left,
                      builder: (_, v, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          value: v < 0 ? null : 1 - (v / total).clamp(0.0, 1.0),
                          backgroundColor: Ui.line,
                          valueColor: AlwaysStoppedAnimation(Ui.red),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ---- the page --------------------------------------------------
              Expanded(
                child: _error
                    ? _ErrorView(
                        onRetry: () {
                          setState(() => _error = false);
                          _wc.loadRequest(Uri.parse(widget.url));
                        },
                        onClose: _closeEarly,
                      )
                    : WebViewWidget(controller: _wc),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onClose;
  const _ErrorView({required this.onRetry, required this.onClose});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 44, color: Ui.dim),
              const SizedBox(height: 12),
              const Text('The page could not load',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Check your internet connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Ui.muted, fontSize: 13)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                children: [
                  FilledButton(onPressed: onRetry, child: const Text('Retry')),
                  OutlinedButton(onPressed: onClose, child: const Text('Close')),
                ],
              ),
            ],
          ),
        ),
      );
}
