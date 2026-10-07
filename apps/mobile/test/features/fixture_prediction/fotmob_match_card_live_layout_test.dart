/// A match in play through the real matches screen, the real card and a
/// fake server (design of 2026-10-07): the live chip and the minute in the
/// header, the score in a box, the player's call between the two names,
/// the three-way split of everyone's calls and the button to them -- and a
/// screen that comes to rest, since nothing on it animates forever.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/ui/team_logo.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/features/fixture_prediction/widgets/fotmob_match_card.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

Map<String, Object?> _item({int total = 100}) => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'الدوري السعودي',
  seasonLabel: '10/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: 'f-1',
    homeTeam: 'Arsenal',
    awayTeam: 'Chelsea',
    kickoffAt: DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 30))
        .toIso8601String(),
  ),
  liveHomeGoals: 0,
  liveAwayGoals: 1,
  liveMinute: 67,
  homeWinPercentage: 77,
  awayWinPercentage: 23,
  decisivePredictions: 78,
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
    switch (request.url.path) {
      case '/feed/current-month-fixtures':
        return okJsonList([_item(total: total)]);
      case '/me/fixture-predictions':
        return okJsonList([
          const FixturePredictionDto(
            id: 'pr-1',
            participantId: 'p-me',
            fixtureId: 'f-1',
            submittedAt: '2026-10-07T10:00:00.000Z',
            homeGoals: 1,
            awayGoals: 2,
            isDouble: false,
            seasonId: 's-1',
          ).toJson(),
        ]);
      case '/seasons/s-1/fixtures/f-1/scores':
        return okJsonObject(const {
          'schema_version': 1,
          'fixture_id': 'f-1',
          'scores': <Object?>[],
        });
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
  // Settles: the live chip's dot is steady. It used to pulse forever,
  // which is why the older card tests pump a bounded number of frames.
  await tester.pumpAndSettle();
}

Finder _in(String key, Finder matching) =>
    find.descendant(of: find.byKey(Key(key)), matching: matching);

void main() {
  testWidgets('the live card reads like the match', (tester) async {
    await _pump(tester);

    // Header: the live chip and the minute.
    expect(
      _in('currentMonthFixtures.liveStatus.f-1', find.text('مباشر')),
      findsOneWidget,
    );
    expect(find.text("67'"), findsOneWidget);
    // The score in its box; RTL puts the home score last.
    expect(
      _in('currentMonthFixtures.liveScore.f-1', find.text('1 - 0')),
      findsOneWidget,
    );
    // The player's call (1-2 home) between the two names.
    expect(
      _in('currentMonthFixtures.myCall.f-1', find.text('توقعك')),
      findsOneWidget,
    );
    expect(
      _in('currentMonthFixtures.myCall.f-1', find.text('2 - 1')),
      findsOneWidget,
    );
    // The three-way split of everyone's calls.
    const String shares = 'currentMonthFixtures.outcomeShares.f-1';
    expect(_in(shares, find.text('60%')), findsOneWidget);
    expect(_in(shares, find.text('22%')), findsOneWidget);
    expect(_in(shares, find.text('18%')), findsOneWidget);
    expect(_in(shares, find.text('التعادل')), findsOneWidget);
    // And the way to everyone's predictions; no steppers after kickoff.
    expect(
      find.byKey(const Key('currentMonthFixtures.reveal.f-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('currentMonthFixtures.home.increment.f-1')),
      findsNothing,
    );
  });

  testWidgets('at double text the score drops under the sides instead of '
      'squeezing them', (tester) async {
    // The UI audit's phone at its largest text size, where the framed
    // score left each side 4px for a 34px crest.
    await _pump(tester, scale: 2.0);

    expect(tester.takeException(), isNull);
    final Finder score = find.byKey(
      const Key('currentMonthFixtures.liveScore.f-1'),
    );
    expect(
      _in('currentMonthFixtures.liveScore.f-1', find.text('1 - 0')),
      findsOneWidget,
    );
    final Finder crests = find.descendant(
      of: find.byType(FotmobMatchCard),
      matching: find.byType(TeamLogo),
    );
    expect(crests, findsNWidgets(2));
    for (final Element crest in crests.evaluate()) {
      final RenderBox box = crest.renderObject! as RenderBox;
      final double bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      expect(tester.getTopLeft(score).dy, greaterThanOrEqualTo(bottom));
      expect(box.size.width, 34);
    }
  });

  testWidgets('no split over a handful of calls', (tester) async {
    await _pump(tester, total: 3);

    expect(
      find.byKey(const Key('currentMonthFixtures.outcomeShares.f-1')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('currentMonthFixtures.liveScore.f-1')),
      findsOneWidget,
    );
  });
}
