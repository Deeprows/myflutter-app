import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../screens/browser_screen.dart';
import '../screens/network_stream_screen.dart';
import '../screens/playlists_screen.dart';
import '../services/settings_service.dart';
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
          leading: Icon(icon, size: 26),
          title: Text(label,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          onTap: () => _go(context, f),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          minVerticalPadding: 14,
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
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Ui.red,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: Ui.red.withValues(alpha: .45), blurRadius: 20)
                    ],
                  ),
                  child: const Icon(Icons.sports_soccer_rounded,
                      color: Colors.white, size: 42),
                ),
                const SizedBox(height: 14),
                const Text('FOOTBOLIVE',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2)),
                const SizedBox(height: 4),
                const Text('Version: ${AppConfig.appVersion}',
                    style: TextStyle(color: Ui.muted, fontSize: 13)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                item(Icons.link_rounded, 'Network Stream',
                    (c) => _push(c, const NetworkStreamScreen())),
                item(Icons.playlist_play_rounded, 'Playlists',
                    (c) => _push(c, const PlaylistsScreen())),
                item(Icons.picture_in_picture_alt_rounded, 'Floating Player',
                    showFloatingPlayerDialog),
                item(Icons.settings_rounded, 'Video Quality Setting',
                    showLowQualityDialog),
                item(Icons.sports_cricket_rounded, 'Cricket Score',
                    (c) => openInApp(c, AppConfig.cricketScoreUrl,
                        title: 'Cricket Score')),
                item(Icons.sports_soccer_rounded, 'Football Score',
                    (c) => openInApp(c, AppConfig.footballScoreUrl,
                        title: 'Football Score')),
                item(Icons.notifications_rounded, 'Notice', showNoticeDialog),
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
          'Footbolive does not host, upload or own any of the channels, '
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

/// Shows the copyright alert once, on the very first launch.
Future<void> maybeShowFirstLaunchCopyright(BuildContext context) async {
  if (await Settings.copyrightSeen()) return;
  await Settings.setCopyrightSeen();
  if (context.mounted) await showCopyrightDialog(context);
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
