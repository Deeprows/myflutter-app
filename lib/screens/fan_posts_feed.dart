import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../models/fan_post_link.dart';
import '../models/fixture.dart';
import '../services/embed_info.dart';
import '../services/stream_resolver.dart';
import '../widgets/fan_post_video.dart';
import '../services/fan_zone_service.dart';
import '../services/content_sync.dart';
import '../theme/app_theme.dart';
import '../utils/safe_error_message.dart';
import 'fan_widgets.dart';
import 'fan_mentions.dart';
import 'fan_post_card.dart';
import 'fan_x_widgets.dart';

const _labels = {
  'all': 'All',
  'prediction': 'Predictions',
  'betslip': 'Bet Slips',
  'banter': 'Banter',
  'video': 'Videos',
};
const _filterIcons = {
  'all': Icons.dashboard_rounded,
  'prediction': Icons.sports_soccer_rounded,
  'betslip': Icons.receipt_long_rounded,
  'banter': Icons.forum_rounded,
  'video': Icons.smart_display_rounded,
};
String _error(Object e) => safeErrorMessage(e);

class FanPostsFeed extends StatefulWidget {
  final bool active;
  final String? authorId;
  final VoidCallback? onSocialChanged;
  final Future<bool> Function() onJoin;
  final VoidCallback onOpenLounge;
  final List<Fixture> fixtures;
  final void Function(Fixture) onOpenMatch;

  /// Bumped by the Thread header's Match Rooms button to open the rooms sheet.
  final ValueNotifier<int>? roomsTrigger;

  /// Signed-in fan, shown in the "What's happening?" box.
  final String viewerName;
  final dynamic viewerAvatarAt;

  const FanPostsFeed({
    super.key,
    required this.active,
    this.authorId,
    this.onSocialChanged,
    this.viewerName = '',
    this.viewerAvatarAt,
    required this.onJoin,
    required this.onOpenLounge,
    required this.fixtures,
    required this.onOpenMatch,
    this.roomsTrigger,
  });
  @override
  State<FanPostsFeed> createState() => _FanPostsFeedState();
}

