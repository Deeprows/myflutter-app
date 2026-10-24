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
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
int? fanPickPoints(Map<String, dynamic> p) {
  final rh = p['result_home'];
  final ra = p['result_away'];
  if (rh is! num || ra is! num) return null;
  final h = (p['home'] as num).toInt();
  final a = (p['away'] as num).toInt();
  if (h == rh.toInt() && a == ra.toInt()) return 3;
  return (h - a).sign == (rh.toInt() - ra.toInt()).sign ? 1 : 0;
}

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
    final settledPicks = <Map<String, dynamic>>[
      for (final p in picks)
        if (fanPickPoints(p) != null) p,
    ]..sort((a, b) => ((b['kickoff'] as num?) ?? 0)
        .compareTo((a['kickoff'] as num?) ?? 0));
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
  const FanLevel(this.name, this.min);
}

const fanLevels = [
  FanLevel('Rookie', 0),
  FanLevel('Regular', 5),
  FanLevel('Pundit', 15),
  FanLevel('Analyst', 35),
  FanLevel('Legend', 75),
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
            'Bet Slip', Icons.receipt_long_rounded, Color(0xFFFFB300));
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
    final initial = trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
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
  const FanPill({super.key, required this.text, required this.color, this.icon});

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
  const FanSectionTitle(this.text, {super.key, this.trailing, this.onTrailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
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
                    fontWeight: FontWeight.w700,
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

/// Grey placeholder block used while the feed loads.
class FanSkeleton extends StatelessWidget {
  final double height;
  const FanSkeleton({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: fanBox(),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Ui.dim),
          ),
        ),
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
