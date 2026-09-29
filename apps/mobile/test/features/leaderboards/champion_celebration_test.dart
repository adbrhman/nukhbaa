/// The champion of the month through the real leaderboard tab, the real
/// `LeaderboardsApi` and `GET /champions`, with only the socket faked
/// ([buildLeaderboardsHarness]).
///
/// The rehearsal of 00:00 on the 1st of October: the new month's board is
/// empty (everyone at zero), and above it the September champion's hero --
/// "بطل شهر سبتمبر 2026", the framed picture, the name, the points, the
/// accuracy, the congratulations and the prize -- for the first 48 hours.
/// Also when October has no fixture yet; afterwards the celebration is gone,
/// a crown opens the champions' record, and the crown sits beside the
/// champion's name on the season board. The champion alone may share it.
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
import 'package:mobile/features/leaderboards/widgets/champion_spotlight.dart';
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
  String? prize,
}) => <String, Object?>{
  'season_id': seasonId,
  'season_label': label,
  'user_id': userId,
  'display_name': name,
  'points': 126,
  'exact_count': 21,
  'decided_count': 210,
  'referral_points': 0,
  'crowned_at': until.subtract(const Duration(hours: 40)).toIso8601String(),
  'celebrate_until': until.toIso8601String(),
  'photo_url': ?photoUrl,
  'prize': ?prize,
};

const ActiveSeasonDto _october = ActiveSeasonDto(
  competitionId: 'c-1',
  competitionName: 'Monthly',
  seasonId: 's-10',
  seasonLabel: '10/2026',
  startAt: '2026-09-30T21:00:00Z',
  endAt: '2026-10-31T21:00:00Z',
);

/// The server at the turnover: the October board has nothing scored yet.
LeaderboardsHarness _harness(
  List<Map<String, Object?>> champions, {
  FixtureLeaderboardDto? octoberBoard,
}) {
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
    if (path == '/seasons/s-10/fixture-leaderboard') {
      return okJsonObject(
        (octoberBoard ??
                const FixtureLeaderboardDto(
                  seasonId: 's-10',
                  entries: <FixtureLeaderboardEntryDto>[],
                ))
            .toJson(),
      );
    }
    if (path == '/leaderboard/season') {
      return okJsonObject(<String, Object?>{
        'schema_version': 1,
        'label': '2026/27',
        'entries': <Map<String, Object?>>[
          <String, Object?>{
            'rank': 1,
            'user_id': 'u-1',
            'display_name': 'عبدالرحمن',
            'total_points': 126,
            'fixtures_scored': 210,
            'exact_count': 21,
            'decided_count': 210,
          },
          <String, Object?>{
            'rank': 2,
            'user_id': 'u-2',
            'display_name': 'Sara',
            'total_points': 96,
            'fixtures_scored': 205,
          },
        ],
      });
    }
    return http.Response('not found', 404);
  });
}

