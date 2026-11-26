import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
          // Layered brand backdrop: gradient, breathing glows, faint pitch lines.
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
                const SizedBox(height: 20),
                _reveal(1, const _HomeHeroCarousel()),
                const SizedBox(height: 26),
                _reveal(
                  2,
                  _featureCard(
                    icon: Icons.sensors_rounded,
                    title: 'LIVE EVENTS',
                    subtitle: 'Follow live matches, fixtures and football action.',
                    featured: true,
                    onTap: () => _openSection(context, thread: false),
                  ),
                ),
                _reveal(
                  3,
                  _featureCard(
                    icon: Icons.forum_rounded,
                    title: 'DEEPROWSS THREAD',
                    subtitle: 'Join the conversation, AI predictions and Match Room.',
                    onTap: () => _openSection(context, thread: true),
                  ),
                ),
                _reveal(
                  4,
                  _featureCard(
                    icon: Icons.cast_connected_rounded,
                    title: 'SMART DECODER',
                    subtitle: 'Connect your TV, Kodi or browser receiver.',
                    onTap: () => _openDecoder(context),
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


/// Rotating editorial banner for movies and football stars.
class _HomeHeroCarousel extends StatefulWidget {
  const _HomeHeroCarousel();
  @override
  State<_HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}
class _HomeHeroCarouselState extends State<_HomeHeroCarousel> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _page = 0;
  static const _slides = <({String title, String subtitle, String image})>[
    (title: 'NOW SHOWING', subtitle: 'Discover movies worth watching', image: 'https://image.tmdb.org/t/p/w1280/1pdfLvkbY9ohJlCjQH2CZjjYVvJ9.jpg'),
    (title: 'CRISTIANO RONALDO', subtitle: 'Al Nassr • The Yellow and Blue', image: 'https://pbs.twimg.com/media/GUnmAvTW0AAbh35.jpg'),
    (title: 'LIONEL MESSI', subtitle: 'Inter Miami • The Herons', image: 'https://images.mlssoccer.com/image/private/t_keep-aspect-ratio-e-mobile/f_auto/mls-mia/dsze8wsazzinknx5f5wf.jpg'),
    (title: 'MOVIE NIGHT', subtitle: 'Explore the latest movie stories', image: 'https://image.tmdb.org/t/p/w1280/8Vt6mWEReuy4Of61Lnj5Xj704m8.jpg'),
    (title: 'CINEMA PICKS', subtitle: 'Your next favourite film awaits', image: 'https://image.tmdb.org/t/p/w1280/ptpr0kGAckfQkJeJIt8st5dglvd.jpg'),
  ];
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients) return;
      _page = (_page + 1) % _slides.length;
      _controller.animateToPage(_page, duration: const Duration(milliseconds: 650), curve: Curves.easeInOutCubic);
    });
  }
  @override
  void dispose() { _timer?.cancel(); _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 188,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(fit: StackFit.expand, children: [
        PageView.builder(
          controller: _controller,
          itemCount: _slides.length,
          onPageChanged: (value) => setState(() => _page = value),
          itemBuilder: (context, index) {
            final slide = _slides[index];
            return Stack(fit: StackFit.expand, children: [
              Image.network(slide.image, fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => Container(
                  color: Ui.panel, alignment: Alignment.center,
                  child: Icon(Icons.movie_creation_outlined, color: Ui.muted, size: 42))),
              DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.centerRight, end: Alignment.centerLeft,
                colors: [Colors.black.withValues(alpha: .08), Colors.black.withValues(alpha: .82)]))),
              Positioned(left: 18, right: 18, bottom: 20, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(slide.title, style: const TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  Text(slide.subtitle, style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.2, fontWeight: FontWeight.w800)),
                ])),
            ]);
          }),
        Positioned(right: 14, bottom: 12, child: Row(
          children: List.generate(_slides.length, (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 220), margin: const EdgeInsets.only(left: 4),
            width: i == _page ? 18 : 6, height: 6,
            decoration: BoxDecoration(color: i == _page ? Ui.red : Colors.white.withValues(alpha: .65), borderRadius: BorderRadius.circular(8)),
          )),
        )),
      ]),
    ),
  );
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

class _HomeBackdropState extends State<_HomeBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final light = Ui.isLight;
    final accent = Ui.red;
    final tint = Color.lerp(Ui.bg, accent, light ? .10 : .16)!;
    final deep = Color.lerp(Ui.bg, Colors.black, light ? .04 : .35)!;
    return RepaintBoundary(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_c.value);
            return Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [tint, Ui.bg, deep],
                      stops: const [0, .45, 1],
                    ),
                  ),
                ),
                // Main glow, behind the logo.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -1.05 + .12 * t),
                      radius: .95,
                      colors: [
                        accent.withValues(alpha: (light ? .16 : .30) + .05 * t),
                        accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                // Soft side glow low on the right.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(1.1 - .2 * t, .55),
                      radius: .8,
                      colors: [
                        Ui.redSoft.withValues(alpha: light ? .07 : .12),
                        Ui.redSoft.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                CustomPaint(
                  painter: _PitchPainter(
                    Ui.text.withValues(alpha: light ? .07 : .05),
                  ),
                ),
                // Vignette so the lower cards stay calm and readable.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Ui.bg.withValues(alpha: .75),
                      ],
                      stops: const [0, .65, 1],
                    ),
                  ),
                ),
              ],
            );
          },
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
