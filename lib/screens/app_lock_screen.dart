import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../player/audio_handler.dart';
import '../player/music_player.dart';
import '../services/app_lock.dart';
import '../theme/app_theme.dart';
import '../theme/theme_watermark.dart';
import '../utils/l10n.dart';
import '../widgets/tr_text.dart';

// ======================================================================
// Overlay: covers the whole app while the lock is active
// ======================================================================

/// Put around the app content (inside MaterialApp.builder). While
/// [AppLock.locked] is true, a full-screen PIN page sits on top of
/// everything, including dialogs and other pages.
class AppLockOverlay extends StatelessWidget {
  final Widget child;
  const AppLockOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLock.instance.locked,
      builder: (_, locked, _) => Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: locked,
            child: ExcludeSemantics(excluding: locked, child: child),
          ),
          if (locked) const Positioned.fill(child: _LockScreen()),
          if (locked) const _LockBannerHost(),
        ],
      ),
    );
  }
}

/// Theme for the lock screen, built from its own palette (the app's theme
/// can be different).
ThemeData lockThemeData(Palette p) {
  final scheme = p.isLight
      ? ColorScheme.light(
          primary: p.accent,
          onPrimary: p.onAccent,
          secondary: p.accentSoft,
          surface: p.panel,
          onSurface: p.text,
        )
      : ColorScheme.dark(
          primary: p.accent,
          onPrimary: p.onAccent,
          secondary: p.accentSoft,
          surface: p.panel,
          onSurface: Colors.white,
        );
  return ThemeData(
    useMaterial3: true,
    brightness: p.isLight ? Brightness.light : Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    dividerColor: p.line,
  );
}

