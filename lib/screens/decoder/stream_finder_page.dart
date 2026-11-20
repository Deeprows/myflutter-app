import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../services/stream_resolver.dart' show StreamKind;
import '../../theme/app_theme.dart';

/// A video address captured from a web page.
class FoundStream {
  final String url;
  final StreamKind kind;
  final String? referer;
  final String? userAgent;
  const FoundStream({required this.url, required this.kind, this.referer, this.userAgent});
}

/// Opens a web page (an embed player, movie page or channel page) and watches
/// the network traffic of the page and of every frame inside it. The first
/// .m3u8 / .mpd stream the player asks for is the real video address, which
/// can then be sent to Kodi, a TV or the receiver page.
class StreamFinderPage extends StatefulWidget {
  final String url;
  final String title;
  final String? referer;
  const StreamFinderPage({super.key, required this.url, required this.title, this.referer});

  /// Streams found earlier in this session, by page address.
  static final Map<String, FoundStream> cache = {};

  @override
  State<StreamFinderPage> createState() => _StreamFinderPageState();
}

class _StreamFinderPageState extends State<StreamFinderPage> {
  InAppWebViewController? _web;
  Timer? _tick;
  bool _done = false;
  bool _loadedOnce = false;
  int _seconds = 0;
  String _initialHost = '';
  String? _ua;
  ({String url, Map<String, String>? headers})? _video; // direct video file, used as last resort
  String _status = 'Looking for the video…';

  static final RegExp _ad = RegExp(r'doubleclick|googlesyndication|adservice|/ads?/|adserver|analytics|pixel|vast', caseSensitive: false);
  static const String _autoPlay = r'''
(function(){try{
  document.querySelectorAll('video').forEach(function(v){v.muted=true;try{v.play();}catch(e){}});
  ['.jw-icon-display','.vjs-big-play-button','.plyr__control--overlaid','.fp-play','#play','.play-button','.btn-play','[aria-label="Play"]','[class*="play-btn"]','[class*="PlayButton"]'].forEach(function(s){
    try{var e=document.querySelector(s); if(e) e.click();}catch(x){}
  });
}catch(e){}})();
''';

  @override
  void initState() {
    super.initState();
    _initialHost = Uri.tryParse(widget.url)?.host ?? '';
    _tick = Timer.periodic(const Duration(seconds: 2), (_) => _onTick());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _onTick() async {
    if (_done || !mounted) return;
    _seconds += 2;
    try {
      await _web?.evaluateJavascript(source: _autoPlay);
    } catch (_) {}
    if (_seconds == 20 && _video != null) {
      _finish(_video!.url, StreamKind.video, _video!.headers);
      return;
    }
    if (_seconds == 40 && !_done && mounted) {
      setState(() => _status = 'Still looking… tap the play button on the page if you see one.');
    }
    if (_seconds >= 90 && !_done && mounted) {
      setState(() => _status = 'No video found on this page. Go back and try another one.');
    }
  }

  void _consider(String? raw, Map<String, String>? headers) {
    if (_done || raw == null) return;
    final lower = raw.toLowerCase();
    if (!lower.startsWith('http')) return;
    final path = (Uri.tryParse(raw)?.path ?? '').toLowerCase();
    StreamKind? kind;
    if (path.contains('.m3u8')) {
      kind = StreamKind.hls;
    } else if (path.endsWith('.mpd')) {
      kind = StreamKind.dash;
    } else if (RegExp(r'\.(mp4|webm|mkv|m4v)$').hasMatch(path)) {
      kind = StreamKind.video;
    }
    if (kind == null || _ad.hasMatch(lower)) return;
    if (kind == StreamKind.video) {
      _video ??= (url: raw, headers: headers);
      return;
    }
    _finish(raw, kind, headers);
  }

  String? _header(Map<String, String>? h, String name) {
    if (h == null) return null;
    for (final e in h.entries) {
      if (e.key.toLowerCase() == name.toLowerCase() && e.value.trim().isNotEmpty) return e.value;
    }
    return null;
  }

  void _finish(String url, StreamKind kind, Map<String, String>? headers) {
    if (_done) return;
    _done = true;
    final found = FoundStream(
      url: url,
      kind: kind,
      referer: _header(headers, 'referer') ?? widget.url,
      userAgent: _header(headers, 'user-agent') ?? _ua,
    );
    StreamFinderPage.cache[widget.url] = found;
    if (mounted) Navigator.of(context).pop(found);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.panel,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: Ui.card,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_status, style: TextStyle(color: Ui.text, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Getting the video address so it can play on your TV. This closes by itself.',
                style: TextStyle(color: Ui.muted, fontSize: 11)),
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ]),
        ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(widget.url),
              headers: (widget.referer ?? '').trim().isEmpty ? null : {'Referer': widget.referer!.trim()},
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              useOnLoadResource: true,
              useShouldInterceptRequest: true,
              useShouldOverrideUrlLoading: true,
              mediaPlaybackRequiresUserGesture: false,
              supportMultipleWindows: false,
              javaScriptCanOpenWindowsAutomatically: false,
              domStorageEnabled: true,
              allowsInlineMediaPlayback: true,
            ),
            onWebViewCreated: (c) => _web = c,
            shouldOverrideUrlLoading: (c, action) async {
              final host = action.request.url?.host ?? '';
              if (_loadedOnce && action.isForMainFrame && _initialHost.isNotEmpty && host != _initialHost) {
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
            shouldInterceptRequest: (c, request) async {
              _consider(request.url.toString(), request.headers);
              return null;
            },
            onLoadResource: (c, resource) {
              _consider(resource.url?.toString(), null);
            },
            onLoadStop: (c, url) async {
              _loadedOnce = true;
              try {
                final ua = await c.evaluateJavascript(source: 'navigator.userAgent');
                if (ua is String && ua.isNotEmpty) _ua = ua;
              } catch (_) {}
            },
          ),
        ),
      ]),
    );
  }
}
