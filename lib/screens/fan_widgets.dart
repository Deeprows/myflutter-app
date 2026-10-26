import '../models/fan_prediction.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// -----------------------------------------------------------------------------
// Small helpers shared by the Fan Zone screens (predictions, rankings, banter,
// chat). Everything here is presentation only and works with the existing
// backend responses.
// -----------------------------------------------------------------------------

const _avatarColors = [
  Color(0xFFFF5252),
  Color(0xFF448AFF),
  Color(0xFF00C896),
  Color(0xFFFFB300),
  Color(0xFFAB47BC),
  Color(0xFF26C6DA),
  Color(0xFFFF7043),
  Color(0xFF7CB342),
];

/// Stable colour for a fan, derived from their id.
Color fanColor(String seed) {
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _avatarColors[h % _avatarColors.length];
}

String fanShortId(dynamic id) {
  final s = '$id';
  return s.length <= 6 ? s : s.substring(0, 6);
}

String fanClock(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:'
      '${l.minute.toString().padLeft(2, '0')}';
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Today", "Tomorrow" or "Sat 25 Oct".
String fanDayLabel(DateTime when, DateTime now) {
  final a = when.toLocal();
  final b = now.toLocal();
  final da = DateTime.utc(a.year, a.month, a.day);
  final db = DateTime.utc(b.year, b.month, b.day);
  final diff = da.difference(db).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return '${_days[a.weekday - 1]} ${a.day} ${_months[a.month - 1]}';
}

String fanTimeAgo(dynamic at) {
  final d = DateTime.fromMillisecondsSinceEpoch((at as num).toInt());
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]}';
}

String fanCountdown(Duration d) {
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes >= 1) return '${d.inMinutes}m';
  return '<1m';
}

// -----------------------------------------------------------------------------
// Scoring, stats and levels (all computed on the phone from the fan's picks)
// -----------------------------------------------------------------------------

/// 3 = exact score, 1 = right winner/draw, 0 = missed, null = not settled yet.
int? fanPickPoints(Map<String, dynamic> p) => fanPredictionScore(p);

class FanStats {
  final int picks, settled, points, exact, correct, streak, bestStreak;
  const FanStats({
    this.picks = 0,
    this.settled = 0,
    this.points = 0,
    this.exact = 0,
    this.correct = 0,
    this.streak = 0,
    this.bestStreak = 0,
  });

  /// Share of settled picks that earned at least one point (0-100).
  int get accuracy => settled == 0 ? 0 : (correct * 100 / settled).round();

  factory FanStats.from(List<Map<String, dynamic>> picks) {
    final settledPicks =
        <Map<String, dynamic>>[
          for (final p in picks)
            if (fanPickPoints(p) != null) p,
        ]..sort(
          (a, b) => ((b['kickoff'] as num?) ?? 0).compareTo(
            (a['kickoff'] as num?) ?? 0,
          ),
        );
    var points = 0, exact = 0, correct = 0;
    for (final p in settledPicks) {
      final v = fanPickPoints(p)!;
      points += v;
      if (v == 3) exact++;
      if (v > 0) correct++;
    }
    var streak = 0;
    for (final p in settledPicks) {
      if (fanPickPoints(p)! > 0) {
        streak++;
      } else {
        break;
      }
    }
    var best = 0, run = 0;
    for (final p in settledPicks.reversed) {
      if (fanPickPoints(p)! > 0) {
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }
    return FanStats(
      picks: picks.length,
      settled: settledPicks.length,
      points: points,
      exact: exact,
      correct: correct,
      streak: streak,
      bestStreak: best,
    );
  }
}

class FanLevel {
  final String name;
  final int min;
  final IconData icon;
  final Color color;
  const FanLevel(this.name, this.min, this.icon, this.color);
}

const fanLevels = [
  FanLevel('Rookie', 0, Icons.sports_soccer_rounded, Color(0xFF90A4AE)),
  FanLevel('Regular', 5, Icons.directions_run_rounded, Color(0xFF4FC3F7)),
  FanLevel('Pundit', 15, Icons.mic_rounded, Color(0xFF66BB6A)),
  FanLevel('Analyst', 35, Icons.insights_rounded, Color(0xFFAB47BC)),
  FanLevel('Legend', 75, Icons.workspace_premium_rounded, Color(0xFFFFC107)),
];

FanLevel fanLevelFor(int points) {
  var level = fanLevels.first;
  for (final l in fanLevels) {
    if (points >= l.min) level = l;
  }
  return level;
}

FanLevel? fanNextLevel(int points) {
  for (final l in fanLevels) {
    if (points < l.min) return l;
  }
  return null;
}

// -----------------------------------------------------------------------------
// Post kinds
// -----------------------------------------------------------------------------

class FanKind {
  final String label;
  final IconData icon;
  final Color color;
  const FanKind(this.label, this.icon, this.color);

