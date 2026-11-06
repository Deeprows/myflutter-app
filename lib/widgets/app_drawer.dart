import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../screens/auth_screen.dart';
import '../screens/bookmarks_screen.dart';
import '../screens/browser_screen.dart';
import '../screens/fan_profile_screen.dart';
import '../screens/fan_widgets.dart';
import '../screens/content_shortcut_screen.dart';
import '../screens/highlights_screen.dart';
import '../screens/notifications_screen.dart';
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
import '../services/notification_center.dart';
import '../services/post_bookmarks.dart';
import '../services/app_sharer.dart';
import '../services/app_updater.dart';
import '../services/subscription_service.dart';
import '../services/settings_service.dart';
import '../utils/l10n.dart';
import 'language_sheet.dart';
import '../theme/app_theme.dart';

void _toast(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

Future<void> _openLink(BuildContext c, String url, String label) async {
  if (url.isEmpty) {
    _toast(c, '{label} link is not set up yet'.trArgs({'label': label}));
    return;
  }
  if (!await openExternally(url) && c.mounted) {
    _toast(c, 'Could not open the link'.tr);
  }
}

/// Side menu in the style of the X (Twitter) menu, tidied up:
///  * profile header (or a Sign in button when signed out) with follower stats
///  * content shortcuts grouped under small headings, rounded tap targets
///  * a pinned bottom dock (Themes, Language, Alerts, More) so the most used
///    settings are always one tap away and never scroll out of sight
///  * everything else lives in a "Settings and support" sheet
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
    PostBookmarks.instance.load();
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

  /// Closes the drawer, then runs [action] on the app's root navigator so
  /// pages, sheets and dialogs never depend on the (now closed) drawer.
  void _go(Future<void> Function(BuildContext) action) {
    final nav = Navigator.of(context);
    nav.pop();
    action(nav.context);
  }

  Future<void> _push(BuildContext c, Widget w) =>
      Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

  // ------------------------------------------------------------ pieces

  /// Rounded, full-width menu row. The ripple stays inside the rounded
  /// shape instead of bleeding edge to edge.
  Widget _row(
    IconData icon,
    String label,
    Future<void> Function(BuildContext) action, {
    Widget? badge,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _go(action),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 25),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 8), badge],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: .9,
        color: Ui.dim,
      ),
    ),
  );

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: Ui.red,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: Ui.palette.onAccent,
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _dock(
    IconData icon,
    String label,
    Future<void> Function(BuildContext) action, {
    ValueListenable<int>? count,
  }) => Expanded(
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _go(action),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Ui.card,
                  border: Border.all(color: Ui.line),
                ),
                child: count == null
                    ? Icon(icon, size: 21)
                    : ValueListenableBuilder<int>(
                        valueListenable: count,
                        builder: (_, n, _) => Badge(
                          isLabelVisible: n > 0,
                          label: Text(n > 99 ? '99+' : '$n'),
                          backgroundColor: Ui.red,
                          textColor: Ui.palette.onAccent,
                          child: Icon(icon, size: 21),
                        ),
                      ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Ui.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _stat(String value, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: Ui.muted)),
    ],
  );

  Widget _header(BuildContext context, AuthUser? user, bool premium) {
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
    final photo = user == null
        ? null
        : FanZoneService.avatarUrl(user.id, fan?['avatar_at']);
    final following = int.tryParse('${fan?['following'] ?? ''}');
    final followers = int.tryParse('${fan?['followers'] ?? ''}');

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Ui.red.withValues(alpha: .14), Ui.red.withValues(alpha: 0)],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 18,
        20,
        12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: user == null
                ? null
                : () => _go(
                    (c) => _push(c, FanProfileScreen(userId: user.id)),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    FanAvatar(
                      name: name,
                      seed: user?.id ?? name,
                      size: 52,
                      imageUrl: photo,
                    ),
                    const Spacer(),
                    if (premium)
                      Icon(Icons.verified_rounded, color: Ui.red, size: 26),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (handle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Ui.muted, fontSize: 14.5),
                  ),
                ],
              ],
            ),
          ),
          if (user != null && following != null && followers != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _stat('$following', 'Following'.tr),
                _stat('$followers', 'Followers'.tr),
              ],
            ),
          ],
          if (user == null) ...[
            const SizedBox(height: 4),
            Text(
              'Sign in to predict, post and join match chats'.tr,
              style: TextStyle(color: Ui.muted, fontSize: 13, height: 1.3),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Ui.red,
                foregroundColor: Ui.palette.onAccent,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              onPressed: () => _go((c) => _push(c, const AuthScreen())),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: Text(
                'Sign in'.tr,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * .86)
        .clamp(280.0, 340.0)
        .toDouble();

    return Drawer(
      width: width,
      backgroundColor: Ui.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([
          AuthService.instance,
          SubscriptionService.instance,
        ]),
        builder: (context, _) {
          final user = AuthService.instance.user;
          final subs = SubscriptionService.instance;

          return Column(
            children: [
              _header(context, user, subs.isPremium),
              Divider(
                height: 1,
                thickness: 1,
                indent: 20,
                endIndent: 20,
                color: Ui.line,
              ),
              // ------------------------------------------------ menu
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 6, bottom: 12),
                  children: [
                    if (widget.onHome != null)
                      _row(
                        Icons.home_outlined,
                        'Home'.tr,
                        (c) async => widget.onHome!(),
                      ),
                    if (user != null)
                      _row(
                        Icons.person_outline_rounded,
                        'Profile'.tr,
                        (c) => _push(c, FanProfileScreen(userId: user.id)),
                      ),
                    _row(
                      Icons.bookmark_border_rounded,
                      'Bookmarks'.tr,
                      (c) => _push(c, const BookmarksScreen()),
                      badge: ValueListenableBuilder<Set<String>>(
                        valueListenable: PostBookmarks.instance.ids,
                        builder: (_, saved, _) => saved.isEmpty
                            ? const SizedBox.shrink()
                            : Text(
                                '${saved.length}',
                                style: TextStyle(
                                  color: Ui.muted,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                    _row(
                      Icons.workspace_premium_outlined,
                      'Premium'.tr,
                      (c) => _push(
                        c,
                        subs.visible
                            ? const PlansScreen()
                            : const RemoveAdsScreen(),
                      ),
                      badge: subs.isPremium ? _pill('Active'.tr) : null,
                    ),
                    _heading('Watch'.tr),
                    _row(
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
                    _row(
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
                    _row(
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
                    _row(
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
                    _heading('Scores'.tr),
                    _row(
                      Icons.sports_soccer_rounded,
                      'Football Score'.tr,
                      (c) => openInApp(
                        c,
                        AppConfig.footballScoreUrl,
                        title: 'Football Score'.tr,
                      ),
                    ),
                    _row(
                      Icons.sports_cricket_rounded,
                      'Cricket Score'.tr,
                      (c) => openInApp(
                        c,
                        AppConfig.cricketScoreUrl,
                        title: 'Cricket Score'.tr,
                      ),
                    ),
                    _heading('Tools'.tr),
                    _row(
                      Icons.link_rounded,
                      'Network Stream'.tr,
                      (c) => _push(c, const NetworkStreamScreen()),
                    ),
                    _row(
                      Icons.playlist_play_rounded,
                      'Playlists'.tr,
                      (c) => _push(c, const PlaylistsScreen()),
                    ),
                  ],
                ),
              ),
              // ------------------------------------------------ pinned dock
              Divider(
                height: 1,
                thickness: 1,
                indent: 20,
                endIndent: 20,
                color: Ui.line,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  10,
                  8,
                  10,
                  MediaQuery.of(context).viewPadding.bottom + 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _dock(Icons.palette_outlined, 'Themes'.tr, showThemeSheet),
                        _dock(
                          Icons.language_rounded,
                          'Language'.tr,
                          showLanguageSheet,
                        ),
                        _dock(
                          Icons.notifications_none_rounded,
                          'Alerts'.tr,
                          (c) async {
                            await _push(c, const NotificationsScreen());
                            NotificationCenter.instance.refreshBadge();
                          },
                          count: NotificationCenter.instance.unread,
                        ),
                        _dock(Icons.tune_rounded, 'More'.tr, showSettingsSheet),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${AppConfig.appName} • ${'Version'.tr} ${AppConfig.appVersion}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Ui.dim, fontSize: 11),
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

// ----------------------------------------------------- settings and support

/// Everything that is not a content shortcut or a quick dock action.
/// [context] is the app's root navigator context (the drawer is already
/// closed when this runs).
Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Ui.panel,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    builder: (ctx) {
      Widget item(
        IconData icon,
        String label,
        Future<void> Function(BuildContext) action, {
        String? hint,
        bool danger = false,
      }) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon, size: 24, color: danger ? Ui.red : null),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: danger ? Ui.red : null,
          ),
        ),
        subtitle: hint == null
            ? null
            : Text(hint, style: TextStyle(color: Ui.muted, fontSize: 12)),
        onTap: () {
          Navigator.pop(ctx);
          action(context);
        },
      );

      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  'Settings and support'.tr,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              item(
                Icons.picture_in_picture_alt_outlined,
                'Floating Player'.tr,
                showFloatingPlayerDialog,
              ),
              item(
                Icons.tune_rounded,
                'Video Quality Setting'.tr,
                showLowQualityDialog,
              ),
              Divider(height: 18, color: Ui.line),
              item(Icons.campaign_outlined, 'Notice'.tr, showNoticeDialog),
              item(
                Icons.chat_bubble_outline_rounded,
                'Join Us'.tr,
                (c) => _openLink(c, AppConfig.joinUrl, 'Join Us'.tr),
              ),
              item(
                Icons.ios_share_rounded,
                'Share App'.tr,
                (c) => AppSharer.instance.share(c),
              ),
              item(
                Icons.sync_rounded,
                'Update App'.tr,
                (c) => AppUpdater.instance.update(c),
              ),
              item(
                Icons.copyright_rounded,
                'Copyright'.tr,
                showCopyrightDialog,
              ),
              Divider(height: 18, color: Ui.line),
              item(
                Icons.exit_to_app_rounded,
                'Exit'.tr,
                (c) async => SystemNavigator.pop(),
                danger: true,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Text(
                  '${'Version'.tr}: ${AppConfig.appVersion}',
                  style: TextStyle(color: Ui.dim, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
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