class _FanPostsFeedState extends State<FanPostsFeed>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _posts = [];
  Set<String> _blocked = {};
  String _kind = 'all', _myId = '';
  String _scope = 'all';
  String? _next, _failure;
  bool _busy = false, _uploads = false, _foreground = true, _loadedOnce = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ContentSync.tick.addListener(_sync);
    widget.roomsTrigger?.addListener(_roomsRequested);
    if (widget.active) _load();
    _poll = Timer.periodic(const Duration(seconds: 45), (_) {
      if (widget.active &&
          _foreground &&
          _posts.length <= 40 &&
          TickerMode.of(context))
        _load();
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
    if (widget.active && _foreground && TickerMode.of(context)) _load();
  }

  @override
  void dispose() {
    ContentSync.tick.removeListener(_sync);
    widget.roomsTrigger?.removeListener(_roomsRequested);
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (!mounted || _busy) return;
    setState(() => _busy = true);
    try {
      final data = await FanZoneService.call(
        'posts',
        query: {
          'kind': _kind,
          'scope': _scope,
          if (widget.authorId != null) 'author': widget.authorId!,
          if (more && _next != null) 'before': _next!,
        },
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

  // ---------------------------------------------------------------------------
  // PIECES
  // ---------------------------------------------------------------------------

  void _roomsRequested() {
    if (mounted && widget.active) _showRooms();
  }

  void _showRooms() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Ui.bg,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 0, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Live match rooms',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              _rooms(onSelected: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rooms({VoidCallback? onSelected}) {
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
      onTap: () {
        onSelected?.call();
        onTap();
      },
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
            Row(children: [lead, const Spacer(), status]),
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
      padding: const EdgeInsets.symmetric(horizontal: 14),
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

  // X-style "What's happening?" box at the top of the home feed.
  Widget _composerRow() => InkWell(
    onTap: _busy ? null : () => _create('banter'),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Ui.line, width: .6)),
      ),
      child: Row(
        children: [
          FanAvatar(
            name: widget.viewerName.isEmpty ? 'You' : widget.viewerName,
            seed: _myId,
            size: 38,
            imageUrl: FanZoneService.avatarUrl(_myId, widget.viewerAvatarAt),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'What’s happening?',
              style: TextStyle(color: Ui.muted, fontSize: 16),
            ),
          ),
          Icon(Icons.image_outlined, color: Ui.red, size: 22),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: Ui.red,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Post',
              style: TextStyle(
                color: Ui.palette.onAccent,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _post(Map<String, dynamic> p) => FanPostCard(
    key: ValueKey(p['id']),
    post: p,
    viewerId: _myId,
    onChanged: () {
      _load();
      widget.onSocialChanged?.call();
    },
    onBlocked: () => _load(),
  );

  void _setScope(String value) {
    if (_busy || value == _scope) return;
    setState(() {
      _scope = value;
      _posts = [];
      _next = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _posts
        .where((p) => !_blocked.contains(p['user_id']))
        .toList();
    final home = widget.authorId == null;
    const pad = EdgeInsets.symmetric(horizontal: 16);
    final list = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: home ? 96 : 28),
        children: [
          if (!home) ...[_filters(), const XDivider()],
          if (home) _composerRow(),
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
              margin: const EdgeInsets.all(16),
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
          if (_busy && visible.isEmpty && !_loadedOnce)
            const Padding(
              padding: pad,
              child: Column(
                children: [
                  SizedBox(height: 12),
                  FanSkeleton(height: 110),
                  FanSkeleton(height: 110),
                  FanSkeleton(height: 110),
                ],
              ),
            ),
          if (!_busy && _failure == null && visible.isEmpty)
            Padding(
              padding: pad,
              child: FanEmpty(
                icon: Icons.forum_outlined,
                title: 'No posts here yet',
                message: widget.authorId != null
                    ? 'This fan has not posted here yet.'
                    : _scope == 'following'
                    ? 'Follow fans from their profiles to see their posts here.'
                    : 'Be the first to share a prediction or some gist.',
                action: widget.authorId != null
                    ? null
                    : FilledButton.icon(
                        onPressed: () => _create('banter'),
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text('Create a post'),
                      ),
              ),
            ),
          for (final p in visible) _post(p),
          if (_busy && visible.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_next != null && !_busy)
            Padding(
              padding: const EdgeInsets.all(14),
              child: OutlinedButton.icon(
                onPressed: () => _load(more: true),
                icon: const Icon(Icons.expand_more_rounded),
                label: const Text('Load older posts'),
              ),
            ),
        ],
      ),
    );
    if (!home) return list;
    return Column(
      children: [
        XTabBar(
          labels: const ['For you', 'Following'],
          index: _scope == 'following' ? 1 : 0,
          onTap: (i) => _setScope(i == 1 ? 'following' : 'all'),
        ),
        Row(
          children: [
            Expanded(child: _filters()),
            IconButton(
              tooltip: 'Match rooms',
              onPressed: _showRooms,
              icon: const Icon(Icons.forum_outlined),
            ),
          ],
        ),
        const XDivider(),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: list),
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  heroTag: null,
                  tooltip: 'New post',
                  backgroundColor: Ui.red,
                  foregroundColor: Ui.palette.onAccent,
                  shape: const CircleBorder(),
                  onPressed: _busy ? null : () => _create('banter'),
                  child: const Icon(Icons.add_rounded, size: 30),
                ),
              ),
            ],
          ),
        ),
      ],
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

/// The pasted link as embed info when it is a YouTube, TikTok or Facebook
/// video link, otherwise null.
EmbedInfo? _supportedVideo(String raw) {
  final link = raw.trim();
  final u = Uri.tryParse(link);
  if (u == null || (u.scheme != 'http' && u.scheme != 'https') || u.host.isEmpty) {
    return null;
  }
  final info = embedInfoFor(link);
  switch (info.kind) {
    case EmbedKind.youtube:
      return fanVideoUrl(link).contains('/embed/') ? info : null;
    case EmbedKind.tiktok:
      return tiktokIdFrom(link) != null || isTikTokShortLink(u) ? info : null;
    case EmbedKind.facebook:
    case EmbedKind.vimeo:
    case EmbedKind.dailymotion:
    case EmbedKind.filemoon:
      return info;
    case EmbedKind.hls:
    case EmbedKind.direct:
      return StreamResolver.resolve(link).usesHtmlPlayer ? info : null;
    case EmbedKind.generic:
      return null;
  }
}

class _ComposePostState extends State<_ComposePost> {
  Fixture? _taggedMatch;
  final _text = TextEditingController();
  final _url = TextEditingController();
  final _title = TextEditingController();
  late String _kind = widget.initialKind;
  Uint8List? _image;
  bool _busy = false, _picking = false;

  static const _hints = {
    'prediction': 'Arsenal 2-1 Chelsea. Saka scores, Palmer gets one back…',
    'betslip': 'Add a caption for your slip (optional)…',
    'banter': 'What is your take on the football today?',
    'video': 'Say something about this video (optional)…',
  };

  static const _kinds = ['prediction', 'betslip', 'banter', 'video'];
  static const _blurbs = {
    'prediction': 'Call a score or a player moment before kick-off.',
    'betslip': 'Show your slip. Crop out account details first.',
    'banter': 'Share a hot take with the community.',
    'video': 'Share a video from YouTube, TikTok, Facebook, Vimeo, Dailymotion, Filemoon or a stream link.',
  };

