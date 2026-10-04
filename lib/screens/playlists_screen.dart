import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/m3u_parser.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'player_screen.dart';

/// Saved M3U playlists (by link). Tap one to browse and play its entries.
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  List<SavedPlaylist> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Settings.playlists().then((l) {
      if (mounted) {
        setState(() {
          _items = l;
          _loading = false;
        });
      }
    });
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name')),
            TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration:
                    const InputDecoration(labelText: 'Playlist link (.m3u)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ADD')),
        ],
      ),
    );
    final link = url.text.trim();
    if (ok != true || !link.startsWith('http')) return;
    final n = name.text.trim().isEmpty ? Uri.parse(link).host : name.text.trim();
    setState(() => _items = [..._items, SavedPlaylist(n, link)]);
    await Settings.savePlaylists(_items);
  }

  Future<void> _remove(SavedPlaylist p) async {
    setState(() => _items = _items.where((e) => e != p).toList());
    await Settings.savePlaylists(_items);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Playlists')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Ui.red))
          : _items.isEmpty
              ? const Center(
                  child: Text('No playlists yet. Tap + to add one.',
                      style: TextStyle(color: Ui.muted)))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final p = _items[i];
                    return ListTile(
                      leading: const Icon(Icons.playlist_play_rounded),
                      title: Text(p.name,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(p.url,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _remove(p),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => PlaylistEntriesScreen(playlist: p)),
                      ),
                    );
                  },
                ),
    );
  }
}

class PlaylistEntriesScreen extends StatefulWidget {
  final SavedPlaylist playlist;
  const PlaylistEntriesScreen({super.key, required this.playlist});

  @override
  State<PlaylistEntriesScreen> createState() => _PlaylistEntriesScreenState();
}

class _PlaylistEntriesScreenState extends State<PlaylistEntriesScreen> {
  List<M3uEntry> _all = [];
  bool _loading = true;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await http
          .get(Uri.parse(widget.playlist.url))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final list = parseM3u(r.body);
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
        if (list.isEmpty) _error = 'No entries found in this playlist';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load this playlist';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list =
        _all.where((e) => q.isEmpty || e.name.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.playlist.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Ui.red))
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Ui.muted)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        onChanged: (v) => setState(() => _q = v),
                        decoration: InputDecoration(
                          hintText: 'Search',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: Ui.card,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final e = list[i];
                          return ListTile(
                            leading: const Icon(Icons.live_tv_rounded),
                            title: Text(e.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: e.group == null ? null : Text(e.group!),
                            onTap: () =>
                                Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => PlayerScreen(
                                  title: e.name, url: e.url, isLive: true),
                            )),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
