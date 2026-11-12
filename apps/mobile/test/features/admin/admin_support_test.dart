/// «رسائل الدعم» (migration 0187, script 167), through the real
/// [AdminSupportSection], [AdminSupportConversationScreen], [AdminApi] and
/// [ApiTransport] against a fake of the server's admin routes.
library;

import 'dart:convert';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/screens/sections/admin_support_section.dart';
import 'package:mobile/features/support/support_images.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';
import '../support/support_fake_server.dart';

const String _c1 = 'aaaaaaaa-0000-4000-8000-000000000001';
const String _c2 = 'aaaaaaaa-0000-4000-8000-000000000002';

/// The admin routes of script 165, over two conversations.
final class _FakeAdminSupport {
  final Map<String, Map<String, Object?>> conversations =
      <String, Map<String, Object?>>{
        _c1: <String, Object?>{
          'id': _c1,
          'player_id': 'p-1',
          'player_name': 'سامي',
          'status': 'open',
          'last_message_at': '2026-10-28T10:05:00.000Z',
          'last_message_preview': 'التطبيق لا يحفظ',
          'last_sender': 'player',
          'support_unread': 2,
          'player_unread': 0,
        },
        _c2: <String, Object?>{
          'id': _c2,
          'player_id': 'p-2',
          'player_name': 'خالد',
          'status': 'closed',
          'last_message_at': '2026-10-27T10:00:00.000Z',
          'last_message_preview': 'شكرًا',
          'last_sender': 'support',
          'support_unread': 0,
          'player_unread': 0,
        },
      };
  final Map<String, List<Map<String, Object?>>> messages =
      <String, List<Map<String, Object?>>>{
        _c1: <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'sender': 'player',
            'body': 'التطبيق لا يحفظ توقعي',
            'created_at': '2026-10-28T10:00:00.000Z',
          },
          <String, Object?>{
            'id': 2,
            'sender': 'player',
            'body': 'التطبيق لا يحفظ',
            'created_at': '2026-10-28T10:05:00.000Z',
          },
        ],
        _c2: <Map<String, Object?>>[],
      };
  final List<String> calls = <String>[];
  final Map<int, List<int>> images = <int, List<int>>{};

  /// The reasons support gave to read a player's open predictions.
  final List<String> peekReasons = <String>[];
  int _nextId = 3;

  http.Response _json(Object body, [int code = 200]) => http.Response(
    jsonEncode(body),
    code,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  Future<http.Response> handle(http.Request request) async {
    final Uri url = request.url;
    calls.add(
      '${request.method} ${url.path}'
      '${url.query.isEmpty ? '' : '?${Uri.decodeQueryComponent(url.query)}'}',
    );
    final List<String> parts = url.pathSegments;
    if (url.path == '/admin/support/conversations') {
      final String filter = url.queryParameters['filter'] ?? 'all';
      final String search = url.queryParameters['search'] ?? '';
      final List<Map<String, Object?>> list =
          conversations.values
              .where(
                (c) => switch (filter) {
                  'unread' => (c['support_unread']! as int) > 0,
                  'open' => c['status'] == 'open',
                  'closed' => c['status'] != 'open',
                  _ => true,
                },
              )
              .where((c) => (c['player_name']! as String).contains(search))
              .toList()
            ..sort(
              (a, b) => (b['last_message_at']! as String).compareTo(
                a['last_message_at']! as String,
              ),
            );
      return _json(<String, Object?>{
        'unread_conversations': conversations.values
            .where((c) => (c['support_unread']! as int) > 0)
            .length,
        'conversations': list,
      });
    }
    if (parts.length >= 4 && parts[0] == 'admin' && parts[1] == 'support') {
      final String id = parts[3];
      final Map<String, Object?>? c = conversations[id];
      if (c == null) {
        return _json(<String, Object?>{
          'code': 'support.conversation_not_found',
          'message': 'المحادثة غير موجودة.',
        }, 409);
      }
      final List<Map<String, Object?>> thread = messages[id]!;
      if (parts.length == 4 && request.method == 'GET') {
        return _json(<String, Object?>{
          'conversation': c,
          'thread': <String, Object?>{
            'status': c['status'],
            'unread': c['support_unread'],
            'has_more': false,
            'messages': thread,
          },
        });
      }
      if (parts.length == 4 && request.method == 'PATCH') {
        final String status =
            (jsonDecode(request.body) as Map<String, Object?>)['status']!
                as String;
        c['status'] = status;
        return _json(<String, Object?>{'status': status});
      }
      if (parts.length == 5 && parts[4] == 'read') {
        final int marked = c['support_unread']! as int;
        c['support_unread'] = 0;
        for (final Map<String, Object?> m in thread) {
          if (m['sender'] == 'player') m['read_at'] = '2026-10-28T11:00:00Z';
        }
        return _json(<String, Object?>{'count': marked});
      }
      if (parts.length == 5 && parts[4] == 'images') {
        final Map<String, Object?> m = <String, Object?>{
          'id': _nextId++,
          'sender': 'support',
          'body': '',
          'created_at': '2026-10-28T11:00:00.000Z',
          'has_image': true,
        };
        thread.add(m);
        images[m['id']! as int] = request.bodyBytes;
        return _json(m, 201);
      }
      if (parts.length == 7 && parts[6] == 'image') {
        final List<int>? bytes = images[int.parse(parts[5])];
        return bytes == null
            ? http.Response('', 404)
            : http.Response.bytes(bytes, 200);
      }
      // Script 261: support reads the player's open predictions; the
      // player is told by a support answer.
      if (parts.length == 5 && parts[4] == 'predictions') {
        if (!thread.any((m) => m['sender'] == 'player')) {
          return _json(<String, Object?>{
            'code': 'support.peek_needs_player_message',
            'message':
                'يُتاح الاطلاع بعد أن يراسل اللاعب الدعم في هذه المحادثة.',
          }, 409);
        }
        peekReasons.add(
          (jsonDecode(request.body) as Map<String, Object?>)['reason']!
              as String,
        );
        final Map<String, Object?> notice = <String, Object?>{
          'id': _nextId++,
          'sender': 'support',
          'body': 'اطّلع فريق الدعم على توقعاتك للمباريات التي لم تبدأ بعد.',
          'created_at': '2026-10-28T11:00:00.000Z',
        };
        thread.add(notice);
        return _json(<String, Object?>{
          'schema_version': 1,
          'predictions': <Object?>[
            <String, Object?>{
              'fixture_id': 'ffffffff-0000-4000-8000-000000000001',
              'home_team': 'الهلال',
              'away_team': 'النصر',
              'kickoff_at': '2026-10-28T18:00:00.000Z',
              'home_goals': 2,
              'away_goals': 1,
              'is_double': true,
              'league_name': 'دوري روشن',
            },
          ],
          'notice': notice,
        });
      }
      if (parts.length == 5 && parts[4] == 'messages') {
        final String body =
            (jsonDecode(request.body) as Map<String, Object?>)['body']!
                as String;
        final Map<String, Object?> m = <String, Object?>{
          'id': _nextId++,
          'sender': 'support',
          'body': body,
          'created_at': '2026-10-28T11:00:00.000Z',
        };
        thread.add(m);
        c['last_sender'] = 'support';
        c['last_message_preview'] = body;
        return _json(m, 201);
      }
    }
    return http.Response('not found', 404);
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeAdminSupport server, {
  double textScale = 1,
  Size size = const Size(1080, 2400),
}) async {
  final AuthHarness harness = buildAuthHarness(server.handle, seedToken: 'jwt');
  addTearDown(harness.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...harness.overrides,
        supportImagePickerProvider.overrideWithValue(
          () async => SupportPickedImage(
            bytes: Uint8List.fromList(FakeSupportServer.png),
            mime: 'image/png',
          ),
        ),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: AdminSupportSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the inbox: newest first, the waiting count, filters, search', (
    tester,
  ) async {
    final _FakeAdminSupport server = _FakeAdminSupport();
    await _pump(tester, server);

    final double sami = tester.getTopLeft(find.text('سامي')).dy;
    final double khaled = tester.getTopLeft(find.text('خالد')).dy;
    expect(sami, lessThan(khaled), reason: 'the latest message first');
    expect(
      find.descendant(
        of: find.byKey(const Key('admin.support.unread.$_c1')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(find.text('غير مقروءة (1)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin.support.filter.3')));
    await tester.pumpAndSettle();
    expect(server.calls.last, 'GET /admin/support/conversations?filter=closed');
    expect(find.text('خالد'), findsOneWidget);
    expect(find.text('سامي'), findsNothing);

    await tester.tap(find.byKey(const Key('admin.support.filter.0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('admin.support.search')), 'خا');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(
      server.calls.last,
      'GET /admin/support/conversations?filter=all&search=خا',
    );
    expect(find.text('سامي'), findsNothing);
  });

  testWidgets('an admin opens a conversation, reads it, answers as support', (
    tester,
  ) async {
    final _FakeAdminSupport server = _FakeAdminSupport();
    await _pump(tester, server);

    await tester.tap(find.byKey(const Key('admin.support.conversation.$_c1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin.support.thread.title')), findsOneWidget);
    expect(find.text('التطبيق لا يحفظ توقعي'), findsOneWidget);
    expect(
      server.calls,
      contains('POST /admin/support/conversations/$_c1/read'),
    );

    // The player's messages on the far side, the answer on the admin's.
    await tester.enterText(
      find.byKey(const Key('support.input')),
      'تم الإصلاح، حدّث التطبيق',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('support.send')));
    await tester.pumpAndSettle();

    expect(server.messages[_c1]!.last['body'], 'تم الإصلاح، حدّث التطبيق');
    expect(find.byKey(const Key('support.status.sent')), findsOneWidget);
    final double answer = tester
        .getCenter(find.text('تم الإصلاح، حدّث التطبيق'))
        .dx;
    final double question = tester
        .getCenter(find.text('التطبيق لا يحفظ توقعي'))
        .dx;
    expect(answer, greaterThan(question));

    // Back in the inbox, the conversation no longer waits.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin.support.unread.$_c1')), findsNothing);
  });

  testWidgets('support reads the open predictions, for a reason, and the '
      'player is told (script 262)', (tester) async {
    final _FakeAdminSupport server = _FakeAdminSupport();
    await _pump(tester, server);
    await tester.tap(find.byKey(const Key('admin.support.conversation.$_c1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin.support.thread.peek')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin.support.peek.notice')), findsOneWidget);
    // No reason, no reading.
    await tester.tap(find.byKey(const Key('admin.support.peek.confirm')));
    await tester.pumpAndSettle();
    expect(server.peekReasons, isEmpty);
    await tester.enterText(
      find.byKey(const Key('admin.support.peek.reason')),
      'يقول إن توقعه لم يُحفظ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('admin.support.peek.confirm')));
    await tester.pumpAndSettle();

    expect(server.peekReasons, <String>['يقول إن توقعه لم يُحفظ']);
    expect(
      find.byKey(
        const Key(
          'admin.support.peek.line.ffffffff-0000-4000-8000-000000000001',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('الهلال - النصر'), findsOneWidget);
    expect(find.text('توقعه: 2-1 · دبل'), findsOneWidget);
    expect(find.textContaining('اطّلع فريق الدعم على توقعاتك'), findsOneWidget);
  });

  testWidgets('cancelling reads nothing', (tester) async {
    final _FakeAdminSupport server = _FakeAdminSupport();
    await _pump(tester, server);
    await tester.tap(find.byKey(const Key('admin.support.conversation.$_c1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin.support.thread.peek')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.support.peek.cancel')));
    await tester.pumpAndSettle();

    expect(server.peekReasons, isEmpty);
    expect(server.calls.where((c) => c.endsWith('/predictions')), isEmpty);
  });

  testWidgets('before the player writes, the server refusal is shown', (
    tester,
  ) async {
    final _FakeAdminSupport server = _FakeAdminSupport();
    await _pump(tester, server);
    await tester.tap(find.byKey(const Key('admin.support.filter.0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.support.conversation.$_c2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin.support.thread.peek')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin.support.peek.reason')),
      'سبب',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('admin.support.peek.confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text('يُتاح الاطلاع بعد أن يراسل اللاعب الدعم في هذه المحادثة.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('admin.support.peek.list')), findsNothing);
  });

  testWidgets('closing asks first; a closed one can be reopened', (
    tester,
  ) async {
    final _FakeAdminSupport server = _FakeAdminSupport();
    await _pump(tester, server);
    await tester.tap(find.byKey(const Key('admin.support.conversation.$_c1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin.support.thread.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.support.thread.close')));
    await tester.pumpAndSettle();
    expect(find.text('إغلاق المحادثة؟'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(server.conversations[_c1]!['status'], 'open');

    await tester.tap(find.byKey(const Key('admin.support.thread.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.support.thread.close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    expect(server.conversations[_c1]!['status'], 'closed');
    expect(
      find.byKey(const Key('admin.support.thread.status')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('admin.support.thread.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.support.thread.reopen')));
    await tester.pumpAndSettle();
    expect(server.conversations[_c1]!['status'], 'open');
    expect(find.byKey(const Key('admin.support.thread.status')), findsNothing);
  });

  testWidgets('the inbox holds at text x2 on a 360px phone', (tester) async {
    await _pump(
      tester,
      _FakeAdminSupport(),
      textScale: 2,
      size: const Size(360, 1600),
    );

    expect(find.byKey(const Key('admin.support.list')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a conversation holds at text x2 on a 360px phone', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeAdminSupport(),
      textScale: 2,
      size: const Size(360, 1600),
    );
    await tester.tap(find.byKey(const Key('admin.support.conversation.$_c1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin.support.thread.list')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an admin answers with a picture; stored ones are drawn', (
    tester,
  ) async {
    final _FakeAdminSupport server = _FakeAdminSupport();
    await _pump(tester, server);
    await tester.tap(find.byKey(const Key('admin.support.conversation.$_c1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('support.attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('support.image.send')));
    await tester.pumpAndSettle();

    expect(server.images.values.single, FakeSupportServer.png);
    expect(find.byKey(const Key('support.image')), findsOneWidget);

    // Read again from the server, the picture comes by its message.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.support.conversation.$_c1')));
    await tester.pumpAndSettle();
    expect(
      server.calls.where((c) => c.endsWith('/messages/3/image')),
      isNotEmpty,
    );
    expect(find.byKey(const Key('support.image')), findsOneWidget);
  });
}
