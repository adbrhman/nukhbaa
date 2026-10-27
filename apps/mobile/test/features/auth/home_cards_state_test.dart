/// Today's matches on the home page (script 126), through the real
/// [HomeScreen]: the one in play first, then the one to come, then the one
/// over; a score once there is one, the kickoff before (script 161); and
/// the open-predictions
/// card counts what is still to call and names the nearest.
library;

import 'dart:convert';

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
import 'package:mobile/features/history/prediction_lookup_providers.dart';
import 'package:mobile/features/notifications/notifications_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

/// Three kickoffs inside today's Riyadh day (UTC+3): one at its start, over
/// with its result; one in play; one still to come.
List<CurrentMonthFixtureItemDto> _items() {
  final DateTime now = DateTime.now().toUtc();
  final DateTime riyadh = now.add(const Duration(hours: 3));
  final DateTime dayStart = DateTime.utc(
    riyadh.year,
    riyadh.month,
    riyadh.day,
  ).subtract(const Duration(hours: 3));
  final DateTime dayEnd = dayStart.add(const Duration(hours: 24));
  final DateTime done = dayStart.add(const Duration(minutes: 1));
  final DateTime soon = now.subtract(const Duration(minutes: 30));
  final DateTime live = soon.isAfter(done)
      ? soon
      : dayStart.add(const Duration(minutes: 2));
  final DateTime later = now.add(const Duration(hours: 1));
  final DateTime up = later.isBefore(dayEnd)
      ? later
      : dayEnd.subtract(const Duration(minutes: 1));
  CurrentMonthFixtureItemDto item(
    String id,
    DateTime kickoff, {
    int? resultHome,
    int? resultAway,
    int? liveHome,
    int? liveAway,
  }) => CurrentMonthFixtureItemDto(
    competitionId: 'c-1',
    competitionName: 'League',
    seasonLabel: '10/2026',
    fixture: SeasonFixtureCardDto(
      seasonId: 's-1',
      fixtureId: id,
      homeTeam: 'Home $id',
      awayTeam: 'Away $id',
      kickoffAt: kickoff.toIso8601String(),
    ),
    resultHomeGoals: resultHome,
    resultAwayGoals: resultAway,
    liveHomeGoals: liveHome,
    liveAwayGoals: liveAway,
  );
  return <CurrentMonthFixtureItemDto>[
    item('f-done', done, resultHome: 2, resultAway: 3),
    item('f-live', live, liveHome: 1, liveAway: 0),
    item('f-up', up),
  ];
}

Finder _in(String key, Finder matching) =>
    find.descendant(of: find.byKey(Key(key)), matching: matching);

void main() {
  testWidgets('in play first, then to come, then over; scores shown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = buildAuthHarness((request) async {
      if (request.url.path == '/me/daily-challenge') {
        return http.Response(
          jsonEncode(
            const MyDailyChallengeDto(
              day: '2026-09-23',
              total: 3,
              predicted: 1,
              complete: false,
            ).toJson(),
          ),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/me/streak') {
        return http.Response(
          jsonEncode(const MyStreakDto(current: 0, longest: 0).toJson()),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      throw StateError(
        'Unexpected request: ${request.method} ${request.url.path}',
      );
    });
    addTearDown(auth.dispose);

    final overrides = <Override>[
      ...auth.overrides,
      currentMonthFixturesProvider.overrideWithValue(
        AsyncData<List<CurrentMonthFixtureItemDto>>(_items()),
      ),
      teamCatalogByIdProvider.overrideWithValue(null),
      activeSeasonsProvider.overrideWithValue(
        AsyncData<List<ActiveSeasonDto>>([
          const ActiveSeasonDto(
            competitionId: 'c-1',
            competitionName: 'الدوري السعودي',
            seasonId: 's-1',
            seasonLabel: '2026/27',
            startAt: '2026-09-01T00:00:00.000Z',
            endAt: '2026-10-01T00:00:00.000Z',
          ),
        ]),
      ),
      myFixturePredictionsByFixtureProvider.overrideWithValue(
        const AsyncData<Map<String, FixturePredictionDto>>({}),
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
            onOpenMatches: () {},
            onOpenAccount: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double top(String id) =>
        tester.getTopLeft(find.byKey(Key('home.highlight.$id'))).dy;
    expect(top('f-live'), lessThan(top('f-up')));
    expect(top('f-up'), lessThan(top('f-done')));

    // RTL scores read home last: home 2, away 3 is "3 - 2".
    String? textOf(String key) =>
        tester.widget<Text>(find.byKey(Key(key))).data;
    expect(textOf('home.highlight.score.f-done'), '3 - 2');
    expect(textOf('home.highlight.score.f-live'), '0 - 1');
    expect(find.byKey(const Key('home.highlight.score.f-up')), findsNothing);
    expect(
      find.byKey(const Key('home.highlight.kickoff.f-up')),
      findsOneWidget,
    );
    expect(
      _in('home.highlight.f-done', find.textContaining('انتهت')),
      findsOneWidget,
    );
    expect(
      _in('home.highlight.f-live', find.textContaining('مباشر')),
      findsOneWidget,
    );

    // One match still to call: the count says so and names it.
    expect(find.text('مباراة واحدة لم تتوقعها بعد'), findsOneWidget);
    expect(
      textOf('home.pendingPredictions.next'),
      startsWith('أقربها: Home f-up × Away f-up'),
    );
  });
}
