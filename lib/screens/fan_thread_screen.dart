import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../utils/safe_error_message.dart';
import '../utils/post_links.dart';
import '../services/fan_zone_service.dart';
import '../services/app_memory.dart';
import '../services/content_sync.dart';
import '../theme/app_theme.dart';
import '../widgets/fan_edit_sheet.dart';
import 'fan_post_card.dart';
import 'fan_mentions.dart';
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
  static const _maxImage = 4 * 1024 * 1024;
  final _text = TextEditingController();
  final _replyFocus = FocusNode();
  Map<String, dynamic>? _post;
  List<Map<String, dynamic>> _comments = [];
  String _viewer = '';
  bool _isAdmin = false;
  String? _next, _error;
  bool _loading = false, _sending = false, _picking = false, _viewed = false;

  /// The comment the fan is answering (null = replying to the post itself).
  Map<String, dynamic>? _replyingTo;
  Uint8List? _image;
  final Set<String> _likeBusy = {};

  @override
  void initState() {
    super.initState();
    PageMemory.open('post', widget.postId);
    _load();
  }

  @override
  void dispose() {
    PageMemory.close('post', widget.postId);
    _replyFocus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _notice(Object e) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(safeErrorMessage(e))),
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
        _isAdmin = data['is_admin'] == true;
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
      _countView();
    } catch (e) {
      if (mounted)
        setState(() {
          _error = safeErrorMessage(e);
          if (!more) {
            _post = null;
            _comments = [];
          }
        });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Opening the post counts one view for this fan.
  Future<void> _countView() async {
    if (_viewed) return;
    _viewed = true;
    final views = await FanZoneService.recordView(widget.postId);
    if (views != null && mounted && _post != null) {
      setState(() => _post = {..._post!, 'views': views});
    }
  }

  // ---------------------------------------------------------------- compose

  Future<void> _pickImage() async {
    if (_picking || _sending) return;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif'],
        withData: false,
        withReadStream: true,
        allowMultiple: false,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      if (file.size > _maxImage) {
        throw Exception('Choose a JPG, PNG or GIF smaller than 4 MB.');
      }
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.readStream != null) {
        final buffer = BytesBuilder(copy: false);
        await for (final chunk in file.readStream!) {
          if (buffer.length + chunk.length > _maxImage) {
            throw Exception('Choose an image smaller than 4 MB.');
          }
          buffer.add(chunk);
        }
        bytes = buffer.takeBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Could not read this image. Choose another one.');
      }
      if (mounted) setState(() => _image = bytes);
    } catch (e) {
      _notice(e);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _replyTo(Map<String, dynamic>? comment) {
    setState(() => _replyingTo = comment);
    _replyFocus.requestFocus();
  }

  bool get _canSend =>
      !_sending && (_text.text.trim().isNotEmpty || _image != null);

  Future<void> _send() async {
    if (!_canSend) return;
    if (textHasWebPageLink(_text.text) && !await ensureLinkPremium(context)) {
      return;
    }
    if (!mounted) return;
    setState(() => _sending = true);
    try {
      await FanZoneService.postComment(
        postId: widget.postId,
        text: _text.text,
        parentId: _replyingTo == null ? null : '${_replyingTo!['id']}',
        image: _image,
      );
      if (!mounted) return;
      _text.clear();
      setState(() {
        _image = null;
        _replyingTo = null;
      });
      FocusScope.of(context).unfocus();
      await _load();
      ContentSync.request(force: true);
    } catch (e) {
      _notice(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------------------------------------------------------------- actions

  Future<void> _toggleLike(Map<String, dynamic> c) async {
    final id = '${c['id']}';
    if (!_likeBusy.add(id)) return;
    final liked = c['liked'] == 1 || c['liked'] == true;
    try {
      final result = await FanZoneService.call(
        'social/comment-like',
        body: {'id': id, 'liked': !liked},
      );
      if (mounted)
        setState(() {
          c['liked'] = result['liked'] == true ? 1 : 0;
          c['likes'] = result['likes'];
        });
    } catch (e) {
      _notice(e);
    } finally {
      _likeBusy.remove(id);
    }
  }

  Future<void> _action(String action, Map<String, dynamic> comment) async {
    if (action == 'edit') {
      final saved = await fanEditContent(
        context,
        title: 'Edit comment',
        initial: '${comment['text'] ?? ''}',
        maxLength: 500,
        save: (text) => FanZoneService.editComment('${comment['id']}', text),
      );
      if (saved != null && mounted) {
        setState(() {
          comment['text'] = saved;
          comment['edited_at'] = DateTime.now().millisecondsSinceEpoch;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comment updated.')),
        );
      }
      return;
    }
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
        if (_replyingTo?['id'] == comment['id']) _replyingTo = null;
        await _load();
        ContentSync.request(force: true);
      } else {
        _notice('Report sent for review.');
      }
    } catch (e) {
      _notice(e);
    }
  }

  // ---------------------------------------------------------------- widgets

  void _openProfile(Map<String, dynamic> c) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FanProfileScreen(userId: '${c['user_id']}'),
    ),
  );

  Widget _commentImage(Map<String, dynamic> c) {
    final url = FanZoneService.commentImageUrl('${c['id']}');
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => _ReplyImageViewer(url: url)),
        ),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            color: Ui.cardDeep,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Ui.line, width: .6),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : const SizedBox(
                    height: 120,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
            errorBuilder: (_, e, s) => const SizedBox(
              height: 70,
              child: Center(child: Text('Image unavailable')),
            ),
          ),
        ),
      ),
    );
  }

  Widget _comment(Map<String, dynamic> c, {required bool isReply}) {
    final mine = c['user_id'] == _viewer, owner = _post?['user_id'] == _viewer;
    final liked = c['liked'] == 1 || c['liked'] == true;
    final replyName = '${c['reply_to_name'] ?? ''}';
    final text = '${c['text'] ?? ''}';
    final highlighted = _replyingTo?['id'] == c['id'];
    return Container(
      padding: EdgeInsets.fromLTRB(isReply ? 40 : 14, 10, 4, 0),
      decoration: BoxDecoration(
        color: highlighted ? Ui.red.withValues(alpha: .06) : null,
        border: isReply
            ? null
            : Border(bottom: BorderSide(color: Ui.line, width: .6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _openProfile(c),
            child: FanAvatar(
              name: '${c['name']}',
              seed: '${c['user_id']}',
              size: isReply ? 30 : 36,
              imageUrl: FanZoneService.avatarUrl(
                '${c['user_id']}',
                c['avatar_at'],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _openProfile(c),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${c['name']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14.5,
                                ),
                              ),
                              if (c['is_premium'] == 1 || c['is_premium'] == true)
                                const WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: FanVerifiedBadge(size: 15),
                                  ),
                                ),
                              TextSpan(
                                text:
                                    '  @${FanZoneService.handleOf(c, '${c['user_id']}')} · ${fanTimeAgo(c['at']).replaceAll(' ago', '')}${(c['edited_at'] is num && (c['edited_at'] as num) > 0) ? ' · edited' : ''}',
                                style: TextStyle(color: Ui.muted, fontSize: 12.5),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          color: Ui.dim,
                          size: 19,
                        ),
                        onSelected: (a) => _action(a, c),
                        itemBuilder: (_) => [
                          if (mine)
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit comment'),
                            ),
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
                    ),
                  ],
                ),
                if (replyName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Replying to ',
                            style: TextStyle(color: Ui.muted, fontSize: 13),
                          ),
                          TextSpan(
                            text: replyName,
                            style: TextStyle(
                              color: Ui.redSoft,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SelectableText.rich(
                      TextSpan(
                        children: xRichSpans(
                          text,
                          base: const TextStyle(fontSize: 15, height: 1.38),
                          onMention: (h) => openProfileByHandle(context, h),
                        ),
                      ),
                    ),
                  ),
                if (c['has_image'] == 1) _commentImage(c),
                Row(
                  children: [
                    XAction(
                      icon: Icons.chat_bubble_outline_rounded,
                      tooltip: 'Reply to ${c['name']}',
                      onTap: () => _replyTo(c),
                    ),
                    const SizedBox(width: 18),
                    XAction(
                      icon: liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      count: (c['likes'] as num?)?.toInt() ?? 0,
                      color: const Color(0xFFF91880),
                      active: liked,
                      tooltip: liked ? 'Unlike' : 'Like',
                      onTap: () => _toggleLike(c),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One top-level reply followed by everything said under it.
  Widget _thread(Map<String, dynamic> root) {
    final replies = _comments
        .where((c) => c['root_id'] == root['id'])
        .toList(growable: false);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Ui.line, width: .6)),
      ),
      child: Column(
        children: [
          Stack(
            children: [
              if (replies.isNotEmpty)
                Positioned(
                  left: 14 + 18 - 1,
                  top: 50,
                  bottom: 0,
                  child: Container(width: 2, color: Ui.line),
                ),
              _comment(root, isReply: false),
            ],
          ),
          for (final r in replies) _comment(r, isReply: true),
          if (replies.isNotEmpty) const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _composer() {
    final target = _replyingTo;
    final hint = target == null
        ? 'Post your reply…'
        : 'Reply to ${target['name']}…';
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        decoration: BoxDecoration(
          color: Ui.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Ui.line, width: .6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (target != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 6, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Replying to ',
                              style: TextStyle(color: Ui.muted, fontSize: 13),
                            ),
                            TextSpan(
                              text: '${target['name']}',
                              style: TextStyle(
                                color: Ui.redSoft,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkResponse(
                      onTap: () => setState(() => _replyingTo = null),
                      radius: 16,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded, size: 18, color: Ui.dim),
                      ),
                    ),
                  ],
                ),
              ),
            if (_image != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _image!,
                          height: 96,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, e, s) => const SizedBox(
                            height: 96,
                            width: 96,
                            child: Center(child: Icon(Icons.image_rounded)),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: InkResponse(
                          onTap: _sending
                              ? null
                              : () => setState(() => _image = null),
                          child: const CircleAvatar(
                            radius: 11,
                            backgroundColor: Colors.black54,
                            child: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: MentionSuggestions(controller: _text),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Attach image or GIF',
                    onPressed: _sending || _picking ? null : _pickImage,
                    icon: _picking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.image_outlined,
                            color: _image != null ? Ui.red : Ui.dim,
                          ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _replyFocus,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 500,
                      onChanged: (_) => setState(() {}),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: hint,
                        counterText: '',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 4,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Post reply',
                    onPressed: _canSend ? _send : null,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.send_rounded,
                            color: _canSend ? Ui.red : Ui.dim,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roots = _comments
        .where((c) => '${c['root_id'] ?? ''}'.isEmpty)
        .toList(growable: false);
    return Scaffold(
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
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [
                  if (_error != null && _post == null && !_loading)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 90, 24, 24),
                      child: Column(
                        children: [
                          Icon(Icons.cloud_off_rounded, size: 46, color: Ui.dim),
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Ui.muted, height: 1.4),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    )
                  else if (_error != null && _post != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!),
                    ),
                  if (_post != null)
                    FanPostCard(
                      post: _post!,
                      viewerId: _viewer,
                      isAdmin: _isAdmin,
                      openThread: false,
                      onReply: () => _replyTo(null),
                      onChanged: _load,
                      onBlocked: () => Navigator.pop(context),
                    ),
                  if (!_loading && _post != null && _comments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No replies yet. Start the conversation.'),
                    ),
                  for (final root in roots) _thread(root),
                  if (_next != null)
                    OutlinedButton(
                      onPressed: _loading ? null : () => _load(more: true),
                      child: const Text('Load older comments'),
                    ),
                ],
              ),
            ),
          ),
          if (_post != null) _composer(),
        ],
      ),
    );
  }
}

/// Full-screen viewer for a reply's image or GIF (GIFs keep animating).
class _ReplyImageViewer extends StatelessWidget {
  final String url;
  const _ReplyImageViewer({required this.url});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(title: const Text('Image'), backgroundColor: Colors.black),
    body: Center(
      child: InteractiveViewer(
        minScale: .5,
        maxScale: 5,
        child: Image.network(
          url,
          errorBuilder: (_, e, s) => const Text('Image unavailable'),
        ),
      ),
    ),
  );
}
