import 'dart:async';

import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Live chat / comment section shown under a football stream.
/// Shares its rooms with the Footbolive website (same Firestore data).
class MatchChat extends StatefulWidget {
  final String matchName;
  const MatchChat({super.key, required this.matchName});

  @override
  State<MatchChat> createState() => _MatchChatState();
}

class _MatchChatState extends State<MatchChat> {
  late final String _slug = ChatService.slugify(widget.matchName);
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _nameInput = TextEditingController();

  List<ChatMessage> _messages = const [];
  String _username = '';
  bool _ready = false; // saved name loaded
  bool _loaded = false; // first fetch finished
  bool _failed = false;
  bool _sending = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _nameInput.text = ChatService.randomName();
    Settings.chatName().then((n) {
      if (!mounted) return;
      setState(() {
        _username = n;
        _ready = true;
      });
    });
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    _input.dispose();
    _nameInput.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final list = await ChatService.fetch(_slug);
      if (!mounted) return;
      final grew = list.length != _messages.length ||
          (list.isNotEmpty &&
              _messages.isNotEmpty &&
              list.last.id != _messages.last.id);
      final nearBottom = !_scroll.hasClients ||
          _scroll.position.maxScrollExtent - _scroll.offset < 120;
      setState(() {
        _messages = list;
        _loaded = true;
        _failed = false;
      });
      if (grew && nearBottom) _toBottom();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _failed = _messages.isEmpty;
        });
      }
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _join() async {
    final n = _nameInput.text.trim();
    if (n.isEmpty) return;
    final name = n.length > 30 ? n.substring(0, 30) : n;
    await Settings.setChatName(name);
    if (mounted) setState(() => _username = name);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _username.isEmpty) return;
    setState(() => _sending = true);
    final err = await ChatService.send(
      _slug,
      matchName: widget.matchName,
      username: _username,
      text: text,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    _input.clear();
    await _refresh();
    _toBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Ui.cardDeep,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Ui.line)),
      ),
      child: Column(
        children: [
          _header(),
          Expanded(child: _body()),
          if (_ready) _bottom(),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Row(
        children: [
          Icon(Icons.forum_rounded, size: 18, color: Ui.redSoft),
          const SizedBox(width: 8),
          const Text('Live chat',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(width: 8),
          if (_loaded && !_failed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text('${_messages.length}',
                  style: TextStyle(
                      color: Ui.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800)),
            ),
          const Spacer(),
          if (_username.isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: () => setState(() {
                _nameInput.text = _username;
                _username = '';
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_rounded, size: 14, color: Ui.muted),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(_username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Ui.muted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.edit_rounded, size: 12, color: Ui.dim),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (!_loaded) {
      return Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Ui.red)));
    }
    if (_failed) {
      return _Hint(
        icon: Icons.cloud_off_rounded,
        text: 'Chat is unavailable right now.',
        action: 'Try again',
        onAction: _refresh,
      );
    }
    if (_messages.isEmpty) {
      return const _Hint(
        icon: Icons.chat_bubble_outline_rounded,
        text: 'No comments yet. Be the first to comment!',
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _Bubble(
        message: _messages[i],
        mine: _messages[i].username == _username,
      ),
    );
  }

  Widget _bottom() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: Ui.panel,
          border: Border(top: BorderSide(color: Ui.line)),
        ),
        child: _username.isEmpty ? _joinRow() : _composer(),
      ),
    );
  }

  Widget _joinRow() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pick a name to join the chat  ·  18+',
            style: TextStyle(
                color: Ui.muted, fontSize: 11.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _field(
                controller: _nameInput,
                hint: 'Your name',
                maxLength: 30,
                onSubmit: (_) => _join(),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: 'Random name',
              onPressed: () =>
                  setState(() => _nameInput.text = ChatService.randomName()),
              icon: const Icon(Icons.casino_rounded, size: 20),
            ),
            const SizedBox(width: 2),
            IconButton.filled(
              tooltip: 'Join',
              style: IconButton.styleFrom(backgroundColor: Ui.red),
              onPressed: _join,
              icon: const Icon(Icons.login_rounded, size: 20),
            ),
          ],
        ),
      ],
    );
  }

  Widget _composer() {
    return Row(
      children: [
        Expanded(
          child: _field(
            controller: _input,
            hint: 'Write a comment...',
            maxLength: ChatService.maxLength,
            onSubmit: (_) => _send(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Send',
          style: IconButton.styleFrom(backgroundColor: Ui.red),
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded, size: 20),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required int maxLength,
    required ValueChanged<String> onSubmit,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      textInputAction: TextInputAction.send,
      onSubmitted: onSubmit,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Ui.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: BorderSide(color: Ui.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: BorderSide(color: Ui.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: BorderSide(color: Ui.red),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  const _Bubble({required this.message, required this.mine});

  static const _tints = [
    Color(0xFFFF6B6B), Color(0xFFFFB84D), Color(0xFF4DD0A1),
    Color(0xFF5BC0FF), Color(0xFFB794F6), Color(0xFFFF8AD8),
  ];

  @override
  Widget build(BuildContext context) {
    final tint = _tints[message.username.hashCode.abs() % _tints.length];
    final t = message.at;
    final time = t == null
        ? ''
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withValues(alpha: .18),
              border: Border.all(color: tint.withValues(alpha: .5)),
            ),
            child: Text(
              message.username.isEmpty
                  ? '?'
                  : message.username.characters.first.toUpperCase(),
              style: TextStyle(
                  color: tint, fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
              decoration: BoxDecoration(
                color: mine ? Ui.red.withValues(alpha: .16) : Ui.card,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                border: Border.all(
                    color: mine ? Ui.red.withValues(alpha: .45) : Ui.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(message.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: tint,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800)),
                      ),
                      if (time.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(time,
                            style: TextStyle(color: Ui.dim, fontSize: 10)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(message.text,
                      style: const TextStyle(fontSize: 13.5, height: 1.3)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const _Hint({required this.icon, required this.text, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: Ui.dim),
          const SizedBox(height: 8),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Ui.muted, fontSize: 13, fontWeight: FontWeight.w700)),
          if (action != null) ...[
            const SizedBox(height: 6),
            TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    );
  }
}