class _LockScreen extends StatelessWidget {
  const _LockScreen();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppLock.instance.themeIndex,
      builder: (_, _, _) {
        final p = AppLock.instance.palette;
        final icons = p.isLight ? Brightness.dark : Brightness.light;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: icons,
            statusBarBrightness: p.isLight ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: p.bg,
            systemNavigationBarIconBrightness: icons,
          ),
          child: Theme(
            data: lockThemeData(p),
            // The overlay sits above the Navigator, so it brings its own
            // Overlay (text fields and tooltips need one).
            child: Material(
              color: p.bg,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Theme decoration (CR7 name, picture, stripes), stronger
                  // than inside the app because nothing else is on screen.
                  ThemeWatermark(palette: p, strength: 4, ignoreHolds: true),
                  Overlay(
                    initialEntries: [
                      OverlayEntry(builder: (_) => const _LockBody()),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Notification card at the top of the lock screen.
class _LockBannerHost extends StatelessWidget {
  const _LockBannerHost();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LockBanner?>(
      valueListenable: AppLock.instance.banner,
      builder: (_, b, _) {
        if (b == null) return const SizedBox.shrink();
        final p = AppLock.instance.palette;
        return Positioned(
          left: 12,
          right: 12,
          top: MediaQuery.paddingOf(context).top + 8,
          child: Material(
            color: p.panel,
            elevation: 8,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              // Tapping only dismisses it: the app stays locked.
              onTap: AppLock.instance.dismissBanner,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.line),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notifications_rounded, color: p.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DefaultTextStyle(
                        style: TextStyle(color: p.text, fontSize: 13.5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (b.title.isNotEmpty)
                              Text(b.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900)),
                            if (b.body.isNotEmpty)
                              Text(b.body,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LockBody extends StatefulWidget {
  const _LockBody();
  @override
  State<_LockBody> createState() => _LockBodyState();
}

class _LockBodyState extends State<_LockBody> {
  Palette get _p => AppLock.instance.palette;
  bool _forgot = false;
  final _answer = TextEditingController();
  String? _forgotError;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    _answer.dispose();
    super.dispose();
  }

  Future<void> _recover() async {
    final lock = AppLock.instance;
    if (lock.lockoutSeconds > 0) {
      _startTick();
      return;
    }
    final ok = await lock.recoverWithAnswer(_answer.text);
    if (!mounted) return;
    if (ok) {
      lock.locked.value = false;
      return;
    }
    setState(() => _forgotError = lock.lockoutSeconds > 0
        ? 'Too many attempts. Try again in {s}s'
            .trArgs({'s': lock.lockoutSeconds})
        : 'Wrong answer'.tr);
    _startTick();
  }

  void _startTick() {
    _tick?.cancel();
    if (AppLock.instance.lockoutSeconds <= 0) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {});
      if (AppLock.instance.lockoutSeconds <= 0) t.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = AppLock.instance;
    return SafeArea(
      child: Column(
        children: [
          Expanded(child: _forgot ? _forgotView(lock) : _pinView()),
          const _LockMiniPlayer(),
        ],
      ),
    );
  }

  Widget _pinView() => PinEntryView(
        key: const ValueKey('unlock'),
        title: 'Enter PIN'.tr,
        subtitle: 'This app is locked'.tr,
        icon: Icons.lock_rounded,
        palette: AppLock.instance.palette,
        respectLockout: true,
        onSubmit: (pin) async {
          final lock = AppLock.instance;
          final ok = await lock.unlockWithPin(pin);
          if (ok) return null;
          return lock.lockoutSeconds > 0
              ? 'Too many attempts. Try again in {s}s'
                  .trArgs({'s': lock.lockoutSeconds})
              : 'Wrong PIN'.tr;
        },
        footer: AppLock.instance.question.isEmpty
            ? null
            : TextButton(
                onPressed: () => setState(() => _forgot = true),
                child: Text('Forgot PIN?'.tr),
              ),
      );

  Widget _forgotView(AppLock lock) {
    final wait = lock.lockoutSeconds;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.help_outline_rounded, size: 48, color: _p.accent),
          const SizedBox(height: 14),
          Text('Forgot PIN?'.tr,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            'Answer your recovery question. The lock will be turned off and '
                    'you can set a new PIN in Settings.'
                .tr,
            textAlign: TextAlign.center,
            style: TextStyle(color: _p.muted, fontSize: 13),
          ),
          const SizedBox(height: 22),
          Text(lock.question,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: _answer,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _recover(),
            decoration: InputDecoration(
              hintText: 'Your answer'.tr,
              filled: true,
              fillColor: _p.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _p.line),
              ),
            ),
          ),
          if (_forgotError != null || wait > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                wait > 0
                    ? 'Too many attempts. Try again in {s}s'
                        .trArgs({'s': wait})
                    : _forgotError!,
                style: TextStyle(color: _p.accent, fontWeight: FontWeight.w700),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _p.accent,
              foregroundColor: _p.onAccent,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: wait > 0 ? null : _recover,
            child: Text('Confirm'.tr),
          ),
          TextButton(
            onPressed: () => setState(() {
              _forgot = false;
              _forgotError = null;
              _answer.clear();
            }),
            child: Text('Back'.tr),
          ),
        ],
      ),
    );
  }
}

/// Music from the Player keeps playing behind the lock, with its
/// notification. This card lets the person pause / resume or skip without
/// unlocking. Videos are never controlled from here.
class _LockMiniPlayer extends StatelessWidget {
  const _LockMiniPlayer();

  @override
  Widget build(BuildContext context) {
    final mp = MusicPlayer.instance;
    return ListenableBuilder(
      listenable: mp,
      builder: (_, _) {
        final h = AudioBridge.current;
        final entry = mp.current;
        if (entry == null || (h?.videoMode ?? false)) {
          return const SizedBox.shrink();
        }
        final p = AppLock.instance.palette;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.line),
          ),
          child: Row(
            children: [
              Icon(Icons.music_note_rounded, color: p.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    Text(mp.playing ? 'Playing'.tr : 'Paused'.tr,
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                onPressed: mp.previous,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              IconButton(
                onPressed: mp.loading ? null : mp.toggle,
                iconSize: 34,
                color: p.accent,
                icon: Icon(mp.playing
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded),
              ),
              IconButton(
                onPressed: mp.next,
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ======================================================================
// PIN entry (dots + number pad), reused by lock / setup / verify
// ======================================================================

class PinEntryView extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData icon;

  /// Called with the 4 digits. Return an error message, or null when the PIN
  /// was accepted.
  final Future<String?> Function(String pin) onSubmit;

  /// Disable the pad while [AppLock.lockoutSeconds] is above zero.
  final bool respectLockout;
  final Widget? footer;

  /// Colours to use (null = the app's current theme).
  final Palette? palette;

  const PinEntryView({
    super.key,
    required this.title,
    required this.onSubmit,
    this.subtitle,
    this.icon = Icons.lock_outline_rounded,
    this.respectLockout = false,
    this.footer,
    this.palette,
  });

  @override
  State<PinEntryView> createState() => _PinEntryViewState();
}

class _PinEntryViewState extends State<PinEntryView> {
  static const _len = 4;
  Palette get _p => widget.palette ?? Ui.palette;
  String _pin = '';
  String? _error;
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _startTick();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  int get _wait => widget.respectLockout ? AppLock.instance.lockoutSeconds : 0;

  void _startTick() {
    _tick?.cancel();
    if (_wait <= 0) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        if (_wait <= 0) {
          _error = null;
          t.cancel();
        } else {
          _error = 'Too many attempts. Try again in {s}s'.trArgs({'s': _wait});
        }
      });
    });
  }

  Future<void> _digit(String d) async {
    if (_busy || _wait > 0 || _pin.length >= _len) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length < _len) return;
    _busy = true;
    final err = await widget.onSubmit(_pin);
    _busy = false;
    if (!mounted || err == null) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _pin = '';
      _error = err;
    });
    _startTick();
  }

  void _back() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _wait > 0;
    // Scrolls on small screens (the mini player takes some height).
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(child: _pinColumn(disabled)),
        ),
      ),
    );
  }

  Widget _pinColumn(bool disabled) {
    return Column(
      children: [
        const Spacer(flex: 2),
        Icon(widget.icon, size: 44, color: _p.accent),
        const SizedBox(height: 12),
        Text(widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(widget.subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: _p.muted, fontSize: 13)),
          ),
        ],
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _len; i++)
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? _p.accent : Colors.transparent,
                  border: Border.all(
                    color: _error != null ? _p.accent : _p.muted,
                    width: 1.6,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(
          height: 34,
          child: Center(
            child: _error == null
                ? null
                : Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _p.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
          ),
        ),
        const Spacer(),
        Opacity(
          opacity: disabled ? 0.4 : 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                _padRow([for (final d in row) _key(d)]),
              _padRow([
                const SizedBox(width: 72, height: 72),
                _key('0'),
                _iconKey(Icons.backspace_outlined, _back),
              ]),
            ],
          ),
        ),
        SizedBox(height: 44, child: Center(child: widget.footer)),
        const Spacer(),
      ],
    );
  }

  Widget _padRow(List<Widget> children) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final c in children)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: c,
              ),
          ],
        ),
      );

  Widget _key(String d) => _round(
        onTap: () => _digit(d),
        child: Text(d,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
      );

  Widget _iconKey(IconData icon, VoidCallback onTap) => _round(
        onTap: onTap,
        filled: false,
        child: Icon(icon, size: 24, color: _p.muted),
      );

  Widget _round({
    required VoidCallback onTap,
    required Widget child,
    bool filled = true,
  }) =>
      SizedBox(
        width: 72,
        height: 72,
        child: Material(
          color: filled ? _p.card : Colors.transparent,
          shape: const CircleBorder(),
          child: InkResponse(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(child: child),
          ),
        ),
      );
}

