import 'package:flutter/material.dart';

import '../models/fan_post_link.dart';
import '../screens/browser_screen.dart' show openExternally, openInApp;
import '../screens/plans_screen.dart' show PlansScreen;
import '../screens/remove_ads_screen.dart' show RemoveAdsScreen;
import '../services/embed_info.dart';
import '../services/fan_zone_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

/// WhatsApp and Telegram links: these open in their own apps, never in the
/// in-app browser.
bool isChatAppLink(String url) {
  final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
  bool on(String site) => host == site || host.endsWith('.$site');
  return on('wa.me') ||
      on('whatsapp.com') ||
      on('whatsapp.net') ||
      on('t.me') ||
      on('telegram.me') ||
      on('telegram.dog') ||
      on('telegram.org') ||
      on('telesco.pe');
}

/// A plain web page (not a YouTube / TikTok / Facebook video / Vimeo /
/// Dailymotion / Filemoon video or a direct stream). Attaching one to a post
/// is a Premium feature.
bool isWebPageLink(String url) =>
    embedInfoFor(url).kind == EmbedKind.generic;

/// True when [text] contains a web page link (WhatsApp / Telegram included).
bool textHasWebPageLink(String text) => fanPostLinks(text).any(isWebPageLink);

/// Paid Premium on this phone, or the weekly Premium the top 3 of the Fan
/// League table receive.
Future<bool> canAttachLinks() async {
  if (SubscriptionService.instance.isPremium) return true;
  return FanZoneService.hasWeeklyPremium();
}

/// Returns true when the person may attach a web page link. Otherwise it
/// explains that links are for Premium members and offers the upgrade page.
Future<bool> ensureLinkPremium(BuildContext context) async {
  if (await canAttachLinks()) return true;
  if (!context.mounted) return false;
  final upgrade = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Ui.panel,
      title: const Text(
        'Links are for Premium',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: const Text(
        'Only Premium members can attach web page links to posts. '
        'Top 3 fans on the table each week get Premium for the week.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Upgrade To Premium'),
        ),
      ],
    ),
  );
  if (upgrade != true || !context.mounted) return false;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SubscriptionService.instance.visible
          ? const PlansScreen()
          : const RemoveAdsScreen(),
    ),
  );
  await SubscriptionService.instance.refresh(force: true);
  return canAttachLinks();
}

/// Web pages open inside the app; WhatsApp and Telegram links open in their
/// own apps.
Future<void> openPostLink(BuildContext context, String url) async {
  if (isChatAppLink(url)) {
    final ok = await openExternally(url);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this link.')),
      );
    }
    return;
  }
  await openInApp(context, url);
}
