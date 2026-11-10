import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../screens/ad_support_screen.dart';
import '../screens/support_browser_screen.dart' show SupportResult;
import 'ad_preloader.dart';
import 'ad_scheduler.dart';
import 'remote_config.dart';
import 'subscription_service.dart';
import 'support_gate.dart';

/// "Or watch ad" unlock for free people.
///
/// Watching the ad page for [RemoteConfig.instance.adUnlockSeconds] seconds (then tapping
/// Skip Ad) unlocks Movies and TV channels for [RemoteConfig.instance.adUnlockMinutes]
/// minutes. When the time is over the next Play / Download / channel tap asks
/// again. The unlock time is saved, so closing the app does not lose it.
class AdUnlock {
  AdUnlock._();
  static final AdUnlock instance = AdUnlock._();

  static const _kUntil = 'ad_unlock_until_ms';

  int _untilMs = 0;
  bool _loaded = false;
  bool _busy = false;

  /// The option is offered: switched on, an ad page is set and the person is
  /// not Premium.
  bool get available =>
      RemoteConfig.instance.adUnlockEnabled &&
      AppConfig.plansEnabled &&
      RemoteConfig.instance.supportUrl.trim().isNotEmpty &&
      !SubscriptionService.instance.isPremium;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      _untilMs =
          (await SharedPreferences.getInstance()).getInt(_kUntil) ?? 0;
    } catch (_) {}
  }

  /// True while an ad-unlock is still running.
  bool get isUnlocked {
    final now = DateTime.now().millisecondsSinceEpoch;
    final left = _untilMs - now;
    // left > window: the phone clock was moved back, so don't trust it.
    return left > 0 && left <= RemoteConfig.instance.adUnlockMinutes * 60000 + 5000;
  }

  /// Time left of the current unlock (zero when locked).
  Duration get remaining => isUnlocked
      ? Duration(
          milliseconds: _untilMs - DateTime.now().millisecondsSinceEpoch)
      : Duration.zero;

  Future<void> _grant() async {
    _untilMs = DateTime.now().millisecondsSinceEpoch +
        RemoteConfig.instance.adUnlockMinutes * 60000;
    try {
      (await SharedPreferences.getInstance()).setInt(_kUntil, _untilMs);
    } catch (_) {}
  }

  /// Opens the same ad screen used for support ads. Returns true when the
  /// person may go ahead: they watched it (and the unlock starts now), or the
  /// ad page could not load at all (let through once, nobody is locked out).
  Future<bool> watchAd(BuildContext context) async {
    await load();
    if (isUnlocked) return true;
    if (_busy || !context.mounted) return false;
    _busy = true;
    try {
      final r = await Navigator.of(context, rootNavigator: true)
          .push<SupportResult>(
        MaterialPageRoute<SupportResult>(
          fullscreenDialog: true,
          builder: (_) => AdSupportScreen(
            url: RemoteConfig.instance.supportUrl,
            preloaded: AdPreloader.instance.take(),
            skipAfterSeconds: RemoteConfig.instance.adUnlockSeconds,
            note:
                'Ad · watch ${RemoteConfig.instance.adUnlockSeconds}s to unlock ${RemoteConfig.instance.adUnlockMinutes} min',
          ),
        ),
      );
      if (r == SupportResult.completed) {
        await _grant();
        // The ad was just watched: no second ad on the next tap, and the
        // normal 10-minute ad clock starts again.
        SupportGate.markShown();
        AdScheduler.instance.restartClock();
        return true;
      }
      return r == SupportResult.failed;
    } finally {
      _busy = false;
    }
  }
}