// ======================================================================
// Setup (new PIN) and verify (current PIN) pages, opened from Settings
// ======================================================================

const _questions = <String>[
  'What is your favourite food?',
  'What was the name of your first school?',
  'What is your mother\'s first name?',
  'What is the name of your first pet?',
  'In which town were you born?',
];

/// Choose a PIN, confirm it, then (first time only) pick a recovery
/// question. Pops `true` when saved.
class AppLockSetupScreen extends StatefulWidget {
  /// True when the lock is already on and only the PIN changes.
  final bool changeOnly;
  const AppLockSetupScreen({super.key, this.changeOnly = false});

  @override
  State<AppLockSetupScreen> createState() => _AppLockSetupScreenState();
}

class _AppLockSetupScreenState extends State<AppLockSetupScreen> {
  int _step = 0; // 0 choose, 1 confirm, 2 recovery
  String _first = '';
  String? _notice;
  String _question = _questions.first;
  final _answer = TextEditingController();
  String? _answerError;
  bool _saving = false;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_answer.text.trim().length < 2) {
      setState(() => _answerError = 'Enter an answer you will remember'.tr);
      return;
    }
    setState(() => _saving = true);
    await AppLock.instance
        .enable(pin: _first, question: _question, answer: _answer.text);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(
        backgroundColor: Ui.bg,
        title: Text(widget.changeOnly ? 'Change PIN'.tr : 'Set up App Lock'.tr),
      ),
      body: SafeArea(child: _stepView()),
    );
  }

  Widget _stepView() {
    if (_step == 0) {
      return PinEntryView(
        key: const ValueKey('choose'),
        title: 'Choose a 4-digit PIN'.tr,
        subtitle: _notice ??
            'Children will not be able to open the app without it'.tr,
        onSubmit: (pin) async {
          _first = pin;
          if (mounted) {
            setState(() {
              _notice = null;
              _step = 1;
            });
          }
          return null;
        },
      );
    }
    if (_step == 1) {
      return PinEntryView(
        key: const ValueKey('confirm'),
        title: 'Confirm your PIN'.tr,
        subtitle: 'Enter the same PIN again'.tr,
        onSubmit: (pin) async {
          if (pin != _first) {
            // Start over so a typo is not saved.
            if (mounted) {
              setState(() {
                _notice = 'PINs did not match. Try again.'.tr;
                _step = 0;
              });
            }
            return null;
          }
          if (widget.changeOnly) {
            await AppLock.instance.changePin(pin);
            if (mounted) Navigator.of(context).pop(true);
          } else if (mounted) {
            setState(() => _step = 2);
          }
          return null;
        },
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.help_outline_rounded, size: 44, color: Ui.red),
          const SizedBox(height: 12),
          Text('Recovery question'.tr,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            'If you forget the PIN, answering this turns the lock off. Pick '
                    'something children cannot guess.'
                .tr,
            textAlign: TextAlign.center,
            style: TextStyle(color: Ui.muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _question,
            isExpanded: true,
            dropdownColor: Ui.panel,
            decoration: InputDecoration(
              filled: true,
              fillColor: Ui.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Ui.line),
              ),
            ),
            items: [
              for (final q in _questions)
                DropdownMenuItem(value: q, child: Text(q.tr)),
            ],
            onChanged: (v) => setState(() => _question = v ?? _question),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _answer,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              hintText: 'Your answer'.tr,
              errorText: _answerError,
              filled: true,
              fillColor: Ui.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Ui.line),
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Ui.red,
              foregroundColor: Ui.palette.onAccent,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _saving ? null : _save,
            child: Text('Turn on App Lock'.tr),
          ),
        ],
      ),
    );
  }
}

