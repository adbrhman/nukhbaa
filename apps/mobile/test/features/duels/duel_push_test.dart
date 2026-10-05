/// The path from a duel push to the prediction, through the real providers
/// and the real `DuelsApi` over the auth harness's fake server: a tapped
/// `duel:CODE` push opens the accept sheet without typing the code; the
/// challenge sheet finds a player by name and sends them a private
/// challenge; an inbox row about a duel opens the Duels page.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/duels/create_duel_sheet.dart';
import 'package:mobile/features/duels/duels_screen.dart';
import 'package:mobile/features/notifications/notifications_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _code = 'ABCDEFGHJKMN';
const String _rivalId = 'u-badr';

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _challenge({required bool isPrivate}) => <String, Object?>{
  'schema_version': 1,
  'id': 'c-1',
  'code': _code,
  'season_id': 's-1',
  'fixture_id': 'f-1',
  'home_team': 'Home FC',
  'away_team': 'Away FC',
  'kickoff_at': '2099-01-01T18:00:00.000Z',
  'challenger_user_id': isPrivate ? 'me' : 'rival',
  'challenger_name': isPrivate ? 'Me' : 'Rival',
  'is_private': isPrivate,
  'capacity': 1,
  'accepted_count': 0,
  'state': 'open',
  'is_mine': isPrivate,
  'is_for_me': !isPrivate,
};

/// Answers the duel and inbox routes and records what reached them.
final class _Server {
  final List<http.Request> requests = <http.Request>[];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/me/duels') {
      return _json(const <String, Object?>{
        'schema_version': 1,
        'challenges': <Object?>[],
        'duels': <Object?>[],
      });
    }
    if (path == '/me/fixture-predictions') {
      return _json(const <Object?>[]);
    }
    if (path == '/duels/codes/$_code') {
      return _json(_challenge(isPrivate: false));
    }
    if (path == '/duels/players') {
      return _json(const <String, Object?>{
        'schema_version': 1,
        'players': <Object?>[
          <String, Object?>{'user_id': _rivalId, 'display_name': 'Badr'},
        ],
      });
    }
    if (path == '/duels/challenges' && request.method == 'POST') {
      return _json(_challenge(isPrivate: true), status: 201);
    }
    if (path == '/notifications/n1/read') {
      return _json(const <String, Object?>{'read': true});
    }
    if (path == '/notifications') {
      return _json(const <String, Object?>{
        'schema_version': 2,
        'recipient_id': 'me',
        'unread_count': 1,
        'notifications': <Object?>[
          <String, Object?>{
            'schema_version': 2,
            'id': 'n1',
            'recipient_id': 'me',
            'kind': 'duel_challenged',
            'read': false,
            'created_at': '2026-10-05T12:00:00Z',
            'actor_user_id': 'rival',
          },
        ],
      });
    }
    return okMe(sampleUser);
  }
}

Future<void> _pump(WidgetTester tester, _Server server, Widget home) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildAuthHarness(server.handle, seedToken: 'saved-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        home: home,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a tapped duel push opens the accept sheet with no code typed', (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server, const DuelsScreen(openCode: _code));

    expect(find.byKey(const Key('acceptDuel.sheet')), findsOneWidget);
    expect(
      server.requests.where((r) => r.url.path == '/duels/codes/$_code'),
      hasLength(1),
    );
  });

  testWidgets('a player found by name gets a private challenge', (
    tester,
  ) async {
    final server = _Server();
    await _pump(
      tester,
      server,
      const Scaffold(
        body: CreateDuelSheet(
          seasonId: 's-1',
          fixtureId: 'f-1',
          homeTeam: 'Home FC',
          awayTeam: 'Away FC',
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('createDuel.search')), 'Ba');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final http.Request search = server.requests.lastWhere(
      (r) => r.url.path == '/duels/players',
    );
    expect(search.url.queryParameters['q'], 'Ba');

    await tester.tap(find.byKey(const Key('createDuel.player.$_rivalId')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('createDuel.target')), findsOneWidget);

    await tester.tap(find.byKey(const Key('createDuel.create')));
    await tester.pumpAndSettle();

    final http.Request create = server.requests.lastWhere(
      (r) => r.url.path == '/duels/challenges',
    );
    final Map<String, Object?> body =
        jsonDecode(create.body) as Map<String, Object?>;
    expect(body['target_user_id'], _rivalId);
    expect(body['capacity'], 1);
    expect(find.byKey(const Key('createDuel.sent')), findsOneWidget);
  });

  testWidgets('a short name searches nothing', (tester) async {
    final server = _Server();
    await _pump(
      tester,
      server,
      const Scaffold(
        body: CreateDuelSheet(
          seasonId: 's-1',
          fixtureId: 'f-1',
          homeTeam: 'Home FC',
          awayTeam: 'Away FC',
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('createDuel.search')), 'B');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(
      server.requests.where((r) => r.url.path == '/duels/players'),
      isEmpty,
    );
  });

  testWidgets('an inbox row about a duel opens the Duels page', (tester) async {
    final server = _Server();
    await _pump(tester, server, const NotificationsScreen());

    await tester.tap(find.byKey(const Key('notifications.item.n1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('duels.screen')), findsOneWidget);
  });
}
