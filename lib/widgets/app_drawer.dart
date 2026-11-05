import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../screens/browser_screen.dart';
import '../screens/fan_profile_screen.dart';
import '../screens/fan_widgets.dart';
import '../screens/content_shortcut_screen.dart';
import '../screens/highlights_screen.dart';
import '../screens/live_screen.dart';
import '../screens/movies_screen.dart';
import '../screens/tv_screen.dart';
import '../screens/network_stream_screen.dart';
import '../screens/playlists_screen.dart';
import '../screens/plans_screen.dart';
import '../screens/remove_ads_screen.dart';
import '../services/auth_service.dart';
import '../services/fan_zone_service.dart';
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

/// Side menu in the style of the X (Twitter) menu: profile header on top,
/// large primary items, a divider, then smaller secondary items.
class FootboliveDrawer extends StatefulWidget {
  final VoidCallback? onHome;
  const FootboliveDrawer({super.key, this.onHome});

  @override
  State<FootboliveDrawer> createState() => _FootboliveDrawerState();
}

class _FootboliveDrawerState extends State<FootboliveDrawer> {
  /// Last loaded Fan Zone profile, kept so the picture shows instantly the
  /// next time the drawer opens.
  static Map<String, dynamic>? _cached;
  static String _cachedFor = '';
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    final id = AuthService.instance.user?.id ?? '';
    if (id.isNotEmpty && _cachedFor == id) _profile = _cached;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final id = AuthService.instance.user?.id ?? '';
    if (id.isEmpty) return;
    try {
      final data = await FanZoneService.call(
        'social/profile',
        query: {'id': id},
      );
      final p = Map<String, dynamic>.from(data['profile'] as Map);
      _cached = p;
      _cachedFor = id;
      if (mounted) setState(() => _profile = p);
    } catch (_) {
      // Keep the cached/initial avatar when offline.
    }
  }

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
    // Big primary row (like Profile / Premium / Communities in X).
    Widget main(
      IconData icon,
      String label,
      Future<void> Function(BuildContext) f, {
      Widget? badge,
    }) => InkWell(
      onTap: () => _go(context, f),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 27),
            const SizedBox(width: 20),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (badge != null) ...[const SizedBox(width: 10), badge],
          ],
        ),
      ),
    );

    // Smaller secondary row (like Settings / Help Center in X).
    Widget sub(
      IconData icon,
      String label,
      Future<void> Function(BuildContext) f,
    ) => InkWell(
      onTap: () => _go(context, f),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Ui.muted),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Widget divider() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Divider(height: 1, thickness: 1, color: Ui.line),
    );

    Widget pill(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Ui.red,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    return Drawer(
      backgroundColor: Ui.bg,
      shape: const RoundedRectangleBorder(),
      child: ListenableBuilder(
        listenable: Listenable.merge([
          AuthService.instance,
          SubscriptionService.instance,
        ]),
        builder: (context, _) {
          final user = AuthService.instance.user;
          final sub0 = SubscriptionService.instance;
          final fan = _profile;
          final fanName = '${fan?['name'] ?? ''}'.trim();
          final fanHandle = '${fan?['handle'] ?? ''}'.trim();
          final name = fanName.isNotEmpty
              ? fanName
              : ((user?.name.trim().isNotEmpty ?? false)
                    ? user!.name.trim()
                    : (user?.email.split('@').first ?? AppConfig.appName));
          final handle = fanHandle.isNotEmpty
              ? '@$fanHandle'
              : (user == null ? '' : '@${FanZoneService.handle(user.id)}');
          // The picture uploaded in the app's own profile (not Google's).
          final photo = user == null
              ? null
              : FanZoneService.avatarUrl(user.id, fan?['avatar_at']);

          return Column(
            children: [
              // ------------------------------------------------ profile
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.of(context).padding.top + 20,
                  20,
                  14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: user == null
                              ? null
                              : () => _go(
                                  context,
                                  (c) => _push(
                                    c,
                                    FanProfileScreen(userId: user.id),
                                  ),
                                ),
                          child: FanAvatar(
                            name: name,
                            seed: user?.id ?? name,
                            size: 46,
                            imageUrl: photo,
                          ),
                        ),
                        const Spacer(),
                        if (sub0.isPremium)
                          Icon(
                            Icons.verified_rounded,
                            color: Ui.red,
                            size: 26,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (handle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Ui.muted, fontSize: 15),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(height: 1, thickness: 1, color: Ui.line),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(
                    top: 6,
                    bottom: MediaQuery.of(context).viewPadding.bottom + 16,
                  ),
                  children: [
                    if (user != null)
                      main(
                        Icons.person_outline_rounded,
                        'Profile'.tr,
                        (c) => _push(c, FanProfileScreen(userId: user.id)),
                      ),
                    main(
                      Icons.workspace_premium_outlined,
                      'Premium'.tr,
                      (c) => _push(
                        c,
                        sub0.visible
                            ? const PlansScreen()
                            : const RemoveAdsScreen(),
                      ),
                      badge: sub0.isPremium ? pill('Active'.tr) : null,
                    ),
                    main(
                      Icons.sensors_rounded,
                      'Live Now'.tr,
                      (c) => _push(
                        c,
                        const ContentShortcutScreen(
                          title: 'Live Now',
                          child: LiveScreen(),
                        ),
                      ),
                    ),
                    main(
                      Icons.play_circle_outline_rounded,
                      'Football Highlights'.tr,
                      (c) => _push(
                        c,
                        const ContentShortcutScreen(
                          title: 'Football Highlights',
                          child: HighlightsScreen(),
                        ),
                      ),
                    ),
                    main(
                      Icons.live_tv_rounded,
                      'TV Channels'.tr,
                      (c) => _push(
                        c,
                        const ContentShortcutScreen(
                          title: 'TV Channels',
                          child: TvScreen(),
                        ),
                      ),
                    ),
                    main(
                      Icons.movie_outlined,
                      'Movies'.tr,
                      (c) => _push(
                        c,
                        const ContentShortcutScreen(
                          title: 'Movies',
                          child: MoviesScreen(),
                        ),
                      ),
                    ),
                    main(
                      Icons.sports_soccer_rounded,
                      'Football Score'.tr,
                      (c) => openInApp(
                        c,
                        AppConfig.footballScoreUrl,
                        title: 'Football Score'.tr,
                      ),
                    ),
                    main(
                      Icons.sports_cricket_rounded,
                      'Cricket Score'.tr,
                      (c) => openInApp(
                        c,
                        AppConfig.cricketScoreUrl,
                        title: 'Cricket Score'.tr,
                      ),
                    ),
                    divider(),
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                        ),
                        leading: Icon(
                          Icons.settings_outlined,
                          size: 22,
                          color: Ui.muted,
                        ),
                        title: Text(
                          'Settings'.tr,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        iconColor: Ui.muted,
                        collapsedIconColor: Ui.muted,
                        childrenPadding: const EdgeInsets.only(left: 16),
                        children: [
                          sub(Icons.palette_outlined, 'Themes'.tr, showThemeSheet),
                          sub(
                            Icons.language_rounded,
                            'Language'.tr,
                            showLanguageSheet,
                          ),
                          sub(
                            Icons.notifications_none_rounded,
                            'Notifications'.tr,
                            showNotificationSettings,
                          ),
                          sub(
                            Icons.picture_in_picture_alt_outlined,
                            'Floating Player'.tr,
                            showFloatingPlayerDialog,
                          ),
                          sub(
                            Icons.link_rounded,
                            'Network Stream'.tr,
                            (c) => _push(c, const NetworkStreamScreen()),
                          ),
                          sub(
                            Icons.playlist_play_rounded,
                            'Playlists'.tr,
                            (c) => _push(c, const PlaylistsScreen()),
                          ),
                          sub(
                            Icons.tune_rounded,
                            'Video Quality Setting'.tr,
                            showLowQualityDialog,
                          ),
                        ],
                      ),
                    ),
                    sub(
                      Icons.campaign_outlined,
                      'Notice'.tr,
                      showNoticeDialog,
                    ),
                    sub(
                      Icons.chat_bubble_outline_rounded,
                      'Join Us'.tr,
                      (c) => _openLink(c, AppConfig.joinUrl, 'Join Us'.tr),
                    ),
                    sub(
                      Icons.ios_share_rounded,
                      'Share App'.tr,
                      (c) => AppSharer.instance.share(c),
                    ),
                    sub(
                      Icons.sync_rounded,
                      'Update App'.tr,
                      (c) => AppUpdater.instance.update(c),
                    ),
                    sub(
                      Icons.copyright_rounded,
                      'Copyright'.tr,
                      showCopyrightDialog,
                    ),
                    sub(
                      Icons.exit_to_app_rounded,
                      'Exit'.tr,
                      (c) async => SystemNavigator.pop(),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Text(
                        '${'Version'.tr}: ${AppConfig.appVersion}',
                        style: TextStyle(color: Ui.dim, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
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
