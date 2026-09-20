/// Widget tests for [DailyChallengeCard] over the real [AuthApi] and the real
/// [ApiTransport], with only the socket faked ([buildAuthHarness]'s
/// `MockClient`). The card is driven exactly as production drives it: it calls
/// `GET /me/daily-challenge` and `GET /me/streak` itself and renders what came
/// back, so a card that stopped asking, or asked the wrong path, fails here.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/gamification/daily_challenge_card.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _okJson(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

/// Answers the two calls the card makes, and nothing else.
Future<http.Response> Function(http.Request) _server({
  required int total,
  required int predicted,
  required bool complete,
  required int current,
  required int longest,
}) {
  return (http.Request request) async {
    switch (request.url.path) {
      case '/me/daily-challenge':
        return _okJson(<String, Object?>{
          'schema_version': 1,
          'day': '2026-09-20',
          'total': total,
          'predicted': predicted,
          'complete': complete,
        });
      case '/me/streak':
        return _okJson(<String, Object?>{
          'schema_version': 1,
          'current': current,
          'longest': longest,
        });
      default:
        return http.Response('not found', 404);
    }
  };
}

Widget _cardUnder(AuthHarness harness, {VoidCallback? onOpenMatches}) =>
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: DailyChallengeCard(onOpenMatches: onOpenMatches ?? () {}),
        ),
      ),
    );

void main() {
  testWidgets('draws the day\'s progress and the streak badge', (tester) async {
    final harness = buildAuthHarness(
      _server(total: 3, predicted: 2, complete: false, current: 5, longest: 9),
      seedToken: 'jwt',
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(_cardUnder(harness));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home.dailyChallenge')), findsOneWidget);
    expect(find.byKey(const Key('home.dailyChallenge.count')), findsOneWidget);
    expect(find.text('2 من 3'), findsOneWidget);
    expect(find.text('السلسلة: 5'), findsOneWidget);
    expect(find.text('الأطول: 9'), findsOneWidget);

    final List<String> paths = harness.captured
        .map((c) => c.request.url.path)
        .toList();
    expect(paths, contains('/me/daily-challenge'));
    expect(paths, contains('/me/streak'));
  });

  testWidgets('a completed day says so and stops inviting a tap', (
    tester,
  ) async {
    var opened = 0;
    final harness = buildAuthHarness(
      _server(total: 2, predicted: 2, complete: true, current: 1, longest: 1),
      seedToken: 'jwt',
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      _cardUnder(harness, onOpenMatches: () => opened += 1),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'أكملت '
        'مباريات '
        'اليوم. أحسنت.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('home.dailyChallenge')));
    await tester.pumpAndSettle();
    expect(opened, 0);
  });

  testWidgets('a rest day with no streak shows nothing at all', (tester) async {
    final harness = buildAuthHarness(
      _server(total: 0, predicted: 0, complete: false, current: 0, longest: 0),
      seedToken: 'jwt',
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(_cardUnder(harness));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home.dailyChallenge')), findsNothing);
  });
}
