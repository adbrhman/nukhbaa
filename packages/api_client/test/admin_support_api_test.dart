import 'dart:convert';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

const String _id = 'bbbbbbbb-0000-4000-8000-000000000001';

/// The admins' support inbox client (migration 0187, script 167).
void main() {
  test(
    'GET /admin/support/conversations sends the filter and search',
    () async {
      final ctx = buildTransport(
        (_) async => okJson(const {
          'unread_conversations': 2,
          'conversations': [
            {
              'id': _id,
              'player_id': 'p-1',
              'player_name': 'سامي',
              'status': 'open',
              'last_message_at': '2026-10-28T10:00:00.000Z',
              'last_message_preview': 'سؤال',
              'last_sender': 'player',
              'support_unread': 1,
              'player_unread': 0,
            },
          ],
        }),
        token: 'jwt-admin',
      );
      final AdminApi api = AdminApi(ctx.transport);

      final result = await api.supportInbox(filter: 'unread', search: ' سا ');
      await api.supportInbox();

      final SupportInboxDto inbox = (result as Ok<SupportInboxDto>).value;
      expect(inbox.unreadConversations, 2);
      expect(inbox.conversations.single.playerName, 'سامي');
      expect(ctx.captured.first.url.path, '/admin/support/conversations');
      expect(ctx.captured.first.url.queryParameters, {
        'filter': 'unread',
        'search': 'سا',
      });
      expect(ctx.captured.last.url.queryParameters, {'filter': 'all'});
      expect(ctx.captured.first.headers['authorization'], 'Bearer jwt-admin');
    },
  );

  test('a conversation, older pages, a reply, read and status', () async {
    final ctx = buildTransport((request) async {
      final String path = request.url.path;
      if (request.method == 'GET') {
        return okJson(const {
          'conversation': {'id': _id, 'player_name': 'سامي'},
          'thread': {'unread': 1, 'has_more': false, 'messages': <Object?>[]},
        });
      }
      if (path.endsWith('/messages')) {
        return okJson(const {
          'id': 9,
          'sender': 'support',
          'body': 'تم',
          'created_at': '2026-10-28T10:00:00.000Z',
        });
      }
      if (path.endsWith('/read')) return okJson(const {'count': 1});
      return okJson(const {'status': 'closed'});
    });
    final AdminApi api = AdminApi(ctx.transport);

    final page = await api.supportConversation(_id, before: 12);
    final reply = await api.replySupport(_id, 'تم');
    final read = await api.markSupportRead(_id);
    final status = await api.setSupportStatus(_id, 'closed');

    expect(
      (page as Ok<SupportConversationPageDto>).value.conversation.playerName,
      'سامي',
    );
    expect((reply as Ok<SupportMessageDto>).value.sender, 'support');
    expect(read, const Result<int>.ok(1));
    expect(status, const Result<String>.ok('closed'));
    expect(ctx.captured[0].url.path, '/admin/support/conversations/$_id');
    expect(ctx.captured[0].url.queryParameters, {'before': '12'});
    expect(ctx.captured[1].method, 'POST');
    expect(
      (jsonDecode(ctx.captured[1].body) as Map<String, Object?>)['body'],
      'تم',
    );
    expect(ctx.captured[2].url.path, '/admin/support/conversations/$_id/read');
    expect(ctx.captured[3].method, 'PATCH');
    expect(
      (jsonDecode(ctx.captured[3].body) as Map<String, Object?>)['status'],
      'closed',
    );
  });

  test(
    'an admin picture goes up as raw bytes; one is read by message',
    () async {
      final List<int> png = <int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ];
      final ctx = buildTransport((request) async {
        if (request.method == 'POST') {
          return okJson(const {
            'id': 4,
            'sender': 'support',
            'body': '',
            'created_at': '2026-10-28T10:00:00.000Z',
            'has_image': true,
          });
        }
        return http.Response.bytes(png, 200);
      });
      final AdminApi api = AdminApi(ctx.transport);

      final sent = await api.replySupportImage(
        _id,
        png,
        contentType: 'image/png',
      );
      final read = await api.supportImage(_id, 4);

      expect((sent as Ok<SupportMessageDto>).value.sender, 'support');
      expect(
        ctx.captured.first.url.path,
        '/admin/support/conversations/$_id/images',
      );
      expect(ctx.captured.first.request.bodyBytes, png);
      expect(
        ctx.captured.last.url.path,
        '/admin/support/conversations/$_id/messages/4/image',
      );
      expect((read as Ok<Uint8List?>).value, png);
    },
  );
}
