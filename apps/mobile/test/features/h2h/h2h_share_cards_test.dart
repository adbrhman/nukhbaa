/// The head-to-head pictures that leave the app (2026-11-08): the group
/// table with its columns named in words, the standings card for one group
/// or the four, the round's matches card, the day's real results card, the
/// rule that picks the day's matches by the Riyadh day, and the preview that
/// hands the drawn picture and its text to the share sheet.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/competition/team_identity.dart';
import 'package:mobile/features/h2h/h2h_texts.dart';
import 'package:mobile/features/h2h/widgets/h2h_share_cards.dart';
import 'package:mobile/features/h2h/widgets/h2h_standings_table.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:share_plus/share_plus.dart';

H2hStandingDto _standing(
  int rank,
  String id,
  String name,
  int points, {
  bool isMe = false,
}) => H2hStandingDto(
  rank: rank,
  userId: id,
  displayName: name,
  played: 2,
  won: points ~/ 3,
  drawn: 0,
  lost: 2 - points ~/ 3,
  leaguePoints: points,
  pointsFor: 30 - rank,
  exactCount: 0,
  form: const <String>[],
  isMe: isMe,
);

List<H2hStandingDto> _table() => <H2hStandingDto>[
  _standing(1, 'u-1', 'سامي', 6),
  _standing(2, 'u-2', 'نورة', 3),
  _standing(3, 'u-3', 'خالد', 0),
];

H2hShareStandings _group(String title) => H2hShareStandings(
  title: title,
  standings: _table(),
  promotionZone: 1,
  relegationZone: 1,
  eliteDraw: false,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
  Size size = const Size(1200, 3600),
  List<Override> overrides = const <Override>[],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (BuildContext context, Widget? app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(child: Align(child: child)),
        ),
      ),
    ),
  );
  await tester.pump();
}

CurrentMonthFixtureItemDto _item(
  String id,
  String kickoff, {
  int? resultHome,
  int? resultAway,
  int? liveHome,
  int? liveAway,
  bool? liveFinished,
  bool hidden = false,
  bool isTest = false,
  String league = 'الدوري',
}) => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: league,
  seasonLabel: '11/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: id,
    homeTeam: 'Liverpool',
    awayTeam: 'Brighton',
    kickoffAt: kickoff,
    hidden: hidden,
    isTest: isTest,
  ),
  resultHomeGoals: resultHome,
  resultAwayGoals: resultAway,
  liveHomeGoals: liveHome,
  liveAwayGoals: liveAway,
  liveFinished: liveFinished,
);

