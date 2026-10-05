import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// One comment in a match chat.
class ChatMessage {
  final String id;
  final String username;
  final String text;
  final DateTime? at;
  const ChatMessage(this.id, this.username, this.text, this.at);
}

/// Match chat shared with the Footbolive website.
///
/// Same Firestore data the website uses:
///   match_chats/<slug of "Home vs Away">/messages/{username, message,
///   matchName, createdAt}
/// so fans on the website and in the app chat in the same room. It talks to
/// Firestore's REST API (no extra Android setup), refreshing by polling.
class ChatService {
  static const _project = 'deeprows-4d37c';
  static const _apiKey = 'AIzaSyBs9eSquNu2drJjM3vqFGDX1QU-VE1_F7U';
  static const _origin = 'https://deeprowss.com';
  static const _base =
      'https://firestore.googleapis.com/v1/projects/$_project/databases/(default)/documents';

  static const maxLength = 300;

  /// Same rule as the website's slugify().
  static String slugify(String value) => value
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'(^-|-$)'), '');

  static const _headers = {
    'Content-Type': 'application/json',
    // The website key may be limited to the website's address.
    'Referer': '$_origin/',
    'Origin': _origin,
  };

  /// Latest [limit] comments, oldest first. Throws on network / permission
  /// errors so the UI can show a message.
  static Future<List<ChatMessage>> fetch(String slug, {int limit = 100}) async {
    final res = await http
        .post(
          Uri.parse('$_base/match_chats/$slug:runQuery?key=$_apiKey'),
          headers: _headers,
          body: jsonEncode({
            'structuredQuery': {
              'from': [
                {'collectionId': 'messages'}
              ],
              'orderBy': [
                {
                  'field': {'fieldPath': 'createdAt'},
                  'direction': 'DESCENDING'
                }
              ],
              'limit': limit,
            }
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('chat ${res.statusCode}');
    }
    final data = jsonDecode(res.body);
    final out = <ChatMessage>[];
    if (data is List) {
      for (final row in data) {
        if (row is! Map || row['document'] is! Map) continue;
        final doc = row['document'] as Map;
        final f = (doc['fields'] as Map?) ?? const {};
        String s(String k) => ((f[k] as Map?)?['stringValue'] ?? '').toString();
        final ts = (f['createdAt'] as Map?)?['timestampValue']?.toString();
        final id = (doc['name'] ?? '').toString().split('/').last;
        final text = s('message');
        if (text.isEmpty) continue;
        out.add(ChatMessage(
          id,
          s('username').isEmpty ? 'Football Fan' : s('username'),
          text,
          ts == null ? null : DateTime.tryParse(ts)?.toLocal(),
        ));
      }
    }
    return out.reversed.toList();
  }

  /// Posts a comment. Returns null on success, otherwise a message to show.
  static Future<String?> send(
    String slug, {
    required String matchName,
    required String username,
    required String text,
  }) async {
    final msg = text.trim();
    if (msg.isEmpty) return null;
    final id = _autoId();
    final name = 'projects/$_project/databases/(default)/documents'
        '/match_chats/$slug/messages/$id';
    try {
      final res = await http
          .post(
            Uri.parse('$_base:commit?key=$_apiKey'),
            headers: _headers,
            body: jsonEncode({
              'writes': [
                {
                  'update': {
                    'name': name,
                    'fields': {
                      'username': {'stringValue': username},
                      'message': {
                        'stringValue': msg.length > maxLength
                            ? msg.substring(0, maxLength)
                            : msg
                      },
                      'matchName': {'stringValue': matchName},
                    },
                  },
                  'updateTransforms': [
                    {
                      'fieldPath': 'createdAt',
                      'setToServerValue': 'REQUEST_TIME'
                    }
                  ],
                  'currentDocument': {'exists': false},
                }
              ]
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) return null;
      return res.statusCode == 403
          ? 'Comments are not allowed right now.'
          : 'Could not send your comment (${res.statusCode}).';
    } catch (_) {
      return 'Could not send your comment. Check your connection.';
    }
  }

  static String _autoId() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static String randomName() {
    const names = [
      'Football Fan', 'Match Fan', 'Goal Hunter', 'Football Lover',
      'Super Fan', 'Game Watcher', 'Goal Master', 'Football King',
      'Football Queen', 'Match Expert',
    ];
    final r = Random();
    return '${names[r.nextInt(names.length)]} ${100 + r.nextInt(900)}';
  }
}
