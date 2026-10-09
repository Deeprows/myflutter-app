import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'lyrics_view.dart';
import 'media_entry.dart';
import 'playlist_screens.dart';
import 'watermark.dart';
import 'music_player.dart';

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
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final mp = MusicPlayer.instance;
    return ListenableBuilder(
      listenable: mp,
      builder: (context, _) {
        final e = mp.current;
        if (e == null) return const SizedBox.shrink();
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
                        icon: Icon(Icons.close_rounded, color: Ui.dim),
                        iconSize: 20,
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
                          color: _lyrics ? Ui.red : Colors.white),
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
