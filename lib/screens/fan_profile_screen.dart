import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/fan_zone_service.dart';
import '../services/content_sync.dart';
import '../widgets/fan_club_picker.dart';
import '../theme/app_theme.dart';
import 'fan_posts_feed.dart';
import 'fan_widgets.dart';
import 'fan_x_widgets.dart';

void _noTab(int index) {}

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
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) =>
            _EditFanProfile(userId: widget.userId, profile: _profile!),
      ),
    );
    if (saved == true && mounted) {
      await _load();
      ContentSync.request(force: true);
    }
  }

  static const double _coverHeight = 128;
  static const double _avatarSize = 76;

  String _text(dynamic v) => v == null ? '' : '$v'.trim();

  Widget _coverImage(Map<String, dynamic> p) {
    final v = p['cover_at'];
    final url = v is num && v > 0
        ? FanZoneService.profileImageUrl(widget.userId, 'cover', v)
        : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                fanColor(widget.userId).withValues(alpha: .65),
                Ui.red.withValues(alpha: .18),
              ],
            ),
          ),
        ),
        if ('${p['club_logo'] ?? ''}'.isNotEmpty)
          FanClubCover(name: '${p['club_name']}', logo: '${p['club_logo']}')
        else if (url != null)
          Image.network(
            url,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
      ],
    );
  }

  Widget _count(String number, String label, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: number,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            TextSpan(
              text: ' $label',
              style: TextStyle(color: Ui.muted),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 14),
      ),
    ),
  );

  Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: Ui.muted),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Ui.muted, fontSize: 13.5),
        ),
      ),
    ],
  );

  Widget _header() {
    final p = _profile!, stats = Map<String, dynamic>.from(p['stats'] as Map);
    final badges = FanZoneService.rows(p['achievements']);
    final followed = p['followed'] == 1 || p['followed'] == true;
    final bio = _text(p['bio']);
    final location = _text(p['location']);
    final mine = p['is_me'] == true;
    final button = mine
        ? OutlinedButton(
            onPressed: _edit,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: const StadiumBorder(),
            ),
            child: const Text(
              'Edit profile',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          )
        : followed
        ? OutlinedButton(
            onPressed: _following ? null : _follow,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: const StadiumBorder(),
            ),
            child: Text(
              _following ? 'Saving…' : 'Following',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          )
        : FilledButton(
            onPressed: _following ? null : _follow,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              backgroundColor: Theme.of(context).colorScheme.onSurface,
              foregroundColor: Theme.of(context).colorScheme.surface,
              shape: const StadiumBorder(),
            ),
            child: Text(
              _following ? 'Saving…' : 'Follow',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cover photo, the round profile photo overlapping it, and the
        // Edit profile / Follow button on the right (like X).
        SizedBox(
          height: _coverHeight + 52,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: _coverHeight,
                child: _coverImage(p),
              ),
              Positioned(
                left: 14,
                top: _coverHeight - _avatarSize / 2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Ui.bg,
                    shape: BoxShape.circle,
                  ),
                  child: FanAvatar(
                    name: '${p['name']}',
                    seed: widget.userId,
                    size: _avatarSize,
                    imageUrl: FanZoneService.avatarUrl(
                      widget.userId,
                      p['avatar_at'],
                    ),
                  ),
                ),
              ),
              Positioned(right: 14, top: _coverHeight + 10, child: button),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${p['name']}',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text('@${p['handle']}', style: TextStyle(color: Ui.muted)),
              if ('${p['club_name'] ?? ''}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '⚽ ${p['club_name']}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              if (bio.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    bio,
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    if (location.isNotEmpty)
                      _meta(Icons.location_on_outlined, location),
                    if (p['joined_at'] is num)
                      _meta(
                        Icons.calendar_month_outlined,
                        'Joined ${_joined((p['joined_at'] as num).toInt())}',
                      ),
                  ],
                ),
              ),
              Wrap(
                spacing: 18,
                children: [
                  _count(
                    '${p['following']}',
                    'Following',
                    () => _people('following'),
                  ),
                  _count(
                    '${p['followers']}',
                    'Followers',
                    () => _people('followers'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FanPill(text: '${stats['points']} points', color: Ui.redSoft),
                  FanPill(
                    text: '${stats['exact']} exact scores',
                    color: Ui.green,
                  ),
                  FanPill(text: '${stats['settled']} settled', color: Ui.muted),
                  FanPill(
                    text: '${p['likes_received']} likes received',
                    color: Ui.muted,
                  ),
                ],
              ),
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  title: const Text(
                    'Achievements',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  children: [
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
                                color: badge['earned'] == true
                                    ? Ui.redSoft
                                    : Ui.muted,
                              ),
                              label: Text(
                                '${badge['title']}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: badge['earned'] == true
                                      ? null
                                      : Ui.muted,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const XTabBar(labels: ['Posts'], index: 0, onTap: _noTab),
      ],
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
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _profile == null ? 'Fan profile' : '${_profile!['name']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          if (_profile != null)
            Text(
              '${_profile!['posts']} posts',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Ui.muted,
              ),
            ),
        ],
      ),
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
  final String userId;
  final Map<String, dynamic> profile;
  const _EditFanProfile({required this.userId, required this.profile});
  @override
  State<_EditFanProfile> createState() => _EditFanProfileState();
}

