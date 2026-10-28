import 'dart:convert';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

/// The player's support chat client (migration 0187, script 166).
void main() {
  test(
    'GET /me/support/messages reads a page, older ones before an id',
    () async {
      final ctx = buildTransport(
        (_) async => okJson(const {
          'status': 'open',
          'unread': 1,
          'has_more': true,
          'messages': [
            {
              'id': 4,
              'sender': 'support',
              'body': 'تم',
              'created_at': '2026-10-28T10:00:00.000Z',
            },
          ],
        }),
        token: 'jwt-abc',
      );
      final SupportApi api = SupportApi(ctx.transport);

      final first = await api.thread();
      final older = await api.thread(before: 4, limit: 30);

      final SupportThreadDto page = (first as Ok<SupportThreadDto>).value;
      expect(page.unread, 1);
      expect(page.hasMore, isTrue);
      expect(page.messages.single.sender, 'support');
      expect(older, isA<Ok<SupportThreadDto>>());
      expect(ctx.captured.first.url.path, '/me/support/messages');
      expect(ctx.captured.first.url.queryParameters, isEmpty);
      expect(ctx.captured.last.url.queryParameters, {
        'before': '4',
        'limit': '30',
      });
      expect(ctx.captured.first.headers['authorization'], 'Bearer jwt-abc');
    },
  );

  test('POST /me/support/messages sends the text, reads the message', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'id': 5,
        'sender': 'player',
        'body': 'سؤال',
        'created_at': '2026-10-28T10:00:00.000Z',
      }),
    );

    final result = await SupportApi(ctx.transport).send('سؤال');

    expect((result as Ok<SupportMessageDto>).value.id, 5);
    final req = ctx.captured.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/me/support/messages');
    expect((jsonDecode(req.body) as Map<String, Object?>)['body'], 'سؤال');
  });

  test('a refused message carries the server code', () async {
    final ctx = buildTransport(
      (_) async =>
          errorEnvelope(400, 'support.empty_message', 'اكتب رسالتك أولًا.'),
    );

    final result = await SupportApi(ctx.transport).send(' ');

    final AppError error = (result as Err<SupportMessageDto>).error;
    expect(error.code, 'support.empty_message');
    expect(error.message, 'اكتب رسالتك أولًا.');
  });

  test('read and unread answer their counts', () async {
    final ctx = buildTransport((_) async => okJson(const {'count': 2}));
    final SupportApi api = SupportApi(ctx.transport);

    expect(await api.markRead(), const Result<int>.ok(2));
    expect(await api.unread(), const Result<int>.ok(2));
    expect(ctx.captured.first.method, 'POST');
    expect(ctx.captured.first.url.path, '/me/support/read');
    expect(ctx.captured.last.method, 'GET');
    expect(ctx.captured.last.url.path, '/me/support/unread');
  });

  test(
    'a picture goes up as raw bytes and comes back the same (0188)',
    () async {
      final List<int> jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2];
      final ctx = buildTransport((request) async {
        if (request.method == 'POST') {
          return okJson(const {
            'id': 6,
            'sender': 'player',
            'body': '',
            'created_at': '2026-10-28T10:00:00.000Z',
            'has_image': true,
          });
        }
        if (request.url.path == '/me/support/messages/6/image') {
          return http.Response.bytes(
            jpeg,
            200,
            headers: const {'content-type': 'image/jpeg'},
          );
        }
        return http.Response('', 404);
      });
      final SupportApi api = SupportApi(ctx.transport);

      final sent = await api.sendImage(jpeg, contentType: 'image/jpeg');
      final back = await api.image(6);
      final none = await api.image(7);

      expect((sent as Ok<SupportMessageDto>).value.hasImage, isTrue);
      expect(ctx.captured.first.url.path, '/me/support/images');
      expect(
        ctx.captured.first.headers['content-type'],
        startsWith('image/jpeg'),
      );
      expect(ctx.captured.first.request.bodyBytes, jpeg);
      expect((back as Ok<Uint8List?>).value, jpeg);
      expect((none as Ok<Uint8List?>).value, isNull);
    },
  );
}