Future<void> _open(
  WidgetTester tester,
  LeaderboardsHarness harness, {
  List<ActiveSeasonDto> seasons = const <ActiveSeasonDto>[_october],
  String viewer = 'u-me',
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        activeSeasonsProvider.overrideWith((ref) async => seasons),
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
        home: LeaderboardsScreen(userId: viewer),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

void main() {
  final AppLocalizations ar = lookupAppLocalizations(const Locale('ar'));

  testWidgets('00:00 on the 1st: the September champion above an empty '
      'October board', (tester) async {
    final harness = _harness(<Map<String, Object?>>[
      _champion(
        userId: 'u-1',
        name: 'عبدالرحمن الأكحلي',
        until: DateTime.now().toUtc().add(const Duration(hours: 47)),
        photoUrl: '/champions/s-9/photos/u-1?v=1',
        prize: '150 ريال سعودي',
      ),
    ]);
    addTearDown(harness.dispose);

    await _open(tester, harness);

    final Iterable<String> paths = harness.captured.map(
      (c) => c.request.url.path,
    );
    expect(paths, contains('/champions'));
    expect(paths, contains('/champions/s-9/photos/u-1'));
    expect(paths, contains('/seasons/s-10/fixture-leaderboard'));

    // Layer 1: the faint picture behind the header.
    expect(find.byKey(const Key('champion.backdrop.photo')), findsOneWidget);
    // The hero: title, framed picture, name, points, accuracy, prize.
    expect(_text(tester, 'leaderboards.champion.title'), 'بطل شهر سبتمبر 2026');
    expect(
      find.byKey(const Key('leaderboards.champion.photo.u-1')),
      findsOneWidget,
    );
    expect(
      _text(tester, 'leaderboards.champion.name.u-1'),
      'عبدالرحمن الأكحلي',
    );
    expect(_text(tester, 'leaderboards.champion.points.u-1'), '126');
    expect(_text(tester, 'leaderboards.champion.accuracy.u-1'), '10%');
    expect(find.text(ar.championCongrats), findsOneWidget);
    expect(find.text(ar.championCongratsLine('سبتمبر')), findsOneWidget);
    expect(
      _text(tester, 'leaderboards.champion.prize.u-1'),
      ar.championPrize('150 ريال سعودي'),
    );
    // October: nobody has a point yet, and the screen says so.
    expect(find.text(ar.leaderboardMonthStarting), findsOneWidget);
    // Only the champion may share it.
    expect(
      find.byKey(const Key('leaderboards.champion.share.u-1')),
      findsNothing,
    );
    // While it runs, the record is reached from the hero.
    expect(
      find.byKey(const Key('leaderboards.champion.record')),
      findsOneWidget,
    );
  });

  testWidgets('the hero leads October\'s standings once they begin', (
    tester,
  ) async {
    final harness = _harness(
      <Map<String, Object?>>[
        _champion(
          userId: 'u-1',
          name: 'عبدالرحمن الأكحلي',
          until: DateTime.now().toUtc().add(const Duration(hours: 30)),
        ),
      ],
      octoberBoard: const FixtureLeaderboardDto(
        seasonId: 's-10',
        entries: <FixtureLeaderboardEntryDto>[
          FixtureLeaderboardEntryDto(
            rank: 1,
            participantId: 'p-o1',
            displayName: 'oday',
            totalPoints: 3,
            fixturesScored: 1,
          ),
        ],
      ),
    );
    addTearDown(harness.dispose);

    await _open(tester, harness);

    expect(
      find.byKey(const Key('leaderboards.champion.name.u-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('leaderboards.participant.p-o1')),
      findsWidgets,
    );
    expect(find.text(ar.leaderboardMonthStarting), findsNothing);
  });

  testWidgets('October without a fixture yet: still the celebration, and no '
      '"join a season"', (tester) async {
    final harness = _harness(<Map<String, Object?>>[
      _champion(
        userId: 'u-1',
        name: 'عبدالرحمن الأكحلي',
        until: DateTime.now().toUtc().add(const Duration(hours: 47)),
      ),
    ]);
    addTearDown(harness.dispose);

    await _open(tester, harness, seasons: const <ActiveSeasonDto>[]);

    expect(find.byKey(const Key('leaderboards.notStarted')), findsOneWidget);
    expect(
      find.byKey(const Key('leaderboards.champion.name.u-1')),
      findsOneWidget,
    );
    expect(find.text(ar.leaderboardMonthStarting), findsOneWidget);
    expect(find.text(ar.leaderboardsJoinSeasonPrompt), findsNothing);
  });

  testWidgets('the champion shares the crowning as a picture', (tester) async {
    final harness = _harness(<Map<String, Object?>>[
      _champion(
        userId: 'u-1',
        name: 'عبدالرحمن الأكحلي',
        until: DateTime.now().toUtc().add(const Duration(hours: 47)),
        prize: '150 ريال سعودي',
      ),
    ]);
    addTearDown(harness.dispose);

    await _open(tester, harness, viewer: 'u-1');

    await tester.tap(find.byKey(const Key('leaderboards.champion.share.u-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('championShare.card')), findsOneWidget);
    expect(_text(tester, 'championShare.title'), 'بطل شهر سبتمبر 2026');
    expect(_text(tester, 'championShare.name.u-1'), 'عبدالرحمن الأكحلي');
    expect(find.byKey(const Key('championShare.share')), findsOneWidget);

    await tester.tap(find.byKey(const Key('championShare.close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('championShare.card')), findsNothing);
  });

  testWidgets('two level champions each get a hero', (tester) async {
    final DateTime until = DateTime.now().toUtc().add(const Duration(hours: 5));
    final harness = _harness(<Map<String, Object?>>[
      _champion(userId: 'u-1', name: 'Ahmad', until: until),
      _champion(userId: 'u-2', name: 'Sara', until: until),
    ]);
    addTearDown(harness.dispose);

    await _open(tester, harness);

    expect(
      _text(tester, 'leaderboards.champion.title'),
      'بطلا شهر سبتمبر 2026',
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

  testWidgets('it folds to one line and opens again', (tester) async {
    final harness = _harness(<Map<String, Object?>>[
      _champion(
        userId: 'u-1',
        name: 'Ahmad',
        until: DateTime.now().toUtc().add(const Duration(hours: 30)),
      ),
    ]);
    addTearDown(harness.dispose);
    await _open(tester, harness);

    await tester.tap(find.byKey(const Key('leaderboards.champion.toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('leaderboards.champion.name.u-1')),
      findsNothing,
    );
    expect(_text(tester, 'leaderboards.champion.title'), contains('Ahmad'));

    await tester.tap(find.byKey(const Key('leaderboards.champion.toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('leaderboards.champion.name.u-1')),
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
  });

  test('a month label by name, in either language', () {
    expect(championMonthName('09/2026', const Locale('ar')), 'سبتمبر 2026');
    expect(
      championMonthName('10/2026', const Locale('ar'), withYear: false),
      'أكتوبر',
    );
    expect(championMonthName('09/2026', const Locale('en')), 'September 2026');
    expect(championMonthName('2026/27', const Locale('ar')), '2026/27');
  });
}
