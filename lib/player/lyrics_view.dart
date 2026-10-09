import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'lyrics_service.dart';
import 'media_entry.dart';
import 'music_player.dart';

const double _rowH = 60;

/// Lyrics for the song that is playing. Synced (.lrc) lyrics follow the music
/// and highlight the current line; tap a line to jump to it.
class LyricsView extends StatefulWidget {
  final MediaEntry entry;
  const LyricsView({super.key, required this.entry});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  Lyrics? _l;
  bool _loading = true;
  int _active = -1;
  final _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = true);
    final l = await LyricsService.load(widget.entry, force: force);
    if (!mounted) return;
    setState(() {
      _l = l;
      _loading = false;
      _active = -1;
    });
  }

  int _indexAt(Duration p) {
    final lines = _l!.lines;
    var idx = -1;
    final t = p + const Duration(milliseconds: 250);
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= t) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  void _follow(int idx) {
    if (idx == _active) return;
    _active = idx;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sc.hasClients || idx < 0) return;
      _sc.animateTo(
        (idx * _rowH).clamp(0.0, _sc.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _body()),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () async {
                  if (await showLyricsEditor(context, widget.entry) && mounted) {
                    _load();
                  }
                },
                icon: const Icon(Icons.edit_note_rounded, size: 20),
                label: const Text('Add / edit'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await LyricsService.forgetOnline(widget.entry);
                  _load(force: true);
                },
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('Search online'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: Ui.red));
    }
    final l = _l;
    if (l == null || l.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lyrics_outlined, size: 54, color: Ui.dim),
              const SizedBox(height: 12),
              const Text('No lyrics yet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                'Search online, paste them, or import an .lrc file.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Ui.muted),
              ),
            ],
          ),
        ),
      );
    }
    if (!l.synced) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(28, 10, 28, 20),
        itemCount: l.lines.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(l.lines[i].text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, height: 1.35)),
        ),
      );
    }
    return LayoutBuilder(
      builder: (_, box) => ValueListenableBuilder<Duration>(
        valueListenable: MusicPlayer.instance.position,
        builder: (_, pos, _) {
          final idx = _indexAt(pos);
          _follow(idx);
          return ListView.builder(
            controller: _sc,
            itemExtent: _rowH,
            padding: EdgeInsets.symmetric(vertical: box.maxHeight / 2 - _rowH / 2),
            itemCount: l.lines.length,
            itemBuilder: (_, i) {
              final on = i == idx;
              final text = l.lines[i].text.isEmpty ? '♪' : l.lines[i].text;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => MusicPlayer.instance.seek(l.lines[i].time),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: on ? 21 : 17,
                        fontWeight: on ? FontWeight.w900 : FontWeight.w700,
                        color: on ? Colors.white : Colors.white38,
                        height: 1.2,
                      ),
                      child: Text(text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Paste or import lyrics (plain text or .lrc). Returns true when saved.
Future<bool> showLyricsEditor(BuildContext context, MediaEntry entry) async {
  final initial = await LyricsService.rawFor(entry) ?? '';
  if (!context.mounted) return false;
  final ctrl = TextEditingController(text: initial);
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Ui.panel,
      title: Text(entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              maxLines: 10,
              minLines: 6,
              decoration: InputDecoration(
                hintText: 'Paste lyrics here. Timed lines like\n[00:12.30] Hello\nmake them follow the music.',
                filled: true,
                fillColor: Ui.cardDeep,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final r = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: const ['lrc', 'txt'],
                  );
                  final path = r?.files.single.path;
                  if (path == null) return;
                  try {
                    ctrl.text = await File(path).readAsString();
                  } catch (_) {}
                },
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('Import .lrc / .txt'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: Ui.red),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (saved == true) {
    await LyricsService.save(entry, ctrl.text);
    return true;
  }
  return false;
}
