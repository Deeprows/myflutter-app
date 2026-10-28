/// Converts internal/network exceptions into short, user-safe messages.
/// Never render raw socket/client exceptions, URLs, hostnames or stack details.
String safeErrorMessage(Object error, {String fallback = 'Something went wrong. Please try again.'}) {
  var message = error.toString().trim();
  message = message.replaceFirst(RegExp(r'^(Exception|StateError|ArgumentError):\s*'), '');
  final lower = message.toLowerCase();
  final looksTechnical =
      lower.contains('clientexception') ||
      lower.contains('socketexception') ||
      lower.contains('socketfailed') ||
      lower.contains('os error:') ||
      lower.contains('errno =') ||
      lower.contains('uri=') ||
      lower.contains('stack trace') ||
      lower.contains(' at ') ||
      lower.contains('workers.dev') ||
      lower.contains('http://') ||
      lower.contains('https://') ||
      lower.contains('unexpected end of input') ||
      lower.contains('format exception') ||
      lower.contains('api key') ||
      lower.contains('api_key') ||
      lower.contains('secret') ||
      lower.contains('cloudflare') ||
      lower.contains('jwt') ||
      lower.contains('database') ||
      lower.contains('sql') ||
      lower.contains('provider setup') ||
      lower.contains('binding');
  if (looksTechnical) return fallback;
  // Avoid displaying unbounded provider/server diagnostics in the UI.
  if (message.isEmpty || message.length > 180 || message.contains(RegExp(r'[\r\n]'))) {
    return fallback;
  }
  return message;
}
