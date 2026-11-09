/// The automatic crowning in the admin's crowning section (script 204),
/// through the real section, its real providers and the real `AdminApi`,
/// over the auth harness's fake server: the card says what the server does
/// by itself and has no prize field (no cash prizes at launch, decided
/// 2026-11-09); a crowning by hand (a tie for first) carries no prize.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/champion_admin_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

final class _Server {
  final List<http.Request> requests = <http.Request>[];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/months') {
      return _json(<Object?>[
        <String, Object?>{
          'id': 'm-11',
          'competition_id': 'c-1',
          'label': '11/2026',
          'start_at': '2026-10-31T21:00:00Z',
          'end_at': '2026-11-30T21:00:00Z',
        },
      ]);
    }
    if (path == '/admin/champions/m-11' && request.method == 'GET') {
      return _json(<String, Object?>{
        'schema_version': 1,
        'season_id': 'm-11',
        'season_label': '11/2026',
        'ended': true,
        'unscored_fixtures': 0,
        'crowned': <String>[],
        'candidates': <Map<String, Object?>>[
          // A tie for first: both are ranked first, the owner decides.
          <String, Object?>{
            'rank': 1,
            'user_id': 'u-1',
            'display_name': 'Ahmad',
            'points': 18,
            'exact_count': 5,
            'decided_count': 30,
          },
          <String, Object?>{
            'rank': 1,
            'user_id': 'u-2',
            'display_name': 'Sinan',
            'points': 18,
            'exact_count': 5,
            'decided_count': 30,
          },
        ],
      });
    }
    if (path == '/admin/champions/m-11' && request.method == 'POST') {
      return _json(<String, Object?>{
        'schema_version': 1,
        'champions': <Object?>[],
      });
    }
    if (path == '/me/active-seasons') {
      return _json(<Object?>[]);
    }
    if (path == '/champions') {
      return _json(<String, Object?>{
        'schema_version': 1,
        'champions': <Object?>[],
        'podium': <Object?>[],
      });
    }
    return http.Response('not found', 404);
  }
}

Future<void> _open(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final harness = buildAuthHarness(server.handle, seedToken: 'admin-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(body: ChampionAdminSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('admin.fixtures.monthField.field')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const Key('admin.fixtures.monthField.m-11')).last,
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the card says what the server does and has no prize field', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server);

    await _scrollTo(tester, find.byKey(const Key('admin.champions.auto')));
    expect(find.text('التتويج التلقائي'), findsOneWidget);
    expect(
      find.byKey(const Key('admin.champions.plannedPrizeField')),
      findsNothing,
    );
    expect(find.byKey(const Key('admin.champions.savePrize')), findsNothing);
  });

  testWidgets('a tie for first is crowned by hand, without a prize', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server);

    // Both level players can be chosen.
    for (final String id in <String>['u-1', 'u-2']) {
      expect(
        tester
            .widget<Checkbox>(find.byKey(Key('admin.champions.choose.$id')))
            .onChanged,
        isNotNull,
      );
    }
    await tester.tap(find.byKey(const Key('admin.champions.choose.u-2')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('admin.champions.crown')));
    await tester.tap(find.byKey(const Key('admin.champions.crown')));
    await tester.pumpAndSettle();
    expect(find.textContaining('الجائزة'), findsNothing);
    await tester.tap(find.text('تتويج'));
    await tester.pumpAndSettle();

    final http.Request crown = server.requests.firstWhere(
      (r) => r.method == 'POST' && r.url.path == '/admin/champions/m-11',
    );
    expect(jsonDecode(crown.body), <String, Object?>{
      'user_ids': <Object?>['u-2'],
      'force': false,
    });
  });
}
