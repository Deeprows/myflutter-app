import 'package:flutter/material.dart';
import '../services/fan_zone_service.dart';
import '../services/content_sync.dart';
import '../theme/app_theme.dart';
import 'fan_posts_feed.dart';
import 'fan_widgets.dart';

class FanProfileScreen extends StatefulWidget {
  final String userId;
  const FanProfileScreen({super.key, required this.userId});
  @override
  State<FanProfileScreen> createState() => _FanProfileScreenState();
}

class _FanProfileScreenState extends State<FanProfileScreen> {
  Map<String, dynamic>? _profile;
  String? _error;
  bool _loading = false, _following = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted || _loading) return;
    setState(() => _loading = true);
    try {
      final data = await FanZoneService.call(
        'social/profile',
        query: {'id': widget.userId},
      );
      if (mounted)
        setState(() {
          _profile = Map<String, dynamic>.from(data['profile'] as Map);
          _error = null;
        });
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice(Object e) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
  }

  Future<void> _follow() async {
    if (_following || _profile == null) return;
    setState(() => _following = true);
    try {
      final result = await FanZoneService.call(
        'social/follow',
        body: {
          'id': widget.userId,
          'following':
              !(_profile!['followed'] == 1 || _profile!['followed'] == true),
        },
      );
      if (mounted)
        setState(() {
          _profile!['followed'] = result['following'];
          _profile!['followers'] = result['followers'];
        });
      ContentSync.request(force: true);
    } catch (e) {
      _notice(e);
    } finally {
      if (mounted) setState(() => _following = false);
    }
  }

  Future<void> _people(String type) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FanPeopleScreen(userId: widget.userId, type: type),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _edit() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditFanProfile(profile: _profile!),
    );
    if (saved == true && mounted) {
      await _load();
      ContentSync.request(force: true);
    }
  }

  Widget _header() {
    final p = _profile!, stats = Map<String, dynamic>.from(p['stats'] as Map);
    final badges = FanZoneService.rows(p['achievements']);
    final followed = p['followed'] == 1 || p['followed'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: [
                  fanColor(widget.userId).withValues(alpha: .65),
                  Ui.red.withValues(alpha: .15),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FanAvatar(name: '${p['name']}', seed: widget.userId, size: 68),
              const Spacer(),
              if (p['is_me'] == true)
                OutlinedButton(
                  onPressed: _edit,
                  child: const Text('Edit profile'),
                )
              else
                FilledButton(
                  onPressed: _following ? null : _follow,
                  child: Text(
                    _following
                        ? 'Saving…'
                        : followed
                        ? 'Following'
                        : 'Follow',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${p['name']}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          Text('@${p['handle']}', style: TextStyle(color: Ui.muted)),
          if ('${p['bio']}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('${p['bio']}', style: const TextStyle(height: 1.5)),
            ),
          if (p['joined_at'] is num)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Joined ${_joined((p['joined_at'] as num).toInt())}',
                style: TextStyle(color: Ui.muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _people('followers'),
                child: Text('${p['followers']} Followers'),
              ),
              TextButton(
                onPressed: () => _people('following'),
                child: Text('${p['following']} Following'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FanPill(text: '${stats['points']} points', color: Ui.redSoft),
              FanPill(text: '${stats['exact']} exact scores', color: Ui.green),
              FanPill(text: '${stats['settled']} settled', color: Ui.muted),
              FanPill(
                text: '${p['likes_received']} likes received',
                color: Ui.muted,
              ),
            ],
          ),
          const FanSectionTitle(
            'Achievements',
            icon: Icons.workspace_premium_outlined,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final badge in badges)
                Tooltip(
                  message: '${badge['description']}',
                  child: Chip(
                    avatar: Icon(
                      badge['earned'] == true
                          ? Icons.verified_rounded
                          : Icons.lock_outline_rounded,
                      size: 17,
                      color: badge['earned'] == true ? Ui.redSoft : Ui.muted,
                    ),
                    label: Text(
                      '${badge['title']}',
                      style: TextStyle(
                        fontSize: 11,
                        color: badge['earned'] == true ? null : Ui.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${p['posts']} Posts',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  String _joined(int epoch) {
    final d = DateTime.fromMillisecondsSinceEpoch(epoch).toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ui.bg,
    appBar: AppBar(
      title: const Text('Fan profile'),
      actions: [
        IconButton(
          tooltip: 'Refresh profile',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
        if (_profile != null)
          Expanded(
            child: NestedScrollView(
              headerSliverBuilder: (_, innerScrolled) => [
                SliverToBoxAdapter(child: _header()),
              ],
              body: FanPostsFeed(
                active: true,
                authorId: widget.userId,
                onSocialChanged: _load,
                onJoin: () async => true,
                onOpenLounge: () {},
                fixtures: const [],
                onOpenMatch: (_) {},
              ),
            ),
          ),
      ],
    ),
  );
}

class _EditFanProfile extends StatefulWidget {
  final Map<String, dynamic> profile;
  const _EditFanProfile({required this.profile});
  @override
  State<_EditFanProfile> createState() => _EditFanProfileState();
}

class _EditFanProfileState extends State<_EditFanProfile> {
  late final TextEditingController _name, _bio;
  String? _error;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: '${widget.profile['name']}');
    _bio = TextEditingController(text: '${widget.profile['bio']}');
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await FanZoneService.call(
        'social/profile',
        body: {'name': _name.text.trim(), 'bio': _bio.text.trim()},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      20,
      8,
      20,
      20 + MediaQuery.of(context).viewInsets.bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Edit public profile',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          maxLength: 30,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: 'Nickname'),
        ),
        TextField(
          controller: _bio,
          maxLength: 160,
          maxLines: 3,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: 'Bio'),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save profile'),
        ),
      ],
    ),
  );
}

class FanPeopleScreen extends StatefulWidget {
  final String userId, type;
  const FanPeopleScreen({super.key, required this.userId, required this.type});
  @override
  State<FanPeopleScreen> createState() => _FanPeopleScreenState();
}

class _FanPeopleScreenState extends State<FanPeopleScreen> {
  List<Map<String, dynamic>> _people = [];
  String? _next, _error;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (!mounted || _loading) return;
    setState(() => _loading = true);
    try {
      final data = await FanZoneService.call(
        'social/people',
        query: {
          'id': widget.userId,
          'type': widget.type,
          if (more && _next != null) 'before': _next!,
        },
      );
      if (!mounted) return;
      setState(() {
        final rows = FanZoneService.rows(data['people']);
        final seen = more ? _people.map((p) => p['id']).toSet() : <dynamic>{};
        _people = [
          ...(more ? _people : <Map<String, dynamic>>[]),
          ...rows.where((p) => seen.add(p['id'])),
        ];
        _next = data['next'] as String?;
        _error = null;
      });
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ui.bg,
    appBar: AppBar(
      title: Text(widget.type == 'followers' ? 'Followers' : 'Following'),
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          if (!_loading && _error == null && _people.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No fans here yet.'),
            ),
          for (final person in _people)
            ListTile(
              leading: FanAvatar(
                name: '${person['name']}',
                seed: '${person['id']}',
                size: 40,
              ),
              title: Text('${person['name']}'),
              subtitle: Text('@${FanZoneService.handle('${person['id']}')}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FanProfileScreen(userId: '${person['id']}'),
                  ),
                );
                if (mounted) _load();
              },
            ),
          if (_next != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton(
                onPressed: _loading ? null : () => _load(more: true),
                child: const Text('Load more fans'),
              ),
            ),
        ],
      ),
    ),
  );
}
