import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/fan_zone_service.dart';
import '../theme/app_theme.dart';
import 'fan_widgets.dart';
import 'fan_profile_screen.dart';
import 'fan_thread_screen.dart';

/// The same post and actions appear in Banter, profiles and comment threads.
class FanPostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final String viewerId;
  final bool openThread;
  final VoidCallback? onChanged, onBlocked;
  const FanPostCard({
    super.key,
    required this.post,
    required this.viewerId,
    this.openThread = true,
    this.onChanged,
    this.onBlocked,
  });
  @override
  State<FanPostCard> createState() => _FanPostCardState();
}

class _FanPostCardState extends State<FanPostCard> {
  late Map<String, dynamic> _post;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _post = Map.of(widget.post);
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
    if (mounted) widget.onChanged?.call();
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

  @override
  Widget build(BuildContext context) {
    final mine = '${_post['user_id']}' == widget.viewerId;
    final liked = _post['liked'] == 1 || _post['liked'] == true;
    final kind = FanKind.of('${_post['kind']}');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: fanBox(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: _profile,
                borderRadius: BorderRadius.circular(30),
                child: FanAvatar(
                  name: '${_post['name']}',
                  seed: '${_post['user_id']}',
                  size: 42,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: _profile,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_post['name']}${mine ? ' (you)' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '@${FanZoneService.handle('${_post['user_id']}')} · ${fanTimeAgo(_post['at'])}',
                        style: TextStyle(color: Ui.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              FanPill(text: kind.label, color: kind.color),
              PopupMenuButton<String>(
                onSelected: _action,
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
                    PopupMenuItem(value: 'report', child: Text('Report post')),
                    PopupMenuItem(
                      value: 'block',
                      child: Text('Hide fan on this device'),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if ('${_post['text']}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SelectableText(
                '${_post['text']}',
                style: const TextStyle(fontSize: 15.5, height: 1.5),
              ),
            ),
          if (_post['has_image'] == 1)
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _FanImage(postId: '${_post['id']}'),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  FanZoneService.imageUrl('${_post['id']}'),
                  height: 230,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  errorBuilder: (_, error, stack) => const SizedBox(
                    height: 90,
                    child: Center(child: Text('Image unavailable')),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: _busy ? null : _like,
                  icon: Icon(
                    liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 18,
                  ),
                  label: Text('${_post['likes'] ?? 0}'),
                  style: TextButton.styleFrom(
                    foregroundColor: liked ? Ui.redSoft : Ui.muted,
                  ),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: widget.openThread ? _thread : null,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: Text('${_post['comments'] ?? 0}'),
                  style: TextButton.styleFrom(foregroundColor: Ui.muted),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _action('share'),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Share'),
                  style: TextButton.styleFrom(foregroundColor: Ui.muted),
                ),
              ),
            ],
          ),
        ],
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
