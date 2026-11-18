import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

/// The group chat client (migration 0216, script 281).
void main() {
  test(
    'GET /me/h2h-league/chat reads a page, then those after an id',
    () async {
      final ctx = buildTransport(
        (_) async => okJson(const {
          'has_group': true,
          'muted': false,
          'rules_accepted': true,
          'unread': 1,
          'messages': [
            {
              'id': 4,
              'sender_id': 'aaaaaaaa-0000-4000-8000-000000000002',
              'sender_name': 'سالم',
              'body': 'مرحبا',
              'created_at': '2026-11-15T10:00:00.000Z',
              'mine': false,
            },
          ],
        }),
        token: 'jwt-abc',
      );
      final H2hChatApi api = H2hChatApi(ctx.transport);

      final first = await api.page();
      await api.page(after: 4, limit: 20);

      final H2hChatPageDto page = (first as Ok<H2hChatPageDto>).value;
      expect(page.messages.single.body, 'مرحبا');
      expect(page.unread, 1);
      expect(ctx.captured.first.url.path, '/me/h2h-league/chat');
      expect(ctx.captured.first.url.queryParameters, isEmpty);
      expect(ctx.captured.last.url.queryParameters, {
        'after': '4',
        'limit': '20',
      });
      expect(ctx.captured.first.headers['authorization'], 'Bearer jwt-abc');
    },
  );

  test('POST sends the text and reads the stored message', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'id': 5,
        'sender_id': 'aaaaaaaa-0000-4000-8000-000000000001',
        'sender_name': 'أنا',
        'body': 'سلام',
        'created_at': '2026-11-15T10:00:00.000Z',
        'mine': true,
      }),
    );

    final result = await H2hChatApi(ctx.transport).send('سلام');

    expect((result as Ok<H2hChatMessageDto>).value.mine, isTrue);
    final req = ctx.captured.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/me/h2h-league/chat');
    expect((jsonDecode(req.body) as Map<String, Object?>)['body'], 'سلام');
  });

  test('reading and the rules hit their routes and answer nothing', () async {
    final ctx = buildTransport((_) async => okJson(const {'ok': true}));
    final H2hChatApi api = H2hChatApi(ctx.transport);

    expect(await api.markRead(), isA<Ok<void>>());
    expect(await api.acceptRules(), isA<Ok<void>>());

    final List<String> calls = [
      for (final r in ctx.captured) '${r.method} ${r.url.path}',
    ];
    expect(calls, [
      'POST /me/h2h-league/chat/read',
      'POST /me/h2h-league/chat/rules',
    ]);
  });

  test('a refusal carries the server code', () async {
    final ctx = buildTransport(
      (_) async => errorEnvelope(
        409,
        'h2h.chat_rules_not_accepted',
        'وافق على قواعد الدردشة أولًا.',
      ),
    );

    final result = await H2hChatApi(ctx.transport).send('سلام');

    expect(
      (result as Err<H2hChatMessageDto>).error.code,
      'h2h.chat_rules_not_accepted',
    );
  });
}
