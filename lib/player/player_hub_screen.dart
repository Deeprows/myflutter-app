import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme/app_theme.dart';
import 'local_media.dart';
import 'local_video_screen.dart';
import 'media_entry.dart';
import 'mini_player.dart';
import 'music_player.dart';
import 'playlist_screens.dart';
import 'playlist_store.dart';

/// The "Player" tab: videos, music and folders stored on the phone.
class PlayerHubScreen extends StatefulWidget {
  /// True while this tab is on screen; the library loads on first show so the
  /// storage permission isn't asked at app start.
  final bool active;
  const PlayerHubScreen({super.key, required this.active});

  @override
  State<PlayerHubScreen> createState() => _PlayerHubScreenState();
}

class _PlayerHubScreenState extends State<PlayerHubScreen> {
  final _media = LocalMedia.instance;
  int _tab = 0; // 0 videos, 1 music, 2 playlists, 3 folders
  bool _searching = false;
  String _q = '';
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _maybeStart();
  }

  @override
  void didUpdateWidget(covariant PlayerHubScreen old) {
    super.didUpdateWidget(old);
    _maybeStart();
  }

  void _maybeStart() {
    if (widget.active && !_started) {
      _started = true;
      _media.load();
      PlaylistStore.instance.load();
    }
  }

  bool _match(MediaEntry e) =>
      _q.isEmpty || e.title.toLowerCase().contains(_q.toLowerCase());

  // -------------------------------------------------------------- actions

  void _playVideos(List<MediaEntry> list, int i) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LocalVideoScreen(items: list, index: i),
    ));
  }

  void _playSongs(List<MediaEntry> list, int i) {
    MusicPlayer.instance.playQueue(list, i);
  }

  void _playAny(List<MediaEntry> list, int i) {
    final e = list[i];
    if (e.audio) {
      final songs = list.where((x) => x.audio).toList();
      _playSongs(songs, songs.indexOf(e));
    } else {
      final vids = list.where((x) => !x.audio).toList();
      _playVideos(vids, vids.indexOf(e));
    }
  }

  Future<void> _openFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [...videoExts, ...audioExts],
    );
    if (res == null) return;
    final list = [
      for (final f in res.files)
        if (f.path != null) MediaEntry.fromPath(f.path!),
    ];
    if (list.isNotEmpty && mounted) _playAny(list, 0);
  }

  Future<void> _openFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || !mounted) return;
    final list = await LocalMedia.scanDirectory(dir);
    if (!mounted) return;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No video or music files found in that folder'),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FolderScreen(
        group: FolderGroup(dir, baseName(dir), list),
        onPlay: _playAny,
      ),
    ));
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _media,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [Ui.red.withValues(alpha: .16), Ui.bg],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _header(),
                _segments(),
                Expanded(child: _body()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
      child: _searching
          ? Row(
              children: [
                Expanded(
                  child: TextField(
                    autofocus: true,
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(
                      hintText: 'Search videos and music',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Ui.card,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() {
                    _searching = false;
                    _q = '';
                  }),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    gradient: LinearGradient(colors: [Ui.red, Ui.redSoft]),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      size: 30, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Player',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w900)),
                      Text(
                        '${_media.videos.length} videos · ${_media.songs.length} songs',
                        style: TextStyle(fontSize: 12, color: Ui.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => setState(() => _searching = true),
                ),
                PopupMenuButton<int>(
                  tooltip: 'Open',
                  icon: const Icon(Icons.folder_open_rounded),
                  color: Ui.panel,
                  onSelected: (v) => v == 0 ? _openFiles() : _openFolder(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 0,
                        child: ListTile(
                            leading: Icon(Icons.video_file_rounded),
                            title: Text('Open file…'),
                            contentPadding: EdgeInsets.zero)),
                    PopupMenuItem(
                        value: 1,
                        child: ListTile(
                            leading: Icon(Icons.folder_rounded),
                            title: Text('Open folder…'),
                            contentPadding: EdgeInsets.zero)),
                  ],
                ),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _media.load,
                ),
              ],
            ),
    );
  }

  Widget _segments() {
    const labels = ['Videos', 'Music', 'Playlists', 'Folders'];
    const icons = [
      Icons.movie_rounded,
      Icons.music_note_rounded,
      Icons.queue_music_rounded,
      Icons.folder_rounded
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Ui.cardDeep,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ui.line),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: _tab == i ? Ui.red : Colors.transparent,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icons[i],
                          size: 16, color: _tab == i ? Colors.white : Ui.dim),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: _tab == i ? Colors.white : Ui.dim)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_media.status) {
      case MediaStatus.idle:
      case MediaStatus.loading:
        return Center(child: CircularProgressIndicator(color: Ui.red));
      case MediaStatus.denied:
        return _message(
          Icons.lock_outline_rounded,
          'Allow access to your media',
          'The player needs permission to see the videos and music on your phone.',
          action: 'Allow access',
          onTap: () async {
            final p = await Permission.videos.status;
            if (p.isPermanentlyDenied) {
              await openAppSettings();
            } else {
              _media.load();
            }
          },
        );
      case MediaStatus.ready:
        break;
    }
    switch (_tab) {
      case 0:
        return _videos();
      case 1:
        return _music();
      case 2:
        return PlaylistsTab(query: _q);
      default:
        return _folders();
    }
  }

  Widget _message(IconData icon, String title, String hint,
      {String? action, VoidCallback? onTap}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Ui.dim),
            const SizedBox(height: 14),
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(hint,
                textAlign: TextAlign.center,
                style: TextStyle(color: Ui.muted)),
            const SizedBox(height: 18),
            if (action != null)
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(backgroundColor: Ui.red),
                child: Text(action),
              ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _openFiles,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Open a file instead'),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- videos

  Widget _videos() {
    final list = _media.videos.where(_match).toList();
    if (list.isEmpty) {
      return _message(Icons.video_library_outlined, 'No videos found',
          'Videos on your phone show up here. You can also open any file or folder.');
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: .98,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => VideoTile(
        entry: list[i],
        onTap: () => _playVideos(list, i),
      ),
    );
  }

  // ---------------------------------------------------------------- music

  Widget _music() {
    final list = _media.songs.where(_match).toList();
    if (list.isEmpty) {
      return _message(Icons.library_music_outlined, 'No music found',
          'MP3, M4A, FLAC and more appear here once they are on your phone.');
    }
    return ListenableBuilder(
      listenable: MusicPlayer.instance,
      builder: (context, _) {
        final cur = MusicPlayer.instance.current;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          itemCount: list.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          MusicPlayer.instance.shuffle = true;
                          _playSongs(list, 0);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: Ui.red,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('Shuffle',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          MusicPlayer.instance.shuffle = false;
                          _playSongs(list, 0);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Ui.line),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play all',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              );
            }
            final e = list[i - 1];
            return SongTile(
              entry: e,
              playing: cur?.key == e.key,
              onTap: () => _playSongs(list, i - 1),
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------- folders

  Widget _folders() {
    final list = _media.folders
        .where((f) => _q.isEmpty || f.name.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    if (list.isEmpty) {
      return _message(Icons.folder_off_outlined, 'No folders',
          'Folders that contain videos or music appear here.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final f = list[i];
        return Material(
          color: Ui.card,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => FolderScreen(group: f, onPlay: _playAny),
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
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Ui.red.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.folder_rounded, color: Ui.red, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (f.videos > 0) '${f.videos} videos',
                            if (f.songs > 0) '${f.songs} songs',
                          ].join(' · '),
                          style: TextStyle(fontSize: 12, color: Ui.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Ui.dim),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ======================================================== shared widgets

class VideoTile extends StatelessWidget {
  final MediaEntry entry;
  final VoidCallback onTap;
  const VideoTile({super.key, required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Ui.cardDeep),
                  if (entry.asset != null)
                    AssetEntityImage(
                      entry.asset!,
                      isOriginal: false,
                      thumbnailSize: const ThumbnailSize.square(360),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: entry.tint),
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: .55),
                        ],
                        stops: const [.5, 1],
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: .45),
                        border: Border.all(color: Colors.white38),
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 28),
                    ),
                  ),
                  if (entry.duration > Duration.zero)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(fmtDur(entry.duration),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(entry.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, height: 1.2)),
        ],
      ),
    );
  }
}