  static FanKind of(String kind) {
    switch (kind) {
      case 'betslip':
        return const FanKind(
          'Bet Slip',
          Icons.receipt_long_rounded,
          Color(0xFFFFB300),
        );
      case 'prediction':
        return FanKind('Prediction', Icons.sports_soccer_rounded, Ui.green);
      default:
        return FanKind('Banter', Icons.forum_rounded, Ui.redSoft);
    }
  }
}

// -----------------------------------------------------------------------------
// Widgets
// -----------------------------------------------------------------------------

BoxDecoration fanBox({Color? border, Color? color, double radius = 16}) =>
    BoxDecoration(
      color: color ?? Ui.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border ?? Ui.line),
    );

class FanAvatar extends StatelessWidget {
  final String name;
  final String seed;
  final double size;
  const FanAvatar({
    super.key,
    required this.name,
    required this.seed,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final c = fanColor(seed.isEmpty ? name : seed);
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : trimmed.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c, c.withValues(alpha: .6)],
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * .42,
        ),
      ),
    );
  }
}

class FanPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const FanPill({
    super.key,
    required this.text,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class FanSectionTitle extends StatelessWidget {
  final String text;
  final String? trailing;
  final VoidCallback? onTrailing;
  final IconData? icon;
  const FanSectionTitle(
    this.text, {
    super.key,
    this.trailing,
    this.onTrailing,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 22, 2, 12),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: Ui.red,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        if (icon != null) ...[
          Icon(icon, size: 18, color: Ui.redSoft),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: .2,
            ),
          ),
        ),
        if (trailing != null)
          GestureDetector(
            onTap: onTrailing,
            child: Text(
              trailing!,
              style: TextStyle(
                color: Ui.redSoft,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Team crest. The feed stores either an API-Sports team id or a full URL.
class TeamCrest extends StatelessWidget {
  final String logo;
  final double size;
  const TeamCrest({super.key, required this.logo, this.size = 44});

  String? get _url {
    final value = logo.trim();
    if (value.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(value)) {
      return 'https://media.api-sports.io/football/teams/$value.png';
    }
    final uri = Uri.tryParse(value);
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty) {
      return value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.sports_soccer_rounded,
      size: size * .5,
      color: Colors.white70,
    );
    final url = _url;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: .06),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: url == null
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }
}

/// Shimmering placeholder block used while the feed loads.
class FanSkeleton extends StatefulWidget {
  final double height;
  const FanSkeleton({super.key, this.height = 120});

  @override
  State<FanSkeleton> createState() => _FanSkeletonState();
}

class _FanSkeletonState extends State<FanSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) {
      final t = _c.value;
      return Container(
        height: widget.height,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Ui.line),
          gradient: LinearGradient(
            begin: Alignment(-1.6 + 3.2 * t, -.3),
            end: Alignment(-.6 + 3.2 * t, .3),
            colors: [Ui.card, Colors.white.withValues(alpha: .07), Ui.card],
          ),
        ),
      );
    },
  );
}

class FanEmpty extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final Widget? action;
  const FanEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
    child: Column(
      children: [
        Icon(icon, size: 46, color: Ui.dim),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Ui.muted, height: 1.35),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

// -----------------------------------------------------------------------------
// Community design kit (hero cards, chips, badges, level avatars, live dot)
// -----------------------------------------------------------------------------

const fanGold = Color(0xFFFFC107);
const fanBlue = Color(0xFF448AFF);
const fanOrange = Color(0xFFFF7043);
const fanAlert = Color(0xFFFF5252);

/// Faint centre-circle and halfway line, drawn behind hero cards.
class FanPitchPainter extends CustomPainter {
  final Color color;
  const FanPitchPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final c = Offset(size.width * .88, size.height * .5);
    canvas.drawCircle(c, size.height * .62, line);
    canvas.drawCircle(c, size.height * .22, line);
    canvas.drawLine(Offset(c.dx, 0), Offset(c.dx, size.height), line);
    canvas.drawCircle(c, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant FanPitchPainter old) => old.color != color;
}

/// Big gradient card with a pitch pattern. Used at the top of every page.
class FanHero extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  const FanHero({
    super.key,
    required this.child,
    required this.color,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: color.withValues(alpha: .38)),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withValues(alpha: .34), Ui.card, Ui.cardDeep],
      ),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: .14),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: FanPitchPainter(
              color: Colors.white.withValues(alpha: .055),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
      ],
    ),
  );
}

/// Pill-shaped selectable chip used for filters (days, leagues, post types).
class FanChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final String? badge;
  final Color? color;
  const FanChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.icon,
    this.badge,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Ui.red;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: .20) : Ui.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? c : Ui.line,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: selected ? c : Ui.muted),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                color: selected ? Colors.white : Ui.muted,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? c : Colors.white12,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: selected ? Ui.palette.onAccent : Ui.muted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Number that counts up when it first appears or changes.
