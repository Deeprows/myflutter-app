import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/fan_prediction.dart';
import '../models/fixture.dart';
import 'fan_zone_service.dart';
import 'auth_service.dart';
import 'content_sync.dart';
import 'feed_service.dart';
import 'native_notifier.dart';
import 'push_service.dart';

/// What an inbox entry is about (also decides its icon, colour and section).
enum InboxKind { social, prediction, live, highlight, movie, trending, result }

/// One line in the in-app notification inbox.
class InboxItem {
  /// Stable id: the same thing keeps the same id, so "unread" survives restarts.
  final String id;
  final InboxKind kind;
  final String title;
  final String body;
  final DateTime? at;

  /// Live/upcoming matches carry the fixture so a tap can open that match.
  final Fixture? fixture;

  /// Highlight / movie link, or the hashtag, depending on [kind].
  final String ref;

  /// Social entries only: `follow`, `like` or `comment`, the fan who did it,
  /// the post it happened on and that fan's picture version.
  final String socialKind;
  final String actorId;
  final String postId;
  final Object? avatarAt;

  const InboxItem({
    required this.id,
    required this.kind,
    required this.title,
    this.body = '',
    this.at,
    this.fixture,
    this.ref = '',
    this.socialKind = '',
    this.actorId = '',
    this.postId = '',
    this.avatarAt,
  });
}

/// Builds the notification inbox from the same feeds the app already uses:
/// live matches and kick-offs, new highlights, latest movies, trending
/// hashtags and the weekly prediction winners, plus the fan's own activity
/// (new followers, likes and comments, from the Fan Zone server).
/// [unread] drives the badge on the bell icon; [start] keeps it fresh.
class NotificationCenter {
  NotificationCenter._();
  static final NotificationCenter instance = NotificationCenter._();

  static const _seenKey = 'inbox_seen_ids';
  static const _maxSeen = 400;

  final ValueNotifier<int> unread = ValueNotifier<int>(0);
  final _feed = FeedService();

  // Network parts are remembered for the session so the badge can count them.
  List<InboxItem> _trending = const [];
  List<InboxItem> _results = const [];
  List<InboxItem> _predictions = const [];
  DateTime _picksCheckedAt = DateTime.fromMillisecondsSinceEpoch(0);
  List<InboxItem> _last = const [];

  // Followers / likes / comments on this fan's posts.
  List<InboxItem> _social = const [];
  DateTime _socialAt = DateTime.fromMillisecondsSinceEpoch(0);
  Set<String> _socialReadIds = <String>{};
  static const _socialNotifiedKey = 'social_notified';

  Timer? _timer;
  bool _started = false;
  bool _foreground = true;

