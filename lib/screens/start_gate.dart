import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../services/ad_scheduler.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import 'plans_screen.dart';
import 'shell_screen.dart';

/// First screen: Free or Premium. Premium people go straight into the app.
class StartGate extends StatefulWidget {
  const StartGate({super.key});

  @override
  State<StartGate> createState() => _StartGateState();
}

class _StartGateState extends State<StartGate> {
  static const _kSeen = 'plans_seen';

  bool _decided = false;
  bool _showPlans = false;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final sub = SubscriptionService.instance;
    var show = sub.enabled && !sub.isPremium;
    if (show && !AppConfig.showPlansEveryStart) {
      try {
        final prefs = await SharedPreferences.getInstance();
        show = !(prefs.getBool(_kSeen) ?? false);
      } catch (_) {}
    }
    if (!show) unawaited(AdScheduler.instance.start());
    if (!mounted) return;
    setState(() {
      _showPlans = show;
      _decided = true;
    });
  }

  Future<void> _enter() async {
    try {
      (await SharedPreferences.getInstance()).setBool(_kSeen, true);
    } catch (_) {}
    unawaited(AdScheduler.instance.start());
    if (mounted) setState(() => _showPlans = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_decided) return Scaffold(backgroundColor: Ui.bg);
    if (_showPlans) return PlansScreen(onContinue: _enter);
    return const ShellScreen();
  }
}
