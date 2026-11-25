import 'package:flutter/material.dart';

import '../config.dart';
import '../screens/plans_screen.dart';
import '../screens/remove_ads_screen.dart';
import '../services/ad_unlock.dart';
import '../services/remote_config.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

/// Everyone can browse the movie catalogue and watch three distinct titles.
/// Further Play / Alternate player / Download actions require Premium.
class PremiumGate {
  PremiumGate._();

  /// True when a non-Premium account has no more movie access.
  static bool get locked =>
      AppConfig.moviesPremiumOnly &&
      SubscriptionService.instance.enabled &&
      !SubscriptionService.instance.isPremium;

  /// True when a non-Premium account has reached the shared three-title limit.
  static bool get downloadLocked =>
      AppConfig.moviesPremiumOnly &&
      SubscriptionService.instance.enabled &&
      !SubscriptionService.instance.isPremium;

  /// The Smart Decoder hub and its features are Premium-only.
  static bool get decoderLocked =>
      SubscriptionService.instance.enabled &&
      !SubscriptionService.instance.isPremium;

  /// The full Decoder, receiver and mirroring features are Premium-only.
  /// Direct TV casting has its own five-use free allowance below.
  static Future<bool> allowDecoder(BuildContext context) => _gate(
        context,
        isLocked: () => decoderLocked,
        title: 'Deeprowss Decoder is for Premium members',
        body: 'Upgrade to Premium to get your Decoder number and unlock the Smart Decoder, Windows EXE and Android TV receiver.',
        allowAd: false,
      );

  /// Free accounts receive five cast attempts; opening the device list is free.
  static Future<bool> allowCast(BuildContext context) async {
    if (!SubscriptionService.instance.enabled || SubscriptionService.instance.isPremium) return true;
    final access = await SubscriptionService.instance.consumeCastAccess();
    if (!access.verified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not verify your free casting allowance. Please try again when connected.')),
      );
      return false;
    }
    if (access.allowed) return true;
    return _gate(
      context,
      isLocked: () => !SubscriptionService.instance.isPremium,
      title: 'Your 5 free casts are used',
      body: 'Upgrade to Premium for unlimited casting to TVs and Kodi.',
      allowAd: false,
    );
  }

  /// Download button: true only for Premium members (or right after they
  /// upgrade). Everyone else sees the upgrade sheet, with no ad option.
  static Future<bool> allowDownload(BuildContext context, String movieKey) =>
      allowMovies(context, movieKey, action: 'download');

  /// One visitor may play / download three distinct titles. The Worker keeps
  /// the count against the app account or persistent guest / receiver ID.
  static Future<bool> allowMovies(
    BuildContext context,
    String movieKey, {
    String action = 'play',
  }) async {
    if (!AppConfig.moviesPremiumOnly || !SubscriptionService.instance.enabled ||
        SubscriptionService.instance.isPremium) return true;
    final access = await SubscriptionService.instance.consumeMovieAccess(movieKey, action: action);
    if (!access.verified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not verify your free movie allowance. Please try again when connected.')),
      );
      return false;
    }
    if (access.allowed) return true;
    return _gate(
      context,
      isLocked: () => !SubscriptionService.instance.isPremium,
      title: 'Your 3 free movies are used',
      body: 'Upgrade to Premium to keep watching, use the alternate player and download movies and series.',
      allowAd: false,
    );
  }

  static Future<bool> _gate(
    BuildContext context, {
    required bool Function() isLocked,
    required String title,
    required String body,
    required bool allowAd,
  }) async {
    await AdUnlock.instance.load();
    if (!isLocked()) return true;
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
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                body,
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
              if (allowAd && AdUnlock.instance.available) ...[
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
    if (go == 'ad' && allowAd) return AdUnlock.instance.watchAd(context);
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
    return !isLocked();
  }
}
