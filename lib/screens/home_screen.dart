import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'games_screen.dart';

import '../services/login_gate.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import 'cast_screen.dart';
import 'shell_screen.dart';

/// First in-app page shown after the launch splash and authentication restore.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime? _lastBack;

  void _handleBack() {
    final now = DateTime.now();
    if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Tap back again to exit app'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _openSection(BuildContext context, {required bool thread}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ShellScreen(
          threadOnly: thread,
          liveOnly: !thread,
          initialTab: thread ? 3 : 0,
          restoreLastTab: false,
          onHome: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _openDecoder(BuildContext context) async {
    if (!await ensureSignedIn(context) || !context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const CastScreen()),
    );
  }

  void _openGames(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const GamesScreen()),
    );
  }

  /// Fades and slides a child up, one after another (index * 90ms delay).
  Widget _reveal(int index, Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + index * 90),
      curve: Curves.easeOutCubic,
      builder: (context, t, c) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 22 * (1 - t)), child: c),
      ),
      child: child,
    );
  }

  Widget _featureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool featured = false,
  }) {
    final onAccent = Ui.palette.onAccent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            if (featured)
              BoxShadow(
                color: Ui.red.withValues(alpha: Ui.isLight ? .18 : .22),
                blurRadius: 28,
                offset: const Offset(0, 10),
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: Ui.isLight ? .06 : .25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              padding: EdgeInsets.fromLTRB(14, featured ? 14 : 11, 12, featured ? 14 : 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: featured ? Ui.red.withValues(alpha: .6) : Ui.line,
                  width: featured ? 1.2 : 1,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: featured
                      ? [
                          Color.alphaBlend(Ui.red.withValues(alpha: .30), Ui.card),
                          Color.alphaBlend(Ui.red.withValues(alpha: .06), Ui.panel),
                        ]
                      : [
                          Ui.card.withValues(alpha: .96),
                          Ui.panel.withValues(alpha: .92),
                        ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: featured ? 50 : 44,
                    height: featured ? 50 : 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: featured
                            ? [Ui.red, Ui.redSoft]
                            : [
                                Ui.red.withValues(alpha: .26),
                                Ui.red.withValues(alpha: .10),
                              ],
                      ),
                      border: Border.all(
                        color: Ui.red.withValues(alpha: featured ? 0 : .30),
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: featured ? onAccent : Ui.red,
                      size: featured ? 26 : 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (featured) ...[
                          const _LiveBadge(),
                          const SizedBox(height: 5),
                        ],
                        Text(
                          title,
                          style: TextStyle(
                            color: Ui.text,
                            fontSize: 14,
                            letterSpacing: .7,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Ui.muted,
                            fontSize: 11.5,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: featured
                          ? Ui.red.withValues(alpha: .20)
                          : Ui.text.withValues(alpha: .07),
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: featured ? Ui.red : Ui.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
      backgroundColor: Ui.bg,
      drawer: const FootboliveDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        toolbarHeight: 56,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Full-page rotating wallpaper with a dark readability overlay.
          const Positioned.fill(child: _HomeBackdrop()),
          // Logo sits lower, in the middle of the header area.
          SafeArea(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Image.asset(
                    'assets/icon/logo_header.png',
                    height: 68,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    semanticLabel: 'Deeprowss',
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 100, 20, 30),
              children: [
                _reveal(
                  0,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome 🤗',
                        style: TextStyle(
                          color: Ui.text,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your entertainment. Your Community.',
                        style: TextStyle(
                          color: Ui.muted,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                _reveal(
                  1,
                  _featureCard(
                    icon: Icons.sensors_rounded,
                    title: 'LIVE EVENTS',
                    subtitle: 'Follow live matches, fixtures and football action.',
                    featured: true,
                    onTap: () => _openSection(context, thread: false),
                  ),
                ),
                _reveal(
                  2,
                  _featureCard(
                    icon: Icons.forum_rounded,
                    title: 'DEEPROWSS THREAD',
                    subtitle: 'Join the conversation, AI predictions and Match Room.',
                    onTap: () => _openSection(context, thread: true),
                  ),
                ),
                _reveal(
                  3,
                  _featureCard(
                    icon: Icons.cast_connected_rounded,
                    title: 'SMART DECODER',
                    subtitle: 'Connect your TV, Kodi or browser receiver.',
                    onTap: () => _openDecoder(context),
                  ),
                ),
                _reveal(
                  4,
                  _featureCard(
                    icon: Icons.sports_esports_rounded,
                    title: 'GAMES',
                    subtitle: 'Play football, racing and arcade games.',
                    onTap: () => _openGames(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}


/// Small "LIVE" pill with a softly pulsing dot.
class _LiveBadge extends StatefulWidget {
  const _LiveBadge();

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Ui.red.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Ui.red.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: .35, end: 1).animate(_pulse),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: Ui.red, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE NOW',
            style: TextStyle(
              color: Ui.red,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Home background: a tinted gradient, two slowly breathing accent glows, faint
/// football-pitch line art and a soft vignette. Follows the active theme
/// colours (dark and light) and sits under the watermark and all content.
class _HomeBackdrop extends StatefulWidget {
  const _HomeBackdrop();

  @override
  State<_HomeBackdrop> createState() => _HomeBackdropState();
}

class _HomeBackdropState extends State<_HomeBackdrop> {
  static const _wallpapers = <String>[
    'https://image.tmdb.org/t/p/w1280/1pdfLvkbY9ohJlCjQH2CZjjYVvJ9.jpg',
    'https://pbs.twimg.com/media/GUnmAvTW0AAbh35.jpg',
    'https://images.mlssoccer.com/image/private/t_keep-aspect-ratio-e-mobile/f_auto/mls-mia/dsze8wsazzinknx5f5wf.jpg',
    'https://image.tmdb.org/t/p/w1280/8Vt6mWEReuy4Of61Lnj5Xj704m8.jpg',
    'https://image.tmdb.org/t/p/w1280/ptpr0kGAckfQkJeJIt8st5dglvd.jpg',
  ];
  Timer? _rotation;
  int _wallpaperIndex = 0;

  @override
  void initState() {
    super.initState();
    _rotation = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted) return;
      setState(() => _wallpaperIndex = (_wallpaperIndex + 1) % _wallpapers.length);
    });
  }

  @override
  void dispose() {
    _rotation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final light = Ui.isLight;
    final tint = Color.lerp(Ui.bg, Ui.red, light ? .10 : .16)!;
    final deep = Color.lerp(Ui.bg, Colors.black, light ? .04 : .35)!;
    return RepaintBoundary(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 1100),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              child: Image.network(
                _wallpapers[_wallpaperIndex],
                key: ValueKey(_wallpaperIndex),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => ColoredBox(color: Ui.bg),
              ),
            ),
            // Dark brand tint keeps the page content readable over every image.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    tint.withValues(alpha: .82),
                    Ui.bg.withValues(alpha: .88),
                    deep.withValues(alpha: .97),
                  ],
                  stops: const [0, .48, 1],
                ),
              ),
            ),
            CustomPaint(
              painter: _PitchPainter(
                Ui.text.withValues(alpha: light ? .07 : .05),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Very faint football-pitch markings (centre circle, halfway line and the
/// penalty areas rising from the bottom edge).
class _PitchPainter extends CustomPainter {
  final Color color;
  const _PitchPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h * .72;
    canvas.drawCircle(Offset(cx, cy), w * .36, line);
    canvas.drawLine(Offset(0, cy), Offset(w, cy), line);
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = color);
    // Penalty area and six-yard box at the bottom edge.
    canvas.drawRect(Rect.fromLTWH(cx - w * .34, h - w * .30, w * .68, w * .31), line);
    canvas.drawRect(Rect.fromLTWH(cx - w * .16, h - w * .12, w * .32, w * .13), line);
    // Penalty area at the top edge.
    canvas.drawRect(Rect.fromLTWH(cx - w * .34, -2, w * .68, w * .30), line);
  }

  @override
  bool shouldRepaint(_PitchPainter old) => old.color != color;
}
