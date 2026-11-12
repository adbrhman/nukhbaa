/// The admin's new-players page (script 202) through its real provider and
/// the real `AdminApi`, over the auth harness's fake server: each player
/// with why his name may be borrowed and the accounts on his phone; a tap
/// opens the ready message asking for his real name, sent to his support
/// chat. Also the push link that opens it, and a 360px phone at text x2.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/notifications/push_link.dart';
import 'package:mobile/features/admin/screens/sections/new_players_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _a = '11111111-1111-4111-8111-111111111111';
const String _b = '22222222-2222-4222-8222-222222222222';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

final class _Server {
  final List<http.Request> requests = <http.Request>[];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/admin/new-players') {
      return _json(const {
        'schema_version': 1,
        'days': 7,
        'players': [
          {
            'user': {
              'schema_version': 1,
              'id': _a,
              'email': 'adil19792025@gmail.com',
              'display_name': 'ملك التوقعات',
              'status': 'active',
            },
            'joined_at': '2026-11-02T13:01:54.000Z',
            'phone_accounts': 11,
            'predictions': 10,
            'name_hint': 'title',
          },
          {
            'user': {
              'schema_version': 1,
              'id': _b,
              'email': 'm@t.io',
              'display_name': 'محمد علي',
              'status': 'active',
            },
            'joined_at': '2026-11-01T09:00:00.000Z',
            'phone_accounts': 1,
            'predictions': 3,
            // Script 263: an account with the same first and last name.
            'similar_to': ['محمد بن علي'],
          },
        ],
      });
    }
    if (path == '/admin/support/players/$_a/messages') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      return _json({
        'schema_version': 1,
        'id': 1,
        'sender': 'support',
        'body': body['body'],
        'created_at': '2026-11-02T14:00:00.000Z',
      }, 201);
    }
    return okMe(sampleUser);
  }

  List<http.Request> to(String path) => [
    for (final r in requests)
      if (r.url.path == path) r,
  ];
}

Future<void> _open(
  WidgetTester tester,
  _Server server, {
  double textScale = 1.0,
}) async {
  const Size size = Size(1080, 2340);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildAuthHarness(server.handle, seedToken: 'admin-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        locale: const Locale('ar'),
        home: MediaQuery(
          data: MediaQueryData(
            size: size / 3.0,
            textScaler: TextScaler.linear(textScale),
          ),
          child: const Scaffold(body: NewPlayersSection()),
        ),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  test('the new-player push opens the account tab, where the list goes', () {
    expect(PushLinks.newPlayers, 'new_players');
    expect(shellTabForLink(PushLinks.newPlayers), 4);
  });

  testWidgets('lists each player with his hint and his phone', (tester) async {
    await _open(tester, _Server());

    expect(find.text('سجّل 2 في آخر 7 أيام'), findsOneWidget);
    expect(find.text('ملك التوقعات'), findsOneWidget);
    expect(find.text('لقب لا اسم'), findsOneWidget);
    expect(find.text('11 حسابات على هاتفه'), findsOneWidget);
    // A real-looking name on a phone of its own carries neither.
    expect(find.byKey(const Key('admin.newPlayers.hint.$_b')), findsNothing);
    expect(find.byKey(const Key('admin.newPlayers.phone.$_b')), findsNothing);
  });

  testWidgets('a name like another account says so (script 264)', (
    tester,
  ) async {
    await _open(tester, _Server());

    expect(
      find.descendant(
        of: find.byKey(const Key('admin.newPlayers.similar.$_b')),
        matching: find.text('يشبه: «محمد بن علي»'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('admin.newPlayers.similar.$_a')), findsNothing);
  });

  testWidgets('a tap opens the ready message; sending writes to his '
      'support chat', (tester) async {
    final server = _Server();
    await _open(tester, server);

    await _tapVisible(tester, const Key('admin.newPlayers.open.$_a'));
    final TextField field = tester.widget<TextField>(
      find.byKey(const Key('admin.newPlayers.message')),
    );
    expect(field.controller!.text, contains('«ملك التوقعات»'));
    expect(field.controller!.text, contains('اسمك الأول واسم عائلتك'));

    await _tapVisible(tester, const Key('admin.newPlayers.send'));

    final sent = server.to('/admin/support/players/$_a/messages').single;
    expect(sent.method, 'POST');
    expect(
      (jsonDecode(sent.body) as Map<String, Object?>)['body'],
      contains('«ملك التوقعات»'),
    );
    expect(
      find.text('أُرسلت الرسالة إلى «ملك التوقعات» في محادثة الدعم'),
      findsOneWidget,
    );
  });

  testWidgets('an emptied message is not sent', (tester) async {
    final server = _Server();
    await _open(tester, server);
    await _tapVisible(tester, const Key('admin.newPlayers.open.$_a'));

    await tester.enterText(
      find.byKey(const Key('admin.newPlayers.message')),
      '  ',
    );
    await _tapVisible(tester, const Key('admin.newPlayers.send'));

    expect(find.text('اكتب الرسالة أولاً'), findsOneWidget);
    expect(server.to('/admin/support/players/$_a/messages'), isEmpty);
  });

  testWidgets('fits a 360px phone at text x2', (tester) async {
    await _open(tester, _Server(), textScale: 2.0);
    await tester.scrollUntilVisible(
      find.byKey(const Key('admin.newPlayers.open.$_a')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('admin.newPlayers.list')),
        matching: find.byType(Scrollable),
      ),
    );
    await _tapVisible(tester, const Key('admin.newPlayers.open.$_a'));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('admin.newPlayers.send')), findsOneWidget);
  });
}
