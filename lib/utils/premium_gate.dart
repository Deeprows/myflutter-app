import 'package:flutter/material.dart';

import '../config.dart';
import '../screens/plans_screen.dart';
import '../screens/remove_ads_screen.dart';
import '../services/ad_unlock.dart';
import '../services/remote_config.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

/// Movies are open for everyone to browse, but Play and Download are for
/// Premium members. Everyone else is sent to the upgrade page.
class PremiumGate {
  PremiumGate._();

  /// True when Play / Download must send this person to upgrade.
  /// (Never locks when subscriptions are not set up, so nobody gets stuck.)
  static bool get locked =>
      AppConfig.moviesPremiumOnly &&
      SubscriptionService.instance.enabled &&
      !SubscriptionService.instance.isPremium &&
      !AdUnlock.instance.isUnlocked;

  /// Returns true when the person may go ahead (already Premium, or just
  /// upgraded). Otherwise explains, opens the upgrade page and returns false
  /// if they did not upgrade.
  static Future<bool> allowMovies(BuildContext context) async {
    await AdUnlock.instance.load();
    if (!locked) return true;
    final go = await showModalBottomSheet<String>(
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
                'Movies are for Premium members',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'You can browse every movie and series for free. Upgrade to '
                'Premium to play and download them.',
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
                  label: const Text(
                    'Upgrade to Premium',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
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
    if (go == 'ad') return AdUnlock.instance.watchAd(context);
    if (go != 'premium') return false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubscriptionService.instance.visible
            ? const PlansScreen()
            : const RemoveAdsScreen(),
      ),
    );
    // They may have just paid: ask the Worker before deciding.
    await SubscriptionService.instance.refresh(force: true);
    return SubscriptionService.instance.isPremium;
  }
}
