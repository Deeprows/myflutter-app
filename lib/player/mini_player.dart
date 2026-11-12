import 'package:flutter/material.dart' hide Text;

import '../services/app_nav.dart';
import '../theme/app_theme.dart';
import 'lyrics_view.dart';
import 'media_entry.dart';
import 'playlist_screens.dart';
import 'watermark.dart';
import 'music_player.dart';
import '../widgets/tr_text.dart';

/// Square artwork: gradient + note icon (tinted from the title).
class MusicArt extends StatelessWidget {
  final MediaEntry entry;
  final double size;
  final double radius;
  const MusicArt(this.entry, {super.key, this.size = 48, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final t = entry.tint;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: t,
        ),
      ),
      child: Icon(Icons.music_note_rounded,
          color: Colors.white.withValues(alpha: .92), size: size * .5),
    );
  }
}

/// Floating "now playing" bar shown above the bottom navigation.
///
/// The user can minimise it (down-arrow). It then turns into a small round,
/// animated, draggable 🎵 button that floats above the whole app (see
/// [MiniPlayerBubble]); tapping that button brings the card back. The X on
/// the card stops the music and removes the player completely.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  /// True while the card is minimised into the floating button. Shared by
  /// every screen that shows a mini player.
  static final ValueNotifier<bool> minimized = ValueNotifier<bool>(false);

  /// How many MiniPlayer cards are currently on screen (so the floating
  /// button knows whether there is a card to bring back).
  static int _mounted = 0;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  @override
  void initState() {
    super.initState();
    MiniPlayer._mounted++;
    MiniPlayerBubble.ensureInit();
  }

  @override
  void dispose() {
    MiniPlayer._mounted--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mp = MusicPlayer.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([mp, MiniPlayer.minimized]),
      builder: (context, _) {
        final e = mp.current;
        // Minimised: the floating button (an overlay) stands in for the card.
        if (e == null || MiniPlayer.minimized.value) {
          return const SizedBox.shrink();
        }
        return GestureDetector(
          onTap: () => showNowPlaying(context),
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            decoration: BoxDecoration(
              color: Ui.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Ui.line),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .4), blurRadius: 14),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
                  child: Row(
                    children: [
                      MusicArt(e, size: 42, radius: 10),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w800)),
                            Text(
                              mp.failed
                                  ? "Can't play this file"
                                  : mp.loading
                                      ? 'Loading…'
                                      : e.folderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: Ui.muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(mp.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded),
                        iconSize: 30,
                        onPressed: mp.toggle,
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded),
                        iconSize: 26,
                        onPressed: mp.next,
                      ),
                      IconButton(
                        tooltip: 'Minimise',
                        icon: Icon(Icons.keyboard_arrow_down_rounded,
                            color: Ui.dim),
                        iconSize: 24,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => MiniPlayer.minimized.value = true,
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: Ui.dim),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        onPressed: mp.stop,
                      ),
                    ],
                  ),
                ),
                ValueListenableBuilder<Duration>(
                  valueListenable: mp.position,
                  builder: (_, p, _) {
                    final total = mp.duration.inMilliseconds;
                    return ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16)),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        value: total <= 0
                            ? 0
                            : (p.inMilliseconds / total).clamp(0.0, 1.0),
                        backgroundColor: Colors.white10,
                        color: Ui.red,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Owns the floating 🎵 button: shows it (in the app's root overlay, above
/// every screen) while music is loaded and the card is minimised.
class MiniPlayerBubble {
  static OverlayEntry? _entry;
  static bool _ready = false;

  /// Where the user last left the button (kept while the app runs).
  static Offset? lastPos;

  static void ensureInit() {
    if (_ready) return;
    _ready = true;
    MusicPlayer.instance.addListener(_sync);
    MiniPlayer.minimized.addListener(_sync);
  }

  static void _sync() {
    final mp = MusicPlayer.instance;
    // Music was closed: next song should open as the full card again.
    if (mp.current == null && MiniPlayer.minimized.value) {
      MiniPlayer.minimized.value = false; // re-enters _sync
      return;
    }
    final show = mp.current != null && MiniPlayer.minimized.value;
    if (show && _entry == null) {
      final overlay = AppNav.key.currentState?.overlay;
      if (overlay == null) return;
      _entry = OverlayEntry(builder: (_) => const _FloatingMusicButton());
      overlay.insert(_entry!);
    } else if (!show && _entry != null) {
      _entry!.remove();
      _entry = null;
    }
  }
}

class _FloatingMusicButton extends StatefulWidget {
  const _FloatingMusicButton();

  @override
  State<_FloatingMusicButton> createState() => _FloatingMusicButtonState();
}

class _FloatingMusicButtonState extends State<_FloatingMusicButton>
    with SingleTickerProviderStateMixin {
  static const double _d = 60;
  final MusicPlayer _mp = MusicPlayer.instance;
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300));
  bool _dragging = false;
  Offset? _pos;

  @override
  void initState() {
    super.initState();
    _mp.addListener(_syncPulse);
    _syncPulse();
  }

  @override
  void dispose() {
    _mp.removeListener(_syncPulse);
    _pulse.dispose();
    super.dispose();
  }

  // Pulses while the music is playing, rests when paused.
  void _syncPulse() {
    if (_mp.playing) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
    if (mounted) setState(() {});
  }

  Offset _clamp(Offset o, Size size, EdgeInsets pad) => Offset(
        o.dx.clamp(4.0, size.width - _d - 4).toDouble(),
        o.dy.clamp(pad.top + 4, size.height - pad.bottom - _d - 4).toDouble(),
      );

  void _open() {
    MiniPlayer.minimized.value = false;
    // No card on this screen to bring back: open the full player instead.
    if (MiniPlayer._mounted == 0) {
      final c = AppNav.overlayContext;
      if (c != null) showNowPlaying(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final start = MiniPlayerBubble.lastPos ??
        Offset(size.width - _d - 12, size.height - pad.bottom - 190);
    final pos = _clamp(_pos ?? start, size, pad);
    final tint = _mp.current?.tint ?? [Ui.red, Ui.red];

    return AnimatedPositioned(
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onTap: _open,
        onPanStart: (_) => setState(() => _dragging = true),
        onPanUpdate: (d) =>
            setState(() => _pos = _clamp(pos + d.delta, size, pad)),
        onPanEnd: (_) {
          // Settle against the nearest side edge.
          final snapX = (pos.dx + _d / 2) < size.width / 2
              ? 8.0
              : size.width - _d - 8;
          setState(() {
            _dragging = false;
            _pos = _clamp(Offset(snapX, pos.dy), size, pad);
            MiniPlayerBubble.lastPos = _pos;
          });
        },
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) {
              final t = Curves.easeInOut.transform(_pulse.value);
              return Transform.scale(
                scale: _dragging ? 1.12 : 1 + .07 * t,
                child: Container(
                  width: _d,
                  height: _d,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: tint,
                    ),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: .85), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: tint.first.withValues(alpha: .35 + .35 * t),
                        blurRadius: 12 + 14 * t,
                        spreadRadius: 1 + 3 * t,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: child,
                ),
              );
            },
            child: Transform.rotate(
              angle: _mp.playing ? 0 : -.2,
              child: const Text('🎵', style: TextStyle(fontSize: 28)),
            ),
          ),
        ),
      ),
    );
  }
}