/// Asks for the current PIN. Pops `true` when it is right.
class AppLockVerifyScreen extends StatelessWidget {
  final String title;
  const AppLockVerifyScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(backgroundColor: Ui.bg, title: Text(title)),
      body: SafeArea(
        child: PinEntryView(
          title: 'Enter current PIN'.tr,
          respectLockout: true,
          onSubmit: (pin) async {
            final lock = AppLock.instance;
            if (await lock.check(pin)) {
              if (context.mounted) Navigator.of(context).pop(true);
              return null;
            }
            return lock.lockoutSeconds > 0
                ? 'Too many attempts. Try again in {s}s'
                    .trArgs({'s': lock.lockoutSeconds})
                : 'Wrong PIN'.tr;
          },
        ),
      ),
    );
  }
}

// ======================================================================
// Settings page
// ======================================================================

/// Opened from "Settings and support" > "App Lock".
Future<void> showAppLockSettings(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AppLockSettingsScreen()),
    );

class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key});
  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  final _lock = AppLock.instance;

  Future<void> _toggle(bool on) async {
    final nav = Navigator.of(context);
    if (on) {
      await nav.push<bool>(
        MaterialPageRoute(builder: (_) => const AppLockSetupScreen()),
      );
    } else {
      final ok = await nav.push<bool>(
        MaterialPageRoute(
          builder: (_) => AppLockVerifyScreen(title: 'Turn off App Lock'.tr),
        ),
      );
      if (ok == true) await _lock.disable();
    }
    if (mounted) setState(() {});
  }

  Future<void> _changePin() async {
    final nav = Navigator.of(context);
    final ok = await nav.push<bool>(
      MaterialPageRoute(
        builder: (_) => AppLockVerifyScreen(title: 'Change PIN'.tr),
      ),
    );
    if (ok != true) return;
    await nav.push<bool>(
      MaterialPageRoute(
        builder: (_) => const AppLockSetupScreen(changeOnly: true),
      ),
    );
    if (mounted) setState(() {});
  }

  String _timeoutLabel(int s) => switch (s) {
        0 => 'Immediately'.tr,
        30 => '30 seconds'.tr,
        60 => '1 minute'.tr,
        _ => '5 minutes'.tr,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(backgroundColor: Ui.bg, title: Text('App Lock'.tr)),
      body: ValueListenableBuilder<bool>(
        valueListenable: _lock.enabled,
        builder: (_, on, _) => ListView(
          // Keep the last item (Lock now) clear of the phone's navigation bar.
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Ui.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Ui.line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.child_care_rounded, color: Ui.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Lock the app with a 4-digit PIN so children cannot '
                              'open it. The PIN is asked when the app starts '
                              'and when you return to it.'
                          .tr,
                      style: TextStyle(color: Ui.muted, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.lock_outline_rounded, color: Ui.red),
              title: Text('App Lock'.tr,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w800)),
              subtitle: Text(on ? 'On'.tr : 'Off'.tr,
                  style: TextStyle(color: Ui.muted, fontSize: 12)),
              value: on,
              onChanged: _toggle,
            ),
            if (on) ...[
              Divider(color: Ui.line),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.password_rounded),
                title: Text('Change PIN'.tr,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _changePin,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_clock_rounded),
                title: Text('Lock again after'.tr,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final s in AppLock.timeoutChoices)
                        ChoiceChip(
                          label: Text(_timeoutLabel(s)),
                          selected: _lock.timeoutSeconds == s,
                          onSelected: (_) async {
                            await _lock.setTimeout(s);
                            if (mounted) setState(() {});
                          },
                        ),
                    ],
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.palette_outlined),
                title: Text('Lock screen theme'.tr,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ValueListenableBuilder<int>(
                    valueListenable: _lock.themeIndex,
                    builder: (_, sel, _) => Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (var i = 0; i < Palettes.all.length; i++)
                          ChoiceChip(
                            avatar: CircleAvatar(
                              radius: 8,
                              backgroundColor: Palettes.all[i].accent,
                            ),
                            label: Text(Palettes.all[i].name),
                            selected: sel == i,
                            onSelected: (_) => _lock.setTheme(i),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _lock.lockNow,
                icon: const Icon(Icons.lock_rounded),
                label: Text('Lock now'.tr),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
