import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../screens/browser_screen.dart';
import '../screens/network_stream_screen.dart';
import '../screens/playlists_screen.dart';
import '../screens/plans_screen.dart';
import '../services/subscription_service.dart';
import '../services/settings_service.dart';
import 'notification_settings.dart';
import '../theme/app_theme.dart';

void _toast(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

/// Side menu: Network Stream, Playlists, Floating Player, Video Quality
/// Setting, scores, Notice, Join Us, Copyright, Update App, Exit.
class FootboliveDrawer extends StatelessWidget {
  const FootboliveDrawer({super.key});

  void _go(BuildContext context, Future<void> Function(BuildContext) action) {
    final nav = Navigator.of(context);
    nav.pop(); // close drawer
    action(nav.context);
  }

  Future<void> _push(BuildContext c, Widget w) =>
      Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

  Future<void> _openLink(BuildContext c, String url, String label) async {
    if (url.isEmpty) {
      _toast(c, '$label link is not set up yet');
      return;
    }
    if (!await openExternally(url) && c.mounted) {
      _toast(c, 'Could not open the link');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, Future<void> Function(BuildContext) f) =>
        ListTile(
          dense: true,
          leading: Icon(icon, size: 21),
          title: Text(label,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          onTap: () => _go(context, f),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          minVerticalPadding: 6,
          horizontalTitleGap: 12,
        );

    return Drawer(
      backgroundColor: Ui.cardDeep,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 24, 20, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Ui.red.withValues(alpha: .28), Ui.cardDeep],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App logo (the splash image) in place of the football icon
                // and the app name.
                Image.asset(
                  'assets/splash/splash.png',
                  height: 132,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 4),
                Text('Version: ${AppConfig.appVersion}',
                    style: TextStyle(color: Ui.muted, fontSize: 11.5)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              // Bottom padding keeps 'Exit' clear of the phone navigation bar.
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewPadding.bottom + 16),
              children: [
                if (SubscriptionService.instance.enabled)
                  item(
                      Icons.workspace_premium_rounded,
                      SubscriptionService.instance.isPremium
                          ? 'Premium (active)'
                          : 'Go Premium - no ads',
                      (c) => _push(c, const PlansScreen())),
                item(Icons.link_rounded, 'Network Stream',
                    (c) => _push(c, const NetworkStreamScreen())),
                item(Icons.playlist_play_rounded, 'Playlists',
                    (c) => _push(c, const PlaylistsScreen())),
                item(Icons.picture_in_picture_alt_rounded, 'Floating Player',
                    showFloatingPlayerDialog),
                item(Icons.settings_rounded, 'Video Quality Setting',
                    showLowQualityDialog),
                item(Icons.palette_rounded, 'Themes', showThemeSheet),
                item(Icons.sports_cricket_rounded, 'Cricket Score',
                    (c) => openInApp(c, AppConfig.cricketScoreUrl,
                        title: 'Cricket Score')),
                item(Icons.sports_soccer_rounded, 'Football Score',
                    (c) => openInApp(c, AppConfig.footballScoreUrl,
                        title: 'Football Score')),
                item(Icons.notifications_active_rounded, 'Notifications',
                    showNotificationSettings),
                item(Icons.campaign_rounded, 'Notice', showNoticeDialog),
                item(Icons.chat_rounded, 'Join Us',
                    (c) => _openLink(c, AppConfig.joinUrl, 'Join Us')),
                item(Icons.copyright_rounded, 'Copyright',
                    showCopyrightDialog),
                item(Icons.sync_rounded, 'Update App',
                    (c) => _openLink(c, AppConfig.updateUrl, 'Update')),
                item(Icons.exit_to_app_rounded, 'Exit',
                    (c) async => SystemNavigator.pop()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ dialogs

Future<void> showThemeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Ui.panel,
    builder: (ctx) => SafeArea(
      child: ValueListenableBuilder<int>(
        valueListenable: ThemeController.index,
        builder: (_, selected, _) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Choose a theme',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              for (var i = 0; i < Palettes.all.length; i++)
                _ThemeTile(
                  palette: Palettes.all[i],
                  selected: i == selected,
                  onTap: () => ThemeController.set(i),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ThemeTile extends StatelessWidget {
  final Palette palette;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeTile(
      {required this.palette, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: selected ? palette.accent : Colors.white12,
                  width: selected ? 2 : 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final c in [
                        palette.accent,
                        palette.accentSoft,
                        palette.panel
                      ])
                        Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration:
                              BoxDecoration(color: c, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(palette.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(palette.tagline,
                          style: TextStyle(
                              color: palette.muted, fontSize: 12)),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, color: palette.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


Future<void> showLowQualityDialog(BuildContext context) async {
  var on = await Settings.forceLowQuality();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Force To Low Video Quality'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Enable this option to reduce buffering on slow connections. '
                'This will reduce video quality but improve playback stability.',
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text('Force to Low Quality',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                Switch(
                  value: on,
                  onChanged: (v) {
                    set(() => on = v);
                    Settings.setForceLowQuality(v);
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE')),
        ],
      ),
    ),
  );
}

Future<void> showFloatingPlayerDialog(BuildContext context) async {
  var on = await Settings.floatingPlayer();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Floating Player'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Adds a button to the player that shrinks the video into a '
                'small floating window (picture-in-picture) so you can keep '
                'watching while using other apps.',
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text('Enable Floating Player',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                Switch(
                  value: on,
                  onChanged: (v) {
                    set(() => on = v);
                    Settings.setFloatingPlayer(v);
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE')),
        ],
      ),
    ),
  );
}

Future<void> showCopyrightDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Copyright Alert'),
      content: const Text(
          'Deeprowss does not host, upload or own any of the channels, '
          'matches or videos shown in this application. All content is the '
          'copyright of its respective owners, and you are responsible for '
          'making sure you have the right to watch what you play.',
          style: TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}

Future<void> showNoticeDialog(BuildContext context) async {
  var title = 'Notice';
  var message = 'No new notices right now.';
  if (AppConfig.noticeUrl.isNotEmpty) {
    try {
      final r = await http
          .get(Uri.parse(AppConfig.noticeUrl))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200 && r.body.trim().isNotEmpty) {
        try {
          final j = jsonDecode(r.body);
          if (j is Map) {
            title = (j['title'] ?? title).toString();
            message = (j['message'] ?? message).toString();
          } else {
            message = r.body.trim();
          }
        } catch (_) {
          message = r.body.trim();
        }
      }
    } catch (_) {}
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message,
          style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}
