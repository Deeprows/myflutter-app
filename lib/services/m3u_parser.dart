class M3uEntry {
  final String name;
  final String url;
  final String? group;
  const M3uEntry(this.name, this.url, this.group);
}

/// Minimal #EXTM3U / #EXTINF parser.
List<M3uEntry> parseM3u(String text) {
  final out = <M3uEntry>[];
  String? name;
  String? group;
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF')) {
      final comma = line.lastIndexOf(',');
      name = comma >= 0 ? line.substring(comma + 1).trim() : null;
      group = RegExp(r'group-title="([^"]*)"').firstMatch(line)?.group(1);
    } else if (!line.startsWith('#')) {
      out.add(M3uEntry(
          (name == null || name.isEmpty) ? line : name, line, group));
      name = null;
      group = null;
    }
  }
  return out;
}
