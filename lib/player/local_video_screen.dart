import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../theme/app_theme.dart';
import 'audio_handler.dart';
import 'media_entry.dart';
import 'music_player.dart';
import 'watermark.dart';

/// Full-screen player for videos stored on the phone (mp4, mkv, webm, mov...).
/// Double-tap the left/right side to skip 10 seconds. Playback continues if
/// the app is minimised, and the position is remembered per file.
class LocalVideoScreen extends StatefulWidget {
  final List<MediaEntry> items;
  final int index;
  const LocalVideoScreen({super.key, required this.items, this.index = 0});

  @override
  State<LocalVideoScreen> createState() => _LocalVideoScreenState();
}

class _LocalVideoScreenState extends State<LocalVideoScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _c;
  late int _i;
  int _gen = 0;
  bool _loading = true;
  bool _error = false;
  bool _controls = true;
  bool _cover = false;
  bool _landscape = false;
  bool _handedOff = false;
  Future<void> _chain = Future.value();
  bool _ended = false;
  double _speed = 1;
  Timer? _hide;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  String? _skipHint;
  Timer? _hintTimer;
  Offset _tapAt = Offset.zero;

  MediaEntry get _item => widget.items[_i];

  @override
  void initState() {
    super.initState();
    _i = widget.index.clamp(0, widget.items.length - 1);
    MusicPlayer.instance.stop();
    WakelockPlus.enable();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  /// "Stop" tapped on the background-playback notification.
  void _onStopTapped() {
    _handedOff = false;
    if (mounted) Navigator.of(context).maybePop();
  }

  void _serial(Future<void> Function() f) {
    _chain = _chain.then((_) => f()).catchError((_) {});
  }

  /// When the app leaves the screen the video surface goes away. Hand the
  /// sound to the background audio service (media notification + lock-screen
  /// controls) and give it back when the app returns.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _serial(_handOff);
    } else if (state == AppLifecycleState.resumed) {
      _serial(_takeBack);
    }
  }

  Future<void> _handOff() async {
    final c = _c;
    if (_handedOff || c == null || !c.value.isInitialized || !c.value.isPlaying) {
      return;
    }
    final file = await _item.file();
    if (file == null) return;
    final pos = c.value.position;
    _savePosition();
    _handedOff = true;
    final ok =
        await AudioBridge.startVideoAudio(file.path, _item.title, pos, _onStopTapped);
    if (ok) {
      await c.pause();
    } else {
      _handedOff = false;
    }
  }

  Future<void> _takeBack() async {
    if (!_handedOff) return;
    _handedOff = false;
    final r = await AudioBridge.endVideoAudio();
    final c = _c;
    if (r == null || c == null || !mounted) return;
    await c.seekTo(r.position);
    if (r.playing) await c.play();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_handedOff) {
      _handedOff = false;
      AudioBridge.endVideoAudio();
    }
    _hide?.cancel();
    _hintTimer?.cancel();
    _gen++;
    _savePosition(force: true);
    _c?.removeListener(_tick);
    _c?.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ------------------------------------------------------------- loading

  Future<void> _open() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = false;
      _ended = false;
    });
    final old = _c;
    _c = null;
    old?.removeListener(_tick);
    await old?.dispose();

    final file = await _item.file();
    if (!mounted || gen != _gen) return;
    if (file == null) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }
    final c = VideoPlayerController.file(file);
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      if (mounted && gen == _gen) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
      return;
    }
    if (!mounted || gen != _gen) {
      await c.dispose();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('lv_pos_${_item.key}') ?? 0;
    if (saved > 3000 && saved < c.value.duration.inMilliseconds - 5000) {
      await c.seekTo(Duration(milliseconds: saved));
    }
    await c.setPlaybackSpeed(_speed);
    c.addListener(_tick);
    await c.play();
    if (!mounted || gen != _gen) return;
    setState(() {
      _c = c;
      _loading = false;
    });
    _scheduleHide();
  }

  void _tick() {
    final c = _c;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.hasError && !_error) {
      setState(() => _error = true);
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastSave).inSeconds >= 5) _savePosition();
    if (!_ended &&
        v.duration > Duration.zero &&
        v.position >= v.duration - const Duration(milliseconds: 300) &&
        !v.isPlaying) {
      _ended = true;
      _clearPosition();
      if (_i < widget.items.length - 1) {
        _go(_i + 1);
      } else {
        setState(() => _controls = true);
      }
    }
  }

  Future<void> _savePosition({bool force = false}) async {
    final c = _c;
    if (c == null || !c.value.isInitialized || _ended) return;
    _lastSave = DateTime.now();
    final p = await SharedPreferences.getInstance();
    await p.setInt('lv_pos_${_item.key}', c.value.position.inMilliseconds);
  }

  Future<void> _clearPosition() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('lv_pos_${_item.key}');
  }

  void _go(int i) {
    if (i < 0 || i >= widget.items.length) return;
    _savePosition();
    setState(() => _i = i);
    _open();
  }

  // ------------------------------------------------------------ controls

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      final c = _c;
      if (mounted && c != null && c.value.isPlaying) {
        setState(() => _controls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _playPause() {
    final c = _c;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      if (_ended) {
        _ended = false;
        c.seekTo(Duration.zero);
      }
      c.play();
    }
    _scheduleHide();
    setState(() {});
  }

  void _skip(int seconds) {
    final c = _c;
    if (c == null) return;
    final d = c.value.duration;
    var t = c.value.position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (t > d) t = d;
    c.seekTo(t);
    _hintTimer?.cancel();
    setState(() => _skipHint = seconds > 0 ? '+${seconds}s' : '${seconds}s');
    _hintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _skipHint = null);
    });
  }

  Future<void> _rotate() async {
    _landscape = !_landscape;
    await SystemChrome.setPreferredOrientations(_landscape
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(
        _landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    if (mounted) setState(() {});
  }

  void _pickSpeed() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Playback speed',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                    ChoiceChip(
                      label: Text(s == 1.0 ? 'Normal' : '${s}x'),
                      selected: _speed == s,
                      selectedColor: Ui.red.withValues(alpha: .25),
                      onSelected: (_) {
                        _speed = s;
                        _c?.setPlaybackSpeed(s);
                        Navigator.pop(ctx);
                        setState(() {});
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return PopScope(
      canPop: !_landscape,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _landscape) _rotate();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (c != null && c.value.isInitialized)
              ClipRect(
                child: FittedBox(
                  fit: _cover ? BoxFit.cover : BoxFit.contain,
                  child: SizedBox(
                    width: c.value.size.width,
                    height: c.value.size.height,
                    child: VideoPlayer(c),
                  ),
                ),
              ),
            // Tap / double-tap layer.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleControls,
                onDoubleTapDown: (d) => _tapAt = d.localPosition,
                onDoubleTap: () {
                  final w = MediaQuery.sizeOf(context).width;
                  if (_tapAt.dx < w / 2) {
                    _skip(-10);
                  } else {
                    _skip(10);
                  }
                },
              ),
            ),
            if (_loading)
              Center(child: CircularProgressIndicator(color: Ui.red)),
            if (_error) _errorView(),
            if (_skipHint != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(_skipHint!,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900)),
                ),
              ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 58,
              right: 14,
              child: const Watermark(),
            ),
            IgnorePointer(
              ignoring: !_controls,
              child: AnimatedOpacity(
                opacity: _controls ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: _overlay(c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 52, color: Ui.red),
              const SizedBox(height: 12),
              const Text("This file can't be played",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                'The phone does not support this video or audio format '
                '(some AVI / WMV / FLV files are not supported).',
                textAlign: TextAlign.center,
                style: TextStyle(color: Ui.muted),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _open,
                style: FilledButton.styleFrom(backgroundColor: Ui.red),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );

  Widget _overlay(VideoPlayerController? c) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: .75),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: .85),
          ],
          stops: const [0, .25, .65, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(
                      _item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton(
                    onPressed: _pickSpeed,
                    child: Text(_speed == 1 ? '1x' : '${_speed}x',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    tooltip: _cover ? 'Fit' : 'Fill',
                    icon: Icon(_cover
                        ? Icons.fit_screen_rounded
                        : Icons.aspect_ratio_rounded),
                    onPressed: () => setState(() => _cover = !_cover),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _round(Icons.skip_previous_rounded, 34,
                    _i > 0 ? () => _go(_i - 1) : null),
                const SizedBox(width: 14),
                _round(Icons.replay_10_rounded, 34, () => _skip(-10)),
                const SizedBox(width: 14),
                _playButton(c),
                const SizedBox(width: 14),
                _round(Icons.forward_10_rounded, 34, () => _skip(10)),
                const SizedBox(width: 14),
                _round(Icons.skip_next_rounded, 34,
                    _i < widget.items.length - 1 ? () => _go(_i + 1) : null),
              ],
            ),
            const Spacer(),
            _seekBar(c),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _round(IconData icon, double size, VoidCallback? onTap) => IconButton(
        iconSize: size,
        color: Colors.white,
        disabledColor: Colors.white24,
        icon: Icon(icon),
        onPressed: onTap,
      );

  Widget _playButton(VideoPlayerController? c) {
    if (c == null) return const SizedBox(width: 72, height: 72);
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (_, v, _) => GestureDetector(
        onTap: _playPause,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Ui.red,
            boxShadow: [
              BoxShadow(
                  color: Ui.red.withValues(alpha: .5),
                  blurRadius: 24,
                  spreadRadius: 1),
            ],
          ),
          child: Icon(
            v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 44,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _seekBar(VideoPlayerController? c) {
    if (c == null) return const SizedBox(height: 56);
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (_, v, _) {
        final total = v.duration.inMilliseconds.toDouble();
        final pos = v.position.inMilliseconds.toDouble().clamp(0, total <= 0 ? 1 : total);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Text(fmtDur(v.position),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    activeTrackColor: Ui.red,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: Ui.red.withValues(alpha: .2),
                  ),
                  child: Slider(
                    min: 0,
                    max: total <= 0 ? 1 : total,
                    value: pos.toDouble(),
                    onChangeStart: (_) => _hide?.cancel(),
                    onChanged: (x) =>
                        c.seekTo(Duration(milliseconds: x.round())),
                    onChangeEnd: (_) => _scheduleHide(),
                  ),
                ),
              ),
              Text(fmtDur(v.duration),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              IconButton(
                icon: Icon(_landscape
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded),
                onPressed: _rotate,
              ),
            ],
          ),
        );
      },
    );
  }
}
