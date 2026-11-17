import 'package:flutter/material.dart';

import '../screens/auth_screen.dart';
import 'auth_service.dart';

/// Guests can open the app and browse Live Events. Anything else calls this
/// first: it returns true when the person is signed in, otherwise it shows
/// the login page and returns false (a successful sign-in rebuilds the app
/// on the Live page, so the person simply taps again).
Future<bool> ensureSignedIn(BuildContext context) async {
  if (AuthService.instance.signedIn) return true;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
  );
  return context.mounted && AuthService.instance.signedIn;
}
