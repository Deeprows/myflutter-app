import 'package:flutter/material.dart';
import '../services/fan_zone_service.dart';
import '../services/content_sync.dart';
import '../theme/app_theme.dart';
import 'fan_post_card.dart';
import 'fan_profile_screen.dart';
import 'fan_widgets.dart';
import 'fan_x_widgets.dart';

class FanThreadScreen extends StatefulWidget {
  final String postId;
  const FanThreadScreen({super.key, required this.postId});
  @override
  State<FanThreadScreen> createState() => _FanThreadScreenState();
}

class _FanThreadScreenState extends State<FanThreadScreen> {
  final _text = TextEditingController();
  Map<String, dynamic>? _post;
  List<Map<String, dynamic>> _comments = [];
  String _viewer = '';
  String? _next, _error;
  bool _loading = false, _sending = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _notice(Object e) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
  }

  Future<void> _load({bool more = false}) async {
    if (!mounted || _loading) return;
    setState(() => _loading = true);
    try {
      final data = await FanZoneService.call(
        'social/comments',
        query: {
          'id': widget.postId,
          if (more && _next != null) 'before': _next!,
        },
      );
      final blocked = await FanZoneService.blocked();
      if (!mounted) return;
      setState(() {
        _post = Map<String, dynamic>.from(data['post'] as Map);
        _viewer = '${data['viewer_id']}';
        final rows = FanZoneService.rows(
          data['comments'],
        ).where((c) => !blocked.contains(c['user_id']));
        final seen = more ? _comments.map((c) => c['id']).toSet() : <dynamic>{};
        _comments = [
          ...(more ? _comments : <Map<String, dynamic>>[]),
          ...rows.where((c) => seen.add(c['id'])),
        ];
        _next = data['next'] as String?;
        _error = null;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          if (!more) {
            _post = null;
            _comments = [];
          }
        });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    if (_sending || _text.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await FanZoneService.call(
        'social/comment',
        body: {'id': widget.postId, 'text': _text.text.trim()},
      );
      if (!mounted) return;
      _text.clear();
      await _load();
      ContentSync.request(force: true);
    } catch (e) {
      _notice(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _action(String action, Map<String, dynamic> comment) async {
    if (action == 'delete') {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove this comment?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    try {
      await FanZoneService.call(
        'social/comment-$action',
        body: {'id': comment['id']},
      );
      if (action == 'delete') {
        await _load();
        ContentSync.request(force: true);
      } else {
        _notice('Report sent for review.');
      }
    } catch (e) {
      _notice(e);
    }
  }

  Widget _comment(Map<String, dynamic> c) {
    final mine = c['user_id'] == _viewer, owner = _post?['user_id'] == _viewer;
    void profile() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FanProfileScreen(userId: '${c['user_id']}'),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Ui.line, width: .6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: profile,
            child: FanAvatar(
              name: '${c['name']}',
              seed: '${c['user_id']}',
              size: 34,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: profile,
                  child: Text(
                    '${c['name']}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  fanTimeAgo(c['at']),
                  style: TextStyle(color: Ui.muted, fontSize: 11),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  '${c['text']}',
                  style: const TextStyle(height: 1.4),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (a) => _action(a, c),
            itemBuilder: (_) => [
              if (mine || owner)
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Remove comment'),
                ),
              if (!mine)
                const PopupMenuItem(
                  value: 'report',
                  child: Text('Report comment'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ui.bg,
    appBar: AppBar(
      title: const Text('Post'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!),
                  ),
                if (_post != null)
                  FanPostCard(
                    post: _post!,
                    viewerId: _viewer,
                    openThread: false,
                    onChanged: _load,
                    onBlocked: () => Navigator.pop(context),
                  ),
                const XSectionGap(),
                if (!_loading && _post != null && _comments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No replies yet. Start the conversation.'),
                  ),
                for (final c in _comments) _comment(c),
                if (_next != null)
                  OutlinedButton(
                    onPressed: _loading ? null : () => _load(more: true),
                    child: const Text('Load older comments'),
                  ),
              ],
            ),
          ),
        ),
        if (_post != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        hintText: 'Post your reply…',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(26)),
                        ),
                      ),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Post comment',
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
