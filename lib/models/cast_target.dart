import 'dart:io';

import '../services/stream_resolver.dart' show StreamKind;

/// What the cast button hands to the cast dashboard: either a stream link
/// (with optional headers) or a video file stored on the phone.
class CastTarget {
  final String title;

  /// Stream link (null for local files, or for web embeds that can't be
  /// sent as a plain link).
  final String? url;

  /// Stream type, used to pick the right MIME type on the TV.
  final StreamKind? kind;

  final String? referer;
  final String? userAgent;

  /// Resolves a local video file on the phone.
  final Future<File?> Function()? file;

  const CastTarget({
    required this.title,
    this.url,
    this.kind,
    this.referer,
    this.userAgent,
    this.file,
  });

  /// True when there is something a TV can actually be sent.
  bool get canCast => file != null || (url != null && url!.trim().isNotEmpty);
}
