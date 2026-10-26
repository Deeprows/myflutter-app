import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/auth_service.dart';
import '../screens/browser_screen.dart';
import '../screens/content_shortcut_screen.dart';
import '../screens/highlights_screen.dart';
import '../screens/live_screen.dart';
import '../screens/movies_screen.dart';
import '../screens/tv_screen.dart';
import '../screens/network_stream_screen.dart';
import '../screens/playlists_screen.dart';
import '../screens/plans_screen.dart';
import '../screens/remove_ads_screen.dart';
import '../services/notice_service.dart';
import '../services/app_sharer.dart';
import '../services/app_updater.dart';
import '../services/subscription_service.dart';
import '../services/settings_service.dart';
import '../utils/l10n.dart';
import 'language_sheet.dart';
import 'notification_settings.dart';
import '../theme/app_theme.dart';

void _toast(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

/// Side menu: Network Stream, Playlists, Floating Player, Video Quality
/// Setting, scores, Notice, Join Us, Copyright, Share App, Update App, Exit.
class FootboliveDrawer extends StatelessWidget {
  final VoidCallback? onHome;
  const FootboliveDrawer({super.key, this.onHome});

  void _go(BuildContext context, Future<void> Function(BuildContext) action) {
    final nav = Navigator.of(context);
    nav.pop(); // close drawer
    action(nav.context);
  }

  Future<void> _push(BuildContext c, Widget w) =>
      Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

  Future<void> _openLink(BuildContext c, String url, String label) async {
    if (url.isEmpty) {
      _toast(c, '{label} link is not set up yet'.trArgs({'label': label}));
      return;
    }
    if (!await openExternally(url) && c.mounted) {
      _toast(c, 'Could not open the link'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget item(
      IconData icon,
      String label,
      Future<void> Function(BuildContext) f,
    ) => ListTile(
      dense: true,
      leading: Icon(icon, size: 21),
      title: Text(
        label,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      onTap: () => _go(context, f),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      minVerticalPadding: 6,
      horizontalTitleGap: 12,
    );

    // "Subscription: Active" + the end date and days left.
    Widget subscriptionItem() {
      final sub = SubscriptionService.instance;
      final date = sub.expiresLabel;
      final left = sub.daysLeft;
      final detail = [
        if (date != null) 'No ads until {date}'.trArgs({'date': date}),
        if (left != null && left <= 400)
          (left == 1 ? '{n} day left' : '{n} days left').trArgs({'n': left}),
      ].join(' · ');
      return ListTile(
        dense: true,
        leading: Icon(Icons.verified_rounded, size: 21, color: Ui.green),
        title: Text(
          'Subscription: Active'.tr,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
        subtitle: detail.isEmpty
            ? null
            : Text(detail, style: TextStyle(color: Ui.muted, fontSize: 11.5)),
        onTap: () => _go(context, (c) => _push(c, const RemoveAdsScreen())),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18),
        minVerticalPadding: 6,
        horizontalTitleGap: 12,
      );
    }

    return Drawer(
      backgroundColor: Ui.cardDeep,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.of(context).padding.top + 24,
              20,
              16,
            ),
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
                Text(
                  '${'Version'.tr}: ${AppConfig.appVersion}',
                  style: TextStyle(color: Ui.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              // Bottom padding keeps 'Exit' clear of the phone navigation bar.
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewPadding.bottom + 16,
              ),
              children: [
                if (onHome != null)
                  item(Icons.apps_rounded, 'Choose experience', (c) async {
                    onHome!();
                  }),
                item(
                  Icons.sensors_rounded,
                  'Live Now',
                  (c) => _push(
                    c,
                    const ContentShortcutScreen(
                      title: 'Live Now',
                      child: LiveScreen(),
                    ),
                  ),
                ),
                item(
                  Icons.play_circle_outline_rounded,
                  'Football Highlights',
                  (c) => _push(
                    c,
                    const ContentShortcutScreen(
                      title: 'Football Highlights',
                      child: HighlightsScreen(),
                    ),
                  ),
                ),
                item(
                  Icons.live_tv_rounded,
                  'TV Channels',
                  (c) => _push(
                    c,
                    const ContentShortcutScreen(
                      title: 'TV Channels',
                      child: TvScreen(),
                    ),
                  ),
                ),
                item(
                  Icons.movie_outlined,
                  'Movies',
                  (c) => _push(
                    c,
                    const ContentShortcutScreen(
                      title: 'Movies',
                      child: MoviesScreen(),
                    ),
                  ),
                ),
                if (AuthService.instance.user != null)
                  ListTile(
                    leading: const Icon(Icons.account_circle_outlined),
                    title: Text(AuthService.instance.user!.name),
                    subtitle: Text(AuthService.instance.user!.email),
                  ),
                item(Icons.logout_rounded, 'Log out', (c) async {
                  final sure = await showDialog<bool>(
                    context: c,
                    builder: (dialog) => AlertDialog(
                      title: const Text('Log out of Deeprowss?'),
                      content: const Text(
                        'You can log in again with the same Gmail account.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('Log out'),
                        ),
                      ],
                    ),
                  );
                  if (sure != true || !c.mounted) return;
                  Navigator.of(c).popUntil((route) => route.isFirst);
                  await AuthService.instance.signOut();
                }),
                if (SubscriptionService.instance.visible)
                  item(
                    Icons.workspace_premium_rounded,
                    SubscriptionService.instance.isPremium
                        ? 'Premium (active)'.tr
                        : 'Go Premium - no ads'.tr,
                    (c) => _push(c, const PlansScreen()),
                  ),
                // Token users: before = "Remove ads"; once ads are gone this
                // becomes the subscription status. (Paystack Premium has its
                // own item above, so it is not repeated.)
                if (SubscriptionService.instance.tokensVisible &&
                    !(SubscriptionService.instance.visible &&
                        SubscriptionService.instance.isPremium))
                  if (SubscriptionService.instance.isPremium)
                    subscriptionItem()
                  else
                    item(
                      Icons.block_rounded,
                      'Remove ads'.tr,
                      (c) => _push(c, const RemoveAdsScreen()),
                    ),
                item(
                  Icons.link_rounded,
                  'Network Stream'.tr,
                  (c) => _push(c, const NetworkStreamScreen()),
                ),
                item(
                  Icons.playlist_play_rounded,
                  'Playlists'.tr,
                  (c) => _push(c, const PlaylistsScreen()),
                ),
                item(
                  Icons.picture_in_picture_alt_rounded,
                  'Floating Player'.tr,
                  showFloatingPlayerDialog,
                ),
                item(
                  Icons.settings_rounded,
                  'Video Quality Setting'.tr,
                  showLowQualityDialog,
                ),
                item(Icons.palette_rounded, 'Themes'.tr, showThemeSheet),
                item(Icons.language_rounded, 'Language'.tr, showLanguageSheet),
                item(
                  Icons.sports_cricket_rounded,
                  'Cricket Score'.tr,
                  (c) => openInApp(
                    c,
                    AppConfig.cricketScoreUrl,
                    title: 'Cricket Score'.tr,
                  ),
                ),
                item(
                  Icons.sports_soccer_rounded,
                  'Football Score'.tr,
                  (c) => openInApp(
                    c,
                    AppConfig.footballScoreUrl,
                    title: 'Football Score'.tr,
                  ),
                ),
                item(
                  Icons.notifications_active_rounded,
                  'Notifications'.tr,
                  showNotificationSettings,
                ),
                item(Icons.campaign_rounded, 'Notice'.tr, showNoticeDialog),
                item(
                  Icons.chat_rounded,
                  'Join Us'.tr,
                  (c) => _openLink(c, AppConfig.joinUrl, 'Join Us'.tr),
                ),
                item(
                  Icons.copyright_rounded,
                  'Copyright'.tr,
                  showCopyrightDialog,
                ),
                item(
                  Icons.share_rounded,
                  'Share App'.tr,
                  (c) => AppSharer.instance.share(c),
                ),
                item(
                  Icons.sync_rounded,
                  'Update App'.tr,
                  (c) => AppUpdater.instance.update(c),
                ),
                item(
                  Icons.exit_to_app_rounded,
                  'Exit'.tr,
                  (c) async => SystemNavigator.pop(),
                ),
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
    // Lets the sheet grow to the screen height; the list scrolls inside it.
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: ValueListenableBuilder<int>(
        valueListenable: ThemeController.index,
        builder: (_, selected, _) => SingleChildScrollView(
          // Extra room at the bottom so the phone's navigation bar never
          // covers the last theme.
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a theme'.tr,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
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
  const _ThemeTile({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

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
                width: selected ? 2 : 1,
              ),
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
                        palette.panel,
                      ])
                        Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        palette.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        palette.tagline,
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
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
        title: Text('Force To Low Video Quality'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enable this option to reduce buffering on slow connections. '
                      'This will reduce video quality but improve playback stability.'
                  .tr,
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Force to Low Quality'.tr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
            onPressed: () => Navigator.pop(ctx),
            child: Text('CLOSE'.tr),
          ),
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
        title: Text('Floating Player'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Adds a button to the player that shrinks the video into a '
                      'small floating window (picture-in-picture) so you can keep '
                      'watching while using other apps.'
                  .tr,
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Enable Floating Player'.tr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
            onPressed: () => Navigator.pop(ctx),
            child: Text('CLOSE'.tr),
          ),
        ],
      ),
    ),
  );
}

Future<void> showCopyrightDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Copyright Alert'.tr),
      content: Text(
        'Deeprowss does not host, upload or own any of the channels, '
                'matches or videos shown in this application. All content is the '
                'copyright of its respective owners, and you are responsible for '
                'making sure you have the right to watch what you play.'
            .tr,
        style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK'.tr)),
      ],
    ),
  );
}

Future<void> showNoticeDialog(BuildContext context) =>
    NoticeService.instance.showFromMenu(context);
