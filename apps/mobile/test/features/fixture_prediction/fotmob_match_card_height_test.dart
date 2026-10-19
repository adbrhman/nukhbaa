/// The match card in each of its states through the real matches screen,
/// the real card and a fake server: on a 360px phone at text x1 and x2 in
/// the dark theme, the card's height goes to the log as a `CARD_HEIGHT`
/// line (script 127) -- the number the redesign is judged by, measured
/// here, not guessed from a picture. Nothing overflows at text x2 on a
/// 360px phone or at text x1 on a 320px one, in the light and the dark
/// theme: the two sizes the UI survey and the overflow test already hold
/// the whole screen to.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/features/fixture_prediction/widgets/fotmob_match_card.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

/// A kickoff already past and inside today's Riyadh day (UTC+3), so the
/// screen's default day holds the card at any hour.
String _pastToday(Duration ago) {
  final DateTime now = DateTime.now().toUtc();
  final DateTime riyadh = now.add(const Duration(hours: 3));
  final DateTime dayStart = DateTime.utc(
    riyadh.year,
    riyadh.month,
    riyadh.day,
  ).subtract(const Duration(hours: 3));
  final DateTime early = now.subtract(ago);
  final DateTime pick = early.isAfter(dayStart)
      ? early
      : dayStart.add(const Duration(seconds: 1));
  return pick.toIso8601String();
}

/// One state of the card: the feed item, the caller's call and its grade.
final class _State {
  const _State(this.name, this.item, {this.call, this.score});

  final String name;
  final CurrentMonthFixtureItemDto item;
  final FixturePredictionDto? call;
  final MyFixtureScoreDto? score;
}

SeasonFixtureCardDto _fixture(String kickoffAt) => SeasonFixtureCardDto(
  seasonId: 's-1',
  fixtureId: 'f-1',
  homeTeam: 'Arsenal',
  awayTeam: 'Chelsea',
  kickoffAt: kickoffAt,
);

const FixturePredictionDto _call = FixturePredictionDto(
  id: 'pr-1',
  participantId: 'p-me',
  fixtureId: 'f-1',
  submittedAt: '2026-10-18T10:00:00.000Z',
  homeGoals: 2,
  awayGoals: 1,
  isDouble: true,
  seasonId: 's-1',
);

List<_State> _states() => <_State>[
  _State(
    'open-no-calls',
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'League',
      seasonLabel: '10/2026',
      fixture: _fixture(futureIso()),
      totalPredictions: 0,
    ),
  ),
  _State(
    'open-few-calls',
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'League',
      seasonLabel: '10/2026',
      fixture: _fixture(futureIso()),
      totalPredictions: 3,
    ),
  ),
  _State(
    'open-saved',
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'League',
      seasonLabel: '10/2026',
      fixture: _fixture(futureIso()),
      homeOutcomeShare: 60,
      drawOutcomeShare: 22,
      awayOutcomeShare: 18,
      totalPredictions: 100,
    ),
    call: _call,
  ),
  _State(
    'live-score',
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'League',
      seasonLabel: '10/2026',
      fixture: _fixture(_pastToday(const Duration(minutes: 30))),
      liveHomeGoals: 1,
      liveAwayGoals: 0,
      liveMinute: 67,
      homeOutcomeShare: 60,
      drawOutcomeShare: 22,
      awayOutcomeShare: 18,
      totalPredictions: 100,
    ),
    call: _call,
  ),
  _State(
    'live-no-score',
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'League',
      seasonLabel: '10/2026',
      fixture: _fixture(_pastToday(const Duration(minutes: 30))),
      homeOutcomeShare: 60,
      drawOutcomeShare: 22,
      awayOutcomeShare: 18,
      totalPredictions: 100,
    ),
    call: _call,
  ),
  _State(
    'finished-graded',
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'League',
      seasonLabel: '10/2026',
      fixture: _fixture(_pastToday(const Duration(hours: 3))),
      resultHomeGoals: 2,
      resultAwayGoals: 1,
      homeOutcomeShare: 60,
      drawOutcomeShare: 22,
      awayOutcomeShare: 18,
      totalPredictions: 100,
    ),
    call: _call,
    score: const MyFixtureScoreDto(
      participantId: 'p-me',
      fixtureId: 'f-1',
      grade: 'exact_scoreline',
      points: 6,
      resultHomeGoals: 2,
      resultAwayGoals: 1,
    ),
  ),
];

/// One screen the card is checked on: its width, text size and theme.
final class _Screen {
  const _Screen(this.width, this.scale, this.dark);

  final double width;
  final double scale;
  final bool dark;

  String get label =>
      '${width.toStringAsFixed(0)}px x$scale ${dark ? 'dark' : 'light'}';
}

/// 360px dark at x1 and x2 for the heights; then the light theme at x2,
/// and the narrowest phone at x1 in both themes.
const List<_Screen> _screens = <_Screen>[
  _Screen(360, 1.0, true),
  _Screen(360, 2.0, true),
  _Screen(360, 2.0, false),
  _Screen(320, 1.0, true),
  _Screen(320, 1.0, false),
];

Future<void> _pump(WidgetTester tester, _State state, _Screen screen) async {
  tester.view.physicalSize = Size(screen.width * 3, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final FixturePredictionDto? call = state.call;
  final MyFixtureScoreDto? score = state.score;
  final harness = buildCurrentMonthFixturesHarness((request) async {
    switch (request.url.path) {
      case '/feed/current-month-fixtures':
        return okJsonList([state.item.toJson()]);
      case '/me/fixture-predictions':
        return okJsonList([if (call != null) call.toJson()]);
      case '/me/fixture-scores':
        return okJsonList([if (score != null) score.toJson()]);
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
        theme: screen.dark ? AppTheme.dark : AppTheme.light,
        locale: const Locale('ar'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(screen.scale)),
          child: child!,
        ),
        home: const CurrentMonthFixturesScreen(),
      ),
    ),
  );
  // Bounded frames rather than a settle: the minute tick is a timer.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// The app's own font, so the heights are the ones a phone draws: the
/// test font draws every glyph a full em square, wider and shorter than
/// the app's, so the heights it gave were not a phone's (script 128).
Future<void> _loadAppFont() async {
  final FontLoader loader = FontLoader('IBMPlexSansArabic')
    ..addFont(rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/IBMPlexSansArabic-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'));
  await loader.load();
}

void main() {
  setUpAll(_loadAppFont);

  for (final _State state in _states()) {
    for (final _Screen screen in _screens) {
      testWidgets('${state.name} on ${screen.label}', (tester) async {
        await _pump(tester, state, screen);

        expect(tester.takeException(), isNull);
        final Finder card = find.byType(FotmobMatchCard);
        expect(card, findsOneWidget);
        final double height = tester.getSize(card).height;
        expect(height, greaterThan(0));
        debugPrint(
          'CARD_HEIGHT ${state.name} ${screen.label}: '
          '${height.toStringAsFixed(0)}',
        );
      });
    }
  }
}
