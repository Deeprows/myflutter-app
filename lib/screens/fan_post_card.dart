import '../widgets/fan_match_link.dart';
import '../widgets/fan_poll_view.dart';
import '../widgets/fan_edit_sheet.dart';
import '../widgets/fan_share_sheet.dart';
import '../widgets/fan_post_video.dart';
import '../widgets/fan_web_link_card.dart';
import '../utils/post_links.dart';
import '../models/fan_post_link.dart';
import 'package:flutter/material.dart';
import '../services/fan_zone_service.dart';
import '../services/post_translation_service.dart';
import '../services/locale_service.dart';
import '../services/post_bookmarks.dart';
import 'bookmarks_screen.dart';
import '../theme/app_theme.dart';
import '../config.dart';
import 'browser_screen.dart' show openExternally;
import 'fan_widgets.dart';
import 'fan_x_widgets.dart';
import 'fan_mentions.dart';
import 'fan_profile_screen.dart';
import 'fan_thread_screen.dart';
import 'fan_video_viewer_screen.dart';
import 'promote_post_screen.dart';
import '../utils/safe_error_message.dart';

/// The same post and actions appear in Banter, profiles and comment threads.
class FanPostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final String viewerId;
  final bool openThread;
  final VoidCallback? onChanged, onBlocked, onReply;

  /// True only for the Deeprowss admin: shows Pin / Unpin in the post menu.
  final bool isAdmin;
  const FanPostCard({
    super.key,
    required this.post,
    required this.viewerId,
    this.isAdmin = false,
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
      _repostBusy = false,
      _followBusy = false,
      _followKnown = false,
      _followed = false;
  bool _translationBusy = false;
  String? _translatedText;
  String? _translationTarget;
  String? _translationError;
  /// Full-screen X-style video viewer opened from the post page.
  final ValueNotifier<int> _viewerRev = ValueNotifier<int>(0);
  bool _viewerOpen = false;

  @override
  void dispose() {
    _viewerRev.dispose();
    super.dispose();
  }

  Future<void> _openVideoViewer(String link) async {
    if (_viewerOpen) return;
    _viewerOpen = true;
    final mine = '${_post['user_id']}' == widget.viewerId;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FanVideoViewerScreen(
          url: link,
          refresh: _viewerRev,
          menuBuilder: (_) => PopupMenuButton<String>(
            tooltip: 'More',
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_vert_rounded, size: 21),
            onSelected: (v) {
              if (v == 'open') {
                openExternally(link);
              } else {
                _action(v);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'share', child: Text('Share post')),
              PopupMenuItem(
                value: 'bookmark',
                child: Text(
                  PostBookmarks.instance.isBookmarked('${_post['id']}')
                      ? 'Remove bookmark'
                      : 'Bookmark post',
                ),
              ),
              const PopupMenuItem(value: 'open', child: Text('Open original link')),
              if (!mine)
                const PopupMenuItem(value: 'report', child: Text('Report post')),
            ],
          ),
          footerBuilder: (_) => _viewerFooter(mine),
        ),
      ),
    );
    _viewerOpen = false;
  }

  Widget _viewerFooter(bool mine) {
    final liked = _post['liked'] == 1 || _post['liked'] == true;
    final handle = '@${FanZoneService.handleOf(_post, '${_post['user_id']}')}';
    final text = '${_post['text']}';
    var caption = text;
    for (final link in fanPostLinks(text)) {
      caption = caption.replaceAll(link, '');
    }
    caption = caption.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    const white = Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              FanAvatar(
                name: '${_post['name']}',
                seed: '${_post['user_id']}',
                size: 44,
                imageUrl: FanZoneService.avatarUrl(
                  '${_post['user_id']}',
                  _post['avatar_at'],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_post['name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF8B98A5), fontSize: 14),
                    ),
                  ],
                ),
              ),
              if (!mine)
                OutlinedButton.icon(
                  onPressed: _followBusy ? null : _follow,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: white,
                    side: const BorderSide(color: Color(0xFF536471)),
                    minimumSize: const Size(72, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: const StadiumBorder(),
                  ),
                  icon: Icon(
                    _followed ? Icons.check_rounded : Icons.person_add_alt_1_outlined,
                    size: 18,
                  ),
                  label: Text(
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
            ],
          ),
        ),
        if (caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              caption,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: white, fontSize: 16, height: 1.35),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _viewerActions(liked),
        ),
      ],
    );
  }

  Widget _viewerActions(bool liked) {
    final reposts = (_post['reposts'] as num?)?.toInt() ?? 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        XAction(
          icon: Icons.chat_bubble_outline_rounded,
          count: (_post['comments'] as num?)?.toInt() ?? 0,
          tooltip: 'Reply to post',
          onTap: () {
            Navigator.of(context).maybePop();
            widget.onReply?.call();
          },
        ),
        XAction(
          icon: Icons.repeat_rounded,
          count: reposts,
          color: const Color(0xFF00BA7C),
          active: _reposted,
          tooltip: _reposted ? 'Reposted' : 'Repost or quote',
          onTap: _repostBusy ? null : _repostMenu,
        ),
        XAction(
          icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          count: (_post['likes'] as num?)?.toInt() ?? 0,
          color: const Color(0xFFF91880),
          active: liked,
          tooltip: liked ? 'Unlike post' : 'Like post',
          onTap: _busy ? null : _like,
        ),
        ValueListenableBuilder<Set<String>>(
          valueListenable: PostBookmarks.instance.ids,
          builder: (_, saved, _) {
            final on = saved.contains('${_post['id']}');
            return XAction(
              icon: on ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: const Color(0xFF1D9BF0),
              active: on,
              tooltip: on ? 'Remove bookmark' : 'Bookmark post',
              onTap: () => _action('bookmark'),
            );
          },
        ),
        XAction(
          icon: Icons.ios_share_rounded,
          tooltip: 'Share post',
          onTap: () => _action('share'),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _post = Map.of(widget.post);
    PostBookmarks.instance.load();
    if (!widget.openThread) _loadFollow();
  }

  @override
  void didUpdateWidget(covariant FanPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy) _post = Map.of(widget.post);
    if (oldWidget.post['id'] != widget.post['id'] ||
        oldWidget.post['text'] != widget.post['text']) {
      _translatedText = null;
      _translationTarget = null;
      _translationError = null;
    }
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
      _notice(safeErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _isRepost => '${_post['kind']}' == 'repost';
  String get _quoteOf => '${_post['quote_of'] ?? ''}';

  Future<void> _openPost(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => FanThreadScreen(postId: id)),
    );
    if (mounted) widget.onChanged?.call();
  }

  /// Opens this post's thread (a plain repost opens the reposted post).
  Future<void> _thread() => _openPost(
    _isRepost && _quoteOf.isNotEmpty ? _quoteOf : '${_post['id']}',
  );

  bool get _reposted => _post['reposted'] == 1 || _post['reposted'] == true;

  /// Repost / undo repost / quote, like the X repost menu.
  Future<void> _repostMenu() async {
    if (_repostBusy) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.repeat_rounded,
                color: _reposted ? const Color(0xFF00BA7C) : null,
              ),
              title: Text(_reposted ? 'Undo repost' : 'Repost'),
              onTap: () => Navigator.pop(ctx, 'repost'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Quote'),
              onTap: () => Navigator.pop(ctx, 'quote'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'repost') await _toggleRepost();
    if (choice == 'quote') await _quote();
  }

  Future<void> _toggleRepost() async {
    setState(() => _repostBusy = true);
    try {
      final result = await FanZoneService.call(
        'social/repost',
        body: {'id': _post['id'], 'reposted': !_reposted},
      );
      if (mounted) {
        setState(() {
          _post['reposted'] = result['reposted'] == true ? 1 : 0;
          _post['reposts'] = result['reposts'];
        });
        _notice(result['reposted'] == true ? 'Reposted' : 'Repost removed');
        widget.onChanged?.call();
      }
    } catch (e) {
      _notice(safeErrorMessage(e));
    } finally {
      if (mounted) setState(() => _repostBusy = false);
    }
  }

  Future<void> _quote() async {
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _QuoteComposer(post: _post),
    );
    if (posted == true && mounted) {
      _notice('Quote posted');
      widget.onChanged?.call();
    }
  }

  Future<void> _promotePost() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PromotePostScreen(
          postId: '${_post['id']}',
          postText: '${_post['text'] ?? ''}',
        ),
      ),
    );
  }

  bool get _isPinned => _post['pinned'] == 1 || _post['pinned'] == true;

  /// Admin only. Pinned posts show on top of the Thread page as "Sponsored".
  Future<void> _pin() async {
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pin as Sponsored post'),
        children: [
          for (final d in const [1, 3, 7, 14, 30])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Text('$d day${d == 1 ? '' : 's'}'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('Until I unpin it'),
          ),
        ],
      ),
    );
    if (days == null) return;
    try {
      await FanZoneService.pinPost('${_post['id']}', pinned: true, days: days);
      if (!mounted) return;
      setState(() => _post['pinned'] = 1);
      _notice('Pinned as Sponsored post');
      widget.onChanged?.call();
    } catch (e) {
      _notice(safeErrorMessage(e));
    }
  }

  Future<void> _unpin() async {
    try {
      await FanZoneService.pinPost('${_post['id']}', pinned: false);
      if (!mounted) return;
      setState(() => _post['pinned'] = 0);
      _notice('Post unpinned');
      widget.onChanged?.call();
    } catch (e) {
      _notice(safeErrorMessage(e));
    }
  }

  /// "Ad" tag (admin ads) and "Sponsored" tag (pinned posts) shown above a post.
  Widget _tags() {
    final ad = _post['is_ad'] == 1 || _post['is_ad'] == true;
    if (!ad && !_isPinned) return const SizedBox.shrink();
    Widget chip(String text, IconData icon) => Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Ui.red.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Ui.redSoft),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: Ui.redSoft,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          if (ad) chip('Ad', Icons.campaign_rounded),
          if (_isPinned) chip('Sponsored', Icons.push_pin_rounded),
        ],
      ),
    );
  }

  Future<void> _action(String action) async {
    if (action == 'promote') {
      await _promotePost();
      return;
    }
    if (action == 'pin') {
      await _pin();
      return;
    }
    if (action == 'unpin') {
      await _unpin();
      return;
    }
    try {
      if (action == 'bookmark') {
        final added = await PostBookmarks.instance.toggle(_post);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                added ? 'Saved to Bookmarks' : 'Removed from Bookmarks',
              ),
              action: added
                  ? SnackBarAction(
                      label: 'View',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BookmarksScreen(),
                        ),
                      ),
                    )
                  : null,
            ),
          );
        return;
      }
      if (action == 'share') {
        if (!mounted) return;
        await showFanShareSheet(
          context,
          author: '${_post['name']}',
          text: '${_post['text'] ?? ''}',
          url: FanZoneService.postUrl('${_post['id']}'),
        );
        return;
      }
      if (action == 'block') {
        await FanZoneService.block('${_post['user_id']}');
        if (mounted) widget.onBlocked?.call();
        _notice('Fan hidden on this device.');
        return;
      }
      if (action == 'edit' && !_isRepost) {
        final saved = await fanEditContent(
          context,
          title: 'Edit post',
          initial: '${_post['text']}',
          maxLength: 5000,
          save: (text) => FanZoneService.editPost('${_post['id']}', text),
        );
        if (saved != null && mounted) {
          setState(() {
            _post['text'] = saved;
            _post['edited_at'] = DateTime.now().millisecondsSinceEpoch;
          });
          widget.onChanged?.call();
          _notice('Post updated.');
        }
        return;
      }
      if (action == 'delete' && !_isRepost) {
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
      _notice(
        action == 'delete'
            ? (_isRepost ? 'Repost removed.' : 'Post deleted.')
            : 'Report sent for review.',
      );
    } catch (e) {
      _notice(safeErrorMessage(e));
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
      _notice(safeErrorMessage(e));
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Widget _menu(bool mine) => PopupMenuButton<String>(
    tooltip: 'Post options',
    onSelected: _action,
    padding: EdgeInsets.zero,
    icon: Icon(Icons.more_horiz_rounded, color: Ui.dim, size: 21),
    itemBuilder: (_) => _isRepost
        ? [
            if (mine)
              const PopupMenuItem(value: 'delete', child: Text('Undo repost'))
            else ...const [
              PopupMenuItem(value: 'report', child: Text('Report post')),
              PopupMenuItem(value: 'block', child: Text('Hide fan on this device')),
            ],
          ]
        : [
      const PopupMenuItem(value: 'share', child: Text('Share post')),
      const PopupMenuItem(
        value: 'promote',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined, size: 18),
            SizedBox(width: 9),
            Text('Promote this post'),
          ],
        ),
      ),
      if (widget.isAdmin)
        PopupMenuItem(
          value: _isPinned ? 'unpin' : 'pin',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 18,
              ),
              const SizedBox(width: 9),
              Text(_isPinned ? 'Unpin post' : 'Pin as Sponsored'),
            ],
          ),
        ),
      PopupMenuItem(
        value: 'bookmark',
        child: Text(
          PostBookmarks.instance.isBookmarked('${_post['id']}')
              ? 'Remove bookmark'
              : 'Bookmark post',
        ),
      ),
      if (mine)
        const PopupMenuItem(value: 'edit', child: Text('Edit post')),
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

  Widget _actions(bool liked, {required bool detail}) {
    final reposts = (_post['reposts'] as num?)?.toInt() ?? 0;
    final views = (_post['views'] as num?)?.toInt() ?? 0;
    const green = Color(0xFF00BA7C);
    final items = <Widget>[
      XAction(
        icon: Icons.chat_bubble_outline_rounded,
        count: detail ? null : (_post['comments'] as num?)?.toInt() ?? 0,
        tooltip: 'Reply to post',
        onTap: widget.openThread ? _thread : widget.onReply,
      ),
      XAction(
        icon: Icons.repeat_rounded,
        count: detail ? null : reposts,
        color: green,
        active: _reposted,
        tooltip: _reposted ? 'Reposted' : 'Repost or quote',
        onTap: _repostBusy ? null : _repostMenu,
      ),
      XAction(
        icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        count: detail ? null : (_post['likes'] as num?)?.toInt() ?? 0,
        color: const Color(0xFFF91880),
        active: liked,
        tooltip: liked ? 'Unlike post' : 'Like post',
        onTap: _busy ? null : _like,
      ),
      if (!detail)
        XAction(
          icon: Icons.bar_chart_rounded,
          count: views,
          tooltip: 'Views',
        ),
      ValueListenableBuilder<Set<String>>(
        valueListenable: PostBookmarks.instance.ids,
        builder: (_, saved, _) {
          final on = saved.contains('${_post['id']}');
          return XAction(
            icon: on ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: const Color(0xFF1D9BF0),
            active: on,
            tooltip: on ? 'Remove bookmark' : 'Bookmark post',
            onTap: () => _action('bookmark'),
          );
        },
      ),
      XAction(
        icon: Icons.ios_share_rounded,
        tooltip: 'Share post',
        onTap: () => _action('share'),
      ),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: items,
    );
  }

  /// The post this one quotes (or, for a plain repost, the reposted post).
  Widget _quoteEmbed() {
    final name = _post['q_name'];
    final available = name != null;
    final text = '${_post['q_text'] ?? ''}';
    final userId = '${_post['q_user_id'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: available ? () => _openPost(_quoteOf) : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Ui.line),
          ),
          child: !available
              ? Text(
                  'This post is unavailable.',
                  style: TextStyle(color: Ui.muted),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        FanAvatar(
                          name: '$name',
                          seed: userId,
                          size: 22,
                          imageUrl: FanZoneService.avatarUrl(
                            userId,
                            _post['q_avatar_at'],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '$name',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      '  @${FanZoneService.handleOf({'handle': _post['q_handle']}, userId)} · ${fanTimeAgo(_post['q_at']).replaceAll(' ago', '')}',
                                  style: TextStyle(color: Ui.muted, fontSize: 12.5),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text.rich(
                          TextSpan(
                            children: xRichSpans(
                              text,
                              base: const TextStyle(fontSize: 14.5, height: 1.38),
                            ),
                          ),
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (_post['q_has_image'] == 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: Image.network(
                              FanZoneService.imageUrl(_quoteOf),
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, e, s) => const SizedBox(
                                height: 60,
                                child: Center(child: Text('Image unavailable')),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _translatePost(String source, String target) async {
    if (_translationBusy) return;
    setState(() {
      _translationBusy = true;
      _translationError = null;
    });
    try {
      final result = await PostTranslationService.instance.translate(
        source,
        target,
      );
      if (!mounted) return;
      setState(() {
        _translatedText = result;
        _translationTarget = target;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _translationError = safeErrorMessage(e));
    } finally {
      if (mounted) setState(() => _translationBusy = false);
    }
  }

  String _languageName(String code) {
    for (final language in AppLocale.supported) {
      if (language.code == code) return language.native;
    }
    return code.toUpperCase();
  }

  Widget _translationControl(String source) {
    final current = AppLocale.code;
    final targets = <String>{current, 'en'}.toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_translatedText != null)
          TextButton.icon(
            onPressed: () => setState(() {
              _translatedText = null;
              _translationTarget = null;
              _translationError = null;
            }),
            icon: const Icon(Icons.translate_rounded, size: 16),
            label: const Text('Show original'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          )
        else
          PopupMenuButton<String>(
            enabled: !_translationBusy,
            tooltip: 'Translate post',
            onSelected: (target) => _translatePost(source, target),
            itemBuilder: (_) => targets
                .map((target) => PopupMenuItem<String>(
                      value: target,
                      child: Text('Translate to ${_languageName(target)}'),
                    ))
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_translationBusy)
                  const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                else
                  const Icon(Icons.translate_rounded, size: 17),
                const SizedBox(width: 5),
                Text(
                  _translationBusy ? 'Translating…' : 'Translate',
                  style: TextStyle(
                    color: Ui.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 17),
              ]),
            ),
          ),
        if (_translationTarget != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('· ${_languageName(_translationTarget!)}',
              style: TextStyle(color: Ui.muted, fontSize: 11)),
          ),
      ],
    );
  }

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
    final originalDisplayText = displayText;
    // Video posts: the first line is the title, the rest is the caption.
    String? videoTitle;
    if (kindKey == 'video' && displayText.isNotEmpty) {
      final nl = displayText.indexOf('\n');
      videoTitle = nl < 0 ? displayText : displayText.substring(0, nl).trim();
      displayText = nl < 0 ? '' : displayText.substring(nl).trim();
    }
    final translated = _translatedText;
    if (translated != null) {
      displayText = translated;
      videoTitle = null;
    }
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
        if (originalDisplayText.trim().isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: _translationControl(originalDisplayText),
          ),
        if (_translationError != null)
          Padding(padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _translationError!,
              style: TextStyle(color: Ui.red, fontSize: 12),
            ),
          ),
        if (videoTitle != null && videoTitle.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: detail ? 12 : 2),
            child: Text(
              videoTitle,
              style: TextStyle(
                fontSize: detail ? 22 : 16.5,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
        if (displayText.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: detail ? 12 : 2),
            child: detail
                ? SelectableText.rich(
                    TextSpan(
                      children: xRichSpans(
                        displayText,
                        base: style,
                        onMention: (h) => openProfileByHandle(context, h),
                      ),
                    ),
                  )
                : Text.rich(
                    TextSpan(
                      children: xRichSpans(
                        displayText,
                        base: style,
                        onMention: (h) => openProfileByHandle(context, h),
                      ),
                    ),
                  ),
          ),
        FanMatchLink(snapshot: '${_post['match_json'] ?? ''}', text: text),
        if (_post['has_image'] == 1) _media(detail),
        if (FanPollView.hasPoll(_post))
          FanPollView(
            key: ValueKey('poll-${_post['id']}'),
            post: _post,
            // Also update the feed's copy so a rebuild keeps the vote.
            onVoted: (u) => widget.post.addAll(u),
          ),
        if (_quoteOf.isNotEmpty && !_isRepost) _quoteEmbed(),
        for (final link in videoLinks)
          if (isWebPageLink(link) && kindKey != 'video')
            FanWebLinkCard(key: ValueKey(link), url: link)
          else
            FanPostVideo(
            key: ValueKey(link),
            url: link,
            inline: true,
            // Feed: tap opens the post. Post page: tap opens the full-screen
            // X-style video viewer.
            onTapPreview: widget.openThread ? _thread : null,
            onOpenViewer: widget.openThread ? null : () => _openVideoViewer(link),
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
    final edited = (_post['edited_at'] is num && (_post['edited_at'] as num) > 0)
        ? ' · edited'
        : '';
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} · ${date.day} ${months[date.month - 1]} ${date.year}$edited';
  }

  @override
  Widget build(BuildContext context) {
    if (_viewerOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _viewerOpen) _viewerRev.value++;
      });
    }
    final mine = '${_post['user_id']}' == widget.viewerId;
    final liked = _post['liked'] == 1 || _post['liked'] == true;
    final handle = '@${FanZoneService.handleOf(_post, '${_post['user_id']}')}';
    if (!widget.openThread)
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tags(),
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${_post['name']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (_post['is_premium'] == 1 || _post['is_premium'] == true) ...[
                              const SizedBox(width: 5),
                              const FanVerifiedBadge(size: 17),
                            ],
                          ],
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
                runSpacing: 6,
                children: [
                  Text(
                    '${_post['views'] ?? 0} Views',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${_post['reposts'] ?? 0} Reposts',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
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
            _actions(liked, detail: true),
            const XDivider(),
          ],
        ),
      );
    if (_isRepost)
      return InkWell(
        onTap: _thread,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Ui.line, width: .6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(width: 24),
                  Icon(Icons.repeat_rounded, size: 15, color: Ui.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: InkWell(
                      onTap: _profile,
                      child: Text(
                        mine ? 'You reposted' : '${_post['name']} reposted',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Ui.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  _menu(mine),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _quoteEmbed(),
              ),
            ],
          ),
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
                  _tags(),
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
                                if (_post['is_premium'] == 1 ||
                                    _post['is_premium'] == true)
                                  const WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Padding(
                                      padding: EdgeInsets.only(left: 4),
                                      child: FanVerifiedBadge(size: 16),
                                    ),
                                  ),
                                TextSpan(
                                  text:
                                      '  $handle · ${fanTimeAgo(_post['at']).replaceAll(' ago', '')}${(_post['edited_at'] is num && (_post['edited_at'] as num) > 0) ? ' · edited' : ''}',
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
                  _actions(liked, detail: false),
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

/// Bottom sheet that adds a comment to a post and publishes it as a quote.
class _QuoteComposer extends StatefulWidget {
  final Map<String, dynamic> post;
  const _QuoteComposer({required this.post});
  @override
  State<_QuoteComposer> createState() => _QuoteComposerState();
}

class _QuoteComposerState extends State<_QuoteComposer> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_busy || _text.text.trim().isEmpty) return;
    if (textHasWebPageLink(_text.text) && !await ensureLinkPremium(context)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FanZoneService.publish(
        kind: 'banter',
        text: _text.text,
        quoteOf: '${widget.post['id']}',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = safeErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final userId = '${p['user_id']}';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _text,
                builder: (_, value, _) => FilledButton(
                  onPressed: _busy || value.text.trim().isEmpty ? null : _publish,
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(_busy ? 'Posting…' : 'Post'),
                ),
              ),
            ],
          ),
          TextField(
            controller: _text,
            autofocus: true,
            enabled: !_busy,
            minLines: 2,
            maxLines: 6,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Add a comment',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
          MentionSuggestions(controller: _text),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Ui.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    FanAvatar(
                      name: '${p['name']}',
                      seed: userId,
                      size: 22,
                      imageUrl: FanZoneService.avatarUrl(userId, p['avatar_at']),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${p['name']}'),
                            if (p['is_premium'] == 1 || p['is_premium'] == true)
                              const WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: EdgeInsets.only(left: 3),
                                  child: FanVerifiedBadge(size: 14),
                                ),
                              ),
                            TextSpan(
                                text:
                                    '  @${FanZoneService.handleOf(p, userId)}'),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                if ('${p['text']}'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${p['text']}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
