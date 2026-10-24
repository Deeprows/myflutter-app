import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/fixture.dart';
import '../services/fan_zone_service.dart';
import '../theme/app_theme.dart';

const _labels = {
  'all': 'All',
  'prediction': 'Predictions',
  'betslip': 'Bet Slips',
  'banter': 'Banter',
};
String _error(Object e) => e.toString().replaceFirst('Exception: ', '');
String _time(dynamic at) {
  final d = DateTime.fromMillisecondsSinceEpoch((at as num).toInt()).toLocal();
  return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

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
  bool _busy = false, _uploads = false, _foreground = true;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _notice(String value) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (!await widget.onJoin() || !mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _ComposePost(uploadsEnabled: _uploads)),
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
        if (mounted)
          setState(() => _posts.removeWhere((p) => p['id'] == post['id']));
        _notice('Post deleted.');
      } else {
        _notice('Report sent for review.');
      }
    } catch (e) {
      _notice(_error(e));
    }
  }

  Widget _post(Map<String, dynamic> p) {
    final mine = p['user_id'] == _myId;
    final kind = p['kind'].toString();
    return Card(
      color: Ui.card,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Ui.red.withValues(alpha: .18),
                  child: Icon(Icons.person, color: Ui.red),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p['name']}${mine ? ' (you)' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '#${p['user_id'].toString().substring(0, 6)} • ${_time(p['at'])}',
                        style: TextStyle(fontSize: 11, color: Ui.muted),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (a) => _action(a, p),
                  itemBuilder: (_) => [
                    if (mine)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete post'),
                      ),
                    if (!mine) ...[
                      const PopupMenuItem(
                        value: 'report',
                        child: Text('Report post'),
                      ),
                      const PopupMenuItem(
                        value: 'block',
                        child: Text('Block fan'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(
                kind == 'betslip'
                    ? Icons.receipt_long
                    : kind == 'prediction'
                    ? Icons.sports_soccer
                    : Icons.forum_outlined,
                size: 16,
              ),
              label: Text(
                kind == 'betslip'
                    ? 'Bet Slip'
                    : kind == 'prediction'
                    ? 'Prediction'
                    : 'Banter',
              ),
            ),
            if (p['text'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: SelectableText(
                  p['text'].toString(),
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            if (p['has_image'] == 1)
              Semantics(
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
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 260,
                      child: Image.network(
                        FanZoneService.imageUrl(p['id'].toString()),
                        fit: BoxFit.contain,
                        cacheWidth: 900,
                        loadingBuilder: (_, child, progress) => progress == null
                            ? child
                            : const Center(child: CircularProgressIndicator()),
                        errorBuilder: (_, _, _) =>
                            const Center(child: Text('Image unavailable')),
                      ),
                    ),
                  ),
                ),
              ),
            if (p['has_image'] == 1)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Tap image to zoom',
                  style: TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
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
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Ui.card,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'The Deeprowss fan feed',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Share your predictions, bet slips and football gist.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.add),
                    label: const Text('Create post'),
                  ),
                  TextButton.icon(
                    onPressed: widget.onOpenLounge,
                    icon: const Icon(Icons.forum_outlined),
                    label: const Text('Open live fan lounge'),
                  ),
                  const Text(
                    'Community opinions, not guaranteed results. Posts do not earn prediction-game points.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          ExpansionTile(
            title: const Text('Match discussions'),
            children: [
              for (final f in widget.fixtures)
                ListTile(
                  title: Text(f.title),
                  subtitle: Text(f.league),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onOpenMatch(f),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final kind in _labels.keys)
                ChoiceChip(
                  label: Text(_labels[kind]!),
                  selected: kind == _kind,
                  onSelected: _busy
                      ? null
                      : (_) {
                          setState(() {
                            _kind = kind;
                            _next = null;
                            _posts = [];
                            _failure = null;
                          });
                          _load();
                        },
                ),
            ],
          ),
          if (_blocked.isNotEmpty)
            TextButton(
              onPressed: () async {
                await FanZoneService.unblockAll();
                if (mounted) setState(() => _blocked = {});
              },
              child: const Text('Unblock all fans'),
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          if (_failure != null)
            ListTile(
              title: Text(_failure!),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _load,
              ),
            ),
          const SizedBox(height: 12),
          if (!_busy && _failure == null && visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No posts here yet. Be the first to share!',
                textAlign: TextAlign.center,
              ),
            ),
          for (final p in visible) _post(p),
          if (_next != null)
            OutlinedButton(
              onPressed: _busy ? null : () => _load(more: true),
              child: const Text('Load older posts'),
            ),
        ],
      ),
    );
  }
}

class _ComposePost extends StatefulWidget {
  final bool uploadsEnabled;
  const _ComposePost({required this.uploadsEnabled});
  @override
  State<_ComposePost> createState() => _ComposePostState();
}

class _ComposePostState extends State<_ComposePost> {
  final _text = TextEditingController();
  String _kind = 'prediction';
  Uint8List? _image;
  bool _busy = false, _picking = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _notice(String value) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
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
      if (file.size > 4 * 1024 * 1024)
        throw Exception('Choose a JPG or PNG smaller than 4 MB.');
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
      if (bytes == null || bytes.isEmpty)
        throw Exception('Could not read this image. Choose another photo.');
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
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Create post'),
        actions: [
          TextButton(
            onPressed: _busy || _picking ? null : _publish,
            child: Text(_busy ? 'Posting…' : 'Publish'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: const InputDecoration(
                labelText: 'Post type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'prediction',
                  child: Text('Prediction'),
                ),
                DropdownMenuItem(value: 'betslip', child: Text('Bet Slip')),
                DropdownMenuItem(value: 'banter', child: Text('Banter')),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _kind = value ?? 'prediction'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              enabled: !_busy,
              maxLength: 1000,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: 'Share your match predictions, explain your picks, or add a caption…',
                border: OutlineInputBorder(),
              ),
            ),
            if (_image != null)
              Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 300,
                    child: Image.memory(
                      _image!,
                      cacheWidth: 900,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton.filled(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _image = null),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            OutlinedButton.icon(
              onPressed: widget.uploadsEnabled && !_busy && !_picking
                  ? _pickImage
                  : null,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                _picking ? 'Opening photos…' : 'Attach bet slip or photo',
              ),
            ),
            Text(
              widget.uploadsEnabled
                  ? 'One JPG/PNG • Up to 4 MB. Crop out account details before sharing.'
                  : 'Image uploads are not enabled yet. You can still publish text predictions and banter.',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your post is public. Predictions are opinions, not guarantees. Published posts cannot be edited; you can delete your own post.',
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    ),
  );
}

class _PostImage extends StatelessWidget {
  final String postId;
  const _PostImage({required this.postId});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Post image')),
    body: Center(
      child: InteractiveViewer(
        minScale: .5,
        maxScale: 5,
        child: Image.network(
          FanZoneService.imageUrl(postId),
          cacheWidth: 2000,
          errorBuilder: (_, _, _) => const Text('Image unavailable'),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : const CircularProgressIndicator(),
        ),
      ),
    ),
  );
}