  @override
  void dispose() {
    _text.dispose();
    _url.dispose();
    _title.dispose();
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
    setState(() => _taggedMatch = f);
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

  Future<void> _pasteLink() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final value = data?.text?.trim() ?? '';
    if (value.isEmpty) {
      _notice('Nothing to paste. Copy a video link first.');
      return;
    }
    setState(() => _url.text = value);
  }

  Future<void> _publish() async {
    if (_busy || _picking) return;
    if (_kind == 'video') {
      final link = _url.text.trim();
      final title = _title.text.trim().replaceAll(RegExp(r'\s*\n\s*'), ' ');
      if (_supportedVideo(link) == null) {
        _notice('Paste a supported video-site link, .m3u8 stream or direct video URL.');
        return;
      }
      if (title.isEmpty) {
        _notice('Add a title for your video.');
        return;
      }
      final caption = _text.text.trim();
      setState(() => _busy = true);
      try {
        await FanZoneService.publish(
          kind: 'video',
          text: [title, if (caption.isNotEmpty) caption, link].join('\n\n'),
          matchKey: _taggedMatch == null
              ? null
              : FanZoneService.matchKey(_taggedMatch!),
        );
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        _notice(_error(e));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
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
        matchKey: _taggedMatch == null
            ? null
            : FanZoneService.matchKey(_taggedMatch!),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _notice(_error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _kindPicker() => SizedBox(
    height: 46,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _kinds.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final kind = _kinds[i];
        final fk = FanKind.of(kind);
        final sel = kind == _kind;
        return Material(
          color: sel ? fk.color.withValues(alpha: .18) : Ui.card,
          shape: StadiumBorder(
            side: BorderSide(
              color: sel ? fk.color : Ui.line,
              width: sel ? 1.4 : 1,
            ),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: _busy ? null : () => setState(() => _kind = kind),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(fk.icon, size: 18, color: sel ? fk.color : Ui.dim),
                  const SizedBox(width: 8),
                  Text(
                    fk.label,
                    style: TextStyle(
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                      color: sel ? fk.color : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _kindHeader(FanKind k) => Row(
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: k.color.withValues(alpha: .16),
          shape: BoxShape.circle,
        ),
        child: Icon(k.icon, color: k.color, size: 21),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              k.label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              _blurbs[_kind] ?? '',
              style: TextStyle(fontSize: 12.5, color: Ui.muted, height: 1.3),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _tagRow(int maxChars) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
    child: Row(
      children: [
        Flexible(
          child: TextButton.icon(
            onPressed: _busy ? null : _tagMatch,
            icon: const Icon(Icons.sports_soccer_rounded, size: 16),
            label: Text(
              _taggedMatch?.title ?? 'Tag a match',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (_taggedMatch != null)
          IconButton(
            onPressed: _busy ? null : () => setState(() => _taggedMatch = null),
            tooltip: 'Remove match tag',
            icon: const Icon(Icons.close, size: 16),
          ),
        const Spacer(),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _text,
          builder: (_, v, __) => Text(
            '${v.text.length}/$maxChars',
            style: TextStyle(fontSize: 12, color: Ui.dim),
          ),
        ),
      ],
    ),
  );

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    Widget? prefix,
    Widget? suffix,
    String? error,
  }) => InputDecoration(
    labelText: label,
    hintText: hint,
    errorText: error,
    counterText: '',
    prefixIcon: prefix,
    suffixIcon: suffix,
    filled: true,
    fillColor: Ui.card,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Ui.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Ui.line),
    ),
  );

  Widget _platformChip(EmbedKind kind, String label, IconData icon, EmbedInfo? found) {
    final on = found?.kind == kind;
    final color = FanKind.of('video').color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: on ? color.withValues(alpha: .18) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: on ? color : Ui.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(on ? Icons.check_circle_rounded : icon, size: 15, color: on ? color : Ui.dim),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: on ? color : Ui.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _howTo() {
    Widget step(int n, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: FanKind.of('video').color.withValues(alpha: .2),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.35)),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: fanBox(radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How to embed a video',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          step(1, 'Open a video on YouTube, TikTok, Facebook, Vimeo, Dailymotion or Filemoon, or copy a direct stream URL.'),
          step(2, 'Tap Share, then Copy link.'),
          step(3, 'Paste the link above (or tap the paste button).'),
          step(4, 'Add a title and an optional caption, then tap Post.'),
          Text(
            'Supports YouTube, TikTok, Facebook, Vimeo, Dailymotion and Filemoon embeds, '
            'plus HLS (.m3u8), DASH (.mpd) and direct video file streams such as MP4/WebM. '
            'Some hosts may block playback in embedded players. Portrait videos '
            'are shown in a tall player automatically.',
            style: TextStyle(fontSize: 12, color: Ui.muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  List<Widget> _videoForm() {
    final link = _url.text.trim();
    final found = _supportedVideo(link);
    final invalid = link.isNotEmpty && found == null;
    return [
      TextField(
        controller: _url,
        enabled: !_busy,
        keyboardType: TextInputType.url,
        autocorrect: false,
        onChanged: (_) => setState(() {}),
        decoration: _fieldDecoration(
          label: 'Video link',
          hint: 'Paste Vimeo, Dailymotion, Filemoon, .m3u8 or direct video URL',
          prefix: const Icon(Icons.link_rounded),
          suffix: link.isEmpty
              ? IconButton(
                  tooltip: 'Paste',
                  onPressed: _busy ? null : _pasteLink,
                  icon: const Icon(Icons.content_paste_rounded),
                )
              : IconButton(
                  tooltip: 'Clear',
                  onPressed: _busy ? null : () => setState(_url.clear),
                  icon: const Icon(Icons.close_rounded),
                ),
          error: invalid
              ? 'Use a supported video-site link or a valid .m3u8/direct stream URL.'
              : null,
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _platformChip(EmbedKind.youtube, 'YouTube', Icons.smart_display_rounded, found),
          _platformChip(EmbedKind.tiktok, 'TikTok', Icons.music_note_rounded, found),
          _platformChip(EmbedKind.facebook, 'Facebook', Icons.facebook_rounded, found),
          _platformChip(EmbedKind.vimeo, 'Vimeo', Icons.play_circle_outline_rounded, found),
          _platformChip(EmbedKind.dailymotion, 'Dailymotion', Icons.ondemand_video_rounded, found),
          _platformChip(EmbedKind.filemoon, 'Filemoon', Icons.movie_rounded, found),
          _platformChip(EmbedKind.hls, 'M3U8 / HLS', Icons.live_tv_rounded, found),
          _platformChip(EmbedKind.direct, 'Direct stream', Icons.video_file_rounded, found),
        ],
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _title,
        enabled: !_busy,
        maxLength: 100,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        decoration: _fieldDecoration(
          label: 'Title',
          hint: 'Give your video a short title',
          prefix: const Icon(Icons.title_rounded),
        ),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: fanBox(border: FanKind.of('video').color.withValues(alpha: .4)),
        child: Column(
          children: [
            TextField(
              controller: _text,
              enabled: !_busy,
              maxLength: 1000,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                counterText: '',
                hintText: _hints['video'],
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            MentionSuggestions(controller: _text),
            _tagRow(1000),
          ],
        ),
      ),
      if (found != null) ...[
        const SizedBox(height: 16),
        Text(
          'Preview',
          style: TextStyle(fontSize: 12.5, color: Ui.muted, fontWeight: FontWeight.w700),
        ),
        FanPostVideo(key: ValueKey(link), url: link, inline: true),
      ],
      const SizedBox(height: 16),
      _howTo(),
    ];
  }

  List<Widget> _standardForm(FanKind k) => [
    Container(
      padding: const EdgeInsets.all(4),
      decoration: fanBox(border: k.color.withValues(alpha: .4)),
      child: Column(
        children: [
          TextField(
            controller: _text,
            enabled: !_busy,
            maxLength: 5000,
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
          MentionSuggestions(controller: _text),
          _tagRow(5000),
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
              child: Image.memory(_image!, cacheWidth: 900, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: IconButton.filled(
              onPressed: _busy ? null : () => setState(() => _image = null),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      )
    else
      OutlinedButton.icon(
        onPressed: widget.uploadsEnabled && !_busy && !_picking ? _pickImage : null,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(
          _picking
              ? 'Opening photos…'
              : _kind == 'betslip'
              ? 'Attach your bet slip'
              : 'Attach a photo',
        ),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
    const SizedBox(height: 8),
    Text(
      widget.uploadsEnabled
          ? 'One JPG/PNG • Up to 4 MB. Crop out account details before sharing.'
          : 'Image uploads are not enabled yet. You can still publish text predictions and banter.',
      style: TextStyle(fontSize: 12, color: Ui.muted),
    ),
  ];

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
              _kindPicker(),
              const SizedBox(height: 16),
              _kindHeader(k),
              const SizedBox(height: 16),
              if (_kind == 'video') ..._videoForm() else ..._standardForm(k),
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
                        'Your post is public. Predictions are opinions, not guarantees. Premium members can edit their posts after publishing; anyone can delete their own post.',
                        style: TextStyle(fontSize: 12, color: Ui.muted, height: 1.4),
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
