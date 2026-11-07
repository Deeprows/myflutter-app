import 'package:flutter/material.dart';

import '../screens/plans_screen.dart';
import '../services/fan_zone_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import '../utils/safe_error_message.dart';

/// Edit a post or a comment (Premium members only).
///
/// Checks Premium first (showing an upgrade prompt if needed), then opens an
/// editor. Returns the text the server saved, or null if nothing changed.
Future<String?> fanEditContent(
  BuildContext context, {
  required String title,
  required String initial,
  required int maxLength,
  required Future<Map<String, dynamic>> Function(String text) save,
}) async {
  final allowed = await FanZoneService.canEditContent();
  if (!context.mounted) return null;
  if (!allowed) {
    await _premiumPrompt(context, title);
    return null;
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _FanEditSheet(
      title: title,
      initial: initial,
      maxLength: maxLength,
      save: save,
    ),
  );
}

Future<void> _premiumPrompt(BuildContext context, String title) {
  final canUpgrade = SubscriptionService.instance.visible;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Premium feature'),
      content: Text(
        '$title is available to Premium members. Upgrade to fix typos and '
        'update your posts and comments any time.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Not now'),
        ),
        if (canUpgrade)
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PlansScreen()),
              );
            },
            child: const Text('See plans'),
          ),
      ],
    ),
  );
}

class _FanEditSheet extends StatefulWidget {
  final String title;
  final String initial;
  final int maxLength;
  final Future<Map<String, dynamic>> Function(String text) save;
  const _FanEditSheet({
    required this.title,
    required this.initial,
    required this.maxLength,
    required this.save,
  });

  @override
  State<_FanEditSheet> createState() => _FanEditSheetState();
}

class _FanEditSheetState extends State<_FanEditSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _text.text.trim();
    if (value == widget.initial.trim()) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.save(value);
      if (!mounted) return;
      Navigator.pop(context, '${result['text'] ?? value}');
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _text,
            autofocus: true,
            enabled: !_busy,
            minLines: 3,
            maxLines: 10,
            maxLength: widget.maxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              filled: true,
              fillColor: Ui.cardDeep,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Ui.line),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
