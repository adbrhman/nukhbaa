/// The home overview when the month's matches cannot be read (audit M-06):
/// it says so and offers a retry, instead of "updating your matches..." for
/// ever, and the retry brings the count back.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/auth/home_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart' show sampleUser;
import '../../support/current_month_fixtures_harness.dart';

Map<String, Object?> _item(String id) => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'Test League',
  seasonLabel: '10/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: id,
    homeTeam: 'Home Side',
    awayTeam: 'Away Side',
    kickoffAt: DateTime.now()
        .toUtc()
        .add(const Duration(days: 2))
        .toIso8601String(),
  ),
).toJson();

void main() {
  testWidgets('a failed read says so, and the retry brings the count back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var offline = true;
    final harness = buildCurrentMonthFixturesHarness((request) async {
      final path = request.url.path;
      if (path == '/feed/current-month-fixtures') {
        if (offline) throw Exception('offline');
        return okJsonList(<Map<String, Object?>>[_item('f-1'), _item('f-2')]);
      }
      if (path == '/me/fixture-predictions' || path == '/teams') {
        return okJsonList(const []);
      }
      return http.Response('not found', 404);
    });
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        retry: (retryCount, error) => null,
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: HomeScreen(
            user: sampleUser,
            onOpenMatches: () {},
            onOpenAccount: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('جارٍ تحديث مبارياتك...'), findsNothing);
    expect(find.byKey(const Key('home.overview.error')), findsOneWidget);
    final Finder retry = find.byKey(const Key('home.overview.retry'));
    expect(retry, findsOneWidget);

    offline = false;
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home.overview.error')), findsNothing);
    expect(find.text('مباراتان متاحتان هذا الشهر'), findsOneWidget);
  });
}
