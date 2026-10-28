/// A fake of the server's `/me/support/*` routes (script 165) for the chat
/// tests: the real [SupportApi] and transport talk to it over HTTP.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

final class FakeSupportServer {
  FakeSupportServer({this.status});

  /// `open`, `closed` or `archived`; null before the first message.
  String? status;

  /// Stored messages, oldest first: `{id, sender, body, created_at, read_at?}`.
  final List<Map<String, Object?>> messages = <Map<String, Object?>>[];

  /// What every request was: `METHOD path?query`.
  final List<String> calls = <String>[];

  /// Answers a send with this status code and envelope instead (once).
  (int, String, String)? failNextSend;

  /// Answers every page read with a 503 while true.
  bool readsFail = false;

  int _nextId = 1;

  /// Pictures by message id (migration 0188), and the type each came as.
  final Map<int, (List<int>, String)> images = <int, (List<int>, String)>{};

  /// A 1x1 PNG, a picture the test image decoder can draw.
  static const List<int> png = <int>[
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    1,
    8,
    2,
    0,
    0,
    0,
    144,
    119,
    83,
    222,
    0,
    0,
    0,
    12,
    73,
    68,
    65,
    84,
    120,
    156,
    99,
    248,
    207,
    192,
    0,
    0,
    3,
    1,
    1,
    0,
    201,
    254,
    146,
    239,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130,
  ];

  /// Adds a stored message, as if it had been sent earlier.
  void add(String sender, String body, {bool read = false}) {
    final int id = _nextId++;
    messages.add(<String, Object?>{
      'id': id,
      'sender': sender,
      'body': body,
      'created_at': DateTime.utc(2026, 10, 28, 9, id).toIso8601String(),
      if (read) 'read_at': DateTime.utc(2026, 10, 28, 9, 59).toIso8601String(),
    });
    status ??= 'open';
  }

  int get _unread => messages
      .where((m) => m['sender'] == 'support' && m['read_at'] == null)
      .length;

  http.Response _json(Object body, [int code = 200]) => http.Response(
    jsonEncode(body),
    code,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  Future<http.Response> handle(http.Request request) async {
    final Uri url = request.url;
    calls.add(
      '${request.method} ${url.path}'
      '${url.query.isEmpty ? '' : '?${url.query}'}',
    );
    if (url.path == '/me/support/unread' && request.method == 'GET') {
      return _json(<String, Object?>{'count': _unread});
    }
    if (url.path == '/me/support/read' && request.method == 'POST') {
      int marked = 0;
      for (final Map<String, Object?> m in messages) {
        if (m['sender'] == 'support' && m['read_at'] == null) {
          m['read_at'] = DateTime.utc(2026, 10, 28, 10).toIso8601String();
          marked++;
        }
      }
      return _json(<String, Object?>{'count': marked});
    }
    if (url.path == '/me/support/messages' && request.method == 'GET') {
      if (readsFail) {
        return _json(<String, Object?>{
          'code': 'db.query_failed',
          'message': 'down',
        }, 503);
      }
      final int? before = int.tryParse(url.queryParameters['before'] ?? '');
      final int limit = int.tryParse(url.queryParameters['limit'] ?? '') ?? 30;
      final List<Map<String, Object?>> older = <Map<String, Object?>>[
        for (final Map<String, Object?> m in messages)
          if (before == null || (m['id']! as int) < before) m,
      ];
      final int start = older.length > limit ? older.length - limit : 0;
      return _json(<String, Object?>{
        if (status != null) 'status': status,
        'unread': _unread,
        'has_more': start > 0,
        'messages': older.sublist(start),
      });
    }
    if (url.path == '/me/support/images' && request.method == 'POST') {
      add('player', '');
      messages.last['has_image'] = true;
      images[messages.last['id']! as int] = (
        request.bodyBytes,
        request.headers['content-type'] ?? '',
      );
      return _json(messages.last, 201);
    }
    final RegExpMatch? image = RegExp(
      r'^/me/support/messages/(\d+)/image$',
    ).firstMatch(url.path);
    if (image != null && request.method == 'GET') {
      final (List<int>, String)? stored = images[int.parse(image.group(1)!)];
      return stored == null
          ? http.Response('', 404)
          : http.Response.bytes(stored.$1, 200);
    }
    if (url.path == '/me/support/messages' && request.method == 'POST') {
      final (int, String, String)? fail = failNextSend;
      if (fail != null) {
        failNextSend = null;
        return _json(<String, Object?>{
          'code': fail.$2,
          'message': fail.$3,
        }, fail.$1);
      }
      final String body =
          (jsonDecode(request.body) as Map<String, Object?>)['body']! as String;
      add('player', body.trim());
      status = 'open';
      return _json(messages.last, 201);
    }
    return http.Response('not found', 404);
  }
}
