/// A viewer whose date is not Riyadh's reads the weekday after the kickoff
/// time ("11:30 م (الأحد)", `formatKickoffTime`). That longer label
/// overflowed the card's header at 320px and at large text, and every test
/// that drew a card failed between 21:00 and 24:00 UTC (CI, 2026-10-10).
///
/// The kickoff here is 21:30 UTC, 00:30 Riyadh the next day, so the label
/// is the long one wherever the device's date differs from Riyadh's then:
/// in CI (UTC) always. On a phone set to Riyadh time the two dates agree
/// and the test is skipped; the batch scripts run this file with TZ=UTC.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

/// A year ahead, at 21:30 UTC: 00:30 Riyadh on the following day.
final DateTime _kickoff = () {
  final DateTime day = DateTime.now().toUtc().add(const Duration(days: 365));
  return DateTime.utc(day.year, day.month, day.day, 21, 30);
}();

/// Whether this device shows the long label for [_kickoff].
bool get _longLabel {
  final DateTime local = _kickoff.toLocal();
  final DateTime riyadh = _kickoff.add(const Duration(hours: 3));
  return local.day != riyadh.day;
}

final CurrentMonthFixtureItemDto _lateItem = CurrentMonthFixtureItemDto(
  competitionId: sampleFeedItem.competitionId,
  competitionName: sampleFeedItem.competitionName,
  seasonLabel: sampleFeedItem.seasonLabel,
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: 'f-1',
    homeTeam: 'Al Hilal',
    awayTeam: 'Al Nassr',
    kickoffAt: _kickoff.toIso8601String(),
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required double scale,
}) async {
  final harness = buildCurrentMonthFixturesHarness((request) async {
    final String path = request.url.path;
    if (path == '/feed/current-month-fixtures') {
      return okJsonList(<Object?>[_lateItem.toJson()]);
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
  addTearDown(harness.dispose);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const CurrentMonthFixturesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final (String name, Size size, double scale) in <(String, Size, double)>[
    ('320px at x1.0', const Size(320, 800), 1.0),
    ('360px at x1.3', const Size(360, 800), 1.3),
    ('360px at x2.0', const Size(360, 1200), 2.0),
  ]) {
    testWidgets('the weekday label fits the card: $name', (tester) async {
      await _pump(tester, size: size, scale: scale);

      expect(tester.takeException(), isNull);
      // The test sees what it tests: the long label, weekday and all.
      final Text label = tester.widget<Text>(
        find.byKey(const Key('matchCard.kickoff')),
      );
      expect(label.data, matches(RegExp(r'\(.+\)')));
    }, skip: !_longLabel);
  }
}
