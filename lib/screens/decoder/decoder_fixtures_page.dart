import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../models/fixture.dart';
import '../../models/cast_target.dart';
import '../../services/stream_resolver.dart';
import '../../theme/app_theme.dart';
import 'decoder_common.dart';
import 'decoder_flows.dart';

enum _EventFilter { all, live, upcoming, ended }

/// Live Events: every match as one clean card. Tapping a card opens the cast
/// options (TV / Kodi, receiver page, mirroring, remote). The main and the
/// backup stream travel together: the main one plays, and the backup takes
/// over automatically if the main one stops.
class DecoderFixturesPage extends StatefulWidget {
  const DecoderFixturesPage({super.key});
  @override
  State<DecoderFixturesPage> createState() => _DecoderFixturesPageState();
}

class _DecoderFixturesPageState extends State<DecoderFixturesPage>
    with SingleTickerProviderStateMixin {
  static const _feedUrl = 'https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data/decoder_fixtures.json';
  List<Fixture> _fixtures = const [];
  bool _loading = true;
  String? _error;
  DateTime _now = DateTime.now();
  Timer? _clock;
  _EventFilter _filter = _EventFilter.all;
  late final AnimationController _blink = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 750),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _blink.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    List<dynamic>? raw;
    try {
      final response = await http.get(Uri.parse(_feedUrl)).timeout(const Duration(seconds: 7));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) raw = decoded;
      }
    } catch (_) {}
    if (raw == null) {
      try {
        final decoded = jsonDecode(await rootBundle.loadString('assets/data/decoder_fixtures.json'));
        if (decoded is List) raw = decoded;
      } catch (_) {}
    }
    final parsed = (raw ?? []).map(Fixture.tryParse).whereType<Fixture>().toList();
    if (!mounted) return;
    setState(() {
      _now = DateTime.now();
      _fixtures = sortFixtures(parsed, _now);
      _loading = false;
      if (parsed.isEmpty) _error = 'No live events are available yet.';
    });
  }

  /// Main stream first, then the backup. Both are sent to the screen together.
  CastTarget? _target(Fixture f) {
    final seen = <String>{};
    final urls = [f.url, f.altUrl, ...f.moreUrls]
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty && seen.add(u))
        .toList();
    if (urls.isEmpty) return null;
    CastTarget make(String u, String title) =>
        CastTarget(title: title, url: u, kind: StreamResolver.kindOfUrl(u));
    return CastTarget(
      title: f.title,
      url: urls.first,
      kind: StreamResolver.kindOfUrl(urls.first),
      backup: urls.length > 1 ? make(urls[1], '${f.title} · Backup') : null,
    );
  }

  Future<void> _open(Fixture f) async {
    final target = _target(f);
    if (target == null) {
      decoderToast(context, 'No stream is available for this match yet.');
      return;
    }
    HapticFeedback.selectionClick();
    await showCastOptions(context, target, meta: '${f.league.isEmpty ? 'Football' : f.league} · ${_status(f)}');
  }

  String _status(Fixture f) {
    switch (f.phaseAt(_now)) {
      case MatchPhase.live:
        final elapsed = _now.difference(f.kickoff);
        final minute = elapsed.isNegative ? 0 : elapsed.inMinutes;
        return 'LIVE · $minute min';
      case MatchPhase.upcoming:
        final d = f.kickoff.difference(_now);
        if (d.inDays > 0) return 'Starts in ${d.inDays}d ${d.inHours.remainder(24)}h';
        if (d.inHours > 0) return 'Starts in ${d.inHours}h ${d.inMinutes.remainder(60)}m';
        return 'Starts in ${d.inMinutes}m';
      case MatchPhase.ended:
        return 'FULL TIME';
    }
  }

  int _count(MatchPhase? p) =>
      p == null ? _fixtures.length : _fixtures.where((f) => f.phaseAt(_now) == p).length;

  bool _matches(Fixture f) {
    final p = f.phaseAt(_now);
    switch (_filter) {
      case _EventFilter.all: return true;
      case _EventFilter.live: return p == MatchPhase.live;
      case _EventFilter.upcoming: return p == MatchPhase.upcoming;
      case _EventFilter.ended: return p == MatchPhase.ended;
    }
  }

  // ------------------------------------------------------------- widgets

  Widget _crest(String logo) {
    final logoUrl = RegExp(r'^\d+$').hasMatch(logo)
        ? 'https://media.api-sports.io/football/teams/$logo.png'
        : (logo.startsWith('http') ? logo : '');
    Widget fallback() => Icon(Icons.shield_outlined, color: Ui.muted, size: 24);
    return Container(
      width: 54, height: 54, padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07), shape: BoxShape.circle,
        border: Border.all(color: Ui.line),
      ),
      child: logoUrl.isEmpty
          ? fallback()
          : Image.network(logoUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback()),
    );
  }

  Widget _team(String name, String logo) => Expanded(
        child: Column(children: [
          _crest(logo),
          const SizedBox(height: 7),
          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: TextStyle(color: Ui.text, fontSize: 13, height: 1.15, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _statusPill(Fixture f) {
    final phase = f.phaseAt(_now);
    final live = phase == MatchPhase.live;
    final ended = phase == MatchPhase.ended;
    final color = live ? Colors.redAccent : ended ? Ui.dim : Ui.redSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (live) ...[
          FadeTransition(
            opacity: Tween<double>(begin: .25, end: 1).animate(_blink),
            child: const Icon(Icons.circle, color: Colors.redAccent, size: 8),
          ),
          const SizedBox(width: 5),
        ],
        Text(_status(f), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .4)),
      ]),
    );
  }

  Widget _card(Fixture f) {
    final phase = f.phaseAt(_now);
    final live = phase == MatchPhase.live;
    final ended = phase == MatchPhase.ended;
    final hasStream = _target(f) != null;
    final local = f.kickoff.toLocal();
    final time = TimeOfDay.fromDateTime(local).format(context);
    final date = '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: ended ? .72 : 1,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color.alphaBlend(Ui.red.withValues(alpha: live ? .10 : .04), Ui.card), Ui.cardDeep],
              ),
              border: Border.all(color: live ? Ui.red.withValues(alpha: .75) : Ui.line),
              boxShadow: live ? [BoxShadow(color: Ui.red.withValues(alpha: .16), blurRadius: 16)] : null,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _open(f),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Column(children: [
                  Row(children: [
                    Icon(Icons.emoji_events_outlined, size: 14, color: Ui.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(f.league.isEmpty ? 'FOOTBALL' : f.league.toUpperCase(),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Ui.muted, fontSize: 10, letterSpacing: .8, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 8),
                    _statusPill(f),
                  ]),
                  const SizedBox(height: 14),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _team(f.home, f.homeLogo),
                    SizedBox(
                      width: 86,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(children: [
                          Text(time, style: TextStyle(color: Ui.text, fontSize: 20, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 2),
                          Text(date, style: TextStyle(color: Ui.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text('VS', style: TextStyle(color: Ui.dim, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900)),
                        ]),
                      ),
                    ),
                    _team(f.away, f.awayLogo),
                  ]),
                  const SizedBox(height: 12),
                  Container(height: 1, color: Ui.line.withValues(alpha: .7)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(hasStream ? Icons.cast_rounded : Icons.hourglass_empty_rounded,
                          size: 17, color: hasStream ? Ui.red : Ui.dim),
                      const SizedBox(width: 8),
                      Text(hasStream ? 'Tap to cast to your screen' : 'Stream coming soon',
                          style: TextStyle(
                            color: hasStream ? Ui.text : Ui.dim, fontSize: 12.5, fontWeight: FontWeight.w800)),
                      if (hasStream) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, size: 18, color: Ui.redSoft),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero() {
    final live = _count(MatchPhase.live);
    final upcoming = _count(MatchPhase.upcoming);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Ui.red.withValues(alpha: .28), Ui.card],
        ),
        border: Border.all(color: Ui.red.withValues(alpha: .35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: Ui.red, borderRadius: BorderRadius.circular(13)),
            child: Icon(Icons.cast_connected_rounded, color: Ui.palette.onAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(live > 0 ? '$live live now' : (upcoming > 0 ? '$upcoming coming up' : 'Live events'),
                  style: TextStyle(color: Ui.text, fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text('Pick a match, choose how to cast it', style: TextStyle(color: Ui.muted, fontSize: 12)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Text(
          'Both streams are sent together. The main stream plays first and the backup takes over if it stops.',
          style: TextStyle(color: Ui.muted, fontSize: 11.5, height: 1.35),
        ),
      ]),
    );
  }

  Widget _chip(String label, _EventFilter value, int count) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
        showCheckmark: false,
        label: Text('$label · $count'),
        labelStyle: TextStyle(
          color: selected ? Ui.palette.onAccent : Ui.text, fontSize: 12, fontWeight: FontWeight.w800),
        selectedColor: Ui.red,
        backgroundColor: Ui.card,
        side: BorderSide(color: selected ? Ui.red : Ui.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      ),
    );
  }

  Widget _sectionLabel(MatchPhase p) {
    final text = p == MatchPhase.live ? 'LIVE NOW' : p == MatchPhase.upcoming ? 'UPCOMING' : 'FINISHED';
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10, left: 2),
      child: Text(text, style: TextStyle(color: Ui.redSoft, fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w900)),
    );
  }

  List<Widget> _list() {
    final shown = _fixtures.where(_matches).toList();
    if (shown.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(child: Text('No matches here right now', style: TextStyle(color: Ui.muted))),
        ),
      ];
    }
    final out = <Widget>[];
    MatchPhase? last;
    for (final f in shown) {
      final p = f.phaseAt(_now);
      if (_filter == _EventFilter.all && p != last) out.add(_sectionLabel(p));
      last = p;
      out.add(_card(f));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Ui.bg,
        appBar: AppBar(
          backgroundColor: Ui.panel,
          title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Live Events', style: TextStyle(fontWeight: FontWeight.w900)),
            Text('Tap a match to cast it to your screen', style: TextStyle(fontSize: 10, color: Colors.white60)),
          ]),
          actions: [
            IconButton(
              onPressed: _loading ? null : _load,
              tooltip: 'Refresh events',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _fixtures.isEmpty
                ? Center(child: Text(_error ?? 'No live events found.', style: TextStyle(color: Ui.muted)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                      children: [
                        _hero(),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(children: [
                            _chip('All', _EventFilter.all, _count(null)),
                            _chip('Live', _EventFilter.live, _count(MatchPhase.live)),
                            _chip('Upcoming', _EventFilter.upcoming, _count(MatchPhase.upcoming)),
                            _chip('Ended', _EventFilter.ended, _count(MatchPhase.ended)),
                          ]),
                        ),
                        ..._list(),
                      ],
                    ),
                  ),
      );
}
