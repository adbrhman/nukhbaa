/// A finished match through the real matches screen, the real card and a
/// fake server (script 119): the verdict in the history's words, the
/// loser's name stepping back, the caption over everyone's calls with the
/// share that called the result still lit, and the two ways out on one
/// row -- also at double text on a 360px phone.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/features/fixture_prediction/widgets/fotmob_match_card.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

/// A kickoff already past and inside today's Riyadh day (UTC+3), so the
/// screen's default day holds the card at any hour.
String _kickoff() {
  final DateTime now = DateTime.now().toUtc();
  final DateTime riyadh = now.add(const Duration(hours: 3));
  final DateTime dayStart = DateTime.utc(
    riyadh.year,
    riyadh.month,
    riyadh.day,
  ).subtract(const Duration(hours: 3));
  final DateTime early = now.subtract(const Duration(hours: 2));
  final DateTime pick = early.isAfter(dayStart)
      ? early
      : dayStart.add(const Duration(seconds: 1));
  return pick.toIso8601String();
}

Map<String, Object?> _item() => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'League',
  seasonLabel: '10/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: 'f-1',
    homeTeam: 'Arsenal',
    awayTeam: 'Chelsea',
    kickoffAt: _kickoff(),
  ),
  resultHomeGoals: 2,
  resultAwayGoals: 1,
  homeOutcomeShare: 60,
  drawOutcomeShare: 22,
  awayOutcomeShare: 18,
  totalPredictions: 100,
).toJson();

Future<void> _pump(WidgetTester tester, {double scale = 1.0}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final harness = buildCurrentMonthFixturesHarness((request) async {
    switch (request.url.path) {
      case '/feed/current-month-fixtures':
        return okJsonList([_item()]);
      case '/me/fixture-predictions':
        return okJsonList([
          const FixturePredictionDto(
            id: 'pr-1',
            participantId: 'p-me',
            fixtureId: 'f-1',
            submittedAt: '2026-10-18T10:00:00.000Z',
            homeGoals: 1,
            awayGoals: 0,
            isDouble: true,
            seasonId: 's-1',
          ).toJson(),
        ]);
      case '/me/fixture-scores':
        return okJsonList([
          const MyFixtureScoreDto(
            participantId: 'p-me',
            fixtureId: 'f-1',
            grade: 'correct_outcome',
            points: 0,
            resultHomeGoals: 2,
            resultAwayGoals: 1,
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
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Finder _in(String key, Finder matching) =>
    find.descendant(of: find.byKey(Key(key)), matching: matching);

Color? _colorOf(WidgetTester tester, Finder text) =>
    tester.widget<Text>(text).style?.color;

void main() {
  testWidgets('the verdict says how the call went', (tester) async {
    await _pump(tester);

    expect(
      _in('currentMonthFixtures.myCall.f-1', find.text('توقعك')),
      findsOneWidget,
    );
    expect(
      _in(
        'currentMonthFixtures.verdict.f-1',
        find.text('أصبت الاتجاه لا النتيجة · 0 نقطة'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the loser steps back and the share that called it stays lit', (
    tester,
  ) async {
    await _pump(tester);
    final AppTokens t = tester.element(find.byType(FotmobMatchCard)).tokens;

    expect(
      _colorOf(
        tester,
        find.byKey(const Key('currentMonthFixtures.side.f-1.home')),
      ),
      t.textPrimary,
    );
    expect(
      _colorOf(
        tester,
        find.byKey(const Key('currentMonthFixtures.side.f-1.away')),
      ),
      t.textSecondary,
    );

    const String shares = 'currentMonthFixtures.outcomeShares.f-1';
    expect(_in(shares, find.text('كيف توقّع اللاعبون')), findsOneWidget);
    expect(find.text('فرص الفوز'), findsNothing);
    expect(_colorOf(tester, _in(shares, find.text('60%'))), t.successText);
    expect(_colorOf(tester, _in(shares, find.text('22%'))), t.textSecondary);
    expect(_colorOf(tester, _in(shares, find.text('18%'))), t.textSecondary);
  });

  testWidgets('both ways out share one row', (tester) async {
    await _pump(tester);

    final Finder reveal = find.byKey(
      const Key('currentMonthFixtures.reveal.f-1'),
    );
    final Finder details = find.byKey(
      const Key('currentMonthFixtures.details.f-1'),
    );
    expect(reveal, findsOneWidget);
    expect(details, findsOneWidget);
    expect(
      (tester.getCenter(reveal).dy - tester.getCenter(details).dy).abs(),
      lessThan(1),
    );
  });

  testWidgets('at double text nothing overflows', (tester) async {
    await _pump(tester, scale: 2.0);

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('currentMonthFixtures.verdict.f-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('currentMonthFixtures.details.f-1')),
      findsOneWidget,
    );
  });
}
