import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/fan_post_link.dart';
import '../screens/player_screen.dart';
import '../services/player_html.dart';
import '../services/stream_resolver.dart';
import '../theme/app_theme.dart';

/// A lightweight play card until tapped. Full playback uses the existing player.
class FanPostVideo extends StatefulWidget {
  final String url;
  final bool inline;
  const FanPostVideo({super.key, required this.url, required this.inline});
  @override
  State<FanPostVideo> createState() => _FanPostVideoState();
}

class _FanPostVideoState extends State<FanPostVideo>
    with WidgetsBindingObserver {
  WebViewController? _controller;
  bool _loading = false, _failed = false;
  String get _url => fanVideoUrl(widget.url);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  void _stop() {
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
    final c = _controller;
    if (c != null)
      unawaited(c.loadHtmlString('<html></html>').catchError((Object _) {}));
    super.dispose();
  }

  Future<void> _full() async {
    _stop();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(title: 'Community video', url: _url),
      ),
    );
  }

  Future<void> _play() async {
    if (!widget.inline) {
      await _full();
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    final stream = StreamResolver.resolve(_url);
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted)
              setState(() {
                _failed = true;
                _loading = false;
              });
          },
          onNavigationRequest: (n) {
            final u = Uri.tryParse(n.url);
            return u != null && ['http', 'https', 'about'].contains(u.scheme)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
    if (!mounted) return;
    setState(() => _controller = c);
    try {
      if (stream.usesHtmlPlayer) {
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

  @override
  Widget build(BuildContext context) => Container(
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
                  ],
                )
              : InkWell(
                  onTap: _play,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_circle_fill_rounded,
                          size: 56,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _failed
                              ? 'Retry video'
                              : widget.inline
                              ? 'Play video'
                              : 'Open video',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          Uri.parse(widget.url).host,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        if (widget.inline)
          Row(
            children: [
              if (_controller != null)
                IconButton(
                  onPressed: _stop,
                  tooltip: 'Stop video',
                  icon: const Icon(Icons.close),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: _full,
                icon: const Icon(Icons.fullscreen),
                label: const Text('Open full player'),
              ),
            ],
          ),
      ],
    ),
  );
}
