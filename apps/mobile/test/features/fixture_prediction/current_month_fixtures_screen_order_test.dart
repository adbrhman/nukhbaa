/// The matches tab draws a day's fixtures in kickoff order, earliest first,
/// whatever order the feed arrives in.
///
/// Goes through the real screen: the genuine `api_client` and providers over
/// a faked socket (`current_month_fixtures_harness.dart`), so a fixture's
/// place in the list is decided by the same code path a device runs. The feed
/// is deliberately NOT chronological -- it mirrors the server's competition
/// order -- and includes a tie and a fixture with no kickoff.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/features/fixture_prediction/widgets/fotmob_match_card.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

/// Local [hour]:00 on a day 30 days ahead, as the UTC ISO string the feed
/// carries. Every call lands on the same LOCAL day whatever the machine's
/// time zone, and far enough ahead that no card is locked or live.
String _kickoff(int hour) {
  final DateTime ahead = DateTime.now().add(const Duration(days: 30));
  return DateTime(
    ahead.year,
    ahead.month,
    ahead.day,
    hour,
  ).toUtc().toIso8601String();
}

Map<String, Object?> _item(String id, String? kickoffAt) =>
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'Test League',
      seasonLabel: '09/2026',
      fixture: SeasonFixtureCardDto(
        seasonId: 's-1',
        fixtureId: id,
        homeTeam: 'Arsenal',
        awayTeam: 'Chelsea',
        kickoffAt: kickoffAt,
      ),
    ).toJson();

void main() {
  testWidgets('a day lists its fixtures by kickoff time, earliest first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Feed order: late, no kickoff, tie (a), early, tie (b).
    final List<Map<String, Object?>> feed = <Map<String, Object?>>[
      _item('f-late', _kickoff(18)),
      _item('f-none', null),
      _item('f-tie-a', _kickoff(14)),
      _item('f-early', _kickoff(12)),
      _item('f-tie-b', _kickoff(14)),
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

    final List<String> shown = tester
        .widgetList<FotmobMatchCard>(find.byType(FotmobMatchCard))
        .map((FotmobMatchCard card) => card.item.fixture.fixtureId)
        .toList();
    expect(
      shown,
      <String>['f-early', 'f-tie-a', 'f-tie-b', 'f-late', 'f-none'],
      reason:
          'earliest kickoff first; equal kickoffs keep feed order; '
          'no kickoff last',
    );

    // Drawn order, not just tree order: each card sits below the previous.
    for (var i = 1; i < shown.length; i++) {
      final double above = tester
          .getTopLeft(find.byKey(ValueKey<String>(shown[i - 1])))
          .dy;
      final double below = tester
          .getTopLeft(find.byKey(ValueKey<String>(shown[i])))
          .dy;
      expect(below, greaterThan(above), reason: '${shown[i]} above its turn');
    }
  });
}
