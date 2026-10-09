import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config.dart';
import '../services/background_playback.dart';
import '../services/stream_resolver.dart';
import '../theme/app_theme.dart';
import 'player_screen.dart';

/// One playable stream with the headers its host may require.
class NativeStream {
  final String url;
  final String? referer;
  final String? userAgent;
  const NativeStream(this.url, {this.referer, this.userAgent});
}

/// Request headers for a stream: its own User-Agent (or the app default) and
/// the Referer when it has one.
Map<String, String> nativeHeaders(String? referer, String? userAgent) {
  final ua = (userAgent ?? '').trim();
  final ref = (referer ?? '').trim();
  return {
    'User-Agent': ua.isEmpty ? AppConfig.userAgent : ua,
    if (ref.isNotEmpty) 'Referer': ref,
  };
}

/// True when the native player can handle this link (m3u8 / mpd / video file).
bool nativePlayable(String url) => StreamResolver.resolve(url).usesHtmlPlayer;

VideoFormat _formatOf(StreamKind k) {
  switch (k) {
    case StreamKind.hls:
      return VideoFormat.hls;
    case StreamKind.dash:
      return VideoFormat.dash;
    default:
      return VideoFormat.other;
  }
}

/// Live TV player built on ExoPlayer. If a stream fails it moves on to the
/// backup stream by itself; when every stream has failed it offers Retry and
/// the web player.
class NativePlayerScreen extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<NativeStream> streams;

  const NativePlayerScreen({
    super.key,
    required this.title,
    required this.streams,
    this.subtitle,
  });

  @override
  State<NativePlayerScreen> createState() => _NativePlayerScreenState();
}

