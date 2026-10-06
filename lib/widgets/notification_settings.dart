import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  bool _loading = true;
  bool _allowed = false;
  final Map<PushTopic, bool> _on = {};
  String _diag = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _push.init();
    final allowed = await _push.notificationsAllowed();
    for (final t in PushTopic.values) {
      _on[t] = await _push.isEnabled(t);
    }
    final diag = await _push.diagnostics();
    if (!mounted) return;
    setState(() {
      _allowed = allowed;
      _diag = diag;
      _loading = false;
    });
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

  Future<void> _copyToken() async {
    final token = await _push.token();
    if (!mounted) return;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device token not available yet')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Device token copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: _loading
            ? const SizedBox(
                height: 140,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Notifications',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('Choose what you want to be alerted about.',
                        style: TextStyle(color: Ui.muted, fontSize: 12.5)),
                    const SizedBox(height: 12),
                    if (!_push.isReady)
                      _notice(
                        'Notifications could not start. See "Status" below.',
                      )
                    else if (!_allowed)
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
                        onChanged: _push.isReady ? (v) => _toggle(t, v) : null,
                      ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      shape: const Border(),
                      collapsedShape: const Border(),
                      leading: const Icon(Icons.info_outline_rounded, size: 20),
                      title: const Text('Status',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(_diag,
                              style: TextStyle(color: Ui.muted, fontSize: 11.5)),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: _diag));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Status copied')),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copy status'),
                        ),
                      ],
                    ),
                    if (_push.isReady)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.copy_rounded, size: 20),
                        title: const Text('Copy device token',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        subtitle: Text('For testing from the Firebase console',
                            style: TextStyle(color: Ui.dim, fontSize: 11.5)),
                        onTap: _copyToken,
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
            if (action != null) action,
          ],
        ),
      );
}
