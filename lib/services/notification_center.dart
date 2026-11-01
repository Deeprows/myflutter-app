import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/fixture.dart';
import 'fan_zone_service.dart';
import 'feed_service.dart';

/// What an inbox entry is about (also decides its icon, colour and section).
enum InboxKind { live, highlight, movie, trending, result }

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

  const InboxItem({
    required this.id,
    required this.kind,
    required this.title,
    this.body = '',
    this.at,
    this.fixture,
    this.ref = '',
  });
}

/// Builds the notification inbox from the same feeds the app already uses:
/// live matches and kick-offs, new highlights, latest movies, trending
/// hashtags and the weekly prediction winners. Nothing extra is needed on the
/// server. [unread] drives the badge on the bell icon.
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
  List<InboxItem> _last = const [];

  Future<Set<String>> _seen() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_seenKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      return (jsonDecode(raw) as List).map((e) => '$e').toSet();
    } catch (_) {
      return <String>{};
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
      await Future.wait([_loadTrending(), _loadResults()]);
    }
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
        !(i.kind == InboxKind.live && i.id.endsWith(':later')));
    unread.value = fresh.length;
  }

  /// Quick badge update without opening the inbox (cached feeds only).
  Future<void> refreshBadge() async {
    try {
      await load();
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
