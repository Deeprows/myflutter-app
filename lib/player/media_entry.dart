import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

const videoExts = {
  'mp4', 'mkv', 'webm', 'mov', 'm4v', '3gp', 'avi', 'ts', 'flv', 'wmv', 'mpg', 'mpeg'
};
const audioExts = {
  'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'wma', 'amr', 'mka'
};

String extOf(String path) {
  final i = path.lastIndexOf('.');
  return i < 0 ? '' : path.substring(i + 1).toLowerCase();
}

String baseName(String path) {
  final n = path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
  return n.isEmpty ? path : n.last;
}

String fmtDur(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
}

/// One playable item: either a MediaStore asset or a plain file path.
class MediaEntry {
  final String title;
  final bool audio;
  final Duration duration;
  final String folder;
  final AssetEntity? asset;
  final String? path;

  const MediaEntry({
    required this.title,
    required this.audio,
    required this.duration,
    required this.folder,
    this.asset,
    this.path,
  });

  factory MediaEntry.fromAsset(AssetEntity a) {
    var rel = (a.relativePath ?? '').replaceAll(RegExp(r'[\\/]+$'), '');
    var name = a.title ?? 'Untitled';
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    return MediaEntry(
      title: name,
      audio: a.type == AssetType.audio,
      duration: Duration(seconds: a.duration),
      folder: rel.isEmpty ? 'Storage' : rel,
      asset: a,
    );
  }

  factory MediaEntry.fromPath(String p) {
    final base = baseName(p);
    final dot = base.lastIndexOf('.');
    final dir = p.length > base.length ? p.substring(0, p.length - base.length - 1) : '';
    return MediaEntry(
      title: dot > 0 ? base.substring(0, dot) : base,
      audio: audioExts.contains(extOf(p)),
      duration: Duration.zero,
      folder: dir.isEmpty ? 'Opened files' : dir,
      path: p,
    );
  }

  String get key => path ?? asset?.id ?? title;
  String get folderName => baseName(folder);

  Future<File?> file() async {
    if (path != null) return File(path!);
    return asset?.originFile;
  }

  /// Stable colour pair derived from the title, used for artwork.
  List<Color> get tint {
    const sets = [
      [Color(0xFFFF1744), Color(0xFF7A0B2E)],
      [Color(0xFF2979FF), Color(0xFF14307A)],
      [Color(0xFF00C48C), Color(0xFF0B5A4A)],
      [Color(0xFFAA47FF), Color(0xFF4A1A8A)],
      [Color(0xFFFF9100), Color(0xFF8A3D00)],
      [Color(0xFF00B8D4), Color(0xFF0B4A66)],
    ];
    return sets[title.hashCode.abs() % sets.length];
  }
}
