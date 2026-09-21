/// Widget tests for [MyBadgesScreen] over the real [AuthApi] and the real
/// [ApiTransport], with only the socket faked ([buildAuthHarness]'s
/// `MockClient`). The screen asks `GET /me/badges` through
/// `myBadgesProvider` and draws what came back, so a screen that stopped
/// asking, asked the wrong path, or decided a badge on its own fails here.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/gamification/my_badges_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const List<String> _catalog = <String>[
  'first_prediction',
  'predictions_25',
  'predictions_100',
  'first_perfect_day',
  'perfect_days_7',
  'perfect_days_30',
  'league_first_week',
  'league_promoted',
  'league_champion',
  'league_elite',
];

http.Response _okJson(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

/// The whole catalog, one badge held, the caller seven predictions in, and
/// a code this build has never heard of.
final Map<String, Object?> _wall = <String, Object?>{
  'schema_version': 1,
  'badges': <Map<String, Object?>>[
    for (final String code in _catalog)
      <String, Object?>{
        'code': code,
        'current': switch (code) {
          'first_prediction' => 1,
          'predictions_25' || 'predictions_100' => 7,
          _ => 0,
        },
        'target': switch (code) {
          'predictions_25' => 25,
          'predictions_100' => 100,
          'perfect_days_7' => 7,
          'perfect_days_30' => 30,
          _ => 1,
        },
        'unlocked_at': code == 'first_prediction'
            ? '2026-09-20T08:00:00.000Z'
            : null,
      },
    <String, Object?>{
      'code': 'badge_from_the_future',
      'current': 0,
      'target': 1,
      'unlocked_at': null,
    },
  ],
};

Future<void> _pump(WidgetTester tester, AuthHarness harness) async {
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const MyBadgesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data ?? '';

void main() {
  final AppLocalizations ar = lookupAppLocalizations(const Locale('ar'));

  testWidgets('draws every known badge, held or on its way', (tester) async {
    final harness = buildAuthHarness((request) async {
      if (request.url.path == '/me/badges') return _okJson(_wall);
      return http.Response('not found', 404);
    }, seedToken: 'jwt');
    addTearDown(harness.dispose);

    await _pump(tester, harness);

    expect(
      harness.captured.map((c) => c.request.url.path),
      contains('/me/badges'),
    );
    expect(_textOf(tester, 'badges.summary'), ar.badgeWallSummary(1, 10));
    for (final String code in _catalog) {
      expect(find.byKey(Key('badges.item.$code')), findsOneWidget);
    }
    expect(
      find.byKey(const Key('badges.item.badge_from_the_future')),
      findsNothing,
    );

    expect(
      _textOf(tester, 'badges.name.first_prediction'),
      ar.badgeWallFirstPredictionName,
    );
    expect(
      find.byKey(const Key('badges.unlocked.first_prediction')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('badges.progress.first_prediction')),
      findsNothing,
    );

    expect(
      _textOf(tester, 'badges.progress.predictions_25'),
      ar.badgeWallProgress(7, 25),
    );
    expect(
      find.byKey(const Key('badges.unlocked.predictions_25')),
      findsNothing,
    );
  });

  testWidgets('a failed read offers a retry that asks the server again', (
    tester,
  ) async {
    var calls = 0;
    final harness = buildAuthHarness((request) async {
      if (request.url.path != '/me/badges') {
        return http.Response('not found', 404);
      }
      calls += 1;
      if (calls == 1) {
        return errorEnvelope(503, 'server.unavailable', 'try later');
      }
      return _okJson(_wall);
    }, seedToken: 'jwt');
    addTearDown(harness.dispose);

    await _pump(tester, harness);

    expect(find.byKey(const Key('browse.error')), findsOneWidget);
    await tester.tap(find.byKey(const Key('browse.error.retry')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(_textOf(tester, 'badges.summary'), ar.badgeWallSummary(1, 10));
  });

  test('every catalog code has its own name and hint', () {
    final Set<String> names = <String>{};
    final Set<String> hints = <String>{};
    for (final String code in _catalog) {
      final look = badgeLookOf(ar, code);
      expect(look, isNotNull, reason: code);
      names.add(look!.name);
      hints.add(look.description);
    }
    expect(names, hasLength(_catalog.length));
    expect(hints, hasLength(_catalog.length));
    expect(badgeLookOf(ar, 'badge_from_the_future'), isNull);
  });
}
