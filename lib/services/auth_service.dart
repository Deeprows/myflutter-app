import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class AuthUser {
  final String id, email, name, photo;
  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    required this.photo,
  });
  Map<String, String> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'photo': photo,
  };
  static AuthUser? parse(dynamic value) {
    if (value is! Map || value['id'] is! String || value['email'] is! String)
      return null;
    return AuthUser(
      id: value['id'],
      email: value['email'],
      name: '${value['name'] ?? ''}',
      photo: '${value['photo'] ?? ''}',
    );
  }
}

class AuthFailure {
  final String message;
  final String? switchTo;
  const AuthFailure(this.message, [this.switchTo]);
}

/// Google owns the credential/session. Only non-secret profile information
/// is cached here for startup/offline display; the backend verifies each token.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final instance = AuthService._();
  static const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const _profileKey = 'deeprowss_google_profile_v1';
  static const _signedOutKey = 'deeprowss_google_signed_out';
  final _google = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: webClientId.isEmpty ? null : webClientId,
  );
  AuthUser? _user;
  bool _ready = false, _busy = false;
  Future<void>? _restoring;
  AuthUser? get user => _user;
  bool get ready => _ready;
  bool get signedIn => _user != null;
  bool _gmail(String email) => RegExp(
    r'@(gmail|googlemail)\.com$',
    caseSensitive: false,
  ).hasMatch(email);

  Future<void> restore() => _restoring ??= _restore();
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_signedOutKey) == true) return;
      final saved = prefs.getString(_profileKey);
      if (saved != null) {
        try {
          _user = AuthUser.parse(jsonDecode(saved));
        } catch (_) {}
      }
      // Returning users see the app immediately; native Google refresh can
      // fail while offline without deleting their last valid local profile.
      if (_user != null) {
        unawaited(_quietRefresh());
        return;
      }
      if (webClientId.isEmpty) return;
      final account = await _google.signInSilently().timeout(
        const Duration(seconds: 8),
      );
      if (account != null && _gmail(account.email))
        await _check(account, signUp: false);
    } catch (_) {
      // First-time users still get the sign-in screen with a retry button.
    } finally {
      _ready = true;
      notifyListeners();
    }
  }

  Future<void> _quietRefresh() async {
    try {
      await _google.signInSilently().timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<AuthFailure?> _check(
    GoogleSignInAccount account, {
    required bool signUp,
  }) async {
    final token = (await account.authentication).idToken;
    if (token == null || token.isEmpty)
      return const AuthFailure(
        'Google did not return an ID token. Check the Web OAuth client ID and Android SHA-1 setup.',
      );
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString('fan_zone_token');
    final response = await http
        .post(
          Uri.parse('${AppConfig.feedBase}/fan/auth'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'mode': signUp ? 'signup' : 'login',
            'idToken': token,
            if (legacy != null) 'legacyToken': legacy,
          }),
        )
        .timeout(const Duration(seconds: 20));
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      return const AuthFailure(
        'Deploy the updated Deeprowss Worker before signing in.',
      );
    }
    if (response.statusCode != 200) {
      return AuthFailure(
        body is Map
            ? '${body['error'] ?? 'Sign-in failed. Try again.'}'
            : 'Sign-in failed. Try again.',
        body is Map ? body['switchTo'] as String? : null,
      );
    }
    final user = AuthUser.parse(body is Map ? body['user'] : null);
    if (user == null)
      return const AuthFailure(
        'The account server returned an invalid profile. Please retry.',
      );
    _user = user;
    try {
      await prefs.setString(_profileKey, jsonEncode(user.toJson()));
      await prefs.setBool(_signedOutKey, false);
      // The server has checked and claimed migration ownership, if a legacy
      // profile existed. Never offer the old device identity to another account.
      await prefs.remove('fan_zone_token');
    } catch (_) {}
    notifyListeners();
    return null;
  }

  Future<AuthFailure?> signIn({required bool signUp}) async {
    if (_busy) return null;
    if (webClientId.isEmpty)
      return const AuthFailure(
        'Google sign-in needs GOOGLE_WEB_CLIENT_ID in the GitHub build settings.',
      );
    _busy = true;
    try {
      await _google.signOut();
      final account = await _google.signIn();
      if (account == null) return null;
      if (!_gmail(account.email)) {
        await _google.signOut();
        return const AuthFailure('Please continue with a Gmail account.');
      }
      final failure = await _check(account, signUp: signUp);
      if (failure != null) await _google.signOut();
      return failure;
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_canceled') return null;
      if (e.code == 'network_error')
        return const AuthFailure(
          'Check your internet connection and try again.',
        );
      if (RegExp(r'(^|\D)10(\D|$)|DEVELOPER_ERROR').hasMatch(e.message ?? '')) {
        return const AuthFailure(
          'Google sign-in is not configured for this APK. Check the Android package, release SHA-1 and Web client ID.',
        );
      }
      return const AuthFailure(
        'Google sign-in could not finish. Please retry.',
      );
    } on TimeoutException {
      return const AuthFailure(
        'The account server took too long. Please retry.',
      );
    } catch (_) {
      return const AuthFailure(
        'Could not sign in. Check your connection and Worker settings.',
      );
    } finally {
      _busy = false;
    }
  }

  Future<String> idToken() async {
    final user = _user;
    if (user == null) throw Exception('Please log in to Deeprowss.');
    final account =
        _google.currentUser ??
        await _google.signInSilently().timeout(const Duration(seconds: 10));
    if (account == null ||
        account.email.toLowerCase() != user.email.toLowerCase()) {
      throw Exception(
        'Google could not restore this account. Log out and log in again.',
      );
    }
    final token = (await account.authentication).idToken;
    if (token == null || token.isEmpty)
      throw Exception(
        'Could not refresh your sign-in. Check your connection or log in again.',
      );
    return token;
  }

  Future<void> signOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_signedOutKey, true);
      await prefs.remove(_profileKey);
    } catch (_) {}
    try {
      await _google.signOut();
    } catch (_) {}
    _user = null;
    notifyListeners();
  }
}
