/// The home overview counts only fixtures still open for prediction: the
/// current-month feed also carries the month's played fixtures, and the
/// label calls its number available.
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

Map<String, Object?> _item(String id, Duration fromNow) =>
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'Test League',
      seasonLabel: '09/2026',
      fixture: SeasonFixtureCardDto(
        seasonId: 's-1',
        fixtureId: id,
        homeTeam: 'Home Side',
        awayTeam: 'Away Side',
        kickoffAt: DateTime.now().toUtc().add(fromNow).toIso8601String(),
      ),
    ).toJson();

void main() {
  testWidgets('the overview counts only fixtures that have not kicked off', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final List<Map<String, Object?>> feed = <Map<String, Object?>>[
      _item('f-played-1', const Duration(days: -2)),
      _item('f-played-2', const Duration(hours: -3)),
      _item('f-open-1', const Duration(hours: 3)),
      _item('f-open-2', const Duration(days: 2)),
      _item('f-open-3', const Duration(days: 5)),
    ];
    final harness = buildCurrentMonthFixturesHarness((request) async {
      final path = request.url.path;
      if (path == '/feed/current-month-fixtures') return okJsonList(feed);
      if (path == '/me/fixture-predictions' || path == '/teams') {
        return okJsonList(const []);
      }
      // Everything else on the page (seasons, challenge, badge count) may
      // fail; the overview line under test does not depend on it.
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

    expect(find.text('3 مباريات متاحة هذا الشهر'), findsOneWidget);
    expect(find.text('5 مباريات متاحة هذا الشهر'), findsNothing);
  });
}
