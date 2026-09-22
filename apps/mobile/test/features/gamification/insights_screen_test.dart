/// Widget tests for [InsightsScreen] over the real [AuthApi] and
/// [ApiTransport], with only the socket faked ([buildAuthHarness]). The page
/// asks `GET /me/insights` and draws what came back.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/gamification/insights_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _okJson(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _week(String start, int decided, int? percent) =>
    <String, Object?>{
      'week_start': start,
      'decided': decided,
      'correct': 0,
      'exact': 0,
      'percent': percent,
    };

Future<void> _pump(WidgetTester tester, Map<String, Object?> body) async {
  final harness = buildAuthHarness((request) async {
    if (request.url.path == '/me/insights') return _okJson(body);
    return http.Response('not found', 404);
  }, seedToken: 'jwt');
  addTearDown(harness.dispose);
  tester.view.physicalSize = const Size(1080, 2400);
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
        home: const InsightsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data ?? '';

void main() {
  final AppLocalizations ar = lookupAppLocalizations(const Locale('ar'));

  testWidgets('draws the month, the recap and the patterns', (tester) async {
    await _pump(tester, <String, Object?>{
      'schema_version': 1,
      'month': {'decided': 4, 'correct': 3, 'exact': 1, 'percent': 75},
      'community_percent': 58,
      'leagues': <Object?>[],
      'best_league': 'L1',
      'longest_correct_run': 3,
      'weeks': <Object?>[
        for (var i = 0; i < 8; i++) _week('2026-08-0$i', i, i == 0 ? null : 50),
      ],
      'last_week': {
        'week_start': '2026-09-14',
        'decided': 2,
        'correct': 2,
        'exact': 1,
        'percent': 100,
        'points': 4,
        'best': {
          'home_team': 'home',
          'away_team': 'away',
          'points': 3,
          'exact': true,
        },
      },
    });

    expect(_textOf(tester, 'insights.month.percent'), '75%');
    expect(_textOf(tester, 'insights.month.line'), ar.insightsMonthLine(3, 4));
    expect(_textOf(tester, 'insights.community'), ar.insightsCommunity(58));
    expect(_textOf(tester, 'insights.lastWeek'), ar.insightsLastWeek(2, 2, 4));
    expect(
      _textOf(tester, 'insights.best'),
      ar.insightsBestPrediction('home', 'away', 3),
    );
    expect(_textOf(tester, 'insights.bestLeague'), ar.insightsBestLeague('L1'));
    expect(find.byKey(const Key('insights.worstLeague')), findsNothing);
    expect(find.byKey(const Key('insights.weeks')), findsOneWidget);
  });

  testWidgets('a player with nothing decided sees the empty line', (
    tester,
  ) async {
    await _pump(tester, <String, Object?>{
      'schema_version': 1,
      'month': {'decided': 0, 'correct': 0, 'exact': 0, 'percent': null},
      'leagues': <Object?>[],
      'longest_correct_run': 0,
      'weeks': <Object?>[_week('2026-09-21', 0, null)],
    });

    expect(_textOf(tester, 'insights.empty'), ar.insightsEmpty);
  });

  test('a missing percent shows a dash, not zero', () {
    expect(percentText(null), '-');
    expect(percentText(0), '0%');
  });
}