  Future<Set<String>> _seen() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_seenKey);
    if (raw == null || raw.isEmpty) return {..._socialReadIds};
    try {
      return {
        ...(jsonDecode(raw) as List).map((e) => '$e'),
        ..._socialReadIds,
      };
    } catch (_) {
      return {..._socialReadIds};
    }
  }

  // ------------------------------------------------------ follows, likes...

  /// Keeps the bell up to date while the app is open: every minute or so, when
  /// the app comes back to the foreground, when new content arrives and when
  /// a push is received. Safe to call more than once.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(_Lifecycle(this));
    _timer = Timer.periodic(const Duration(seconds: 75), (_) => poll());
    ContentSync.tick.addListener(() => refreshBadge());
    AuthService.instance.addListener(_onAuthChanged);
    unawaited(refreshBadge());
  }

  void _onAuthChanged() {
    _social = const [];
    _socialReadIds = <String>{};
    _socialAt = DateTime.fromMillisecondsSinceEpoch(0);
    _last = _last.where((e) => e.kind != InboxKind.social).toList();
    unawaited(refreshBadge());
  }

  /// Cheap check for new follows / likes / comments (one small request).
  Future<void> poll() async {
    if (!_foreground) return;
    try {
      await _loadSocial(force: true);
      _last = [..._social, ..._last.where((e) => e.kind != InboxKind.social)];
      await _refreshBadge(_last);
      unawaited(PushService.instance.registerDevice());
      unawaited(_alertNew());
    } catch (_) {}
  }

  Future<void> _loadSocial({bool force = false}) async {
    if (!AuthService.instance.signedIn) {
      _social = const [];
      _socialReadIds = <String>{};
      return;
    }
    if (!force &&
        DateTime.now().difference(_socialAt) < const Duration(seconds: 30)) {
      return;
    }
    _socialAt = DateTime.now();
    try {
      final data = await FanZoneService.call('social/notifications');
      final readAt = (data['read_at'] as num?)?.toInt() ?? 0;
      final items = <InboxItem>[];
      final read = <String>{};
      for (final n in FanZoneService.rows(data['notifications'])) {
        final id = 'soc:${n['id']}';
        final atMs = (n['at'] as num?)?.toInt() ?? 0;
        final kind = '${n['kind']}';
        final name = '${n['actor_name'] ?? ''}'.trim();
        final who = name.isEmpty ? 'Someone' : name;
        final (title, body) = switch (kind) {
          'follow' => ('$who started following you', 'Tap to view their profile'),
          'like' => ('$who liked your post', 'Tap to open the post'),
          _ => ('$who commented on your post', '${n['text'] ?? ''}'),
        };
        if (atMs <= readAt) read.add(id);
        items.add(InboxItem(
          id: id,
          kind: InboxKind.social,
          title: title,
          body: body,
          at: DateTime.fromMillisecondsSinceEpoch(atMs),
          socialKind: kind,
          actorId: '${n['actor_id'] ?? ''}',
          postId: '${n['post_id'] ?? ''}',
          avatarAt: n['avatar_at'],
        ));
      }
      _social = items;
      _socialReadIds = read;
    } catch (_) {
      // Offline: keep what we already have.
    }
  }

  /// A push for this entry was already drawn by Firebase, so the in-app
  /// fallback below must not draw it a second time.
  Future<void> markNotified(String nid) async {
    if (nid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getStringList(_socialNotifiedKey) ?? <String>[];
      if (!done.contains('soc:$nid')) done.add('soc:$nid');
      await prefs.setStringList(_socialNotifiedKey, _trim(done));
    } catch (_) {}
  }

  static List<String> _trim(List<String> l) =>
      l.length > 200 ? l.sublist(l.length - 200) : l;

  /// Fallback "outside the app" alert while the app is open but Firebase
  /// push did not deliver (for example the server has no push key yet).
  /// Entries younger than 30 seconds are left alone so a real push can win.
  Future<void> _alertNew() async {
    if (!_foreground || _social.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final first = !prefs.containsKey(_socialNotifiedKey);
    final done = (prefs.getStringList(_socialNotifiedKey) ?? <String>[]);
    if (first) {
      // Existing history is not news: remember it silently.
      await prefs.setStringList(
        _socialNotifiedKey,
        _trim(_social.map((e) => e.id).toList()),
      );
      return;
    }
    final seen = await _seen();
    final now = DateTime.now();
    final fresh = _social.where((i) {
      if (seen.contains(i.id) || done.contains(i.id)) return false;
      final at = i.at;
      return at != null &&
          now.difference(at) > const Duration(seconds: 30) &&
          now.difference(at) < const Duration(hours: 1);
    }).toList();
    if (fresh.isEmpty) return;
    for (final i in fresh) {
      done.add(i.id);
    }
    await prefs.setStringList(_socialNotifiedKey, _trim(done));
    for (final i in fresh.take(3)) {
      unawaited(NativeNotifier.show(
        title: i.title,
        body: i.body,
        channel: 'social',
        payload: jsonEncode({
          'type': 'social',
          'kind': i.socialKind,
          'postId': i.postId,
          'actorId': i.actorId,
        }),
      ));
    }
  }

  /// Everything currently worth showing, newest / most relevant first inside
  /// each kind. [network] also asks the server for trending tags and results.
  Future<List<InboxItem>> load({bool network = false}) async {
    final now = DateTime.now();
    final items = <InboxItem>[];

    // ---- Live matches, kick-offs and what is coming up ---------------------
    try {
      final fixtures = await _feed.loadFixtures();
      final live = <Fixture>[];
      final soon = <Fixture>[];
      final later = <Fixture>[];
      for (final f in fixtures) {
        switch (f.phaseAt(now)) {
          case MatchPhase.live:
            live.add(f);
          case MatchPhase.upcoming:
            final mins = f.kickoff.difference(now).inMinutes;
            if (mins <= 60) {
              soon.add(f);
            } else if (mins <= 24 * 60) {
              later.add(f);
            }
          case MatchPhase.ended:
            break;
        }
      }
      soon.sort((a, b) => a.kickoff.compareTo(b.kickoff));
      later.sort((a, b) => a.kickoff.compareTo(b.kickoff));
      for (final f in live) {
        items.add(InboxItem(
          id: 'live:${f.id}:${f.kickoff.millisecondsSinceEpoch}:on',
          kind: InboxKind.live,
          title: '⚽ Kick-off! ${f.title} is live',
          body: f.league.isEmpty ? 'Tap to watch now' : '${f.league} • Tap to watch now',
          at: f.kickoff,
          fixture: f,
        ));
      }
      for (final f in soon) {
        final mins = f.kickoff.difference(now).inMinutes.clamp(1, 60);
        items.add(InboxItem(
          id: 'live:${f.id}:${f.kickoff.millisecondsSinceEpoch}:soon',
          kind: InboxKind.live,
          title: '⏰ ${f.title} kicks off in $mins min',
          body: f.league,
          at: f.kickoff,
          fixture: f,
        ));
      }
      for (final f in later.take(6)) {
        items.add(InboxItem(
          id: 'live:${f.id}:${f.kickoff.millisecondsSinceEpoch}:later',
          kind: InboxKind.live,
          title: f.title,
          body: '${f.league.isEmpty ? 'Match' : f.league} • ${_clock(f.kickoff.toLocal())}',
          at: f.kickoff,
          fixture: f,
        ));
      }
    } catch (_) {}

    // ---- Newest highlights --------------------------------------------------
    try {
      final all = await _feed.loadHighlights();
      final list = [...all]..sort((a, b) =>
          (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));
      for (final h in list.take(5)) {
        items.add(InboxItem(
          id: 'hl:${h.url}',
          kind: InboxKind.highlight,
          title: h.name,
          body: 'New match highlights',
          at: h.date,
          ref: h.url,
        ));
      }
    } catch (_) {}

    // ---- Latest movies -----------------------------------------------------
    try {
      final all = await _feed.loadMovies();
      final list = all.where((m) => m.name.trim().isNotEmpty).toList()
        ..sort((a, b) =>
            (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));
      for (final m in list.take(5)) {
        items.add(InboxItem(
          id: 'mv:${m.url}',
          kind: InboxKind.movie,
          title: m.name,
          body: 'New movie added',
          at: m.date,
          ref: m.url,
        ));
      }
    } catch (_) {}

    // ---- Trending hashtags + weekly prediction results ----------------------
    if (network) {
      await Future.wait([_loadTrending(), _loadResults(), checkPredictions(force: true)]);
    }
    items.insertAll(0, _predictions);
    await _loadSocial(force: network);
    items.insertAll(0, _social);
    items.addAll(_trending);
    items.addAll(_results);

    _last = items;
    await _refreshBadge(items);
    return items;
  }

  Future<void> _loadTrending() async {
    try {
      final data = await FanZoneService.call('social/trending');
      final week = _weekStamp(DateTime.now());
      final tags = FanZoneService.rows(data['tags']).take(5).toList();
      _trending = [
        for (var i = 0; i < tags.length; i++)
          if ('${tags[i]['tag'] ?? ''}'.isNotEmpty)
            InboxItem(
              id: 'tag:${tags[i]['tag']}:$week',
              kind: InboxKind.trending,
              title: '${tags[i]['tag']}',
              body: '#${i + 1} trending'
                  '${tags[i]['posts'] != null ? ' • ${tags[i]['posts']} posts' : ''}',
              ref: '${tags[i]['tag']}',
            ),
      ];
    } catch (_) {}
  }

  Future<void> _loadResults() async {
    try {
      final data = await FanZoneService.call('state');
      final weeks = FanZoneService.rows(data['winners']);
      if (weeks.isEmpty) return;
      final w = weeks.first;
      final winners = FanZoneService.rows(w['winners']);
      if (winners.isEmpty) return;
      final ms = (w['week'] as num?)?.toInt() ?? 0;
      final names = winners
          .take(3)
          .map((e) => '${e['rank']}. ${e['name']} (${e['points']} pts)')
          .join('  ');
      _results = [
        InboxItem(
          id: 'win:$ms',
          kind: InboxKind.result,
          title: '🏆 Weekly prediction results are out',
          body: names,
          at: ms > 0
              ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal()
              : null,
        ),
      ];
    } catch (_) {}
  }

  Future<void> _refreshBadge([List<InboxItem>? items]) async {
    final seen = await _seen();
    final list = items ?? _last;
    // Matches further ahead than an hour are only a heads-up, not "new".
    final fresh = list.where((i) =>
        !seen.contains(i.id) &&
        !(i.kind == InboxKind.live && i.id.endsWith(':later')) &&
        !(i.kind == InboxKind.prediction &&
            (i.id.endsWith(':saved') || i.id.endsWith(':wait'))));
    unread.value = fresh.length;
  }

  /// Quick badge update without opening the inbox (cached feeds only).
  Future<void> refreshBadge() async {
    try {
      await checkPredictions();
      await load();
    } catch (_) {}
  }

  static const _notifiedKey = 'pred_result_notified';

  /// Reads the user's predictions (this also makes the server check ESPN for
  /// finished matches), lists them in the inbox and shows a phone notification
  /// once for each prediction that has just been settled.
  Future<void> checkPredictions({bool force = false}) async {
    if (!AuthService.instance.signedIn) return;
    final waiting = _predictions.any((e) => e.ref == 'pending');
    final every = waiting || _predictions.isEmpty
        ? const Duration(minutes: 3)
        : const Duration(minutes: 20);
    if (!force && DateTime.now().difference(_picksCheckedAt) < every) return;
    _picksCheckedAt = DateTime.now();
    try {
      final data = await FanZoneService.call('state');
      final picks = FanZoneService.rows(data['picks']);
      final cutoff = DateTime.now().subtract(const Duration(days: 4));
      final prefs = await SharedPreferences.getInstance();
      final notified = (prefs.getStringList(_notifiedKey) ?? <String>[]).toSet();
      final items = <InboxItem>[];
      for (final p in picks) {
        final ko = DateTime.fromMillisecondsSinceEpoch(
          ((p['kickoff'] as num?) ?? 0).toInt(),
        );
        if (ko.isBefore(cutoff)) continue;
        final key = '${p['match_key']}';
        final title = '${p['title']}';
        final mine = fanPredictionLabel(p);
        final pts = fanPredictionScore(p);
        final settled = p['result_home'] != null;
        if (!settled) {
          // Only matches that have already kicked off are "waiting".
          if (ko.isAfter(DateTime.now())) {
            items.add(InboxItem(
              id: 'pick:$key:saved',
              kind: InboxKind.prediction,
              title: '🗳️ Prediction saved: $title',
              body: 'Your pick: $mine',
              at: ko,
              ref: 'upcoming',
            ));
          } else {
            items.add(InboxItem(
              id: 'pick:$key:wait',
              kind: InboxKind.prediction,
              title: '⏳ Waiting for the final score: $title',
              body: 'Your pick: $mine. Verified with ESPN, then added to Ranks.',
              at: ko,
              ref: 'pending',
            ));
          }
          continue;
        }
        final score = '${p['result_home']}–${p['result_away']}';
        final head = switch (pts) {
          3 => '🎯 Exact score! +3 points',
          1 => '✅ Correct! +1 point',
          0 => '❌ Missed, 0 points',
          _ => '↩️ Refunded (push)',
        };
        items.add(InboxItem(
          id: 'pick:$key:done',
          kind: InboxKind.prediction,
          title: '$head: $title',
          body: 'Final score $score. Your pick: $mine. Ranks updated.',
          at: ko,
          ref: 'done',
        ));
        if (!notified.contains(key)) {
          notified.add(key);
          unawaited(NativeNotifier.show(
            title: head,
            body: '$title finished $score. Your pick: $mine.',
            channel: 'content',
            payload: '{}',
          ));
        }
      }
      items.sort((a, b) => (b.at ?? DateTime(2000)).compareTo(a.at ?? DateTime(2000)));
      _predictions = items;
      final keep = notified.toList();
      await prefs.setStringList(
        _notifiedKey,
        keep.length > 200 ? keep.sublist(keep.length - 200) : keep,
      );
    } catch (_) {}
  }

  /// Called when the inbox is opened: everything shown counts as read.
  Future<void> markAllSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = await _seen();
    final merged = <String>[...seen, ..._last.map((e) => e.id)];
    final unique = merged.toSet().toList();
    final kept = unique.length > _maxSeen
        ? unique.sublist(unique.length - _maxSeen)
        : unique;
    await prefs.setString(_seenKey, jsonEncode(kept));
    unread.value = 0;
    if (AuthService.instance.signedIn && _social.isNotEmpty) {
      _socialReadIds = {..._socialReadIds, ..._social.map((e) => e.id)};
      unawaited(
        FanZoneService.call('social/notifications-read', body: {})
            .then<void>((_) {}, onError: (_) {}),
      );
    }
  }

  Future<bool> isUnread(String id) async => !(await _seen()).contains(id);

  /// Ids already read when the inbox was opened (kept so the screen can still
  /// show which lines were new this time).
  Future<Set<String>> seenIds() => _seen();

  static String _weekStamp(DateTime d) {
    final start = DateTime(d.year, 1, 1);
    final week = (d.difference(start).inDays / 7).floor();
    return '${d.year}-$week';
  }

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }
}

/// Tells [NotificationCenter] when the app goes to / comes back from the
/// background, so it refreshes the bell right when the user returns.
class _Lifecycle with WidgetsBindingObserver {
  final NotificationCenter _center;
  _Lifecycle(this._center);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _center._foreground = state == AppLifecycleState.resumed;
    if (_center._foreground) unawaited(_center.refreshBadge());
  }
}
