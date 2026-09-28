/// The champion of the month through the real leaderboard tab, the real
/// `LeaderboardsApi` and `GET /champions`, with only the socket faked
/// ([buildLeaderboardsHarness]): for 48 hours the tab draws the faint
/// picture, the spotlight (crown, framed picture, name, points, accuracy)
/// above the untouched board; afterwards the celebration is gone, a crown
/// opens the champions' record, and the crown sits beside the champion's
/// name on the season board.
library;

import 'dart:async';
import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/competition/competition_providers.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_providers.dart';
import 'package:mobile/features/leaderboards/champions_providers.dart';
import 'package:mobile/features/leaderboards/leaderboards_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/leaderboards_harness.dart';

/// A 1x1 transparent PNG.
final List<int> _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

Map<String, Object?> _champion({
  required String userId,
  required String name,
  required DateTime until,
  String seasonId = 's-9',
  String label = '09/2026',
  String? photoUrl,
}) => <String, Object?>{
  'season_id': seasonId,
  'season_label': label,
  'user_id': userId,
  'display_name': name,
  'points': 42,
  'exact_count': 6,
  'decided_count': 30,
  'referral_points': 2,
  'crowned_at': until.subtract(const Duration(hours: 48)).toIso8601String(),
  'celebrate_until': until.toIso8601String(),
  'photo_url': ?photoUrl,
};

LeaderboardsHarness _harness(List<Map<String, Object?>> champions) {
  return buildLeaderboardsHarness((http.Request request) async {
    final String path = request.url.path;
    if (path == '/champions') {
      return okJsonObject(<String, Object?>{
        'schema_version': 1,
        'champions': champions,
      });
    }
    if (path == '/champions/s-9/photos/u-1') {
      return http.Response.bytes(
        _png,
        200,
        headers: const {'content-type': 'image/png'},
      );
    }
    if (path == '/seasons/s-1/fixture-leaderboard') {
      return okJsonObject(sampleFixtureBoard.toJson());
    }
    if (path == '/leaderboard/season') {
      return okJsonObject(<String, Object?>{
        'schema_version': 1,
        'label': '2026/27',
        'entries': <Map<String, Object?>>[
          <String, Object?>{
            'rank': 1,
            'user_id': 'u-1',
            'display_name': 'Ahmad',
            'total_points': 42,
            'fixtures_scored': 30,
            'exact_count': 6,
            'decided_count': 30,
          },
          <String, Object?>{
            'rank': 2,
            'user_id': 'u-2',
            'display_name': 'Sara',
            'total_points': 30,
            'fixtures_scored': 30,
          },
        ],
      });
    }
    return http.Response('not found', 404);
  });
}

Future<void> _open(WidgetTester tester, LeaderboardsHarness harness) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        activeSeasonsProvider.overrideWith(
          (ref) async => const <ActiveSeasonDto>[
            ActiveSeasonDto(
              competitionId: 'c-1',
              competitionName: 'Monthly',
              seasonId: 's-1',
              seasonLabel: '10/2026',
              startAt: '2026-09-30T21:00:00Z',
              endAt: '2026-10-31T21:00:00Z',
            ),
          ],
        ),
        // Never answers: every active season stays visible.
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
}

