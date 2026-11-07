import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/push_target.dart';
import '../services/fan_zone_service.dart';
import '../services/notification_center.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/notification_settings.dart';
import 'content_shortcut_screen.dart';
import 'fan_profile_screen.dart';
import 'fan_thread_screen.dart';
import 'fan_widgets.dart';
import 'fan_zone_screen.dart';
import 'prediction_results_screen.dart';

/// In-app notification inbox: new followers, likes and comments, live matches
/// and kick-offs, new highlights, latest movies, trending hashtags and the
/// weekly prediction results.
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
      case InboxKind.social:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => i.socialKind == 'follow' || i.postId.isEmpty
                ? FanProfileScreen(userId: i.actorId)
                : FanThreadScreen(postId: i.postId),
          ),
        );
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
      case InboxKind.prediction:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const PredictionResultsScreen(),
          ),
        );
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
    InboxKind.social: ('Activity', Icons.favorite_rounded, Color(0xFFF91880)),
    InboxKind.prediction: ('My predictions', Icons.how_to_vote_rounded, Color(0xFF7C4DFF)),
    InboxKind.live: ('Live matches', Icons.sports_soccer_rounded, Color(0xFFE53935)),
    InboxKind.highlight: ('Highlights', Icons.play_circle_rounded, Color(0xFFFFA000)),
    InboxKind.movie: ('Latest movies', Icons.movie_rounded, Color(0xFF8E6BFF)),
    InboxKind.trending: ('Trending hashtags', Icons.tag_rounded, Color(0xFF1E88E5)),
    InboxKind.result: ('Weekly winners', Icons.emoji_events_rounded, Color(0xFF43A047)),
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

  /// Icon + colour of a social entry (follow / like / comment).
  static (IconData, Color) _socialStyle(String kind) => switch (kind) {
    'follow' => (Icons.person_add_alt_1_rounded, const Color(0xFF1D9BF0)),
    'like' => (Icons.favorite_rounded, const Color(0xFFF91880)),
    'repost' || 'quote' => (Icons.repeat_rounded, const Color(0xFF00BA7C)),
    'mention' => (Icons.alternate_email_rounded, const Color(0xFF1D9BF0)),
    _ => (Icons.chat_bubble_rounded, const Color(0xFF00BA7C)),
  };

  /// The fan's picture with a small follow / like / comment badge.
  Widget _socialLeading(InboxItem i) {
    final (icon, color) = _socialStyle(i.socialKind);
    final name = i.title.split(' ').first;
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FanAvatar(
            name: name,
            seed: i.actorId,
            size: 40,
            imageUrl: FanZoneService.avatarUrl(i.actorId, i.avatarAt),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Ui.bg, width: 2),
              ),
              child: Icon(icon, size: 11, color: Ui.text),
            ),
          ),
        ],
      ),
    );
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
            if (i.kind == InboxKind.social)
              _socialLeading(i)
            else
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

  @override
  Widget build(BuildContext context) {
    // One mixed list ordered by time (no section-by-section grouping).
    // Past items: newest first. Upcoming items (e.g. a kick-off in 2h) are
    // placed by how close they are to now, so they blend in with the rest.
    final now = DateTime.now().millisecondsSinceEpoch;
    int rank(InboxItem i) {
      final t = i.at?.millisecondsSinceEpoch;
      if (t == null) return -1 << 52; // undated items go last
      return t <= now ? t : now - (t - now);
    }

    final sorted = [..._items]..sort((a, b) => rank(b).compareTo(rank(a)));
    final children = <Widget>[...sorted.map(_tile)];
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
                            'New followers, likes, comments, live matches, highlights and results will show up here.',
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
/// While something is unread the bell gives a little ring every few seconds
/// and shows the number (99+ at most) so missed notifications get noticed.
class NotificationBell extends StatefulWidget {
  final String? label;

  /// Drawn as a small round button (like the Live header's other buttons).
  final bool round;
  const NotificationBell({super.key, this.label, this.round = false});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    NotificationCenter.instance.unread.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    if (NotificationCenter.instance.unread.value > 0) {
      if (_timer == null) {
        _timer = Timer.periodic(const Duration(seconds: 8), (_) {
          if (mounted) _ring.forward(from: 0);
        });
        _ring.forward(from: 0);
      }
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    NotificationCenter.instance.unread.removeListener(_sync);
    _timer?.cancel();
    _ring.dispose();
    super.dispose();
  }

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
      final label = widget.label;
      final bell = AnimatedBuilder(
        animation: _ring,
        builder: (_, child) {
          final t = _ring.value;
          // Quick left-right swing that settles.
          final angle = math.sin(t * math.pi * 7) * 0.38 * (1 - t);
          return Transform.rotate(
            angle: n > 0 ? angle : 0,
            alignment: Alignment.topCenter,
            child: child,
          );
        },
        child: Icon(
          n > 0
              ? Icons.notifications_active_rounded
              : Icons.notifications_none_rounded,
          size: widget.round ? 19 : (label == null ? null : 24),
          color: n > 0 ? Ui.red : null,
        ),
      );
      final icon = Badge(
        isLabelVisible: n > 0,
        label: Text(
          n > 99 ? '99+' : '$n',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Ui.red,
        textColor: Ui.palette.onAccent,
        child: bell,
      );
      if (widget.round) {
        return Padding(
          padding: const EdgeInsets.only(left: 5),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Material(
              color: Colors.white.withValues(alpha: .06),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: n > 0 ? '$n new notifications' : 'Notifications',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                onPressed: () => _open(context),
                icon: icon,
              ),
            ),
          ),
        );
      }
      if (label == null) {
        return IconButton(
          tooltip: n > 0 ? '$n new notifications' : 'Notifications',
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
                label,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: n > 0 ? Ui.red : null,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
