/// The home's month card through the real [HomeScreen] (script 161): once
/// the viewer has a line on the month's board it says where he stands --
/// place, points, the next step up -- and opens the leaderboard; before
/// that it keeps the count of matches and the way to them. The highlighted
/// matches carry their state between the clubs: the kickoff, live, the
/// score.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/home_screen.dart';
import 'package:mobile/features/competition/competition_providers.dart';
import 'package:mobile/features/competition/team_catalog_index.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_providers.dart';
import 'package:mobile/features/history/prediction_history_providers.dart';
import 'package:mobile/features/history/prediction_lookup_providers.dart';
import 'package:mobile/features/leaderboards/leaderboards_providers.dart';
import 'package:mobile/features/notifications/notifications_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

CurrentMonthFixtureItemDto _item(
  String id,
  DateTime kickoff, {
  int? liveHome,
  int? liveAway,
}) => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'شهر 10',
  seasonLabel: '10/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: id,
    homeTeam: 'Home $id',
    awayTeam: 'Away $id',
    kickoffAt: kickoff.toUtc().toIso8601String(),
  ),
  liveHomeGoals: liveHome,
  liveAwayGoals: liveAway,
);

FixtureLeaderboardEntryDto _line(int rank, String id, int points) =>
    FixtureLeaderboardEntryDto(
      rank: rank,
      participantId: id,
      displayName: id,
      totalPoints: points,
      fixturesScored: 10,
    );

Future<List<String>> _pump(
  WidgetTester tester, {
  required bool onBoard,
  List<FixtureLeaderboardEntryDto>? board,
}) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = buildAuthHarness((request) async => http.Response('[]', 404));
  addTearDown(auth.dispose);
  final DateTime now = DateTime.now();
  // All three on today's Riyadh day whatever the hour (the home lists
  // today's matches): shares of the time since and until its midnight.
  final DateTime riyadh = now.toUtc().add(const Duration(hours: 3));
  final Duration sinceMidnight = Duration(
    hours: riyadh.hour,
    minutes: riyadh.minute,
    seconds: riyadh.second,
  );
  final Duration untilMidnight =
      const Duration(days: 1) - sinceMidnight - const Duration(seconds: 1);
  Duration atMost(Duration a, Duration b) => a < b ? a : b;
  final List<String> opened = <String>[];
  final overrides = <Override>[
    ...auth.overrides,
    currentMonthFixturesProvider.overrideWithValue(
      AsyncData<List<CurrentMonthFixtureItemDto>>([
        _item(
          'live-score',
          now.subtract(
            atMost(const Duration(minutes: 40), sinceMidnight * 0.6),
          ),
          liveHome: 2,
          liveAway: 1,
        ),
        _item(
          'live',
          now.subtract(
            atMost(const Duration(minutes: 10), sinceMidnight * 0.3),
          ),
        ),
        _item(
          'later',
          now.add(atMost(const Duration(hours: 3), untilMidnight * 0.5)),
        ),
      ]),
    ),
    teamCatalogByIdProvider.overrideWithValue(null),
    activeSeasonsProvider.overrideWithValue(
      AsyncData<List<ActiveSeasonDto>>([
        ActiveSeasonDto(
          competitionId: 'c-1',
          competitionName: 'شهر 10',
          seasonId: 's-1',
          seasonLabel: '10/2026',
          startAt: now
              .subtract(const Duration(days: 20))
              .toUtc()
              .toIso8601String(),
          endAt: now.add(const Duration(days: 5)).toUtc().toIso8601String(),
        ),
      ]),
    ),
    myFixturePredictionsProvider.overrideWithValue(
      AsyncData<List<FixturePredictionDto>>(
        onBoard
            ? const <FixturePredictionDto>[
                FixturePredictionDto(
                  id: 'pr-1',
                  participantId: 'me',
                  fixtureId: 'later',
                  submittedAt: '2026-10-27T10:00:00.000Z',
                  homeGoals: 1,
                  awayGoals: 1,
                  seasonId: 's-1',
                ),
              ]
            : const <FixturePredictionDto>[],
      ),
    ),
    myFixturePredictionsByFixtureProvider.overrideWithValue(
      const AsyncData<Map<String, FixturePredictionDto>>({}),
    ),
    fixtureLeaderboardProvider('s-1').overrideWithValue(
      AsyncData<FixtureLeaderboardDto>(
        FixtureLeaderboardDto(
          seasonId: 's-1',
          entries:
              board ??
              <FixtureLeaderboardEntryDto>[
                _line(1, 'a', 120),
                _line(2, 'b', 90),
                _line(2, 'c', 90),
                _line(4, 'me', 84),
                _line(5, 'd', 80),
              ],
        ),
      ),
    ),
    unreadCountProvider.overrideWithValue(const AsyncData<int>(0)),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        theme: AppTheme.dark,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('ar'),
        home: HomeScreen(
          user: const AuthenticatedUserDto(
            userId: 'u-1',
            role: 'user',
            status: 'active',
            displayName: 'عبدالرحمن',
          ),
          onOpenMatches: () => opened.add('matches'),
          onOpenAccount: () => opened.add('account'),
          onOpenLeaders: () => opened.add('leaders'),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  return opened;
}

void main() {
  testWidgets('on the board: the place, the points and the next step', (
    tester,
  ) async {
    final List<String> opened = await _pump(tester, onBoard: true);

    expect(find.text('ترتيبك هذا الشهر'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('home.overview.rank'))).data,
      '4',
    );
    expect(find.text('من 5'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('home.overview.points'))).data,
      '84 نقطة',
    );
    // The nearest higher total is 90, held at rank 2 by two players.
    expect(
      find.descendant(
        of: find.byKey(const Key('home.overview.next')),
        matching: find.text('6 نقاط للوصول للمرتبة 2'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('home.startPredicting')), findsNothing);
    await tester.tap(find.byKey(const Key('home.overview.leaders')));
    expect(opened, <String>['leaders']);
  });

  testWidgets('the leader reads that he leads', (tester) async {
    await _pump(
      tester,
      onBoard: true,
      board: <FixtureLeaderboardEntryDto>[
        _line(1, 'me', 120),
        _line(2, 'b', 90),
      ],
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('home.overview.next')),
        matching: find.textContaining('أنت في الصدارة'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('not on the board yet: the count and the way to the matches', (
    tester,
  ) async {
    final List<String> opened = await _pump(tester, onBoard: false);

    expect(find.text('لوحة النخبة'), findsOneWidget);
    expect(find.byKey(const Key('home.overview.standing')), findsNothing);
    expect(find.text('مباراة واحدة متاحة هذا الشهر'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home.startPredicting')));
    expect(opened, <String>['matches']);
  });

  testWidgets('each highlight carries its state between the clubs', (
    tester,
  ) async {
    await _pump(tester, onBoard: true);

    expect(
      find.byKey(const Key('home.highlight.score.live-score')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('home.highlight.live.live')), findsOneWidget);
    expect(
      find.byKey(const Key('home.highlight.kickoff.later')),
      findsOneWidget,
    );
    // "Live" once per match: beside the score, or in the middle alone.
    expect(
      find.descendant(
        of: find.byKey(const Key('home.highlight.live-score')),
        matching: find.textContaining('مباشر'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('home.highlight.live')),
        matching: find.textContaining('مباشر'),
      ),
      findsOneWidget,
    );
  });
}
