import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../models/fixture.dart';
import '../../models/cast_target.dart';
import '../../theme/app_theme.dart';
import 'decoder_common.dart';
import 'decoder_flows.dart';

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
      _fixtures = sortFixtures(parsed, _now);
      _loading = false;
      if (parsed.isEmpty) _error = 'No decoder fixtures are available yet.';
    });
  }

  Future<void> _cast(Fixture fixture, String url, String label) async {
    final clean = url.trim();
    if (clean.isEmpty) {
      decoderToast(context, '$label is not available for this match.');
      return;
    }
    await chooseConnectivity(context, CastTarget(title: fixture.title + ' · ' + label, url: clean));
  }

  String _status(Fixture f) {
    switch (f.phaseAt(_now)) {
      case MatchPhase.live:
        final elapsed = _now.difference(f.kickoff);
        final minute = elapsed.isNegative ? 0 : elapsed.inMinutes;
        return 'LIVE · $minute min';
      case MatchPhase.upcoming:
        final d = f.kickoff.difference(_now);
        if (d.inDays > 0) return 'Starts in ' + d.inDays.toString() + 'd ' + d.inHours.remainder(24).toString() + 'h';
        if (d.inHours > 0) return 'Starts in ' + d.inHours.toString() + 'h ' + d.inMinutes.remainder(60).toString() + 'm';
        return 'Starts in ' + d.inMinutes.toString() + 'm';
      case MatchPhase.ended:
        return 'FULL TIME';
    }
  }

  Widget _team(String name, String logo, {required bool right}) {
    final logoUrl = RegExp(r'^\d+$').hasMatch(logo)
        ? 'https://media.api-sports.io/football/teams/$logo.png'
        : (logo.startsWith('http') ? logo : '');
    return Expanded(child: Column(
      crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          width: 34, height: 34, padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .06),
            shape: BoxShape.circle, border: Border.all(color: Ui.line)),
          child: logoUrl.isEmpty
              ? Icon(Icons.sports_soccer_rounded, color: Ui.muted, size: 19)
              : ClipOval(child: Image.network(logoUrl, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(Icons.sports_soccer_rounded, color: Ui.muted, size: 19))),
        ),
        const SizedBox(height: 4),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          textAlign: right ? TextAlign.end : TextAlign.start,
          style: TextStyle(color: Ui.text, fontSize: 12, fontWeight: FontWeight.w800)),
      ],
    ));
  }

  Widget _streamButton(Fixture f, String url, String label, {required bool primary}) {
    final enabled = url.trim().isNotEmpty;
    return Expanded(child: SizedBox(height: 37, child: primary
      ? FilledButton.icon(
          onPressed: enabled ? () => _cast(f, url, label) : null,
          icon: const Icon(Icons.cast_rounded, size: 16),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          style: FilledButton.styleFrom(backgroundColor: Ui.red, disabledBackgroundColor: Ui.panel,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
        )
      : OutlinedButton.icon(
          onPressed: enabled ? () => _cast(f, url, label) : null,
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          style: OutlinedButton.styleFrom(foregroundColor: Ui.text, disabledForegroundColor: Ui.dim,
            side: BorderSide(color: Ui.line), padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
        )));
  }

  Widget _card(Fixture f) {
    final phase = f.phaseAt(_now);
    final live = phase == MatchPhase.live;
    final ended = phase == MatchPhase.ended;
    final local = f.kickoff.toLocal();
    final time = TimeOfDay.fromDateTime(local).format(context);
    final date = local.day.toString().padLeft(2, '0') + '/' + local.month.toString().padLeft(2, '0');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(color: Ui.cardDeep, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: live ? Ui.red.withValues(alpha: .8) : Ui.line),
        boxShadow: live ? [BoxShadow(color: Ui.red.withValues(alpha: .12), blurRadius: 10)] : null),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(f.league.isEmpty ? 'FOOTBALL' : f.league.toUpperCase(),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Ui.muted, fontSize: 9, letterSpacing: .65, fontWeight: FontWeight.w800))),
          if (live) FadeTransition(opacity: Tween<double>(begin: .25, end: 1).animate(_blink),
            child: const Icon(Icons.circle, color: Colors.redAccent, size: 9)),
          if (live) const SizedBox(width: 5),
          Text(_status(f), style: TextStyle(color: live ? Colors.redAccent : ended ? Ui.dim : Ui.redSoft,
            fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: .3)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _team(f.home, f.homeLogo, right: false),
          SizedBox(width: 78, child: Column(children: [
            Text(time, style: TextStyle(color: Ui.text, fontSize: 14, fontWeight: FontWeight.w900)),
            const SizedBox(height: 1),
            Text(date, style: TextStyle(color: Ui.muted, fontSize: 9, fontWeight: FontWeight.w700)),
          ])),
          _team(f.away, f.awayLogo, right: true),
        ]),
        const SizedBox(height: 9),
        Row(children: [
          _streamButton(f, f.url, 'STREAM 1 · MAIN', primary: true),
          const SizedBox(width: 8),
          _streamButton(f, f.altUrl, 'STREAM 2 · BACKUP', primary: false),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ui.bg,
    appBar: AppBar(
      backgroundColor: Ui.panel,
      title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Live Events', style: TextStyle(fontWeight: FontWeight.w900)),
        Text('Choose a stream and cast to your screen', style: TextStyle(fontSize: 10, color: Colors.white60)),
      ]),
      actions: [IconButton(onPressed: _loading ? null : _load, tooltip: 'Refresh events',
        icon: const Icon(Icons.refresh_rounded))],
    ),
    body: _loading ? const Center(child: CircularProgressIndicator())
      : _fixtures.isEmpty ? Center(child: Text(_error ?? 'No fixtures found.', style: TextStyle(color: Ui.muted)))
      : RefreshIndicator(onRefresh: _load, child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(11), margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Ui.panel, borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Ui.line)),
              child: Row(children: [
                Icon(Icons.cast_connected_rounded, color: Ui.red, size: 20),
                const SizedBox(width: 9),
                Expanded(child: Text('Cast-only page. Stream 1 is the main link; use Stream 2 if it fails.',
                  style: TextStyle(color: Ui.muted, fontSize: 11, height: 1.3))),
              ]),
            ),
            for (final f in _fixtures) _card(f),
          ],
        )),
  );
}
