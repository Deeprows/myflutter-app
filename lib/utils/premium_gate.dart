import 'package:flutter/material.dart';

import '../config.dart';
import '../screens/plans_screen.dart';
import '../screens/remove_ads_screen.dart';
import '../services/ad_unlock.dart';
import '../services/auth_service.dart';
import '../services/login_gate.dart';
import '../services/remote_config.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

/// Central entitlement checks for Smart Decoder, movies and casting.
class PremiumGate {
  PremiumGate._();

  static bool get locked =>
      AppConfig.moviesPremiumOnly &&
      SubscriptionService.instance.enabled &&
      !SubscriptionService.instance.isPremium;

  static bool get downloadLocked => locked;
  static bool get decoderLocked => !AuthService.instance.signedIn;

  /// Sign-in plus server-side first-entry trial registration.
  static Future<DecoderAccessResult?> _decoderAccess(BuildContext context) async {
    if (!await ensureSignedIn(context) || !context.mounted) return null;
    final access = await SubscriptionService.instance.beginDecoderAccess();
    if (!context.mounted) return null;
    if (!access.verified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not verify Smart Decoder access. Please connect to the internet and try again.')),
      );
      return null;
    }
    return access;
  }

  static Future<bool> allowDecoder(BuildContext context) async =>
      await _decoderAccess(context) != null;

  /// Live events are available only during the 72-hour trial or Premium.
  static Future<bool> allowLiveEvents(BuildContext context) async {
    final access = await _decoderAccess(context);
    if (access == null) return false;
    if (access.premium || access.trialActive) return true;
    return _gate(
      context,
      isLocked: () => !SubscriptionService.instance.isPremium,
      title: 'Premium required for Live Events',
      body: 'Your free Smart Decoder trial has ended. Subscribe to Premium to watch and cast live events.',
      allowAd: false,
    );
  }

  /// TV / Kodi casting and receiver-page access require an active trial or
  /// Premium. There are no five-cast free attempts after the trial.
  static Future<bool> allowCast(BuildContext context) async {
    final access = await _decoderAccess(context);
    if (access == null) return false;
    if (access.premium || access.trialActive) return true;
    return _gate(
      context,
      isLocked: () => !SubscriptionService.instance.isPremium,
      title: 'Premium required for casting',
      body: 'Your free Smart Decoder trial has ended. Upgrade to Premium to cast to TVs, Kodi or the receiver page.',
      allowAd: false,
    );
  }

  static Future<bool> consumeReceiverAccess(BuildContext context) =>
      allowCast(context);

  /// One of four distinct channels per UTC day after the trial.
  static Future<bool> allowTvChannel(BuildContext context, String channelKey) async {
    final access = await _decoderAccess(context);
    if (access == null) return false;
    if (access.premium || access.trialActive) return true;
    final quota = await SubscriptionService.instance.consumeTvAccess(channelKey);
    if (!context.mounted) return false;
    if (!quota.verified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not verify today’s TV channel allowance. Please try again.')),
      );
      return false;
    }
    if (quota.allowed) return true;
    return _gate(
      context,
      isLocked: () => !SubscriptionService.instance.isPremium,
      title: 'Today’s 4 free TV channels are used',
      body: 'Your TV channel allowance resets at midnight UTC. Upgrade to Premium for unlimited channels.',
      allowAd: false,
    );
  }

  static Future<bool> allowDownload(BuildContext context, String movieKey) =>
      allowMovies(context, movieKey, action: 'download');

  /// Existing Movies catalogue allowance remains three distinct titles
  /// across the account. Smart Decoder uses its separate daily quota below.
  static Future<bool> allowMovies(
    BuildContext context,
    String movieKey, {
    String action = 'play',
  }) async {
    final service = SubscriptionService.instance;
    if (!AppConfig.moviesPremiumOnly || !service.enabled || service.isPremium) return true;
    final quota = await service.consumeMovieAccess(movieKey, action: action);
    if (!context.mounted) return false;
    if (!quota.verified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not verify your movie allowance. Please try again when connected.')),
      );
      return false;
    }
    if (quota.allowed) return true;
    return _gate(
      context,
      isLocked: () => !SubscriptionService.instance.isPremium,
      title: 'Your 3 free movies are used',
      body: 'Upgrade to Premium to keep watching, use the alternate player and download movies and series.',
      allowAd: false,
    );
  }

  /// Smart Decoder Moviebox: unlimited during the trial, then three distinct
  /// titles per UTC day. The main Movies catalogue does not start the trial.
  static Future<bool> allowDecoderMovies(
    BuildContext context,
    String movieKey, {
    String action = 'play',
  }) async {
    final access = await _decoderAccess(context);
    if (access == null) return false;
    if (access.premium || access.trialActive) return true;
    final quota = await SubscriptionService.instance.consumeDecoderMovieAccess(movieKey, action: action);
    if (!context.mounted) return false;
    if (!quota.verified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not verify today’s movie allowance. Please try again.')),
      );
      return false;
    }
    if (quota.allowed) return true;
    return _gate(
      context,
      isLocked: () => !SubscriptionService.instance.isPremium,
      title: 'Today’s 3 free movies are used',
      body: 'Your Smart Decoder movie allowance resets at midnight UTC. Upgrade to Premium for unlimited movies and series.',
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
              Text(title, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
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
                      'or watch ad ${RemoteConfig.instance.adUnlockSeconds} secs every ten minutes to unlock access',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
              TextButton(onPressed: () => Navigator.of(ctx).pop('no'),
                  child: const Text('Not now')),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted) return false;
    if (go == 'ad' && allowAd) return AdUnlock.instance.watchAd(context);
    if (go != 'premium') return false;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SubscriptionService.instance.visible
          ? const PlansScreen()
          : const RemoveAdsScreen(),
    ));
    await SubscriptionService.instance.refresh(force: true);
    return !isLocked();
  }
}