class _EditFanProfileState extends State<_EditFanProfile> {
  static const double _coverHeight = 128;
  static const double _avatarSize = 76;
  late final TextEditingController _name, _bio, _location;
  Uint8List? _avatar, _cover;
  late String _clubName = '${widget.profile['club_name'] ?? ''}',
      _clubLogo = '${widget.profile['club_logo'] ?? ''}';
  bool _avatarSent = false, _coverSent = false;
  String? _error;
  bool _saving = false, _picking = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: '${widget.profile['name']}');
    _bio = TextEditingController(text: '${widget.profile['bio'] ?? ''}');
    _location = TextEditingController(
      text: '${widget.profile['location'] ?? ''}',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pick(String kind) async {
    if (_picking || _saving) return;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        withData: false,
        withReadStream: true,
        allowMultiple: false,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      const limit = 4 * 1024 * 1024;
      if (file.size > limit) {
        throw Exception('Choose a JPG or PNG smaller than 4 MB.');
      }
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.readStream != null) {
        final buffer = BytesBuilder(copy: false);
        await for (final chunk in file.readStream!) {
          if (buffer.length + chunk.length > limit) {
            throw Exception('Choose an image smaller than 4 MB.');
          }
          buffer.add(chunk);
        }
        bytes = buffer.takeBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Could not read that image.');
      }
      if (!mounted) return;
      setState(() {
        if (kind == 'avatar') {
          _avatar = bytes;
          _avatarSent = false;
        } else {
          _cover = bytes;
          _clubLogo = '';

          _coverSent = false;
        }
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
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
        body: {
          'name': _name.text.trim(),
          'bio': _bio.text.trim(),
          'location': _location.text.trim(),
          'club_name': _clubName,
          'club_logo': _clubLogo,
        },
      );
      final avatar = _avatar, cover = _cover;
      if (avatar != null && !_avatarSent) {
        await FanZoneService.uploadProfileImage(kind: 'avatar', image: avatar);
        _avatarSent = true;
      }
      if (cover != null && !_coverSent) {
        await FanZoneService.uploadProfileImage(kind: 'cover', image: cover);
        _coverSent = true;
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _cameraBadge() => Container(
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .55),
      shape: BoxShape.circle,
    ),
    child: const Icon(
      Icons.add_a_photo_outlined,
      size: 20,
      color: Colors.white,
    ),
  );

  Widget _coverArea() {
    final v = widget.profile['cover_at'];
    final url = v is num && v > 0
        ? FanZoneService.profileImageUrl(widget.userId, 'cover', v)
        : null;
    return GestureDetector(
      onTap: () => _pick('cover'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  fanColor(widget.userId).withValues(alpha: .65),
                  Ui.red.withValues(alpha: .18),
                ],
              ),
            ),
          ),
          if (_clubLogo.isNotEmpty)
            FanClubCover(name: _clubName, logo: _clubLogo)
          else if (_cover != null)
            Image.memory(_cover!, fit: BoxFit.cover)
          else if (url != null)
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => const SizedBox.shrink(),
            ),
          Center(child: _cameraBadge()),
        ],
      ),
    );
  }

  Widget _avatarArea() {
    final name = _name.text.trim().isEmpty
        ? '${widget.profile['name']}'
        : _name.text;
    return GestureDetector(
      onTap: () => _pick('avatar'),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Ui.bg, shape: BoxShape.circle),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_avatar != null)
              ClipOval(
                child: Image.memory(
                  _avatar!,
                  width: _avatarSize,
                  height: _avatarSize,
                  fit: BoxFit.cover,
                ),
              )
            else
              FanAvatar(
                name: name,
                seed: widget.userId,
                size: _avatarSize,
                imageUrl: FanZoneService.avatarUrl(
                  widget.userId,
                  widget.profile['avatar_at'],
                ),
              ),
            _cameraBadge(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ui.bg,
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Close',
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        icon: const Icon(Icons.close_rounded),
      ),
      title: const Text(
        'Edit profile',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              backgroundColor: Theme.of(context).colorScheme.onSurface,
              foregroundColor: Theme.of(context).colorScheme.surface,
              shape: const StadiumBorder(),
            ),
            child: Text(
              _saving ? 'Saving…' : 'Save',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    ),
    body: ListView(
      padding: EdgeInsets.only(
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      children: [
        if (_saving) const LinearProgressIndicator(minHeight: 2),
        SizedBox(
          height: _coverHeight + _avatarSize / 2 + 8,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: _coverHeight,
                child: _coverArea(),
              ),
              Positioned(
                left: 14,
                top: _coverHeight - _avatarSize / 2,
                child: _avatarArea(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                maxLength: 30,
                enabled: !_saving,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: _bio,
                maxLength: 160,
                maxLines: 3,
                minLines: 2,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  hintText: 'Tell fans a bit about yourself',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sports_soccer),
                title: Text(_clubName.isEmpty ? 'Select your club' : _clubName),
                subtitle: const Text(
                  'Choose a crest cover, or upload your own club image',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _saving
                    ? null
                    : () async {
                        final club = await chooseFanClub(context);
                        if (club != null && mounted)
                          setState(() {
                            _clubName = club.key;
                            _clubLogo = club.value;
                          });
                      },
              ),
              TextField(
                controller: _location,
                maxLength: 40,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Tap the cover or profile photo to change it. JPG or PNG, up to 4 MB.',
                  style: TextStyle(color: Ui.muted, fontSize: 12.5),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
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
                imageUrl: FanZoneService.avatarUrl(
                  '${person['id']}',
                  person['avatar_at'],
                ),
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
