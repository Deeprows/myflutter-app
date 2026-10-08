import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../theme/app_theme.dart';
import '../widgets/support_overlay.dart';
import 'push_service.dart';

/// The OLD trigger for the "We Need Your Support" overlay (tapping a card).
/// It is switched off ([AppConfig.supportOnCardTap] = false): free-plan ads
/// now come from `AdScheduler` every 15 minutes. [guard] just lets the tap
/// through while it is off. Call [guard] from a card's tap handler:
///
///   SupportGate.guard(context, () => openThePlayer());
///
/// The overlay appears at most once every 12 hours (AppConfig). Either way,
/// `proceed` runs afterwards so the tapped card still opens.
class SupportGate {
  static const _kDone = 'support_last_done_ms';
  static const _kRetry = 'support_last_retry_ms';
  static bool _showing = false;

  /// Pure rule, unit-tested. [lastDoneMs] = last time the support page was
  /// viewed to the end; [lastRetryMs] = last time the support page could not
  /// load and the person was let through.
  static bool isDue({
    required int nowMs,
    int? lastDoneMs,
    int? lastRetryMs,
    int intervalHours = AppConfig.supportIntervalHours,
    int retryHours = AppConfig.supportRetryHours,
  }) {
    bool within(int? last, int hours) {
      if (last == null) return false;
      final elapsed = nowMs - last;
      // elapsed < 0: the phone clock was moved back, so don't trust it.
      return elapsed >= 0 && elapsed < hours * 3600000;
    }

    return !within(lastDoneMs, intervalHours) &&
        !within(lastRetryMs, retryHours);
  }

  static Future<void> guard(BuildContext context, VoidCallback proceed) async {
    if (_showing) return; // ignore a second tap while the overlay is up
    if (!AppConfig.supportOnCardTap || AppConfig.supportUrl.trim().isEmpty) {
      proceed();
      return;
    }

    SharedPreferences? prefs;
    var due = false;
    try {
      prefs = await SharedPreferences.getInstance();
      due = isDue(
        nowMs: DateTime.now().millisecondsSinceEpoch,
        lastDoneMs: prefs.getInt(_kDone),
        lastRetryMs: prefs.getInt(_kRetry),
      );
    } catch (_) {}

    if (!due || prefs == null || !context.mounted) {
      proceed();
      return;
    }

    _showing = true;
    SupportChoice? choice;
    try {
      choice = await showSupportOverlay(context);
    } finally {
      _showing = false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      if (choice == SupportChoice.supported) {
        await prefs.setInt(_kDone, now);
      } else {
        await prefs.setInt(_kRetry, now);
      }
    } catch (_) {}

    if (choice == SupportChoice.supported) showThanks();
    proceed();
  }

  /// "Thanks 💗" banner, shown right after the support page closes.
  static void showThanks() {
    final messenger = PushService.messengerKey.currentState;
    if (messenger == null) return;
    final m = AppConfig.adIntervalMinutes;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        duration: const Duration(seconds: 5),
        content: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          decoration: BoxDecoration(
            color: Ui.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Ui.red.withValues(alpha: .55)),
            boxShadow: [
              BoxShadow(
                color: Ui.red.withValues(alpha: .25),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [Ui.red, Ui.redSoft]),
                ),
                child: const Icon(Icons.favorite_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Thanks 💗',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(
                      'Enjoy $m minutes of uninterrupted streaming.',
                      style: TextStyle(color: Ui.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ));
  }
}
