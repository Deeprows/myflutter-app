import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const _gold = Color(0xFFFFC857);
const _goldDeep = Color(0xFFE59E1B);

/// Card shown once, right after a new fan finishes setting up their profile,
/// inviting them into the weekly prediction game. Resolves to true when they
/// tap "Join the Prediction Game".
Future<bool?> showPredictionPromo(BuildContext context) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Prediction game',
    barrierColor: Colors.black.withValues(alpha: .72),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (ctx, _, _) => const Center(child: _PredictionPromoCard()),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: curved, child: child),
      );
    },
  );
}

class _PredictionPromoCard extends StatelessWidget {
  const _PredictionPromoCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: Ui.panel,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _gold.withValues(alpha: .45), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: _gold.withValues(alpha: .22),
              blurRadius: 40,
              spreadRadius: 1,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                child: Column(
                  children: [
                    Text(
                      'Rank Top 3. Win Premium.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Ui.text,
                        fontSize: 22,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Predict match results, climb the weekly leaderboard '
                      'and the top three fans get Premium access, free.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Ui.muted,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _podium(),
                    const SizedBox(height: 18),
                    _step(Icons.sports_soccer_rounded, 'Pick your match winners'),
                    _step(Icons.trending_up_rounded, 'Earn points for every correct call'),
                    _step(
                      Icons.workspace_premium_rounded,
                      'Finish Top 3: 7 days of Premium + blue tick',
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_gold, _goldDeep],
                          ),
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: _gold.withValues(alpha: .35),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF2A1B00),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Icon(Icons.emoji_events_rounded),
                          label: const Text(
                            'Join the Prediction Game',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        'Maybe later',
                        style: TextStyle(
                          color: Ui.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _gold.withValues(alpha: .38),
            _goldDeep.withValues(alpha: .10),
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: -30,
            left: -20,
            child: _glow(110, .16),
          ),
          Positioned(
            bottom: -40,
            right: -10,
            child: _glow(130, .12),
          ),
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFE08A), _goldDeep],
              ),
              boxShadow: [
                BoxShadow(
                  color: _gold.withValues(alpha: .55),
                  blurRadius: 30,
                ),
              ],
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              size: 52,
              color: Color(0xFF3A2600),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              onPressed: () => Navigator.pop(context, false),
              icon: Icon(Icons.close_rounded, color: Ui.text),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: .25),
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'WEEKLY PRIZE',
                style: TextStyle(
                  color: _gold,
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, double alpha) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: alpha),
    ),
  );

  Widget _podium() {
    Widget spot(String rank, String label, Color c, double h) => Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(Icons.workspace_premium_rounded, color: c, size: 26),
          const SizedBox(height: 4),
          Container(
            height: h,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [c.withValues(alpha: .38), c.withValues(alpha: .10)],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: Border.all(color: c.withValues(alpha: .5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  rank,
                  style: TextStyle(
                    color: Ui.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: Ui.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        spot('2', 'PREMIUM', const Color(0xFFB8C2CC), 62),
        const SizedBox(width: 8),
        spot('1', 'PREMIUM', _gold, 82),
        const SizedBox(width: 8),
        spot('3', 'PREMIUM', const Color(0xFFD08A4E), 50),
      ],
    );
  }

  Widget _step(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: _gold),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Ui.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
