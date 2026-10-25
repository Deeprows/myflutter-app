import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/fixture.dart';
import '../services/fan_zone_service.dart';
import '../services/content_sync.dart';
import '../theme/app_theme.dart';
import 'fan_widgets.dart';

const _labels = {
  'all': 'All',
  'prediction': 'Predictions',
  'betslip': 'Bet Slips',
  'banter': 'Banter',
};
const _filterIcons = {
  'all': Icons.dashboard_rounded,
  'prediction': Icons.sports_soccer_rounded,
  'betslip': Icons.receipt_long_rounded,
  'banter': Icons.forum_rounded,
};
String _error(Object e) => e.toString().replaceFirst('Exception: ', '');

class FanPostsFeed extends StatefulWidget {
  final bool active;
  final Future<bool> Function() onJoin;
  final VoidCallback onOpenLounge;
  final List<Fixture> fixtures;
  final void Function(Fixture) onOpenMatch;
  const FanPostsFeed({
    super.key,
    required this.active,
    required this.onJoin,
    required this.onOpenLounge,
    required this.fixtures,
    required this.onOpenMatch,
  });
  @override
  State<FanPostsFeed> createState() => _FanPostsFeedState();
}

class _FanPostsFeedState extends State<FanPostsFeed>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _posts = [];
  Set<String> _blocked = {};
  String _kind = 'all', _myId = '';
  String? _next, _failure;
  bool _busy = false, _uploads = false, _foreground = true, _loadedOnce = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ContentSync.tick.addListener(_sync);
    if (widget.active) _load();
    _poll = Timer.periodic(const Duration(seconds: 45), (_) {
      if (widget.active && _foreground && _posts.length <= 40) _load();
    });
  }

  @override
  void didUpdateWidget(covariant FanPostsFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && widget.active) _load();
  }

  void _sync() {
    if (widget.active && _foreground) _load();
  }

  @override
  void dispose() {
    ContentSync.tick.removeListener(_sync);
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _notice(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(value)),
      );
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await FanZoneService.call(
        'posts',
        query: {'kind': _kind, if (more && _next != null) 'before': _next!},
      );
      final blocked = await FanZoneService.blocked();
      if (!mounted) return;
      final incoming = FanZoneService.rows(data['posts']);
      setState(() {
        _blocked = blocked;
        if (more) {
          final ids = _posts.map((p) => p['id']).toSet();
          _posts = [..._posts, ...incoming.where((p) => ids.add(p['id']))];
        } else {
          _posts = incoming;
        }
        _next = data['next'] as String?;
        _myId = (data['id'] ?? '').toString();
        _uploads = data['uploads_enabled'] == true;
        _failure = null;
      });
    } catch (e) {
      if (mounted) setState(() => _failure = _error(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loadedOnce = true;
        });
      }
    }
  }

  Future<void> _create([String kind = 'prediction']) async {
    if (!await widget.onJoin() || !mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ComposePost(
          uploadsEnabled: _uploads,
          initialKind: kind,
          fixtures: widget.fixtures,
        ),
      ),
    );
    if (created == true && mounted) {
      setState(() {
        _kind = 'all';
        _next = null;
      });
      await _load();
    }
  }

  Future<void> _action(String action, Map<String, dynamic> post) async {
    try {
      if (action == 'share') {
        final text = post['text'].toString().trim();
        await Share.share(
          '${post['name']} on Deeprowss Fan Zone'
          '${text.isEmpty ? '' : ':\n$text'}',
        );
        return;
      }
      if (action == 'block') {
        await FanZoneService.block(post['user_id'].toString());
        if (mounted) setState(() => _blocked.add(post['user_id'].toString()));
        _notice('Fan blocked on this device.');
        return;
      }
      if (!await widget.onJoin() || !mounted) return;
      if (action == 'delete') {
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete this post?'),
            content: const Text(
              'This removes the post and its image from the community feed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (yes != true) return;
      }
      await FanZoneService.call(
        'post/${action == 'delete' ? 'delete' : 'report'}',
        body: {
          'id': post['id'],
          if (action == 'report') 'reason': 'Inappropriate content',
        },
      );
      if (action == 'delete') {
        if (mounted) {
          setState(() => _posts.removeWhere((p) => p['id'] == post['id']));
        }
        _notice('Post deleted.');
      } else {
        _notice('Report sent for review.');
      }
    } catch (e) {
      _notice(_error(e));
    }
  }

  // ---------------------------------------------------------------------------
  // PIECES
  // ---------------------------------------------------------------------------

  Widget _composer() {
    Widget quick(String kind, String hint) {
      final k = FanKind.of(kind);
      return Expanded(
        child: GestureDetector(
          onTap: _busy ? null : () => _create(kind),
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: k.color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: k.color.withValues(alpha: .32)),
            ),
            child: Column(
              children: [
                Icon(k.icon, size: 22, color: k.color),
                const SizedBox(height: 4),
                Text(
                  k.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: Ui.muted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return FanHero(
      color: Ui.red,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _busy ? null : () => _create('banter'),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Ui.red, Ui.redSoft],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(
                    Icons.edit_rounded,
                    size: 20,
                    color: Ui.palette.onAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .28),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: Ui.line),
                    ),
                    child: Text(
                      'What\'s the gist? Drop a take…',
                      style: TextStyle(color: Ui.muted, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              quick('prediction', 'Call the score'),
              quick('betslip', 'Show your slip'),
              quick('banter', 'Trash talk'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rooms() {
    final now = DateTime.now();
    final fixtures = widget.fixtures.take(20).toList();
    Widget room({
      required Widget lead,
      required String title,
      required String subtitle,
      required Color color,
      required Widget status,
      required VoidCallback onTap,
    }) => GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .4)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: .26), Ui.card],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                lead,
                const Spacer(),
                status,
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Ui.muted),
            ),
            const Spacer(),
            Row(
              children: [
                Icon(Icons.forum_rounded, size: 13, color: color),
                const SizedBox(width: 5),
                Text(
                  'Join chat',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 16, color: color),
              ],
            ),
          ],
        ),
      ),
    );

    Widget crests(Fixture f) => SizedBox(
      width: 62,
      height: 32,
      child: Stack(
        children: [
          TeamCrest(logo: f.homeLogo, size: 32),
          Positioned(left: 26, child: TeamCrest(logo: f.awayLogo, size: 32)),
        ],
      ),
    );

    Widget status(Fixture f) {
      final phase = f.phaseAt(now);
      if (phase == MatchPhase.live) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FanLiveDot(),
            const SizedBox(width: 5),
            Text(
              'LIVE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: fanAlert,
              ),
            ),
          ],
        );
      }
      if (phase == MatchPhase.upcoming) {
        return FanPill(
          text: fanDayLabel(f.kickoff, now) == 'Today'
              ? fanClock(f.kickoff)
              : fanDayLabel(f.kickoff, now),
          color: Ui.muted,
          icon: Icons.schedule_rounded,
        );
      }
      return FanPill(text: 'FT', color: Ui.dim);
    }

    return SizedBox(
      height: 142,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          room(
            lead: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fanOrange.withValues(alpha: .2),
              ),
              child: const Icon(
                Icons.local_fire_department_rounded,
                color: fanOrange,
                size: 22,
              ),
            ),
            title: 'Fan lounge',
            subtitle: 'Open to every fan, all day',
            color: fanOrange,
            status: const FanPill(text: 'OPEN', color: fanOrange),
            onTap: widget.onOpenLounge,
          ),
          for (final f in fixtures) ...[
            const SizedBox(width: 10),
            room(
              lead: crests(f),
              title: f.title,
              subtitle: f.league.isEmpty ? 'Match chat' : f.league,
              color: Ui.redSoft,
              status: status(f),
              onTap: () => widget.onOpenMatch(f),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filters() => SizedBox(
    height: 40,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final kind in _labels.keys) ...[
          FanChip(
            icon: _filterIcons[kind],
            label: _labels[kind]!,
            color: kind == 'all' ? Ui.red : FanKind.of(kind).color,
            selected: kind == _kind,
            onTap: _busy
                ? null
                : () {
                    setState(() {
                      _kind = kind;
                      _next = null;
                      _posts = [];
                      _failure = null;
                    });
                    _load();
                  },
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );

  Widget _post(Map<String, dynamic> p) {
    final mine = p['user_id'] == _myId;
    final k = FanKind.of(p['kind'].toString());
    final name = '${p['name']}';
    final text = p['text'].toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Ui.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: mine ? Ui.red.withValues(alpha: .4) : Ui.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [k.color, k.color.withValues(alpha: 0)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 0),
            child: Row(
              children: [
                FanAvatar(name: name, seed: '${p['user_id']}', size: 42),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mine ? '$name (you)' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '#${fanShortId(p['user_id'])} • ${fanTimeAgo(p['at'])}',
                        style: TextStyle(fontSize: 11, color: Ui.muted),
                      ),
                    ],
                  ),
                ),
                FanPill(text: k.label, color: k.color, icon: k.icon),
                PopupMenuButton<String>(
                  onSelected: (a) => _action(a, p),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'share',
                      child: Text('Share post'),
                    ),
                    if (mine)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete post'),
                      ),
                    if (!mine) ...const [
                      PopupMenuItem(
                        value: 'report',
                        child: Text('Report post'),
                      ),
                      PopupMenuItem(
                        value: 'block',
                        child: Text('Block fan'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: SelectableText(
                text,
                style: const TextStyle(fontSize: 15.5, height: 1.45),
              ),
            ),
          if (p['has_image'] == 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Semantics(
                label: 'Open post image',
                button: true,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => _PostImage(postId: p['id'].toString()),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      height: 240,
                      color: Colors.black26,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            FanZoneService.imageUrl(p['id'].toString()),
                            fit: BoxFit.contain,
                            cacheWidth: 900,
                            loadingBuilder: (_, child, progress) =>
                                progress == null
                                ? child
                                : const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                            errorBuilder: (_, __, ___) =>
                                const Center(child: Text('Image unavailable')),
                          ),
                          const Positioned(
                            right: 8,
                            bottom: 8,
                            child: Icon(
                              Icons.zoom_out_map_rounded,
                              size: 18,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _action('share', p),
                  icon: const Icon(Icons.ios_share_rounded, size: 17),
                  label: const Text('Share'),
                  style: TextButton.styleFrom(foregroundColor: Ui.muted),
                ),
                TextButton.icon(
                  onPressed: widget.onOpenLounge,
                  icon: const Icon(Icons.forum_outlined, size: 17),
                  label: const Text('Reply in lounge'),
                  style: TextButton.styleFrom(foregroundColor: Ui.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _posts
        .where((p) => !_blocked.contains(p['user_id']))
        .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _composer(),
          const FanSectionTitle('Live chat rooms', icon: Icons.chat_rounded),
          _rooms(),
          const FanSectionTitle('Community feed', icon: Icons.dynamic_feed_rounded),
          _filters(),
          const SizedBox(height: 12),
          if (_blocked.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await FanZoneService.unblockAll();
                  if (mounted) setState(() => _blocked = {});
                },
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                label: Text(
                  'Unblock ${_blocked.length} blocked fan'
                  '${_blocked.length == 1 ? '' : 's'}',
                ),
              ),
            ),
          if (_failure != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              decoration: fanBox(radius: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _failure!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _busy ? null : _load,
                  ),
                ],
              ),
            ),
          if (_busy && visible.isEmpty && !_loadedOnce) ...const [
            FanSkeleton(height: 130),
            FanSkeleton(height: 130),
            FanSkeleton(height: 130),
          ],
          if (!_busy && _failure == null && visible.isEmpty)
            FanEmpty(
              icon: Icons.forum_outlined,
              title: 'No posts here yet',
              message: 'Be the first to share a prediction or some gist.',
              action: FilledButton.icon(
                onPressed: () => _create('banter'),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Create a post'),
              ),
            ),
          for (final p in visible) _post(p),
          if (_busy && visible.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_next != null && !_busy)
            OutlinedButton.icon(
              onPressed: () => _load(more: true),
              icon: const Icon(Icons.expand_more_rounded),
              label: const Text('Load older posts'),
            ),
          const SizedBox(height: 12),
          Text(
            'Community opinions, not guaranteed results. Posts do not earn prediction-game points.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Ui.dim, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// COMPOSE
// -----------------------------------------------------------------------------

class _ComposePost extends StatefulWidget {
  final bool uploadsEnabled;
  final String initialKind;
  final List<Fixture> fixtures;
  const _ComposePost({
    required this.uploadsEnabled,
    required this.initialKind,
    required this.fixtures,
  });
  @override
  State<_ComposePost> createState() => _ComposePostState();
}

class _ComposePostState extends State<_ComposePost> {
  final _text = TextEditingController();
  late String _kind = widget.initialKind;
  Uint8List? _image;
  bool _busy = false, _picking = false;

  static const _hints = {
    'prediction': 'Arsenal 2-1 Chelsea. Saka scores, Palmer gets one back…',
    'betslip': 'Add a caption for your slip (optional)…',
    'banter': 'What is your take on the football today?',
  };

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _notice(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(value)),
      );
  }

  Future<void> _tagMatch() async {
    final f = await showModalBottomSheet<Fixture>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Ui.panel,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * .6,
          ),
          child: widget.fixtures.isEmpty
              ? const FanEmpty(
                  icon: Icons.event_busy_rounded,
                  title: 'No matches to tag',
                  message: 'Fixtures will appear here when they are available.',
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(
                        'Tag a match',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    for (final f in widget.fixtures.take(40))
                      ListTile(
                        leading: TeamCrest(logo: f.homeLogo, size: 34),
                        title: Text(f.title),
                        subtitle: Text(
                          '${f.league.isEmpty ? 'Football' : f.league} • '
                          '${fanDayLabel(f.kickoff, DateTime.now())} ${fanClock(f.kickoff)}',
                        ),
                        onTap: () => Navigator.pop(ctx, f),
                      ),
                  ],
                ),
        ),
      ),
    );
    if (f == null || !mounted) return;
    final tag = '⚽ ${f.title}';
    if (!_text.text.contains(tag)) {
      _text.text = _text.text.isEmpty ? '$tag\n' : '$tag\n${_text.text}';
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
    }
  }

  Future<void> _pickImage() async {
    if (_picking || _busy) return;
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
      if (file.size > 4 * 1024 * 1024) {
        throw Exception('Choose a JPG or PNG smaller than 4 MB.');
      }
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.readStream != null) {
        final buffer = BytesBuilder(copy: false);
        await for (final chunk in file.readStream!) {
          if (buffer.length + chunk.length > 4 * 1024 * 1024) {
            throw Exception('Choose an image smaller than 4 MB.');
          }
          buffer.add(chunk);
        }
        bytes = buffer.takeBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Could not read this image. Choose another photo.');
      }
      // Read dimensions before decoding to avoid large full-resolution allocations.
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          if (descriptor.width > 6000 ||
              descriptor.height > 6000 ||
              descriptor.width * descriptor.height > 16000000) {
            throw Exception(
              'Choose an image up to 6,000 pixels per side and 16 megapixels.',
            );
          }
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
      if (mounted) setState(() => _image = bytes);
    } catch (e) {
      _notice(_error(e));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _publish() async {
    if (_busy || _picking) return;
    if (_kind == 'betslip' && _image == null) {
      _notice('Attach your bet-slip image.');
      return;
    }
    if (_kind == 'prediction' && _text.text.trim().isEmpty) {
      _notice('Write your prediction first.');
      return;
    }
    if (_image == null && _text.text.trim().isEmpty) {
      _notice('Write something or attach an image.');
      return;
    }
    setState(() => _busy = true);
    try {
      await FanZoneService.publish(
        kind: _kind,
        text: _text.text,
        image: _image,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _notice(_error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = FanKind.of(_kind);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New post'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _busy || _picking ? null : _publish,
                child: Text(_busy ? 'Posting…' : 'Post'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  for (final kind in const ['prediction', 'betslip', 'banter'])
                    ButtonSegment<String>(
                      value: kind,
                      icon: Icon(FanKind.of(kind).icon, size: 16),
                      label: Text(FanKind.of(kind).label),
                    ),
                ],
                selected: {_kind},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: fanBox(border: k.color.withValues(alpha: .4)),
                child: Column(
                  children: [
                    TextField(
                      controller: _text,
                      enabled: !_busy,
                      maxLength: 1000,
                      minLines: 6,
                      maxLines: 12,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: _hints[_kind],
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: _busy ? null : _tagMatch,
                            icon: const Icon(
                              Icons.sports_soccer_rounded,
                              size: 16,
                            ),
                            label: const Text('Tag a match'),
                          ),
                          const Spacer(),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _text,
                            builder: (_, v, __) => Text(
                              '${v.text.length}/1000',
                              style: TextStyle(fontSize: 12, color: Ui.dim),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_image != null)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: double.infinity,
                        height: 260,
                        color: Colors.black26,
                        child: Image.memory(
                          _image!,
                          cacheWidth: 900,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: IconButton.filled(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _image = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                )
              else
                OutlinedButton.icon(
                  onPressed: widget.uploadsEnabled && !_busy && !_picking
                      ? _pickImage
                      : null,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    _picking
                        ? 'Opening photos…'
                        : _kind == 'betslip'
                        ? 'Attach your bet slip'
                        : 'Attach a photo',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                widget.uploadsEnabled
                    ? 'One JPG/PNG • Up to 4 MB. Crop out account details before sharing.'
                    : 'Image uploads are not enabled yet. You can still publish text predictions and banter.',
                style: TextStyle(fontSize: 12, color: Ui.muted),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: fanBox(radius: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: Ui.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your post is public. Predictions are opinions, not guarantees. Published posts cannot be edited; you can delete your own post.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Ui.muted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostImage extends StatelessWidget {
  final String postId;
  const _PostImage({required this.postId});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      title: const Text('Post image'),
    ),
    body: Center(
      child: InteractiveViewer(
        minScale: .5,
        maxScale: 5,
        child: Image.network(
          FanZoneService.imageUrl(postId),
          cacheWidth: 2000,
          errorBuilder: (_, __, ___) => const Text('Image unavailable'),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : const CircularProgressIndicator(),
        ),
      ),
    ),
  );
}
