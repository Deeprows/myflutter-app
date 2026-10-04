import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import '../services/download_manager.dart';
import '../theme/app_theme.dart';
import 'downloads_screen.dart';

/// File links (apk, zip, mkv…) can't be saved by a WebView, so when a page
/// redirects to one it is downloaded by the in-app download manager.
final _fileLink = RegExp(
  r'\.(apk|zip|rar|7z|tar|gz|iso|exe|msi|dmg|torrent|mkv|mp4|avi|mov|m4v|webm|mp3|pdf)$',
  caseSensitive: false,
);

bool isDirectFileLink(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && _fileLink.hasMatch(uri.path);
}

Future<bool> openExternally(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Opens [url] in the in-app browser window. Many file hosts serve a landing
/// page even when the address ends in .mkv, so the first load always happens
/// in-app; file redirects that happen afterwards are downloaded in-app.
Future<void> openInApp(BuildContext context, String url, {String? title}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => BrowserScreen(url: url, title: title),
  ));
}

/// Clean in-app browser window: slim top bar with page title and host,
/// progress line, back/reload/menu. Pop-up windows and app-scheme redirects
/// (intent://, market://…) are blocked.
class BrowserScreen extends StatefulWidget {
  final String url;
  final String? title;
  const BrowserScreen({super.key, required this.url, this.title});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController _wc;
  int _progress = 0;
  bool _canGoBack = false;
  bool _error = false;
  String _url = '';
  String _pageTitle = '';

  @override
  void initState() {
    super.initState();
    _url = widget.url;

    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Ui.bg)
      ..setUserAgent(AppConfig.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _onNavigation,
        onPageStarted: (u) {
          if (!mounted) return;
          setState(() {
            _url = u;
            _error = false;
          });
        },
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageFinished: (u) async {
          final title = await _wc.getTitle();
          final back = await _wc.canGoBack();
          if (!mounted) return;
          setState(() {
            _url = u;
            _pageTitle = title ?? '';
            _canGoBack = back;
            _progress = 100;
          });
        },
        onUrlChange: (c) async {
          final back = await _wc.canGoBack();
          if (!mounted) return;
          setState(() {
            if (c.url != null) _url = c.url!;
            _canGoBack = back;
          });
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) {
            setState(() => _error = true);
          }
        },
      ));

    final p = _wc.platform;
    if (p is AndroidWebViewController) {
      p.setMediaPlaybackRequiresUserGesture(false);
      final cookies = WebViewCookieManager().platform;
      if (cookies is AndroidWebViewCookieManager) {
        cookies.setAcceptThirdPartyCookies(p, true);
      }
    }

    _wc.loadRequest(Uri.parse(widget.url));
  }

  NavigationDecision _onNavigation(NavigationRequest r) {
    final uri = Uri.tryParse(r.url);
    if (uri == null) return NavigationDecision.prevent;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'about' || scheme == 'data' || scheme == 'blob') {
      return NavigationDecision.navigate;
    }
    // intent://, market://, custom app schemes: never leave the app.
    if (scheme != 'http' && scheme != 'https') {
      return NavigationDecision.prevent;
    }
    if (r.isMainFrame && r.url != widget.url && isDirectFileLink(r.url)) {
      _startDownload(r.url);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  String get _host => Uri.tryParse(_url)?.host ?? '';
  bool get _secure => _url.startsWith('https://');

  /// Best effort: cookies the page can see (HttpOnly cookies are not
  /// readable), so hosts that check a session still accept the request.
  Future<String> _pageCookies() async {
    try {
      final r = await _wc.runJavaScriptReturningResult('document.cookie');
      return r.toString().replaceAll(RegExp(r'^"|"$'), '');
    } catch (_) {
      return '';
    }
  }

  Future<void> _startDownload(String url) async {
    final cookie = await _pageCookies();
    DownloadManager.instance.enqueue(
      url,
      referer: _url,
      cookie: cookie,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Download started'),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Ui.redSoft,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const DownloadsScreen(),
          )),
        ),
      ));
  }

  Future<void> _share() async {
    final t = widget.title;
    try {
      await Share.share(t == null || t.isEmpty ? _url : '$t\n$_url',
          subject: t);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Couldn\'t open share')));
    }
  }

  Future<void> _external() async {
    final ok = await openExternally(_url);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Couldn\'t open the link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final heading = widget.title ??
        (_pageTitle.isNotEmpty ? _pageTitle : (_host.isEmpty ? 'Loading…' : _host));

    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _wc.goBack();
      },
      child: Scaffold(
        backgroundColor: Ui.bg,
        body: SafeArea(
          child: Column(
            children: [
              Container(
                height: 56,
                padding: const EdgeInsets.only(left: 4, right: 4),
                decoration: const BoxDecoration(
                  color: Ui.panel,
                  border: Border(bottom: BorderSide(color: Ui.line)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            heading,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                          if (_host.isNotEmpty)
                            Row(
                              children: [
                                Icon(
                                  _secure
                                      ? Icons.lock_rounded
                                      : Icons.lock_open_rounded,
                                  size: 11,
                                  color: _secure ? Ui.green : Ui.dim,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    _host,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Ui.muted,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Reload',
                      onPressed: () {
                        setState(() => _error = false);
                        _wc.reload();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    PopupMenuButton<String>(
                      color: Ui.panel,
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (v) {
                        if (v == 'share') _share();
                        if (v == 'external') _external();
                        if (v == 'download') _startDownload(_url);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'download',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.download_rounded),
                            title: Text('Download this link'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'share',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.share_rounded),
                            title: Text('Share'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'external',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.open_in_browser_rounded),
                            title: Text('Open in browser'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 2.5,
                child: _progress < 100 && !_error
                    ? LinearProgressIndicator(
                        value: _progress == 0 ? null : _progress / 100,
                        color: Ui.red,
                        backgroundColor: Colors.transparent,
                      )
                    : null,
              ),
              Expanded(
                child: Stack(
                  children: [
                    WebViewWidget(controller: _wc),
                    if (_error)
                      Container(
                        color: Ui.bg,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wifi_off_rounded,
                                size: 40, color: Ui.redSoft),
                            const SizedBox(height: 10),
                            const Text('Couldn\'t load this page',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: () {
                                    setState(() => _error = false);
                                    _wc.reload();
                                  },
                                  style: FilledButton.styleFrom(
                                      backgroundColor: Ui.red),
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 18),
                                  label: const Text('Retry'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _external,
                                  icon: const Icon(
                                      Icons.open_in_browser_rounded,
                                      size: 18),
                                  label: const Text('Open in browser'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
