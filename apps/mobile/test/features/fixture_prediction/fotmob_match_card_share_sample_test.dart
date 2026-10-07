/// The win shares and the league logo through the real matches screen, the
/// real card and a fake server: a share over fewer than five decisive
/// calls is not shown (one call read as "100%"), five or more are; a feed
/// from an older server, with no count, shows the shares as before; and a
/// league logo sits whole on a light disc, readable on the dark card.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

Map<String, Object?> _item({int? decisive}) => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'League',
  seasonLabel: '10/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: 'f-1',
    homeTeam: 'Malaga',
    awayTeam: 'Espanyol',
    kickoffAt: futureIso(),
    leagueName: 'Ligue 1',
    leagueLogoUrl: 'https://logos.example/ligue1.png',
  ),
  homeWinPercentage: 0,
  awayWinPercentage: 100,
  decisivePredictions: decisive,
).toJson();

Future<void> _pump(WidgetTester tester, Map<String, Object?> item) async {
  final harness = buildCurrentMonthFixturesHarness((request) async {
    switch (request.url.path) {
      case '/feed/current-month-fixtures':
        return okJsonList([item]);
      case '/me/fixture-predictions':
      case '/teams':
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
        locale: const Locale('ar'),
        home: const CurrentMonthFixturesScreen(),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  testWidgets('one decisive call shows no share', (tester) async {
    await _pump(tester, _item(decisive: 1));

    expect(find.text('100%'), findsNothing);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('five decisive calls show the shares', (tester) async {
    await _pump(tester, _item(decisive: 5));

    expect(find.text('100%'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('an older feed without a count shows the shares', (tester) async {
    await _pump(tester, _item());

    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('the league logo sits whole on a light disc', (tester) async {
    await _pump(tester, _item(decisive: 5));

    final Finder plate = find.byKey(const Key('competitionLogo.plate'));
    expect(plate, findsOneWidget);
    final BoxDecoration disc =
        tester.widget<Container>(plate).decoration! as BoxDecoration;
    expect(disc.shape, BoxShape.circle);
    expect(disc.color, Colors.white);
    expect(
      find.ancestor(of: plate, matching: find.byType(ClipOval)),
      findsNothing,
    );
  });
}