void main() {
  testWidgets('the table names its columns in words and lists every player', (
    tester,
  ) async {
    await _pump(
      tester,
      SizedBox(
        width: 330,
        child: H2hStandingsTable(
          standings: _table(),
          promotionZone: 1,
          relegationZone: 1,
          eliteDraw: false,
        ),
      ),
    );

    expect(find.byKey(const Key('h2h.standings.compact')), findsOneWidget);
    for (final String column in <String>[
      'فوز',
      'تعادل',
      'خسارة',
      'التوقع',
      'النقاط',
    ]) {
      expect(find.text(column), findsOneWidget);
    }
    expect(find.text('سامي'), findsOneWidget);
    expect(find.text('نورة'), findsOneWidget);
    expect(find.text('خالد'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('h2h.standings.u-1.points')))
          .data,
      '6',
    );
    expect(find.text('يصعد أول 1'), findsOneWidget);
    expect(find.text('يهبط آخر 1'), findsOneWidget);
    expect(find.text(h2hTableNote), findsOneWidget);
  });

  testWidgets('a month of the elite draw says the cup, not a rise', (
    tester,
  ) async {
    await _pump(
      tester,
      SizedBox(
        width: 330,
        child: H2hStandingsTable(
          standings: _table(),
          promotionZone: 3,
          relegationZone: 0,
          eliteDraw: true,
        ),
      ),
    );

    expect(find.text('يتأهل للكأس أول 3'), findsOneWidget);
    expect(find.byKey(const Key('h2h.standings.zone.down')), findsNothing);
  });

  testWidgets('large text turns each player into two lines', (tester) async {
    await _pump(
      tester,
      SizedBox(
        width: 330,
        child: H2hStandingsTable(
          standings: _table(),
          promotionZone: 1,
          relegationZone: 1,
          eliteDraw: false,
        ),
      ),
      textScale: 2,
    );

    expect(find.byKey(const Key('h2h.standings.lines')), findsOneWidget);
    expect(find.byKey(const Key('h2h.standings.header')), findsNothing);
    expect(find.byKey(const Key('h2h.standings.u-1.record')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the standings card: one group is narrow, four sit two by two', (
    tester,
  ) async {
    await _pump(
      tester,
      H2hStandingsShareCard(
        heading: 'ترتيب دوري المواجهات',
        subheading: 'المجموعة 1 · نوفمبر 2026',
        groups: <H2hShareStandings>[_group('المجموعة 1')],
      ),
    );
    final double single = tester
        .getSize(find.byKey(const Key('h2h.share.standings.card')))
        .width;
    expect(find.text('ترتيب دوري المواجهات'), findsOneWidget);
    expect(find.text('سامي'), findsOneWidget);

    await _pump(
      tester,
      H2hStandingsShareCard(
        heading: 'ترتيب دوري المواجهات',
        subheading: 'مجموعات النخبة الأربع · نوفمبر 2026',
        groups: <H2hShareStandings>[
          _group('المجموعة 1'),
          _group('المجموعة 2'),
          _group('المجموعة 3'),
          _group('المجموعة 4'),
        ],
      ),
    );
    final Size four = tester.getSize(
      find.byKey(const Key('h2h.share.standings.card')),
    );
    for (final String title in <String>[
      'المجموعة 1',
      'المجموعة 2',
      'المجموعة 3',
      'المجموعة 4',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('سامي'), findsNWidgets(4));
    expect(four.width, greaterThan(single * 1.8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the matches card draws names and points as the server sent', (
    tester,
  ) async {
    await _pump(
      tester,
      H2hMatchesShareCard(
        heading: 'مواجهات الجولة 3',
        subheading: '8 نوفمبر · المجموعة 1',
        groups: <H2hShareMatches>[
          H2hShareMatches(
            title: 'المجموعة 1',
            status: 'settled',
            matches: const <H2hGroupMatchDto>[
              H2hGroupMatchDto(
                homeUserId: 'u-1',
                homeName: 'سامي',
                homePoints: 9,
                awayUserId: 'u-2',
                awayName: 'نورة',
                awayPoints: 4,
                winner: 'home',
              ),
              H2hGroupMatchDto(
                homeUserId: 'u-3',
                homeName: 'عمر',
                homePoints: 5,
                awayUserId: 'u-4',
                awayName: 'خالد',
                awayPoints: 7,
                winner: 'away',
                awayAbsent: true,
              ),
              H2hGroupMatchDto(
                homeUserId: 'u-5',
                homeName: 'ليلى',
                homePoints: 2,
                awayPoints: 6.5,
                winner: 'away',
              ),
            ],
          ),
        ],
      ),
    );

    expect(find.text('مكتملة'), findsOneWidget);
    expect(find.text('سامي'), findsOneWidget);
    expect(find.text('نورة'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('خالد (غائب)'), findsOneWidget);
    expect(find.text(h2hAverageOpponent), findsOneWidget);
    expect(find.text('6.5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the results card: a score, a live match and one to come', (
    tester,
  ) async {
    const ResolvedTeamIdentity home = ResolvedTeamIdentity(
      displayName: 'ليفربول',
    );
    const ResolvedTeamIdentity away = ResolvedTeamIdentity(
      displayName: 'برايتون',
    );
    await _pump(
      tester,
      const H2hFixturesShareCard(
        heading: 'نتائج مباريات الجولة 3',
        subheading: '8 نوفمبر · انتهت 1 من 3',
        fixtures: <H2hShareFixture>[
          H2hShareFixture(
            league: 'الدوري الإنجليزي',
            home: home,
            away: away,
            state: 'final',
            homeGoals: 2,
            awayGoals: 1,
            timeLabel: '6:00 م',
          ),
          H2hShareFixture(
            league: 'الدوري الإنجليزي',
            home: away,
            away: home,
            state: 'live',
            homeGoals: 0,
            awayGoals: 0,
            timeLabel: '8:00 م',
          ),
          H2hShareFixture(
            league: 'دوري الأبطال',
            home: home,
            away: away,
            state: 'upcoming',
            timeLabel: '10:00 م',
          ),
        ],
      ),
    );

    expect(find.text('الدوري الإنجليزي'), findsOneWidget);
    expect(find.text('دوري الأبطال'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('جارية'), findsOneWidget);
    expect(find.text('10:00 م'), findsOneWidget);
    expect(find.text('6:00 م'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('the day keeps the Riyadh day, the visible matches and the order', () {
    final List<CurrentMonthFixtureItemDto> items = <CurrentMonthFixtureItemDto>[
      // 21:30 UTC on the 7th is 00:30 Riyadh on the 8th: the day's first.
      _item(
        'f-night',
        '2026-11-07T21:30:00.000Z',
        resultHome: 0,
        resultAway: 0,
      ),
      _item('f-late', '2026-11-08T17:00:00.000Z', liveHome: 1, liveAway: 1),
      _item('f-mid', '2026-11-08T12:00:00.000Z', resultHome: 2, resultAway: 1),
      _item('f-next', '2026-11-08T21:30:00.000Z', resultHome: 3, resultAway: 3),
      _item(
        'f-hidden',
        '2026-11-08T13:00:00.000Z',
        resultHome: 1,
        resultAway: 0,
        hidden: true,
      ),
      _item(
        'f-test',
        '2026-11-08T14:00:00.000Z',
        resultHome: 1,
        resultAway: 0,
        isTest: true,
      ),
      _item(
        'f-done-live',
        '2026-11-08T15:00:00.000Z',
        liveHome: 4,
        liveAway: 2,
        liveFinished: true,
      ),
      _item('f-wait', '2026-11-08T19:00:00.000Z'),
    ];

    final List<H2hShareFixture> day = h2hShareFixturesOf(
      items: items,
      day: '2026-11-08',
      catalogById: null,
      timeLabel: (String iso) => 'T:$iso',
    );

    expect(day.map((H2hShareFixture f) => f.state).toList(), <String>[
      'final',
      'final',
      'final',
      'live',
      'upcoming',
    ]);
    expect(day.map((H2hShareFixture f) => f.homeGoals).toList(), <int?>[
      0,
      2,
      4,
      1,
      null,
    ]);
    expect(day.first.timeLabel, 'T:2026-11-07T21:30:00.000Z');
    expect(day.first.league, 'الدوري');
  });

  test('the four groups of the elite draw, and none outside it', () {
    H2hAdminGroupDto group(String id, int division, int index) =>
        H2hAdminGroupDto(
          leagueId: id,
          division: division,
          groupIndex: index,
          capacity: 20,
          promotionZone: 3,
          relegationZone: 0,
          standings: const <H2hStandingDto>[],
        );
    H2hAdminGroupsDto month(String start) => H2hAdminGroupsDto(
      monthStart: start,
      drawn: true,
      isPilot: false,
      seatedCount: 0,
      rounds: const <H2hRoundDto>[],
      groups: <H2hAdminGroupDto>[
        group('g-1', 1, 0),
        group('g-2', 1, 1),
        group('g-5', 2, 0),
      ],
    );

    expect(
      h2hEliteGroupsOf(month('2026-11-01')).map((g) => g.leagueId).toList(),
      <String>['g-1', 'g-2'],
    );
    expect(h2hEliteGroupsOf(month('2026-10-01')), isEmpty);
  });

  testWidgets('the share button hands the drawn picture and its text over', (
    tester,
  ) async {
    final List<ShareParams> sent = <ShareParams>[];
    await _pump(
      tester,
      H2hShareDialog(
        keyPrefix: 'h2h.share.standings',
        fileName: 'nukhba-h2h-standings.png',
        shareText: 'ترتيب المجموعة 1',
        card: H2hStandingsShareCard(
          heading: 'ترتيب دوري المواجهات',
          subheading: 'المجموعة 1',
          groups: <H2hShareStandings>[_group('المجموعة 1')],
        ),
      ),
      overrides: <Override>[
        h2hShareSheetProvider.overrideWithValue((ShareParams params) async {
          sent.add(params);
          return null;
        }),
      ],
    );

    await tester.tap(find.byKey(const Key('h2h.share.standings.share')));
    for (int i = 0; i < 20 && sent.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(sent, hasLength(1));
    expect(sent.single.text, 'ترتيب المجموعة 1');
    expect(sent.single.files, hasLength(1));
    expect(sent.single.fileNameOverrides, <String>['nukhba-h2h-standings.png']);
    expect(find.byKey(const Key('h2h.share.standings.failed')), findsNothing);
  });
}