void main() {
  final AppLocalizations ar = lookupAppLocalizations(const Locale('ar'));

  testWidgets('for 48 hours the champion sits above the untouched board', (
    tester,
  ) async {
    final harness = _harness(<Map<String, Object?>>[
      _champion(
        userId: 'u-1',
        name: 'Ahmad',
        until: DateTime.now().toUtc().add(const Duration(hours: 30)),
        photoUrl: '/champions/s-9/photos/u-1?v=1',
      ),
    ]);
    addTearDown(harness.dispose);

    await _open(tester, harness);

    final Iterable<String> paths = harness.captured.map(
      (c) => c.request.url.path,
    );
    expect(paths, contains('/champions'));
    expect(paths, contains('/champions/s-9/photos/u-1'));

    // Layer 1: the faint picture behind the header.
    expect(find.byKey(const Key('champion.backdrop.photo')), findsOneWidget);
    // Layers 2-4: the title, the framed picture, name, points, accuracy.
    expect(
      tester
          .widget<Text>(find.byKey(const Key('leaderboards.champion.title')))
          .data,
      ar.championTitleOne('شهر 9'),
    );
    expect(
      find.byKey(const Key('leaderboards.champion.photo.u-1')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('leaderboards.champion.name.u-1')))
          .data,
      'Ahmad',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('leaderboards.champion.points.u-1')),
          )
          .data,
      ar.pointsAbbreviated(42),
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('leaderboards.champion.accuracy.u-1')),
          )
          .data,
      ar.boardAccuracyIs(20),
    );
    // The screen stays a leaderboard: the month's board is still there.
    expect(find.byKey(const Key('leaderboards.participant.p-a')), findsWidgets);
    // While it runs, the record is reached from the spotlight.
    expect(
      find.byKey(const Key('leaderboards.champion.record')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('leaderboards.champions.record')),
      findsNothing,
    );

    // It folds to one line and opens again.
    await tester.tap(find.byKey(const Key('leaderboards.champion.toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('leaderboards.champion.name.u-1')),
      findsNothing,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('leaderboards.champion.title')))
          .data,
      contains('Ahmad'),
    );
    await tester.tap(find.byKey(const Key('leaderboards.champion.toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('leaderboards.champion.name.u-1')),
      findsOneWidget,
    );
  });

  testWidgets('two level champions share the spotlight', (tester) async {
    final DateTime until = DateTime.now().toUtc().add(const Duration(hours: 5));
    final harness = _harness(<Map<String, Object?>>[
      _champion(userId: 'u-1', name: 'Ahmad', until: until),
      _champion(userId: 'u-2', name: 'Sara', until: until),
    ]);
    addTearDown(harness.dispose);

    await _open(tester, harness);

    expect(
      tester
          .widget<Text>(find.byKey(const Key('leaderboards.champion.title')))
          .data,
      ar.championTitleTwo('شهر 9'),
    );
    expect(
      find.byKey(const Key('leaderboards.champion.name.u-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('leaderboards.champion.name.u-2')),
      findsOneWidget,
    );
  });

  testWidgets('after 48 hours: no celebration, the record and the crown stay', (
    tester,
  ) async {
    final harness = _harness(<Map<String, Object?>>[
      _champion(
        userId: 'u-1',
        name: 'Ahmad',
        until: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      ),
    ]);
    addTearDown(harness.dispose);

    await _open(tester, harness);

    expect(
      find.byKey(const Key('leaderboards.champion.spotlight')),
      findsNothing,
    );
    expect(find.byKey(const Key('champion.backdrop.photo')), findsNothing);

    // The crown beside the champion's name on the season board.
    await tester.tap(find.byKey(const Key('leaderboards.scope.2')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('leaderboards.season.crown.u-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('leaderboards.season.crown.u-2')),
      findsNothing,
    );

    // The record keeps the champion.
    await tester.tap(find.byKey(const Key('leaderboards.champions.record')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('champions.record.title')), findsOneWidget);
    expect(
      find.byKey(const Key('champions.record.champion.s-9.u-1')),
      findsOneWidget,
    );
    expect(find.text('Ahmad'), findsOneWidget);
  });

  test('the celebration is the newest crowning, until celebrate_until', () {
    final DateTime now = DateTime.utc(2026, 10, 2, 12);
    MonthChampionDto c(String season, String user, DateTime until) =>
        MonthChampionDto.fromJson(
          _champion(userId: user, name: user, until: until, seasonId: season),
        );
    final MonthChampionsDto list = MonthChampionsDto(
      champions: <MonthChampionDto>[
        c('s-9', 'u-1', now.add(const Duration(hours: 1))),
        c('s-9', 'u-2', now.add(const Duration(hours: 1))),
        c('s-8', 'u-3', now.add(const Duration(hours: 9))),
      ],
    );

    expect(celebratingChampions(list, now).map((m) => m.userId), <String>[
      'u-1',
      'u-2',
    ]);
    expect(
      celebratingChampions(list, now.add(const Duration(hours: 1))),
      isEmpty,
    );
    expect(celebratingChampions(null, now), isEmpty);
    expect(
      celebratingChampions(const MonthChampionsDto(champions: []), now),
      isEmpty,
    );
  });
}
