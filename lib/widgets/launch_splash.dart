import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kodi-style launch splash: the Deeprowss logo flips/spins inside a glowing
/// ring while a short launch sound plays. Same look and sound as the Windows
/// EXE, Android TV, LG / Samsung TV and web receiver (assets/receiver/index.html).
///
/// Wrap the whole app with it. It shows once per cold start, then fades out.
/// Sound can be muted by saving the string 'off' under [kSplashSoundKey].
class LaunchSplash extends StatefulWidget {
  const LaunchSplash({super.key, required this.child});

  final Widget child;

  static const kSplashSoundKey = 'dr_splash_sound';

  /// Shown only the first time per process (not again on hot restarts of the
  /// widget tree, theme / language changes, etc.).
  static bool _shown = false;

  @override
  State<LaunchSplash> createState() => _LaunchSplashState();
}

class _LaunchSplashState extends State<LaunchSplash>
    with TickerProviderStateMixin {
  static const _minShow = Duration(milliseconds: 2600);
  static const _fadeOut = Duration(milliseconds: 600);

  late final AnimationController _flip; // logo rotateY, 2.4s loop
  late final AnimationController _ring; // spinning ring, 1.7s loop
  late final AnimationController _pulse; // glow, 2.4s ping-pong
  late final AnimationController _bar; // progress bar, 1.3s loop
  late final AnimationController _fade; // splash -> app

  bool _visible = !LaunchSplash._shown;
  AudioPlayer? _player;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _ring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _bar = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    _fade = AnimationController(vsync: this, duration: _fadeOut, value: 1);

    if (_visible) {
      LaunchSplash._shown = true;
      _flip.repeat();
      _ring.repeat();
      _pulse.repeat(reverse: true);
      _bar.repeat();
      unawaited(_playSting());
      Timer(_minShow, _finish);
    }
  }

  Future<void> _playSting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(LaunchSplash.kSplashSoundKey) == 'off') return;
    } catch (_) {}
    try {
      final p = AudioPlayer();
      _player = p;
      await p.setAsset('assets/sounds/launch_sting.wav');
      await p.setVolume(1.0);
      if (!mounted || !_visible) {
        await p.dispose();
        return;
      }
      unawaited(p.play());
    } catch (_) {
      // Sound is a nicety: never block or crash start-up because of it.
    }
  }

  Future<void> _finish() async {
    if (!mounted || !_visible) return;
    // Fade the sound out together with the picture (like the web version).
    final p = _player;
    if (p != null) {
      unawaited(_fadeSound(p));
    }
    await _fade.reverse();
    if (!mounted) return;
    _flip.stop();
    _ring.stop();
    _pulse.stop();
    _bar.stop();
    setState(() => _visible = false);
  }

  Future<void> _fadeSound(AudioPlayer p) async {
    try {
      for (var i = 9; i >= 0; i--) {
        await p.setVolume(i / 10);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await p.stop();
    } catch (_) {}
    try {
      await p.dispose();
    } catch (_) {}
    if (identical(_player, p)) _player = null;
  }

  @override
  void dispose() {
    _flip.dispose();
    _ring.dispose();
    _pulse.dispose();
    _bar.dispose();
    _fade.dispose();
    try {
      _player?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always a Stack with the app at slot 0, so removing the splash never
    // rebuilds the Navigator (and loses the app's state) underneath it.
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // Absorbs taps while the splash is up (the web version blocks input too).
        if (_visible)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _fade,
              builder: (_, child) => IgnorePointer(
                ignoring: _fade.status == AnimationStatus.reverse,
                child: Opacity(opacity: _fade.value, child: child),
              ),
              child: _buildSplash(context),
            ),
          ),
      ],
    );
  }

  Widget _buildSplash(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final logo = math.min(size.width * .46, 210.0);
    final nameSize = (size.width * .05).clamp(17.0, 26.0).toDouble();
    final subSize = (size.width * .028).clamp(9.0, 13.0).toDouble();

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        type: MaterialType.canvas,
        color: Colors.transparent,
        child: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -.16),
              radius: .85,
              colors: [Color(0xFF2B0B16), Color(0xFF0A0C12), Color(0xFF05070B)],
              stops: [0, .62, 1],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: logo,
                height: logo,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Pulsing glow
                    Positioned(
                      left: -logo * .22,
                      top: -logo * .22,
                      right: -logo * .22,
                      bottom: -logo * .22,
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, _) {
                          final t = Curves.easeInOut.transform(_pulse.value);
                          return Opacity(
                            opacity: .55 + .45 * t,
                            child: Transform.scale(
                              scale: .94 + .12 * t,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [Color(0x60FF2D55), Color(0x00FF2D55)],
                                    stops: [0, .66],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Spinning ring
                    Positioned(
                      left: -logo * .06,
                      top: -logo * .06,
                      right: -logo * .06,
                      bottom: -logo * .06,
                      child: RotationTransition(
                        turns: _ring,
                        child: const CustomPaint(painter: _RingPainter()),
                      ),
                    ),
                    // Flipping logo
                    AnimatedBuilder(
                      animation: _flip,
                      builder: (_, child) {
                        // rotateY(0 -> 360deg) over the first 72% of the loop,
                        // then holds, easing like cubic-bezier(.45,.05,.25,1).
                        final p = (_flip.value / .72).clamp(0.0, 1.0);
                        final eased = const Cubic(.45, .05, .25, 1).transform(p);
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 1 / 900)
                            ..rotateY(eased * 2 * math.pi),
                          child: child,
                        );
                      },
                      child: Container(
                        width: logo,
                        height: logo,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Color(0x55FF2D55), blurRadius: 44),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/splash/splash.png',
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: logo * .24),
              Text(
                'DEEPROWSS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: nameSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: nameSize * .34,
                  decoration: TextDecoration.none,
                ),
              ),
              SizedBox(height: subSize * .7),
              Text(
                'CINEMA & LIVE TV',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF6FD6FB),
                  fontSize: subSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: subSize * .32,
                  decoration: TextDecoration.none,
                ),
              ),
              SizedBox(height: logo * .16),
              // Loading bar
              SizedBox(
                width: math.min(size.width * .5, 220.0),
                height: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: ColoredBox(
                    color: const Color(0x1CFFFFFF),
                    child: LayoutBuilder(
                      builder: (_, box) => AnimatedBuilder(
                        animation: _bar,
                        builder: (_, _) {
                          final t = Curves.easeInOut.transform(_bar.value);
                          final w = box.maxWidth * .4;
                          // translateX(-100% -> 250%) of its own width
                          final x = w * (-1 + 3.5 * t);
                          return Stack(
                            children: [
                              Positioned(
                                left: x,
                                top: 0,
                                width: w,
                                height: 3,
                                child: const DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(3)),
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFFFF2D55),
                                        Color(0xFF6FD6FB),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin conic-gradient ring (red tail fading out, blue head), same as the
/// `.drs-ring` element of the web / EXE / TV splash.
class _RingPainter extends CustomPainter {
  const _RingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFF2D55),
          Color(0x00FF2D55),
          Color(0x006FD6FB),
          Color(0x006FD6FB),
          Color(0xFF6FD6FB),
        ],
        stops: [0, .38, .55, .70, 1],
      ).createShader(rect);
    canvas.drawArc(rect.deflate(1.5), 0, 2 * math.pi, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
