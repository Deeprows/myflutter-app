import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/channel.dart';
import '../screens/native_player_screen.dart';
import '../screens/plans_screen.dart';
import '../screens/player_screen.dart';
import '../screens/remove_ads_screen.dart';
import '../services/ad_unlock.dart';
import '../services/remote_config.dart';
import '../services/subscription_service.dart';
import '../services/support_gate.dart';
import '../theme/app_theme.dart';

/// Opens a TV channel in the app's own channel player: the same free daily
/// allowance / Premium check, support overlay and player choice (native for
/// HLS / DASH / video links, web player for embed pages) as the Live TV tab.
Future<void> openChannelPlayer(BuildContext context, Channel c) async {
  if (!await _allowChannel(context, c) || !context.mounted) return;
  SupportGate.guard(context, () {
    if (context.mounted) _openNow(context, c);
  });
}

const int _freeChannelsPerDay = 2;

String _todayKey() {
  final now = DateTime.now();
  final day = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  return 'tv_daily_channel_access_$day';
}

String _channelAccessId(Channel c) =>
    (c.id?.trim().isNotEmpty == true ? c.id!.trim() : '${c.name.trim()}|${c.url.trim()}');

Future<bool> _allowChannel(BuildContext context, Channel c) async {
  final subscription = SubscriptionService.instance;
  // Match the movie premium gate: when subscriptions are not configured,
  // don't strand users behind a paywall.
  if (!subscription.enabled || subscription.isPremium) return true;
  await AdUnlock.instance.load();
  // Watched the ad in the last ten minutes: every channel is open.
  if (AdUnlock.instance.isUnlocked) return true;

  final prefs = await SharedPreferences.getInstance();
  final key = _todayKey();
  final accessed = prefs.getStringList(key) ?? <String>[];
  final channelId = _channelAccessId(c);

  // Reopening either of the two channels already used today is allowed.
  if (accessed.contains(channelId)) return true;

  if (accessed.length >= _freeChannelsPerDay) {
    final upgrade = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium_rounded, size: 46, color: Ui.red),
              const SizedBox(height: 12),
              const Text(
                'Daily free TV limit reached',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'Free users can watch up to 2 different TV channels per day. '
                'Upgrade to Premium to watch every channel without limits.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(ctx).pop('premium'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Ui.red,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.workspace_premium_rounded),
                  label: const Text('Upgrade to Premium',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
              if (AdUnlock.instance.available) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(ctx).pop('ad'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Ui.red,
                      side: BorderSide(color: Ui.red.withValues(alpha: .7)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.ondemand_video_rounded, size: 20),
                    label: Text(
                      'or watch ad ${RemoteConfig.instance.adUnlockSeconds} secs every ten '
                      'minutes to unlock access',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('no'),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted) return false;
    if (upgrade == 'ad') {
      final ok = await AdUnlock.instance.watchAd(context);
      return ok && context.mounted;
    }
    if (upgrade != 'premium') return false;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => subscription.visible
          ? const PlansScreen()
          : const RemoveAdsScreen(),
    ));
    await subscription.refresh(force: true);
    return subscription.isPremium;
  }

  accessed.add(channelId);
  await prefs.setStringList(key, accessed);
  return true;
}


void _openNow(BuildContext context, Channel c) {
  // HLS / DASH / video links: native player (real Referer + User-Agent).
  // Embed pages (and anything it can't handle) keep using the web player.
  if (AppConfig.nativeTvPlayer && nativePlayable(c.url)) {
    final alt = (c.altUrl ?? '').trim();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NativePlayerScreen(
        title: c.name,
        subtitle: 'Live TV · ${c.category.label}',
        streams: [
          NativeStream(c.url, referer: c.referer, userAgent: c.userAgent),
          if (alt.isNotEmpty && nativePlayable(alt))
            NativeStream(alt,
                referer: c.altReferer, userAgent: c.altUserAgent),
        ],
      ),
    ));
    return;
  }

  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => PlayerScreen(
      title: c.name,
      subtitle: 'Live TV · ${c.category.label}',
      url: c.url,
      referer: c.referer,
      userAgent: c.userAgent,
      altUrl: c.altUrl,
      altReferer: c.altReferer,
      altUserAgent: c.altUserAgent,
      isLive: true,
    ),
  ));
}