void showNowPlaying(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Ui.bg,
    builder: (_) => const _NowPlaying(),
  );
}

class _NowPlaying extends StatefulWidget {
  const _NowPlaying();

  @override
  State<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<_NowPlaying> {
  bool _lyrics = false;

  @override
  Widget build(BuildContext context) {
    final mp = MusicPlayer.instance;
    return ListenableBuilder(
      listenable: mp,
      builder: (context, _) {
        final e = mp.current;
        if (e == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).maybePop();
          });
          return const SizedBox.shrink();
        }
        final t = e.tint;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [t.first.withValues(alpha: .38), Ui.bg, Ui.bg],
              stops: const [0, .55, 1],
            ),
          ),
          // Keep the controls above the phone's navigation bar / gesture area
          // (the sheet only pads the top by itself).
          child: SafeArea(
            top: false,
            child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      iconSize: 32,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Text('NOW PLAYING',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                      tooltip: 'Lyrics',
                      icon: Icon(Icons.lyrics_rounded,
                          color: _lyrics ? Ui.red : Ui.text),
                      onPressed: () => setState(() => _lyrics = !_lyrics),
                    ),
                    IconButton(
                      tooltip: 'Add to playlist',
                      icon: const Icon(Icons.playlist_add_rounded),
                      onPressed: () => showAddToPlaylist(context, e),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _lyrics
                    ? LyricsView(key: ValueKey(e.key), entry: e)
                    : Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: t,
                          ),
                          boxShadow: [
                            BoxShadow(
                                color: t.first.withValues(alpha: .45),
                                blurRadius: 44,
                                offset: const Offset(0, 18)),
                          ],
                        ),
                        child: const Icon(Icons.music_note_rounded,
                            size: 110, color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(e.folderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Ui.muted)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<Duration>(
                valueListenable: mp.position,
                builder: (_, p, _) {
                  final total = mp.duration.inMilliseconds.toDouble();
                  final v = p.inMilliseconds.toDouble().clamp(0, total <= 0 ? 1 : total);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Text(fmtDur(p), style: TextStyle(fontSize: 12, color: Ui.muted)),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              activeTrackColor: Ui.red,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              min: 0,
                              max: total <= 0 ? 1 : total,
                              value: v.toDouble(),
                              onChanged: (x) =>
                                  mp.seek(Duration(milliseconds: x.round())),
                            ),
                          ),
                        ),
                        Text(fmtDur(mp.duration),
                            style: TextStyle(fontSize: 12, color: Ui.muted)),
                      ],
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.shuffle_rounded,
                          color: mp.shuffle ? Ui.red : Ui.dim),
                      onPressed: mp.toggleShuffle,
                    ),
                    IconButton(
                      iconSize: 38,
                      icon: const Icon(Icons.skip_previous_rounded),
                      onPressed: mp.previous,
                    ),
                    GestureDetector(
                      onTap: mp.toggle,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Ui.red,
                          boxShadow: [
                            BoxShadow(
                                color: Ui.red.withValues(alpha: .5),
                                blurRadius: 24),
                          ],
                        ),
                        child: mp.loading
                            ? const Padding(
                                padding: EdgeInsets.all(22),
                                child: CircularProgressIndicator(
                                    strokeWidth: 3, color: Colors.white),
                              )
                            : Icon(
                                mp.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 44,
                                color: Colors.white),
                      ),
                    ),
                    IconButton(
                      iconSize: 38,
                      icon: const Icon(Icons.skip_next_rounded),
                      onPressed: mp.next,
                    ),
                    IconButton(
                      icon: Icon(
                        mp.repeat == 2
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        color: mp.repeat == 0 ? Ui.dim : Ui.red,
                      ),
                      onPressed: mp.cycleRepeat,
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Watermark(),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}
