import '../widgets/fan_match_link.dart';
import '../widgets/fan_post_video.dart';
import '../models/fan_post_link.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/fan_zone_service.dart';
import '../theme/app_theme.dart';
import 'fan_widgets.dart';
import 'fan_x_widgets.dart';
import 'fan_profile_screen.dart';
import 'fan_thread_screen.dart';

/// The same post and actions appear in Banter, profiles and comment threads.
class FanPostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final String viewerId;
  final bool openThread;
  final VoidCallback? onChanged, onBlocked, onReply;
  const FanPostCard({
    super.key,
    required this.post,
    required this.viewerId,
    this.openThread = true,
    this.onChanged,
    this.onBlocked,
    this.onReply,
  });
  @override
  State<FanPostCard> createState() => _FanPostCardState();
}

class _FanPostCardState extends State<FanPostCard> {
  late Map<String, dynamic> _post;
  bool _busy = false,
      _followBusy = false,
      _followKnown = false,
      _followed = false;
  @override
  void initState() {
    super.initState();
    _post = Map.of(widget.post);
    if (!widget.openThread) _loadFollow();
  }

  @override
  void didUpdateWidget(covariant FanPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy) _post = Map.of(widget.post);
  }

  void _notice(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _profile() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FanProfileScreen(userId: '${_post['user_id']}'),
      ),
    );
    if (mounted) {
      widget.onChanged?.call();
      if (!widget.openThread) _loadFollow();
    }
  }

  Future<void> _like() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FanZoneService.call(
        'social/like',
        body: {
          'id': _post['id'],
          'liked': !(_post['liked'] == 1 || _post['liked'] == true),
        },
      );
      if (mounted)
        setState(() {
          _post['liked'] = result['liked'];
          _post['likes'] = result['likes'];
        });
      if (mounted) widget.onChanged?.call();
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _thread() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FanThreadScreen(postId: '${_post['id']}'),
      ),
    );
    if (mounted) widget.onChanged?.call();
  }

  Future<void> _action(String action) async {
    try {
      if (action == 'share') {
        await Share.share(
          '${_post['name']} on Deeprowss\n${_post['text']}\n\n${FanZoneService.postUrl('${_post['id']}')}',
        );
        return;
      }
      if (action == 'block') {
        await FanZoneService.block('${_post['user_id']}');
        if (mounted) widget.onBlocked?.call();
        _notice('Fan hidden on this device.');
        return;
      }
      if (action == 'delete') {
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete this post?'),
            content: const Text(
              'The post and its comment thread will no longer be visible.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
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
          'id': _post['id'],
          if (action == 'report') 'reason': 'Inappropriate content',
        },
      );
      if (mounted) widget.onChanged?.call();
      _notice(action == 'delete' ? 'Post deleted.' : 'Report sent for review.');
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _loadFollow() async {
    if (_followBusy || '${_post['user_id']}' == widget.viewerId) return;
    setState(() => _followBusy = true);
    try {
      final data = await FanZoneService.call(
        'social/profile',
        query: {'id': '${_post['user_id']}'},
      );
      if (mounted)
        setState(() {
          final profile = data['profile'] as Map;
          _followed = profile['followed'] == 1 || profile['followed'] == true;
          _followKnown = true;
        });
    } catch (_) {
      /* The retry button never guesses the current follow state. */
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _follow() async {
    if (_followBusy) return;
    if (!_followKnown) {
      await _loadFollow();
      return;
    }
    setState(() => _followBusy = true);
    try {
      final data = await FanZoneService.call(
        'social/follow',
        body: {'id': _post['user_id'], 'following': !_followed},
      );
      if (mounted) {
        setState(() => _followed = data['following'] == true);
        widget.onChanged?.call();
      }
    } catch (e) {
      _notice(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Widget _menu(bool mine) => PopupMenuButton<String>(
    tooltip: 'Post options',
    onSelected: _action,
    padding: EdgeInsets.zero,
    icon: Icon(Icons.more_horiz_rounded, color: Ui.dim, size: 21),
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'share', child: Text('Share post')),
      if (mine)
        const PopupMenuItem(value: 'delete', child: Text('Delete post')),
      if (!mine) ...const [
        PopupMenuItem(value: 'report', child: Text('Report post')),
        PopupMenuItem(value: 'block', child: Text('Hide fan on this device')),
      ],
    ],
  );

  Widget _avatar(double size) => InkResponse(
    onTap: _profile,
    radius: size / 2 + 4,
    child: FanAvatar(
      name: '${_post['name']}',
      seed: '${_post['user_id']}',
      size: size,
      imageUrl: FanZoneService.avatarUrl(
        '${_post['user_id']}',
        _post['avatar_at'],
      ),
    ),
  );

  Widget _media(bool detail) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _FanImage(postId: '${_post['id']}'),
        ),
      ),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: detail ? 800 : 520),
        decoration: BoxDecoration(
          color: Ui.cardDeep,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Ui.line, width: .6),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          FanZoneService.imageUrl('${_post['id']}'),
          width: double.infinity,
          fit: BoxFit.contain,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const SizedBox(
                  height: 200,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
          errorBuilder: (_, error, stack) => const SizedBox(
            height: 100,
            child: Center(child: Text('Image unavailable')),
          ),
        ),
      ),
    ),
  );

  Widget _actions(bool liked) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      XAction(
        icon: Icons.chat_bubble_outline_rounded,
        count: (_post['comments'] as num?)?.toInt() ?? 0,
        tooltip: 'Reply to post',
        onTap: widget.openThread ? _thread : widget.onReply,
      ),
      XAction(
        icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        count: (_post['likes'] as num?)?.toInt() ?? 0,
        color: const Color(0xFFF91880),
        active: liked,
        tooltip: liked ? 'Unlike post' : 'Like post',
        onTap: _busy ? null : _like,
      ),
      XAction(
        icon: Icons.ios_share_rounded,
        tooltip: 'Share post',
        onTap: () => _action('share'),
      ),
    ],
  );

  Widget _content(bool detail) {
    final kindKey = '${_post['kind']}';
    final kind = FanKind.of(kindKey);
    final text = '${_post['text']}';
    final videoLinks = fanPostLinks(text);
    // Video URLs are rendered as embedded preview cards, not as raw links.
    var displayText = text;
    for (final link in videoLinks) {
      displayText = displayText.replaceAll(link, '').replaceAll(RegExp(r'[ \t]+\n'), '\n');
    }
    displayText = displayText.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    final style = TextStyle(fontSize: detail ? 21 : 15.5, height: 1.42);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (kindKey == 'prediction' || kindKey == 'betslip')
          Padding(
            padding: const EdgeInsets.only(top: 5, bottom: 4),
            child: FanPill(
              text: kind.label,
              color: kind.color,
              icon: kind.icon,
            ),
          ),
        if (text.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: detail ? 12 : 2),
            child: detail
                ? SelectableText.rich(
                    TextSpan(children: xRichSpans(displayText, base: style)),
                  )
                : Text.rich(TextSpan(children: xRichSpans(displayText, base: style))),
          ),
        FanMatchLink(snapshot: '${_post['match_json'] ?? ''}', text: text),
        if (_post['has_image'] == 1) _media(detail),
        for (final link in videoLinks)
          FanPostVideo(
            key: ValueKey(link),
            url: link,
            inline: true,
            // Feed: tap opens the post. Post page: video plays in place.
            onTapPreview: widget.openThread ? _thread : null,
            autoPlay: !widget.openThread && link == videoLinks.first,
          ),
      ],
    );
  }

  String _timestamp() {
    final date = DateTime.fromMillisecondsSinceEpoch(
      (_post['at'] as num).toInt(),
    ).toLocal();
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
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} · ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final mine = '${_post['user_id']}' == widget.viewerId;
    final liked = _post['liked'] == 1 || _post['liked'] == true;
    final handle = '@${FanZoneService.handle('${_post['user_id']}')}';
    if (!widget.openThread)
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _avatar(48),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: _profile,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_post['name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          handle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Ui.muted, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!mine)
                  FilledButton(
                    onPressed: _followBusy ? null : _follow,
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.onSurface,
                      foregroundColor: Theme.of(context).colorScheme.surface,
                      minimumSize: const Size(72, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      _followBusy
                          ? '…'
                          : !_followKnown
                          ? 'Retry'
                          : _followed
                          ? 'Following'
                          : 'Follow',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                _menu(mine),
              ],
            ),
            _content(true),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _timestamp(),
                style: TextStyle(color: Ui.muted, fontSize: 13),
              ),
            ),
            const XDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Wrap(
                spacing: 20,
                children: [
                  Text(
                    '${_post['likes'] ?? 0} Likes',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${_post['comments'] ?? 0} Replies',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const XDivider(),
            _actions(liked),
            const XDivider(),
          ],
        ),
      );
    return InkWell(
      onTap: _thread,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 0),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Ui.line, width: .6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 4), child: _avatar(42)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _profile,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${_post['name']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      '  $handle · ${fanTimeAgo(_post['at']).replaceAll(' ago', '')}',
                                  style: TextStyle(
                                    color: Ui.muted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      _menu(mine),
                    ],
                  ),
                  _content(false),
                  _actions(liked),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FanImage extends StatelessWidget {
  final String postId;
  const _FanImage({required this.postId});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: const Text('Post image'),
      backgroundColor: Colors.black,
    ),
    body: Center(
      child: InteractiveViewer(
        minScale: .5,
        maxScale: 5,
        child: Image.network(
          FanZoneService.imageUrl(postId),
          errorBuilder: (_, error, stack) => const Text('Image unavailable'),
        ),
      ),
    ),
  );
}
