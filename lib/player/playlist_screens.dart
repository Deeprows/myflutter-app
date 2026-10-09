import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'lyrics_view.dart';
import 'local_media.dart';
import 'media_entry.dart';
import 'mini_player.dart';
import 'music_player.dart';
import 'playlist_store.dart';

Future<String?> askName(BuildContext context,
    {String title = 'New playlist', String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Ui.panel,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      content: TextField(
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text),
          style: FilledButton.styleFrom(backgroundColor: Ui.red),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}

/// "Add to playlist" picker for one song.
Future<void> showAddToPlaylist(BuildContext context, MediaEntry e) async {
  final store = PlaylistStore.instance;
  await store.load();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListenableBuilder(
        listenable: store,
        builder: (_, _) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Text('Add to playlist',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ),
              ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Ui.red.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.add_rounded, color: Ui.red),
                ),
                title: const Text('New playlist',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                onTap: () async {
                  final name = await askName(ctx);
                  if (name == null) return;
                  final p = store.create(name);
                  store.add(p, e);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) _toast(context, 'Added to ${p.name}');
                },
              ),
              for (final p in store.lists)
                ListTile(
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Ui.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Ui.line),
                    ),
                    child: const Icon(Icons.queue_music_rounded),
                  ),
                  title: Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${p.items.length} songs',
                      style: TextStyle(color: Ui.muted)),
                  trailing: store.contains(p, e)
                      ? Icon(Icons.check_circle_rounded, color: Ui.green)
                      : null,
                  onTap: () {
                    final added = store.add(p, e);
                    Navigator.pop(ctx);
                    _toast(context, added ? 'Added to ${p.name}' : 'Already in ${p.name}');
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The ⋮ menu on a song row.
void showSongMenu(BuildContext context, MediaEntry e) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
            child: Row(
              children: [
                MusicArt(e, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(e.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded),
            title: const Text('Add to playlist'),
            onTap: () {
              Navigator.pop(ctx);
              showAddToPlaylist(context, e);
            },
          ),
          ListTile(
            leading: const Icon(Icons.lyrics_rounded),
            title: const Text('Add / edit lyrics'),
            onTap: () {
              Navigator.pop(ctx);
              showLyricsEditor(context, e);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

// =================================================== Playlists tab (hub)

class PlaylistsTab extends StatelessWidget {
  final String query;
  const PlaylistsTab({super.key, this.query = ''});

  @override
  Widget build(BuildContext context) {
    final store = PlaylistStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([store, LocalMedia.instance]),
      builder: (context, _) {
        final lists = store.lists
            .where((p) => query.isEmpty || p.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.icon(
                onPressed: () async {
                  final name = await askName(context);
                  if (name != null) store.create(name);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Ui.red,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New playlist',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            if (lists.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 50),
                child: Column(
                  children: [
                    Icon(Icons.queue_music_rounded, size: 56, color: Ui.dim),
                    const SizedBox(height: 12),
                    const Text('No playlists yet',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text('Tap ⋮ on any song to add it to a playlist.',
                        style: TextStyle(color: Ui.muted)),
                  ],
                ),
              ),
            for (final p in lists)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PlaylistCard(p),
              ),
          ],
        );
      },
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final Playlist p;
  const _PlaylistCard(this.p);

  @override
  Widget build(BuildContext context) {
    final first = p.items.isEmpty
        ? null
        : PlaylistStore.instance.resolve(p.items.first);
    final tint = first?.tint ?? [Ui.red, Ui.cardDeep];
    return Material(
      color: Ui.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PlaylistScreen(id: p.id),
        )),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Ui.line),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: tint,
                  ),
                ),
                child: const Icon(Icons.queue_music_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('${p.items.length} songs',
                        style: TextStyle(fontSize: 12, color: Ui.muted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Ui.dim),
            ],
          ),
        ),
      ),
    );
  }
}

// ========================================================= one playlist

class PlaylistScreen extends StatelessWidget {
  final String id;
  const PlaylistScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    final store = PlaylistStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([store, LocalMedia.instance, MusicPlayer.instance]),
      builder: (context, _) {
        final p = store.byId(id);
        if (p == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).maybePop();
          });
          return const Scaffold();
        }
        final resolved = [for (final it in p.items) store.resolve(it)];
        final playable = resolved.whereType<MediaEntry>().toList();
        final cur = MusicPlayer.instance.current;

        void play(int startAt, {bool shuffle = false}) {
          if (playable.isEmpty) return;
          MusicPlayer.instance.shuffle = shuffle;
          MusicPlayer.instance.playQueue(playable, startAt);
        }

        return Scaffold(
          backgroundColor: Ui.bg,
          appBar: AppBar(
            backgroundColor: Ui.bg,
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w900)),
            actions: [
              PopupMenuButton<int>(
                color: Ui.panel,
                onSelected: (v) async {
                  if (v == 0) {
                    final n = await askName(context,
                        title: 'Rename playlist', initial: p.name);
                    if (n != null) store.rename(p, n);
                  } else {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: Ui.panel,
                        title: const Text('Delete playlist?'),
                        content: Text('"${p.name}" will be removed. Your songs stay on the phone.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel')),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: FilledButton.styleFrom(backgroundColor: Ui.red),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) store.delete(p);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 0, child: Text('Rename')),
                  PopupMenuItem(value: 1, child: Text('Delete playlist')),
                ],
              ),
            ],
          ),
          bottomNavigationBar: const SafeArea(child: MiniPlayer()),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: playable.isEmpty ? null : () => play(0),
                        style: FilledButton.styleFrom(
                          backgroundColor: Ui.red,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: playable.isEmpty
                            ? null
                            : () => play(0, shuffle: true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Ui.line),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('Shuffle',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: p.items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'This playlist is empty.\nTap ⋮ on a song in the Music tab to add it.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Ui.muted),
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
                        itemCount: p.items.length,
                        onReorder: (a, b) {
                          if (b > a) b -= 1;
                          store.move(p, a, b);
                        },
                        itemBuilder: (_, i) {
                          final e = resolved[i];
                          final it = p.items[i];
                          final on = e != null && cur?.key == e.key;
                          return Material(
                            key: ValueKey('${it.key}#$i'),
                            color: on ? Ui.red.withValues(alpha: .12) : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: e == null ? null : () => play(playable.indexOf(e)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                child: Row(
                                  children: [
                                    e == null
                                        ? Container(
                                            width: 46,
                                            height: 46,
                                            decoration: BoxDecoration(
                                              color: Ui.cardDeep,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Icon(Icons.music_off_rounded, color: Ui.dim),
                                          )
                                        : MusicArt(e, size: 46),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(e?.title ?? it.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w800,
                                                color: e == null
                                                    ? Ui.dim
                                                    : on
                                                        ? Ui.red
                                                        : Colors.white,
                                              )),
                                          Text(e == null ? 'Not on this phone' : e.folderName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 12, color: Ui.muted)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Remove',
                                      icon: Icon(Icons.remove_circle_outline_rounded,
                                          color: Ui.dim, size: 20),
                                      onPressed: () => store.removeAt(p, i),
                                    ),
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Icon(Icons.drag_handle_rounded, color: Ui.dim),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