class FanCountUp extends StatelessWidget {
  final int value;
  final String suffix;
  final TextStyle? style;
  const FanCountUp({
    super.key,
    required this.value,
    this.suffix = '',
    this.style,
  });

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: value.toDouble()),
    duration: const Duration(milliseconds: 800),
    curve: Curves.easeOutCubic,
    builder: (_, v, __) => Text('${v.round()}$suffix', style: style),
  );
}

/// One stat in a row: tinted icon, animated number, small label.
class FanStatTile extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;
  final Color color;
  final String? suffix;
  final bool empty;
  const FanStatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.suffix,
    this.empty = false,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          empty
              ? const Text(
                  '–',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                )
              : FanCountUp(
                  value: value,
                  suffix: suffix ?? '',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
          Text(label, style: TextStyle(fontSize: 11, color: Ui.muted)),
        ],
      ),
    ),
  );
}

/// Avatar wrapped in a ring that fills as the fan climbs to the next level.
class FanLevelAvatar extends StatelessWidget {
  final String name;
  final String seed;
  final double size;
  final double progress;
  final Color color;
  const FanLevelAvatar({
    super.key,
    required this.name,
    required this.seed,
    required this.progress,
    required this.color,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size + 12,
    height: size + 12,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.expand(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => CircularProgressIndicator(
              value: v,
              strokeWidth: 4,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        FanAvatar(name: name, seed: seed, size: size),
      ],
    ),
  );
}

/// Small pill showing a fan's level (icon + name) in the level colour.
class FanLevelPill extends StatelessWidget {
  final FanLevel level;
  const FanLevelPill(this.level, {super.key});

  @override
  Widget build(BuildContext context) =>
      FanPill(text: level.name, color: level.color, icon: level.icon);
}

/// A pulsing dot for live things.
class FanLiveDot extends StatefulWidget {
  final Color color;
  final double size;
  const FanLiveDot({super.key, this.color = fanAlert, this.size = 8});

  @override
  State<FanLiveDot> createState() => _FanLiveDotState();
}

class _FanLiveDotState extends State<FanLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) => Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: .65 * _c.value),
            blurRadius: 4 + 5 * _c.value,
            spreadRadius: 1 + _c.value,
          ),
        ],
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// Achievements (all computed on the phone from the fan's picks)
// -----------------------------------------------------------------------------

class FanBadge {
  final String title;
  final String hint;
  final IconData icon;
  final Color color;
  final bool unlocked;
  const FanBadge(this.title, this.hint, this.icon, this.color, this.unlocked);
}

List<FanBadge> fanBadgesFor(FanStats s) => [
  FanBadge(
    'First pick',
    'Make your first prediction',
    Icons.flag_rounded,
    const Color(0xFF4FC3F7),
    s.picks >= 1,
  ),
  FanBadge(
    'Sharpshooter',
    'Nail one exact score',
    Icons.track_changes_rounded,
    Ui.green,
    s.exact >= 1,
  ),
  FanBadge(
    'Hat-trick',
    'Nail 3 exact scores',
    Icons.looks_3_rounded,
    const Color(0xFF00C896),
    s.exact >= 3,
  ),
  FanBadge(
    'On fire',
    'Get 3 correct picks in a row',
    Icons.local_fire_department_rounded,
    fanOrange,
    s.bestStreak >= 3,
  ),
  FanBadge(
    'Unstoppable',
    'Get 7 correct picks in a row',
    Icons.bolt_rounded,
    const Color(0xFFFFB300),
    s.bestStreak >= 7,
  ),
  FanBadge(
    'Regular',
    'Get 10 picks settled',
    Icons.event_available_rounded,
    const Color(0xFF7986CB),
    s.settled >= 10,
  ),
  FanBadge(
    'Analyst',
    'Reach 35 points',
    Icons.insights_rounded,
    const Color(0xFFAB47BC),
    s.points >= 35,
  ),
  FanBadge(
    'Legend',
    'Reach 75 points',
    Icons.workspace_premium_rounded,
    fanGold,
    s.points >= 75,
  ),
];

class FanBadgeTile extends StatelessWidget {
  final FanBadge badge;
  const FanBadgeTile(this.badge, {super.key});

  @override
  Widget build(BuildContext context) {
    final on = badge.unlocked;
    final c = on ? badge.color : Ui.dim;
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              on ? '${badge.title} unlocked' : '${badge.title}: ${badge.hint}',
            ),
          ),
        ),
      child: SizedBox(
        width: 78,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.withValues(alpha: on ? .20 : .08),
                    border: Border.all(
                      color: c.withValues(alpha: on ? .8 : .25),
                      width: on ? 2 : 1,
                    ),
                    boxShadow: on
                        ? [
                            BoxShadow(
                              color: c.withValues(alpha: .35),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(badge.icon, color: c, size: 26),
                ),
                if (!on)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Ui.cardDeep,
                        shape: BoxShape.circle,
                        border: Border.all(color: Ui.line),
                      ),
                      child: Icon(Icons.lock_rounded, size: 11, color: Ui.dim),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              badge.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: on ? Colors.white : Ui.dim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
