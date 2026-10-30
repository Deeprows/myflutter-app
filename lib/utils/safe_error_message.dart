/// Converts internal/network exceptions into short, user-safe messages.
/// Never render raw socket/client exceptions, URLs, hostnames, backend/setup
/// details or stack traces in the UI.
const _offline = 'No connection. Check your internet and try again.';
const _slow = 'This is taking too long. Check your connection and try again.';

String safeErrorMessage(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  var message = error.toString().trim();
  message = message.replaceFirst(
    RegExp(r'^(Exception|StateError|ArgumentError):\s*'),
    '',
  );
  final lower = message.toLowerCase();

  if (lower.contains('timeoutexception') ||
      lower.contains('timed out') ||
      lower.contains('future not completed')) {
    return _slow;
  }

  // Connectivity problems get a friendly, specific message.
  const network = [
    'socketexception',
    'clientexception',
    'socketfailed',
    'failed host lookup',
    'connection abort',
    'connection closed',
    'connection refused',
    'connection reset',
    'connection timed out',
    'network is unreachable',
    'handshakeexception',
    'tlsexception',
    'os error:',
    'errno',
  ];
  if (network.any(lower.contains)) return _offline;

  const technical = [
    'uri=',
    'stack trace',
    '#0 ',
    ' at ',
    'workers.dev',
    'http://',
    'https://',
    'localhost',
    '/fan/',
    '/api/',
    'unexpected end of input',
    'format exception',
    'formatexception',
    'platformexception',
    'dioexception',
    'httpexception',
    'null check',
    'type \'',
    'is not a subtype',
    'api key',
    'api_key',
    'apikey',
    'secret',
    'cloudflare',
    'worker',
    'deploy',
    'endpoint',
    'backend',
    'server error',
    'internal server',
    'status code',
    'statuscode',
    'jwt',
    'oauth',
    'sha-1',
    'sha1',
    'client id',
    'database',
    'sql',
    'd1_',
    'kv ',
    'provider setup',
    'setup needed',
    'binding',
    'exception',
  ];
  if (technical.any(lower.contains)) return fallback;

  // Avoid displaying unbounded provider/server diagnostics in the UI.
  if (message.isEmpty ||
      message.length > 140 ||
      message.contains(RegExp(r'[\r\n]'))) {
    return fallback;
  }
  return message;
}
