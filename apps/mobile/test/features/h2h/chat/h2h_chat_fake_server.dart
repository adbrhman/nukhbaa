/// A fake of the server's `/me/h2h-league/chat` routes (script 281) and of
/// the support chat a report goes to (script 225), for the chat's tests:
/// the real [H2hChatApi] and transport talk to it over HTTP.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

final class FakeH2hChatServer {
  FakeH2hChatServer({
    this.hasGroup = true,
    this.rulesAccepted = true,
    this.muted = false,
  });

  /// Whether the caller sits in a group this month.
  bool hasGroup;

  /// Whether the caller accepted the rules.
  bool rulesAccepted;

  /// Whether an admin muted the caller.
  bool muted;

  /// Stored messages, oldest first: `{id, sender_id, sender_name, body,
  /// created_at}`; the caller is [me].
  final List<Map<String, Object?>> messages = <Map<String, Object?>>[];

  /// What every request was: `METHOD path?query`.
  final List<String> calls = <String>[];

  /// What reports put in the support chat.
  final List<String> supportMessages = <String>[];

  /// Answers every page read with a 503 while true.
  bool readsFail = false;

  /// Answers a send with this status code and envelope instead (once).
  (int, String, String)? failNextSend;

  /// The caller's id in `sender_id`.
  static const String me = 'aaaaaaaa-0000-4000-8000-000000000001';

  int _nextId = 1;

  /// Adds a message of another player (or of the caller when [sender] is
  /// [me]).
  void add(
    String body, {
    String sender = 'bbbbbbbb-0000-4000-8000-000000000002',
    String name = 'سالم',
  }) {
    messages.add(<String, Object?>{
      'id': _nextId++,
      'sender_id': sender,
      'sender_name': sender == me ? 'أنا' : name,
      'body': body,
      'created_at': DateTime.utc(2026, 11, 15, 10, _nextId).toIso8601String(),
    });
  }

  http.Response _json(Map<String, Object?> body, [int status = 200]) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );

  Map<String, Object?> _view(Map<String, Object?> m) => <String, Object?>{
    ...m,
    'mine': m['sender_id'] == me,
  };

  Future<http.Response> handle(http.Request request) async {
    final Uri url = request.url;
    calls.add(
      '${request.method} ${url.path}'
      '${url.query.isEmpty ? '' : '?${url.query}'}',
    );
    if (url.path == '/me/h2h-league/chat' && request.method == 'GET') {
      if (readsFail) {
        return _json(<String, Object?>{
          'code': 'db.query_failed',
          'message': 'down',
        }, 503);
      }
      if (!hasGroup) {
        return _json(<String, Object?>{
          'has_group': false,
          'muted': false,
          'rules_accepted': false,
          'unread': 0,
          'messages': <Object?>[],
        });
      }
      final int? after = int.tryParse(url.queryParameters['after'] ?? '');
      final List<Map<String, Object?>> page = <Map<String, Object?>>[
        for (final Map<String, Object?> m in messages)
          if (after == null || (m['id']! as int) > after) _view(m),
      ];
      return _json(<String, Object?>{
        'has_group': true,
        'muted': muted,
        'rules_accepted': rulesAccepted,
        'unread': page.where((m) => m['mine'] != true).length,
        'messages': page,
      });
    }
    if (url.path == '/me/h2h-league/chat' && request.method == 'POST') {
      final (int, String, String)? fail = failNextSend;
      if (fail != null) {
        failNextSend = null;
        return _json(<String, Object?>{
          'code': fail.$2,
          'message': fail.$3,
        }, fail.$1);
      }
      if (!rulesAccepted) {
        return _json(<String, Object?>{
          'code': 'h2h.chat_rules_not_accepted',
          'message': 'وافق على قواعد الدردشة أولًا.',
        }, 409);
      }
      if (muted) {
        return _json(<String, Object?>{
          'code': 'h2h.chat_muted',
          'message': 'مُنعت من الكتابة في الدردشة.',
        }, 409);
      }
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      add(body['body']! as String, sender: me);
      return _json(_view(messages.last), 201);
    }
    if (url.path == '/me/h2h-league/chat/read' && request.method == 'POST') {
      return _json(<String, Object?>{'ok': true});
    }
    if (url.path == '/me/h2h-league/chat/rules' && request.method == 'POST') {
      rulesAccepted = true;
      return _json(<String, Object?>{'ok': true});
    }
    if (url.path == '/me/support/messages' && request.method == 'POST') {
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      supportMessages.add(body['body']! as String);
      return _json(<String, Object?>{
        'id': supportMessages.length,
        'sender': 'player',
        'body': body['body'],
        'created_at': DateTime.utc(2026, 11, 15, 11).toIso8601String(),
      }, 201);
    }
    return _json(<String, Object?>{
      'code': 'not_found',
      'message': 'no route',
    }, 404);
  }
}
