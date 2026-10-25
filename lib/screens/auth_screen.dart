import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _signUp = true, _busy = false;
  AuthFailure? _failure;
  Future<void> _continue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final failure = await AuthService.instance.signIn(signUp: _signUp);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
      if (failure?.switchTo != null) _signUp = failure!.switchTo == 'signup';
    });
  }

  Future<void> _help() async {
    final base = Uri.tryParse(AppConfig.whatsappUrl);
    if (base == null) return;
    final uri = base.replace(
      queryParameters: {
        ...base.queryParameters,
        'text': 'Hello Admin, I need help with Deeprowss login or sign up.',
      },
    );
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp. Please try again.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Ui.bg,
    body: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/themes/cr7.png',
          fit: BoxFit.cover,
          color: Colors.black.withValues(alpha: .6),
          colorBlendMode: BlendMode.darken,
          errorBuilder: (_, _, _) => ColoredBox(color: Ui.bg),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Ui.bg.withValues(alpha: .25),
                Ui.bg.withValues(alpha: .8),
                Ui.bg,
              ],
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - 52),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        Image.asset(
                          'assets/splash/splash.png',
                          height: 100,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'DEEPROWSS',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          'Let’s Go Deep!',
                          style: TextStyle(color: Ui.muted, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Ui.card.withValues(alpha: .85),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Ui.line),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Ui.bg,
                                  borderRadius: BorderRadius.circular(32),
                                ),
                                child: Row(
                                  children: [
                                    _tab('Log in', false),
                                    _tab('Sign up', true),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 26),
                              Text(
                                _signUp
                                    ? 'Create your account'
                                    : 'Welcome back',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _signUp
                                    ? 'Join with Gmail to watch, predict and connect with other fans.'
                                    : 'Log in with Gmail to return to your Deeprowss profile.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Ui.muted,
                                  fontSize: 15,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF202124),
                                  ),
                                  onPressed: _busy ? null : _continue,
                                  icon: _busy
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.account_circle_outlined,
                                          color: Color(0xFF4285F4),
                                        ),
                                  label: Text(
                                    _busy
                                        ? 'Please wait…'
                                        : 'Continue with Gmail',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                              if (_failure != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Text(
                                    _failure!.message,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 14),
                              const Text(
                                'Gmail accounts only. No password needed.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12),
                              ),
                              TextButton.icon(
                                onPressed: _busy ? null : _help,
                                icon: const Icon(Icons.chat_outlined, size: 18),
                                label: const Text('Message Admin'),
                              ),
                              Text(
                                'Your Fan Zone name is public. Your Gmail stays private. Choose a nickname inside Fan Zone.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Ui.muted,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _tab(String label, bool signUp) => Expanded(
    child: TextButton(
      style: TextButton.styleFrom(
        backgroundColor: _signUp == signUp ? Ui.red : Colors.transparent,
        foregroundColor: _signUp == signUp ? Ui.palette.onAccent : Ui.muted,
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
      onPressed: _busy
          ? null
          : () => setState(() {
              _signUp = signUp;
              _failure = null;
            }),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    ),
  );
}
