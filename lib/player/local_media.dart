import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

import 'media_entry.dart';

enum MediaStatus { idle, loading, denied, ready }

class FolderGroup {
  final String path;
  final String name;
  final List<MediaEntry> items;
  const FolderGroup(this.path, this.name, this.items);
  int get videos => items.where((e) => !e.audio).length;
  int get songs => items.where((e) => e.audio).length;
}

/// Reads the phone's videos and music (MediaStore) once permission is given.
class LocalMedia extends ChangeNotifier {
  static final LocalMedia instance = LocalMedia._();
  LocalMedia._();

  MediaStatus status = MediaStatus.idle;
  List<MediaEntry> videos = [];
  List<MediaEntry> songs = [];

  List<FolderGroup> get folders {
    final map = <String, List<MediaEntry>>{};
    for (final e in [...videos, ...songs]) {
      map.putIfAbsent(e.folder, () => []).add(e);
    }
    final list = [
      for (final k in map.keys) FolderGroup(k, baseName(k), map[k]!),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<bool> _ask() async {
    final res = await [Permission.videos, Permission.audio, Permission.storage]
        .request();
    bool ok(Permission p) => res[p]?.isGranted == true || res[p]?.isLimited == true;
    return ok(Permission.videos) || ok(Permission.audio) || ok(Permission.storage);
  }

  Future<void> load() async {
    if (status == MediaStatus.loading) return;
    status = MediaStatus.loading;
    notifyListeners();
    try {
      if (!await _ask()) {
        status = MediaStatus.denied;
        notifyListeners();
        return;
      }
      await PhotoManager.setIgnorePermissionCheck(true);
      videos = await _fetch(RequestType.video);
      songs = await _fetch(RequestType.audio);
      status = MediaStatus.ready;
    } catch (_) {
      status = MediaStatus.ready;
    }
    notifyListeners();
  }

  Future<List<MediaEntry>> _fetch(RequestType type) async {
    final paths = await PhotoManager.getAssetPathList(
      type: type,
      onlyAll: true,
    );
    if (paths.isEmpty) return [];
    final all = paths.first;
    final count = await all.assetCountAsync;
    if (count == 0) return [];
    final assets = await all.getAssetListRange(start: 0, end: count);
    return [for (final a in assets) MediaEntry.fromAsset(a)];
  }

  /// Lists playable files inside a folder picked with the system picker.
  static Future<List<MediaEntry>> scanDirectory(String dir) async {
    final out = <MediaEntry>[];
    try {
      await for (final f in Directory(dir).list(recursive: true, followLinks: false)) {
        if (f is! File) continue;
        final e = extOf(f.path);
        if (videoExts.contains(e) || audioExts.contains(e)) {
          out.add(MediaEntry.fromPath(f.path));
        }
      }
    } catch (_) {}
    out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return out;
  }
}
