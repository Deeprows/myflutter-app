import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../services/movie_library.dart';
import '../services/support_gate.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/open_movie.dart';
import '../widgets/movie_card.dart' show MoviePoster;

/// "Watch later" and "Watch history" in one page with two tabs.
class LibraryScreen extends StatelessWidget {
  /// 0 = Watch later, 1 = Watch history.
  final int initialTab;
  const LibraryScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    final lib = MovieLibrary.instance;
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: ListenableBuilder(
        listenable: lib,
        builder: (context, _) => Scaffold(
          backgroundColor: Ui.bg,
          appBar: AppBar(
            backgroundColor: Ui.bg,
            title: const Text('My Library',
                style: TextStyle(fontWeight: FontWeight.w900)),
            actions: [
              Builder(
                builder: (ctx) {
                  final tab = DefaultTabController.of(ctx);
                  return ListenableBuilder(
                    listenable: tab,
                    builder: (_, _) => tab.index == 1 && lib.history.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear history',
                            icon: const Icon(Icons.delete_sweep_rounded),
                            onPressed: () => _confirmClear(ctx),
                          )
                        : const SizedBox.shrink(),
                  );
                },
              ),
            ],
            bottom: TabBar(
              indicatorColor: Ui.red,
              labelColor: Colors.white,
              unselectedLabelColor: Ui.muted,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800),
              tabs: [
                Tab(
                  icon: const Icon(Icons.bookmark_rounded, size: 20),
                  text: 'Watch later (${lib.watchLater.length})',
                ),
                Tab(
                  icon: const Icon(Icons.history_rounded, size: 20),
                  text: 'History (${lib.history.length})',
                ),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _Grid(
                items: [for (final m in lib.watchLater) (m, null)],
                emptyIcon: Icons.bookmark_add_outlined,
                emptyTitle: 'Nothing saved yet',
                emptyHint:
                    'Tap the bookmark on any movie to save it here for later.',
                removeTip: 'Remove from Watch later',
                onRemove: lib.removeWatchLater,
              ),
              _Grid(
                items: [for (final e in lib.history) (e.movie, e.at)],
                emptyIcon: Icons.history_toggle_off_rounded,
                emptyTitle: 'No watch history',
                emptyHint: 'Movies and series you open will show up here.',
                removeTip: 'Remove from history',
                onRemove: lib.removeFromHistory,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear watch history?'),
        content: const Text('This removes every title from your history.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Clear', style: TextStyle(color: Ui.red))),
        ],
      ),
    );
    if (ok == true) await MovieLibrary.instance.clearHistory();
  }
}

String _ago(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return shortDate(at);
}

class _Grid extends StatelessWidget {
  final List<(Movie, DateTime?)> items;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyHint;
  final String removeTip;
  final Future<void> Function(Movie) onRemove;
  const _Grid({
    required this.items,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyHint,
    required this.removeTip,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(emptyIcon, size: 52, color: Ui.dim),
              const SizedBox(height: 12),
              Text(emptyTitle,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(emptyHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.4)),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 288,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final (m, at) = items[i];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => SupportGate.guard(context, () {
              if (context.mounted) openMoviePlayer(context, m);
            }),
            borderRadius: BorderRadius.circular(Ui.radius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MoviePoster(movie: m, badges: true),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Tooltip(
                          message: removeTip,
                          child: Material(
                            color: Colors.black.withValues(alpha: .65),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => onRemove(m),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.close_rounded, size: 16),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(m.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, height: 1.2, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  at != null
                      ? 'Watched ${_ago(at)}'
                      : [
                          m.isSeries ? 'Series' : 'Movie',
                          if (m.year != null) m.year!,
                        ].join(' · '),
                  style: TextStyle(
                      color: Ui.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
