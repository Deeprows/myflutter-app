import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/ad_scheduler.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

/// Restores authentication before showing the Deeprowss landing page.
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
    // Guests now see the live page, so ads are no longer held back.
    if (_adsHeld) {
      AdScheduler.instance.release();
      _adsHeld = false;
    }
  }

  void _authChanged() {
    _syncAds();
    if (mounted) {
      setState(() {});
      if (AuthService.instance.ready) {
        // Signed out, or just signed in from a login page opened over the
        // app: return to the first page.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
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
    // The landing page is the first in-app screen after the splash finishes.
    // Guests can browse Live Events; protected areas request sign-in.
    return KeyedSubtree(
      key: ValueKey(auth.user?.id ?? 'guest'),
      child: const HomeScreen(),
    );
  }
}
