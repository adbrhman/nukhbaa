/// Duel wins beside the names on the month's leaderboard, through the real
/// leaderboard tab, the real `LeaderboardsApi` and a fake server: the
/// winners carry the mark with their count, on the podium and in the
/// table; a player with no win carries none; the day's board shows none.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/competition/competition_providers.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_providers.dart';
import 'package:mobile/features/leaderboards/leaderboards_screen.dart';
import 'package:mobile/features/leaderboards/widgets/duel_wins_mark.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/leaderboards_harness.dart';

const ActiveSeasonDto _october = ActiveSeasonDto(
  competitionId: 'c-1',
  competitionName: 'Monthly',
  seasonId: 's-10',
  seasonLabel: '10/2026',
  startAt: '2026-09-30T21:00:00Z',
  endAt: '2026-10-31T21:00:00Z',
);

FixtureLeaderboardEntryDto _entry(int rank, String id, String name) =>
    FixtureLeaderboardEntryDto(
      rank: rank,
      participantId: id,
      displayName: name,
      totalPoints: 40 - rank,
      fixturesScored: 10,
    );

Future<List<String>> _open(WidgetTester tester) async {
  final List<String> paths = <String>[];
  final harness = buildLeaderboardsHarness((http.Request request) async {
    final String path = request.url.path;
    paths.add(path);
    if (path == '/champions') {
      return okJsonObject(const <String, Object?>{
        'schema_version': 1,
        'champions': <Object?>[],
      });
    }
    if (path == '/seasons/s-10/fixture-leaderboard') {
      return okJsonObject(
        FixtureLeaderboardDto(
          seasonId: 's-10',
          entries: <FixtureLeaderboardEntryDto>[
            _entry(1, 'p-1', 'Ali'),
            _entry(2, 'p-2', 'Badr'),
            _entry(3, 'p-3', 'Sara'),
            _entry(4, 'p-4', 'Huda'),
          ],
        ).toJson(),
      );
    }
    if (path == '/seasons/s-10/duel-wins') {
      return okJsonObject(const <String, Object?>{
        'schema_version': 1,
        'wins': <String, Object?>{'p-1': 3, 'p-4': 1},
      });
    }
    return http.Response('not found', 404);
  });
  addTearDown(harness.dispose);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        activeSeasonsProvider.overrideWith(
          (ref) async => const <ActiveSeasonDto>[_october],
        ),
        currentMonthFixturesProvider.overrideWith(
          (ref) => Completer<List<CurrentMonthFixtureItemDto>>().future,
        ),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const LeaderboardsScreen(userId: 'u-me'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return paths;
}

int _wins(WidgetTester tester, String key) =>
    tester.widget<DuelWinsMark>(find.byKey(Key(key))).wins;

void main() {
  testWidgets('the winners carry their duel wins beside the name', (
    tester,
  ) async {
    final List<String> paths = await _open(tester);

    expect(paths, contains('/seasons/s-10/duel-wins'));
    expect(_wins(tester, 'leaderboards.duelWins.p-1'), 3);
    expect(_wins(tester, 'leaderboards.duelWins.p-4'), 1);
    expect(find.byKey(const Key('leaderboards.duelWins.p-2')), findsNothing);
  });

  testWidgets('the day board shows no duel wins', (tester) async {
    await _open(tester);

    await tester.tap(find.byKey(const Key('leaderboards.scope.1')));
    await tester.pumpAndSettle();

    expect(find.byType(DuelWinsMark), findsNothing);
  });

  test('the label speaks Arabic plurals', () {
    expect(duelWinsLabel(1), 'فاز في مواجهة واحدة');
    expect(duelWinsLabel(2), 'فاز في مواجهتين');
    expect(duelWinsLabel(5), 'فاز في 5 مواجهات');
    expect(duelWinsLabel(11), 'فاز في 11 مواجهة');
  });
}
