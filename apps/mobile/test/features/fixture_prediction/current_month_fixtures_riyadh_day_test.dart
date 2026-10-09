/// Two matches of one Riyadh day are listed on one day of the matches tab,
/// whatever zone the device is in.
///
/// The tab used to file a match under the device's own calendar day. For a
/// player in the Emirates a 23:30 Riyadh kickoff fell on the next day; for
/// one in Egypt or Morocco a 00:30 kickoff fell on the day before. The
/// server counts both on the Riyadh day (one double a day, the daily
/// challenge), so a double the strip showed on two days was refused as two
/// on one.
///
/// The edge match is placed where the device's own calendar would move it:
/// 23:30 Riyadh on a device east of Riyadh, 00:30 Riyadh on one west of it.
/// On a device at exactly UTC+3 the two calendars agree and this test cannot
/// tell them apart, which is why `48_one_match_day.sh` also runs it with
/// TZ=UTC.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/time/riyadh_day_turnover.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/features/fixture_prediction/widgets/fotmob_match_card.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

Map<String, Object?> _item(String id, DateTime kickoffUtc) =>
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'Test League',
      seasonLabel: '10/2026',
      fixture: SeasonFixtureCardDto(
        seasonId: 's-1',
        fixtureId: id,
        homeTeam: 'Arsenal',
        awayTeam: 'Chelsea',
        kickoffAt: kickoffUtc.toIso8601String(),
      ),
    ).toJson();

void main() {
  testWidgets('a late and an early match of one Riyadh day share its tab', (
    tester,
  ) async {
    // Tall enough that every card of the day is built.
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Ten Riyadh days ahead: nothing is locked or live.
    final DateTime day = RiyadhDayTurnover.riyadhDayOf(
      DateTime.now(),
    ).add(const Duration(days: 10));
    final DateTime opens = RiyadhDayTurnover.opensAt(day);
    final bool eastOfRiyadh =
        DateTime.now().timeZoneOffset > const Duration(hours: 3);
    final DateTime edge = opens.add(
      eastOfRiyadh
          ? const Duration(hours: 23, minutes: 30)
          : const Duration(minutes: 30),
    );
    final DateTime evening = opens.add(const Duration(hours: 18));

    final List<Map<String, Object?>> feed = <Map<String, Object?>>[
      _item('f-edge', edge),
      _item('f-evening', evening),
    ];
    final harness = buildCurrentMonthFixturesHarness((request) async {
      final path = request.url.path;
      if (path == '/feed/current-month-fixtures') return okJsonList(feed);
      if (path.endsWith('/prediction-distribution')) {
        return okJsonObject(const {
          'schema_version': 1,
          'home_win_percentage': 50,
          'away_win_percentage': 50,
        });
      }
      if (path == '/me/fixture-predictions' || path == '/teams') {
        return okJsonList(const []);
      }
      throw StateError('Unexpected request: ${request.method} $path');
    });
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        retry: (retryCount, error) => null,
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const CurrentMonthFixturesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Set<String> shown = tester
        .widgetList<FotmobMatchCard>(find.byType(FotmobMatchCard))
        .map((FotmobMatchCard card) => card.item.fixture.fixtureId)
        .toSet();
    expect(
      shown,
      <String>{'f-edge', 'f-evening'},
      reason:
          'both kick off on the same Riyadh day (zone offset '
          '${DateTime.now().timeZoneOffset})',
    );
  });
}
