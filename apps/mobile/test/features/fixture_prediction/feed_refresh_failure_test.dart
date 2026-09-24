/// Coming back to the matches tab from the background: the minute tick
/// refreshes the feed at once, and when that one refresh fails the list the
/// user was looking at stays -- it is not replaced by "could not reach the
/// server". Only a first load with nothing to show falls back to the error.
/// Pumped through the real [CurrentMonthFixturesScreen].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_providers.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

void main() {
  bool offline = false;

  CurrentMonthFixturesHarness harness() =>
      buildCurrentMonthFixturesHarness((request) async {
        final String path = request.url.path;
        if (offline) throw Exception('Connection closed');
        if (path == '/feed/current-month-fixtures') {
          return okJsonList(<Object?>[sampleFeedItem.toJson()]);
        }
        if (path == '/seasons/s-1/fixtures/f-1/prediction-distribution') {
          return okJsonObject(const <String, Object?>{
            'schema_version': 1,
            'home_win_percentage': 68,
            'away_win_percentage': 32,
          });
        }
        if (path == '/me/fixture-predictions' || path == '/teams') {
          return okJsonList(const <Object?>[]);
        }
        throw StateError('Unexpected request: ${request.method} $path');
      });

  Future<void> pump(WidgetTester tester, CurrentMonthFixturesHarness h) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: h.overrides,
        retry: (retryCount, error) => null,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const CurrentMonthFixturesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const Key card = Key('currentMonthFixtures.home.increment.f-1');
  const Key error = Key('currentMonthFixtures.error');

  testWidgets('a failed refresh keeps the list on screen', (tester) async {
    offline = false;
    final h = harness();
    addTearDown(h.dispose);
    await pump(tester, h);
    expect(find.byKey(card), findsOneWidget);

    offline = true;
    ProviderScope.containerOf(
      tester.element(find.byType(CurrentMonthFixturesScreen)),
    ).invalidate(currentMonthFixturesProvider);
    await tester.pumpAndSettle();

    expect(find.byKey(card), findsOneWidget);
    expect(find.byKey(error), findsNothing);
  });

  testWidgets('a first load that fails still shows the error', (tester) async {
    offline = true;
    final h = harness();
    addTearDown(h.dispose);
    await pump(tester, h);

    expect(find.byKey(error), findsOneWidget);
    expect(find.byKey(card), findsNothing);
  });
}