class _NativePlayerScreenState extends State<NativePlayerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _c;
  int _idx = 0;
  int _gen = 0; // bumps on every start, so stale async work can bail out
  final Set<int> _tried = {};

  bool _loading = true;
  bool _error = false;
  bool _buffering = false;
  bool _controls = true;
  bool _muted = false;
  bool _landscape = false;
  bool _failing = false;
  Timer? _hide;

  static const _initTimeout = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    WidgetsBinding.instance.addObserver(this);
    BackgroundPlayback.start(
      widget.title,
      _onStopTapped,
      onPlay: _bgPlay,
      onPause: _bgPause,
      onSeekBy: _bgSeek,
    );
    _start(0);
  }

  /// "Stop" on the background-playback notification: close the player.
  void _onStopTapped() {
    if (mounted) Navigator.of(context).maybePop();
  }

  bool _wasPlaying = false;
  bool _lastPlaying = true;

  // Notification / lock-screen buttons.
  void _bgPlay() {
    _c?.play();
  }

  void _bgPause() {
    _wasPlaying = false; // don't let the minimise-resume logic restart it
    _c?.pause();
  }

  void _bgSeek(int seconds) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    var t = c.value.position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    final end = c.value.duration;
    if (end > Duration.zero && t > end) t = end;
    c.seekTo(t);
  }

  /// Keeps the stream going when the app is minimised; if the player paused
  /// itself because the video surface went away, start it again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _wasPlaying = _wasPlaying || c.value.isPlaying;
      for (final ms in const [300, 1200]) {
        Future.delayed(Duration(milliseconds: ms), () {
          final cur = _c;
          if (mounted && cur != null && _wasPlaying && !cur.value.isPlaying) {
            cur.play();
          }
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_wasPlaying && !c.value.isPlaying) c.play();
      _wasPlaying = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BackgroundPlayback.stop(_onStopTapped);
    _hide?.cancel();
    _gen++;
    final c = _c;
    c?.removeListener(_onTick);
    c?.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------------------------------------------------------- loading

  Future<void> _start(int idx) async {
    final gen = ++_gen;

    final old = _c;
    _c = null;
    old?.removeListener(_onTick);
    await old?.dispose();
    if (!mounted || gen != _gen) return;

    setState(() {
      _idx = idx;
      _loading = true;
      _error = false;
      _buffering = false;
      _failing = false;
    });

    final s = widget.streams[idx];
    final r = StreamResolver.resolve(s.url);
    final uri = Uri.tryParse(r.url);
    if (uri == null || r.kind == StreamKind.invalid) {
      _failed(idx);
      return;
    }

    final c = VideoPlayerController.networkUrl(
      uri,
      formatHint: _formatOf(r.kind),
      httpHeaders: nativeHeaders(s.referer, s.userAgent),
    );

    try {
      await c.initialize().timeout(_initTimeout);
      if (!mounted || gen != _gen) {
        await c.dispose();
        return;
      }
      await c.setVolume(_muted ? 0 : 1);
      c.addListener(_onTick);
      _c = c;
      await c.play();
      if (!mounted || gen != _gen) return;
      setState(() => _loading = false);
      _scheduleHide();
    } catch (_) {
      await c.dispose();
      if (!mounted || gen != _gen) return;
      _failed(idx);
    }
  }

  void _failed(int idx) {
    _tried.add(idx);
    for (var i = 0; i < widget.streams.length; i++) {
      if (!_tried.contains(i)) {
        _start(i);
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = true;
      _controls = true;
    });
  }

  void _onTick() {
    final c = _c;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.hasError) {
      if (_failing) return;
      _failing = true;
      _failed(_idx);
      return;
    }
    if (v.isBuffering != _buffering) {
      setState(() => _buffering = v.isBuffering);
    }
    if (v.isInitialized && v.isPlaying != _lastPlaying) {
      _lastPlaying = v.isPlaying;
      BackgroundPlayback.setPlaying(v.isPlaying);
    }
  }

  void _retry() {
    _tried.clear();
    _start(0);
  }

  void _next() {
    if (widget.streams.length < 2) return;
    _start((_idx + 1) % widget.streams.length);
  }

  void _openWeb() {
    final s = widget.streams;
    final alt = s.length > 1 ? s[1] : null;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        title: widget.title,
        subtitle: widget.subtitle,
        url: s.first.url,
        referer: s.first.referer,
        userAgent: s.first.userAgent,
        altUrl: alt?.url,
        altReferer: alt?.referer,
        altUserAgent: alt?.userAgent,
        isLive: true,
      ),
    ));
  }

  // --------------------------------------------------------------- controls

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && !_error && !_loading) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _togglePlay() {
    final c = _c;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
    setState(() {});
    _scheduleHide();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _c?.setVolume(_muted ? 0 : 1);
    _scheduleHide();
  }

  Future<void> _toggleLandscape() async {
    _landscape = !_landscape;
    if (_landscape) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (mounted) setState(() {});
    _scheduleHide();
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ready = c != null && c.value.isInitialized && !_error;
    final showUi = _controls || _error;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (c != null && ready)
              Center(
                child: AspectRatio(
                  aspectRatio:
                      c.value.aspectRatio <= 0 ? 16 / 9 : c.value.aspectRatio,
                  child: VideoPlayer(c),
                ),
              ),
            if ((_loading || _buffering) && !_error)
              Center(child: CircularProgressIndicator(color: Ui.red)),
            if (_error) _errorView(),
            AnimatedOpacity(
              opacity: showUi ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !showUi,
                child: _overlay(c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overlay(VideoPlayerController? c) {
    final playing = c?.value.isPlaying ?? false;
    final multi = widget.streams.length > 1;
    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC000000), Color(0x00000000)],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                      if ((widget.subtitle ?? '').isNotEmpty)
                        Text(widget.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (multi)
                  TextButton.icon(
                    onPressed: _next,
                    icon: const Icon(Icons.swap_horiz_rounded,
                        size: 18, color: Colors.white),
                    label: Text('${_idx + 1}/${widget.streams.length}',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: (_error || _loading)
                  ? const SizedBox.shrink()
                  : IconButton(
                      iconSize: 56,
                      onPressed: _togglePlay,
                      icon: Icon(
                          playing
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_filled_rounded,
                          color: Colors.white.withValues(alpha: .92)),
                    ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 6),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xCC000000)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Ui.red,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text('LIVE',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1)),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _toggleMute,
                  icon: Icon(
                      _muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: Colors.white),
                ),
                IconButton(
                  onPressed: _toggleLandscape,
                  icon: Icon(
                      _landscape
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.signal_wifi_connected_no_internet_4_rounded,
                color: Colors.white54, size: 44),
            const SizedBox(height: 12),
            const Text("Couldn't play this channel",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
                'The stream may be offline, geo-blocked or protected.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 12.5)),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Ui.red),
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                ),
                OutlinedButton.icon(
                  onPressed: _openWeb,
                  icon: const Icon(Icons.language_rounded, size: 18),
                  label: const Text('Web player'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
