import 'dart:async';

import 'package:flutter/material.dart';

import '../services/fan_zone_service.dart';
import '../theme/app_theme.dart';
import 'fan_profile_screen.dart';
import 'fan_widgets.dart';

/// Opens the profile of the fan who owns [handle] (the text after the @).
Future<void> openProfileByHandle(BuildContext context, String handle) async {
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final data = await FanZoneService.call(
      'social/profile',
      query: {'handle': handle},
    );
    final profile = Map<String, dynamic>.from(data['profile'] as Map);
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => FanProfileScreen(userId: '${profile['id']}'),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not find @$handle.')),
    );
  }
}

/// Suggestion list shown while the user types `@name` in [controller].
/// Tapping a fan replaces the typed `@part` with `@username `.
/// Place it directly above or below the text field.
class MentionSuggestions extends StatefulWidget {
  final TextEditingController controller;
  const MentionSuggestions({super.key, required this.controller});

  @override
  State<MentionSuggestions> createState() => _MentionSuggestionsState();
}

class _MentionSuggestionsState extends State<MentionSuggestions> {
  static final _token = RegExp(r'(?:^|[\s(])@([A-Za-z0-9_]{0,20})$');
  Timer? _debounce;
  List<Map<String, dynamic>> _users = const [];
  String? _query;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _debounce?.cancel();
    super.dispose();
  }

  /// The `@part` being typed at the cursor, as (start of '@', query).
  (int, String)? _current() {
    final value = widget.controller.value;
    final sel = value.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    final before = value.text.substring(0, sel.baseOffset);
    final m = _token.firstMatch(before);
    if (m == null) return null;
    final q = m.group(1)!;
    return (before.length - q.length - 1, q);
  }

  void _changed() {
    final cur = _current();
    if (cur == null) {
      _debounce?.cancel();
      _query = null;
      if (_users.isNotEmpty) setState(() => _users = const []);
      return;
    }
    if (cur.$2 == _query) return;
    _query = cur.$2;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _load(cur.$2));
  }

  Future<void> _load(String q) async {
    final seq = ++_seq;
    try {
      final data = await FanZoneService.call(
        'social/mentions',
        query: {'q': q},
      );
      if (!mounted || seq != _seq || _query != q) return;
      final list = data['users'];
      setState(() {
        _users = list is List
            ? list.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : const [];
      });
    } catch (_) {
      if (mounted && seq == _seq) setState(() => _users = const []);
    }
  }

  void _pick(Map<String, dynamic> user) {
    final cur = _current();
    if (cur == null) return;
    final value = widget.controller.value;
    final end = value.selection.baseOffset;
    final handle = FanZoneService.handleOf(user, '${user['id']}');
    final text = value.text.replaceRange(cur.$1, end, '@$handle ');
    final caret = cur.$1 + handle.length + 2;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_users.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Ui.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Ui.line),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final u in _users)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: FanAvatar(
                name: '${u['name']}',
                seed: '${u['id']}',
                size: 30,
                imageUrl: FanZoneService.avatarUrl('${u['id']}', u['avatar_at']),
              ),
              title: Text(
                '${u['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '@${FanZoneService.handleOf(u, '${u['id']}')}',
                style: TextStyle(color: Ui.muted, fontSize: 12.5),
              ),
              onTap: () => _pick(u),
            ),
        ],
      ),
    );
  }
}
