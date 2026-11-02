import 'package:flutter/material.dart';

import '../models/push_target.dart';
import '../services/notification_center.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/notification_settings.dart';
import 'content_shortcut_screen.dart';
import 'fan_zone_screen.dart';

/// In-app notification inbox: live matches and kick-offs, new highlights,
/// latest movies, trending hashtags and the weekly prediction results.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<InboxItem> _items = const [];
  Set<String> _seenBefore = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final center = NotificationCenter.instance;
    // Remember what was already read, so this visit can still mark new lines.
    final seen = await center.seenIds();
    // Show what is cached right away, then fill in trending + results.
    final quick = await center.load();
    if (!mounted) return;
    setState(() {
      _seenBefore = seen;
      _items = quick;
    });
    final full = await center.load(network: true);
    if (!mounted) return;
    setState(() {
      _items = full;
      _loading = false;
    });
    await center.markAllSeen();
  }

  void _tap(InboxItem i) {
    final push = PushService.instance;
    switch (i.kind) {
      case InboxKind.live:
        final f = i.fixture;
        if (f == null) return;
        Navigator.of(context).pop();
        push.open(PushTarget(
          kind: 'kickoff',
          home: f.home,
          away: f.away,
          kickoffMs: f.kickoff.millisecondsSinceEpoch,
        ));
      case InboxKind.highlight:
        Navigator.of(context).pop();
        push.open(PushTarget(kind: 'highlights', url: i.ref));
      case InboxKind.movie:
        Navigator.of(context).pop();
        push.open(PushTarget(kind: 'movies', url: i.ref));
      case InboxKind.trending:
        Navigator.of(context).pop();
        push.openTab(8); // Search tab, where trending tags live
      case InboxKind.result:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ContentShortcutScreen(
              title: 'Ranks',
              child: FanZoneScreen(
                active: true,
                page: FanZonePage.ranks,
                embedded: true,
              ),
            ),
          ),
        );
    }
  }

  static const _sections = <InboxKind, (String, IconData, Color)>{
    InboxKind.live: ('Live matches', Icons.sports_soccer_rounded, Color(0xFFE53935)),
    InboxKind.highlight: ('Highlights', Icons.play_circle_rounded, Color(0xFFFFA000)),
    InboxKind.movie: ('Latest movies', Icons.movie_rounded, Color(0xFF8E6BFF)),
    InboxKind.trending: ('Trending hashtags', Icons.tag_rounded, Color(0xFF1E88E5)),
    InboxKind.result: ('Prediction results', Icons.emoji_events_rounded, Color(0xFF43A047)),
  };

  String _ago(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.isNegative) {
      final m = (-d.inMinutes);
      if (m < 60) return 'in ${m < 1 ? 1 : m} min';
      if (m < 24 * 60) return 'in ${(m / 60).floor()}h';
      return 'soon';
    }
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${(d.inDays / 7).floor()}w ago';
  }

  Widget _tile(InboxItem i) {
    final (_, icon, color) = _sections[i.kind]!;
    final isNew = !_seenBefore.contains(i.id);
    return InkWell(
      onTap: () => _tap(i),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.25,
                      fontWeight: isNew ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                  if (i.body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      i.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Ui.muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _ago(i.at),
                  style: TextStyle(fontSize: 11, color: Ui.dim),
                ),
                if (isNew)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Ui.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(InboxKind kind) {
    final (label, _, color) = _sections[kind]!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w900,
              color: Ui.muted,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final kind in InboxKind.values) {
      final group = _items.where((e) => e.kind == kind).toList();
      if (group.isEmpty) continue;
      children.add(_header(kind));
      children.addAll(group.map(_tile));
    }
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Notification settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => showNotificationSettings(context),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: children.isEmpty && !_loading
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_none_rounded,
                            size: 48,
                            color: Ui.dim,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "You're all caught up",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Live matches, highlights, movies and results will show up here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Ui.muted),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: children,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Header bell with an unread count; opens the notification inbox.
/// With [label] it is drawn like the Thread header actions (icon + name).
class NotificationBell extends StatelessWidget {
  final String? label;
  const NotificationBell({super.key, this.label});

  Future<void> _open(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
    NotificationCenter.instance.refreshBadge();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: NotificationCenter.instance.unread,
    builder: (context, n, _) {
      final icon = Badge(
        isLabelVisible: n > 0,
        label: Text(n > 9 ? '9+' : '$n'),
        backgroundColor: Ui.red,
        child: Icon(
          n > 0
              ? Icons.notifications_active_rounded
              : Icons.notifications_none_rounded,
          size: label == null ? null : 24,
        ),
      );
      if (label == null) {
        return IconButton(
          tooltip: 'Notifications',
          onPressed: () => _open(context),
          icon: icon,
        );
      }
      return InkResponse(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 2),
              Text(
                label!,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
