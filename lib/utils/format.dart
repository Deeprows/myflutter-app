const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December'
];

String two(int n) => n.toString().padLeft(2, '0');

String fmtTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String weekdayName(DateTime d) => _weekdays[d.weekday - 1];

/// "Saturday, 3 October 2026"
String longDate(DateTime d) =>
    '${weekdayName(d)}, ${d.day} ${_months[d.month - 1]} ${d.year}';

/// "Sat, 3 Oct"
String shortDate(DateTime d) =>
    '${weekdayName(d).substring(0, 3)}, ${d.day} ${_months[d.month - 1].substring(0, 3)}';

int _daysFromToday(DateTime d, DateTime now) =>
    DateTime.utc(d.year, d.month, d.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;

/// Today / Tomorrow / Yesterday, otherwise "Sat, 3 Oct".
String dayLabel(DateTime d, DateTime now) {
  switch (_daysFromToday(d, now)) {
    case 0:
      return 'Today';
    case 1:
      return 'Tomorrow';
    case -1:
      return 'Yesterday';
    default:
      return shortDate(d);
  }
}

String countdownText(Duration d) {
  if (d.isNegative) return '0m';
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inMinutes}m ${two(d.inSeconds % 60)}s';
}

/// 1536 -> "1.5 KB", 734003200 -> "700 MB".
String fmtBytes(num bytes) {
  if (bytes < 1024) return '${bytes.toInt()} B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

/// "GMT+1", "GMT-5", "GMT+5:30" for the given (local) time.
String gmtOffset(DateTime d) {
  final m = d.timeZoneOffset.inMinutes;
  final sign = m < 0 ? '-' : '+';
  final h = m.abs() ~/ 60;
  final mm = m.abs() % 60;
  return 'GMT$sign$h${mm == 0 ? '' : ':${two(mm)}'}';
}

/// Short zone name for the user's device ("WAT" in Nigeria), or "GMT+1" when
/// the platform only reports an offset.
String tzShort(DateTime d) {
  final n = d.timeZoneName;
  if (n.isNotEmpty && n.length <= 5 && RegExp(r'^[A-Za-z]+$').hasMatch(n)) {
    return n.toUpperCase();
  }
  return gmtOffset(d);
}