class SongTile extends StatelessWidget {
  final MediaEntry entry;
  final bool playing;
  final VoidCallback onTap;
  const SongTile(
      {super.key,
      required this.entry,
      required this.playing,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: playing ? Ui.red.withValues(alpha: .12) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                MusicArt(entry, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: playing ? Ui.red : Colors.white)),
                      const SizedBox(height: 2),
                      Text(entry.folderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Ui.muted)),
                    ],
                  ),
                ),
                if (playing)
                  Icon(Icons.equalizer_rounded, color: Ui.red)
                else if (entry.duration > Duration.zero)
                  Text(fmtDur(entry.duration),
                      style: TextStyle(fontSize: 12, color: Ui.dim)),
                IconButton(
                  tooltip: 'More',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.more_vert_rounded, color: Ui.dim, size: 20),
                  onPressed: () => showSongMenu(context, entry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Contents of one folder (videos as a grid, music as a list).
class FolderScreen extends StatelessWidget {
  final FolderGroup group;
  final void Function(List<MediaEntry> list, int index) onPlay;
  const FolderScreen({super.key, required this.group, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final vids = group.items.where((e) => !e.audio).toList();
    final songs = group.items.where((e) => e.audio).toList();
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.bg,
        title: Text(group.name,
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      bottomNavigationBar: const SafeArea(child: MiniPlayer()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        children: [
          if (vids.isNotEmpty) ...[
            _label('Videos', vids.length),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 12,
                childAspectRatio: .98,
              ),
              itemCount: vids.length,
              itemBuilder: (_, i) => VideoTile(
                entry: vids[i],
                onTap: () => onPlay(vids, i),
              ),
            ),
          ],
          if (songs.isNotEmpty) ...[
            _label('Music', songs.length),
            ListenableBuilder(
              listenable: MusicPlayer.instance,
              builder: (_, _) => Column(
                children: [
                  for (var i = 0; i < songs.length; i++)
                    SongTile(
                      entry: songs[i],
                      playing: MusicPlayer.instance.current?.key == songs[i].key,
                      onTap: () => onPlay(songs, i),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String t, int n) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 10),
        child: Text('$t · $n',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
                color: Ui.muted)),
      );
}
