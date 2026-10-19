/// An open match through the real matches screen, the real card and a fake
/// server (script 123): everyone's calls in three shares, draws included,
/// under their caption, none until five calls, only a line that says when
/// they will; the double under them, beside the share (script 128);
/// a ranking icon to the league's table -- also at double text on a 360px
/// phone.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/competition/team_registry.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/features/fixture_prediction/widgets/fotmob_match_card.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

Map<String, Object?> _item({required int total}) => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'League',
  seasonLabel: '10/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: 'f-1',
    homeTeam: 'Arsenal',
    awayTeam: 'Chelsea',
    kickoffAt: futureIso(),
  ),
  homeWinPercentage: 100,
  awayWinPercentage: 0,
  decisivePredictions: total,
  homeOutcomeShare: 60,
  drawOutcomeShare: 22,
  awayOutcomeShare: 18,
  totalPredictions: total,
).toJson();

Future<void> _pump(
  WidgetTester tester, {
  int total = 100,
  double scale = 1.0,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final harness = buildCurrentMonthFixturesHarness((request) async {
    if (request.url.path == '/feed/current-month-fixtures') {
      return okJsonList([_item(total: total)]);
    }
    if (request.url.path == '/me/fixture-predictions' ||
        request.url.path == '/teams') {
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const CurrentMonthFixturesScreen(),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Finder _in(String key, Finder matching) =>
    find.descendant(of: find.byKey(Key(key)), matching: matching);

const String _shares = 'currentMonthFixtures.outcomeShares.f-1';

void main() {
  testWidgets('three shares, draws included, under their caption', (
    tester,
  ) async {
    await _pump(tester);

    expect(_in(_shares, find.text('كيف توقّع اللاعبون')), findsOneWidget);
    expect(_in(_shares, find.text('60%')), findsOneWidget);
    expect(_in(_shares, find.text('22%')), findsOneWidget);
    expect(_in(_shares, find.text('18%')), findsOneWidget);
    expect(_in(_shares, find.text('التعادل')), findsOneWidget);
    // Each win under its team's name, not "win" twice (script 131).
    expect(_in(_shares, find.text(teamDisplayName('Arsenal'))), findsOneWidget);
    expect(_in(_shares, find.text(teamDisplayName('Chelsea'))), findsOneWidget);
    expect(_in(_shares, find.text('فوز')), findsNothing);
    // The decisive-only split (100% / 0%) is gone.
    expect(find.text('100%'), findsNothing);
    // The double sits in the last row, under the shares (script 128).
    final Finder doubleButton = find.byKey(
      const Key('currentMonthFixtures.double.f-1'),
    );
    expect(doubleButton, findsOneWidget);
    expect(
      tester.getTopLeft(doubleButton).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byKey(const Key(_shares))).dy,
      ),
    );
  });

  testWidgets('no figure until five calls, a line that says so', (
    tester,
  ) async {
    await _pump(tester, total: 3);

    expect(find.byKey(const Key(_shares)), findsNothing);
    expect(find.text('0%'), findsNothing);
    expect(find.text('60%'), findsNothing);
    expect(
      find.text('تظهر نسب الجمهور بعد $minShareSample توقعات'),
      findsOneWidget,
    );
  });

  testWidgets('the header icon is a ranking, not a link out', (tester) async {
    await _pump(tester);

    expect(find.byIcon(Icons.leaderboard_rounded), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
  });

  testWidgets('at double text nothing overflows', (tester) async {
    await _pump(tester, scale: 2.0);

    expect(tester.takeException(), isNull);
    expect(_in(_shares, find.text('22%')), findsOneWidget);
  });
}
