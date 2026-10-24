import 'dart:async';

import 'package:flutter/material.dart';

import '../models/fixture.dart';
import '../services/content_sync.dart';
import '../services/fan_zone_service.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';
import 'highlights_screen.dart';

String _error(Object e) => e.toString().replaceFirst('Exception: ', '');
String _date(DateTime value) {
  final d = value.toLocal();
  return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

class FanZoneScreen extends StatefulWidget {
  final bool active;
  const FanZoneScreen({super.key, required this.active});
  @override
  State<FanZoneScreen> createState() => _FanZoneScreenState();
}

class _FanZoneScreenState extends State<FanZoneScreen>
    with WidgetsBindingObserver {
  final _feed = FeedService();
  List<Fixture> _fixtures = [];
  Map<String, dynamic> _data = {};
  String? _failure;
  bool _busy = false;
  bool _saving = false;
  bool _foreground = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ContentSync.tick.addListener(_sync);
    if (widget.active) _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _sync());
  }

  @override
  void didUpdateWidget(covariant FanZoneScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _sync();
  }

  void _sync() {
    if (widget.active && _foreground) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ContentSync.tick.removeListener(_sync);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Load independently so fixture viewing still works during backend setup.
      final fixtures = await _feed.loadFixtures(remote: true);
      if (!mounted) return;
      setState(() => _fixtures = sortFixtures(fixtures, DateTime.now()));
      final data = await FanZoneService.call('state');
      if (mounted)
        setState(() {
          _data = data;
          _failure = null;
        });
    } catch (e) {
      if (mounted) setState(() => _failure = _error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notice(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _profile() async {
    final input = TextEditingController(text: (_data['name'] ?? '').toString());
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your Fan Zone nickname'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: input,
              maxLength: 30,
              autofocus: true,
              decoration: const InputDecoration(hintText: '3–30 characters'),
            ),
            const Text(
              'Your name and rank are public. This profile stays on this device; clearing app data removes access to it.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().length >= 3)
                Navigator.pop(ctx, input.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // The route may still be animating out; do not dispose its input mid-frame.
    Future<void>.delayed(const Duration(seconds: 1), input.dispose);
    if (name == null || !mounted) return false;
    try {
      await FanZoneService.call('profile', body: {'name': name});
      if (!mounted) return false;
      setState(() => _data['name'] = name);
      await _refresh();
      return true;
    } catch (e) {
      _notice(_error(e));
      return false;
    }
  }

  Future<void> _pick(Fixture f) async {
    if (_saving) return;
    if ((_data['name'] ?? '').toString().isEmpty && !await _profile()) return;
    if (!mounted) return;
    final key = FanZoneService.matchKey(f);
    final picks = FanZoneService.rows(_data['picks']);
    final old = picks.where((p) => p['match_key'] == key).firstOrNull;
    var home = (old?['home'] as num?)?.toInt() ?? 0;
    var away = (old?['away'] as num?)?.toInt() ?? 0;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(f.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Predict the final score. Picks lock at kickoff.'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: home,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: f.home),
                      items: List.generate(
                        21,
                        (n) => DropdownMenuItem(value: n, child: Text('$n')),
                      ),
                      onChanged: (n) => update(() => home = n ?? 0),
                    ),
                  ),
                  const Padding(padding: EdgeInsets.all(12), child: Text('–')),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: away,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: f.away),
                      items: List.generate(
                        21,
                        (n) => DropdownMenuItem(value: n, child: Text('$n')),
                      ),
                      onChanged: (n) => update(() => away = n ?? 0),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save prediction'),
            ),
          ],
        ),
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await FanZoneService.call(
        'pick',
        body: {'key': key, 'home': home, 'away': away},
      );
      await _refresh();
      _notice('Prediction saved. Good luck!');
    } catch (e) {
      _notice(_error(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _discussion(String room, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FanDiscussion(
          room: room,
          title: title,
          name: (_data['name'] ?? '').toString(),
          onJoin: _profile,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Fan Zone'),
          actions: [
            IconButton(
              tooltip: 'Highlights',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const HighlightsScreen(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Your nickname',
              icon: const Icon(Icons.person_outline),
              onPressed: _profile,
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Predict'),
              Tab(text: 'Rankings'),
              Tab(text: 'Banter'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            if (_failure != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _failure!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [_predictions(), _rankings(), _banter()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(Widget child) => Card(
    color: Ui.card,
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
  Widget _predictions() {
    final picks = FanZoneService.rows(_data['picks']);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _panel(
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Know football? Prove it.',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Exact score: 3 points • Correct winner or draw: 1 point\nFree points and bragging rights. Weekly rankings reset Monday at 00:00 UTC.',
                ),
              ],
            ),
          ),
          if (_fixtures.isEmpty && !_busy)
            const Text('No fixtures available. Pull down to refresh.'),
          for (final f in _fixtures) _fixture(f, picks),
          if (picks.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Your prediction history',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
            ),
            for (final p in picks)
              _panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p['title']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('Your pick: ${p['home']} – ${p['away']}'),
                    Text(
                      p['result_home'] == null
                          ? 'Awaiting confirmed result'
                          : 'Final: ${p['result_home']} – ${p['result_away']} • ${_points(p)} points',
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  int _points(Map<String, dynamic> p) =>
      p['home'] == p['result_home'] && p['away'] == p['result_away']
      ? 3
      : ((p['home'] as num) - (p['away'] as num)).sign ==
            ((p['result_home'] as num) - (p['result_away'] as num)).sign
      ? 1
      : 0;
  Widget _fixture(Fixture f, List<Map<String, dynamic>> picks) {
    final key = FanZoneService.matchKey(f);
    final pick = picks.where((p) => p['match_key'] == key).firstOrNull;
    final open = DateTime.now().isBefore(f.kickoff);
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            f.league,
            style: TextStyle(color: Ui.red, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            f.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text('${_date(f.kickoff)} • Your local time'),
          if (pick != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Your pick: ${pick['home']} – ${pick['away']}'),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: open && !_saving && _failure == null
                    ? () => _pick(f)
                    : null,
                icon: Icon(open ? Icons.sports_soccer : Icons.lock_outline),
                label: Text(
                  open
                      ? (pick == null ? 'Predict score' : 'Edit prediction')
                      : 'Picks locked',
                ),
              ),
              TextButton.icon(
                onPressed: () => _discussion(key, f.title),
                icon: const Icon(Icons.forum_outlined),
                label: const Text('Discuss'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rankings() {
    final rows = FanZoneService.rows(_data['leaderboard']);
    final myId = _data['id'];
    final rank = rows.indexWhere((r) => r['id'] == myId);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.emoji_events_outlined, size: 40),
                const Text(
                  'Weekly top 100',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text(
                  rank < 0
                      ? 'Your rank appears after a confirmed result puts you in the top 100.'
                      : 'You are #${rank + 1} this week!',
                ),
                const Text(
                  'Ranked by points, then fewer settled picks. Nicknames may be shared; the short ID identifies each fan.',
                ),
              ],
            ),
          ),
          if (rows.isEmpty)
            const Text(
              'No confirmed results this week yet. Make your picks to join the competition.',
            ),
          for (var i = 0; i < rows.length; i++)
            _panel(
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(
                  '#${i + 1}',
                  style: TextStyle(color: Ui.red, fontSize: 20),
                ),
                title: Text(
                  '${rows[i]['name']}${rows[i]['id'] == myId ? ' (you)' : ''}',
                ),
                subtitle: Text(
                  'Fan ${rows[i]['id'].toString().substring(0, 6)} • ${rows[i]['played']} settled picks',
                ),
                trailing: Text(
                  '${rows[i]['points']} pts',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _banter() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The Deeprowss fan lounge',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Football gist, friendly rivalries and match reactions. Keep it respectful. Report abuse and block fans from a message menu.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _discussion('lounge', 'Fan lounge'),
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Join the conversation'),
            ),
          ],
        ),
      ),
      const Text(
        'Match discussions',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
      ),
      for (final f in _fixtures)
        ListTile(
          title: Text(f.title),
          subtitle: Text(f.league),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _discussion(FanZoneService.matchKey(f), f.title),
        ),
    ],
  );
}

class _FanDiscussion extends StatefulWidget {
  final String room, title, name;
  final Future<bool> Function() onJoin;
  const _FanDiscussion({
    required this.room,
    required this.title,
    required this.name,
    required this.onJoin,
  });
  @override
  State<_FanDiscussion> createState() => _FanDiscussionState();
}

class _FanDiscussionState extends State<_FanDiscussion>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  Set<String> _blocked = {};
  String? _failure;
  bool _loading = false, _sending = false, _joined = false, _foreground = true;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    _joined = widget.name.isNotEmpty;
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_foreground) _refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final blocked = await FanZoneService.blocked();
      final data = await FanZoneService.call(
        'messages',
        query: {'room': widget.room},
      );
      if (mounted)
        setState(() {
          _messages = FanZoneService.rows(data['messages']);
          _blocked = blocked;
          _failure = null;
        });
    } catch (e) {
      if (mounted) setState(() => _failure = _error(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send() async {
    if (_sending || _input.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await FanZoneService.call(
        'message',
        body: {'room': widget.room, 'text': _input.text.trim()},
      );
      if (!mounted) return;
      _input.clear();
      await _refresh();
    } catch (e) {
      _notice(_error(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _action(String action, Map<String, dynamic> message) async {
    try {
      if (action == 'block') {
        await FanZoneService.block(message['user_id'].toString());
        if (mounted)
          setState(() => _blocked.add(message['user_id'].toString()));
        _notice('Fan blocked on this device.');
      } else {
        if (!_joined) {
          if (!await widget.onJoin()) return;
          if (mounted) setState(() => _joined = true);
        }
        await FanZoneService.call(
          'report',
          body: {'id': message['id'], 'reason': 'Inappropriate content'},
        );
        _notice('Report sent for review.');
      }
    } catch (e) {
      _notice(_error(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _messages
        .where((m) => !_blocked.contains(m['user_id']))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Unblock all fans',
            icon: const Icon(Icons.person_add_alt),
            onPressed: () async {
              await FanZoneService.unblockAll();
              if (mounted) setState(() => _blocked = {});
            },
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Friendly banter only. Use ⋮ to report abuse or block a fan.',
              ),
            ),
            if (_failure != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_failure!),
              ),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        _loading
                            ? 'Loading discussion…'
                            : 'Start the conversation!',
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final m = visible[visible.length - 1 - i];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: ListTile(
                            title: Text(
                              '${m['name']} #${m['user_id'].toString().substring(0, 6)} • ${_date(DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()))}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${m['text']}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 15,
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (a) => _action(a, m),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'report',
                                  child: Text('Report abuse'),
                                ),
                                PopupMenuItem(
                                  value: 'block',
                                  child: Text('Block fan'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (!_joined)
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () async {
                    if (await widget.onJoin() && mounted)
                      setState(() => _joined = true);
                  },
                  child: const Text('Choose nickname to join'),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        maxLength: 300,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Share your football gist…',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _sending ? null : _send,
                      icon: Icon(_sending ? Icons.hourglass_top : Icons.send),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
