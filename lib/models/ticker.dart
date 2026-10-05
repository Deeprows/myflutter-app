/// Content of the scrolling ticker on the home screen (assets/data/ticker.json).
///
///   { "enabled": true, "speed": 40, "items": ["Message one", "Message two"] }
///
/// * enabled - false hides the ticker
/// * speed   - scroll speed in pixels per second (10 - 120, default 40)
/// * items   - messages shown one after another; each can be a plain string
///             or an object like {"text": "Message"}. A plain JSON list of
///             strings also works.
class TickerData {
  final bool enabled;
  final double speed;
  final List<String> items;

  const TickerData({
    this.enabled = true,
    this.speed = 40,
    this.items = const [],
  });

  static const empty = TickerData(enabled: false);

  bool get visible => enabled && items.isNotEmpty;

  static TickerData parse(dynamic raw) {
    List<dynamic> list;
    var enabled = true;
    var speed = 40.0;
    if (raw is List) {
      list = raw;
    } else if (raw is Map) {
      list = raw['items'] is List
          ? raw['items'] as List
          : (raw['messages'] is List ? raw['messages'] as List : const []);
      final e = raw['enabled'];
      if (e is bool) enabled = e;
      if (e is String) enabled = e.toLowerCase() != 'false';
      final s = double.tryParse((raw['speed'] ?? '').toString());
      if (s != null) speed = s;
    } else {
      return empty;
    }
    final items = <String>[];
    for (final i in list) {
      final t = (i is Map ? (i['text'] ?? i['message'] ?? '') : i)
          .toString()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (t.isNotEmpty) items.add(t);
    }
    return TickerData(
      enabled: enabled,
      speed: speed.clamp(10, 120).toDouble(),
      items: items,
    );
  }
}
