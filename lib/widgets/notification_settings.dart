import 'package:flutter/material.dart';

import '../services/push_service.dart';
import '../theme/app_theme.dart';

/// Bottom sheet from the drawer: choose which push notifications to receive.
Future<void> showNotificationSettings(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ui.panel,
    builder: (_) => const _NotificationSheet(),
  );
}

class _NotificationSheet extends StatefulWidget {
  const _NotificationSheet();

  @override
  State<_NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<_NotificationSheet> {
  final _push = PushService.instance;
  bool _starting = true; // push is still starting in the background
  bool _allowed = true;
  final Map<PushTopic, bool> _on = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Opens at once with the saved choices, then catches up when Firebase has
  /// finished starting. Nothing here can keep the sheet on a spinner.
  Future<void> _load() async {
    await _readLocal();
    if (mounted) setState(() {});
    try {
      await _push.init();
    } catch (_) {}
    await _readLocal();
    if (mounted) setState(() => _starting = false);
  }

  Future<void> _readLocal() async {
    for (final t in PushTopic.values) {
      try {
        _on[t] = await _push.isEnabled(t);
      } catch (_) {
        _on[t] = true;
      }
    }
    if (_push.isReady) {
      try {
        _allowed = await _push
            .notificationsAllowed()
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
  }

  Future<void> _allow() async {
    final ok = await _push.requestPermission();
    if (mounted) setState(() => _allowed = ok);
  }

  Future<void> _toggle(PushTopic t, bool v) async {
    setState(() => _on[t] = v);
    try {
      await _push.setEnabled(t, v);
    } catch (_) {
      if (!mounted) return;
      setState(() => _on[t] = !v);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update. Check your connection.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Notifications',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Choose what you want to be alerted about.',
                  style: TextStyle(color: Ui.muted, fontSize: 12.5)),
              const SizedBox(height: 12),
              if (!_starting && !_push.isReady)
                _notice(
                  'Notifications could not start. Check your internet '
                  'connection and reopen the app.',
                )
              else if (!_starting && !_allowed)
                _notice(
                  'Notifications are turned off for this app.',
                  action: TextButton(
                    onPressed: _allow,
                    child: const Text('ALLOW'),
                  ),
                ),
              for (final t in PushTopic.values)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(t.icon, color: Ui.red),
                  title: Text(t.title,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800)),
                  subtitle: Text(t.subtitle,
                      style: TextStyle(color: Ui.muted, fontSize: 12)),
                  value: _on[t] ?? true,
                  onChanged: (v) => _toggle(t, v),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notice(String text, {Widget? action}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: Ui.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Ui.line),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_off_rounded, size: 20, color: Ui.red),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
            ?action,
          ],
        ),
      );
}
