import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/ad_scheduler.dart';
import '../theme/app_theme.dart';
import 'auth_screen.dart';
import 'shell_screen.dart';

/// Signed-in users choose the live-football or community experience.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _adsHeld = false;
  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_authChanged);
    _syncAds();
    unawaited(AuthService.instance.restore());
  }

  void _syncAds() {
    if (!AuthService.instance.signedIn && !_adsHeld) {
      AdScheduler.instance.hold();
      _adsHeld = true;
    }
    if (AuthService.instance.signedIn && _adsHeld) {
      AdScheduler.instance.release();
      _adsHeld = false;
    }
  }

  void _authChanged() {
    _syncAds();
    if (mounted) {
      setState(() {});
      if (AuthService.instance.ready && !AuthService.instance.signedIn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !AuthService.instance.signedIn) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_authChanged);
    if (_adsHeld) {
      AdScheduler.instance.release();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    if (!auth.ready) {
      return Scaffold(
        backgroundColor: Ui.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!auth.signedIn) {
      return const AuthScreen();
    }
    // Skip the separate Experience page and open the main app directly.
    return KeyedSubtree(
      key: ValueKey(auth.user!.id),
      child: const ShellScreen(),
    );
  }
}
