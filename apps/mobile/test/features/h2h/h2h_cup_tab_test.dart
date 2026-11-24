// NK316_05
/// The Elite Cup board inside [H2hScreen]: the fifth section of a seated
/// month, and under the state card of a player without a seat. The board
/// itself is tested in `h2h_cup_board_test.dart`; here only its place in the
/// tab, its request, and that a failing board leaves the other sections
/// alone.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/h2h_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

const MyH2hLeagueDto _noSeat = MyH2hLeagueDto(
  state: 'not_started',
  monthStart: '2026-11-01',
  startsOn: '2026-12-01',
  isPilot: false,
  myRank: 0,
  promotionZone: 0,
  relegationZone: 0,
  standings: <H2hStandingDto>[],
  rounds: <H2hRoundViewDto>[],
);

const MyH2hLeagueDto _seated = MyH2hLeagueDto(
  state: 'open',
  monthStart: '2026-11-01',
  startsOn: '2026-11-01',
  isPilot: false,
  division: 2,
  groupIndex: 0,
  myRank: 1,
  promotionZone: 2,
  relegationZone: 2,
  daysLeft: 21,
  standings: <H2hStandingDto>[
    H2hStandingDto(
      rank: 1,
      userId: 'u-me',
      displayName: 'سامي',
      played: 0,
      won: 0,
      drawn: 0,
      lost: 0,
      leaguePoints: 0,
      pointsFor: 0,
      exactCount: 0,
      form: <String>[],
      isMe: true,
    ),
  ],
  rounds: <H2hRoundViewDto>[
    H2hRoundViewDto(
      round: 4,
      day: '2026-11-12',
      status: 'open',
      fixtureCount: 9,
      opponentUserId: 'u-d',
      opponentName: 'عمر',
      firstKickoff: '2026-11-12T15:00:00.000Z',
    ),
  ],
);

const H2hCupBoardDto _board = H2hCupBoardDto(
  monthStart: '2026-11-01',
  paths: <H2hCupBoardPathDto>[
    H2hCupBoardPathDto(
      place: 1,
      stages: <H2hCupBoardStageDto>[
        H2hCupBoardStageDto(
          round: 'semi',
          cupDay: 1,
          phase: 'live',
          attempt: 1,
          pairs: <H2hCupBoardPairDto>[
            H2hCupBoardPairDto(
              slot: 1,
              home: H2hCupPlayerDto(
                userId: 'u-me',
                displayName: 'سامي',
                groupNumber: 1,
                isMe: true,
              ),
              away: H2hCupPlayerDto(
                userId: 'u-n',
                displayName: 'نورة',
                groupNumber: 3,
                isMe: false,
              ),
              decided: false,
              fixtures: <H2hCupBoardFixtureDto>[
                H2hCupBoardFixtureDto(
                  fixtureId: 'f-next',
                  homeTeam: 'Alpha',
                  awayTeam: 'Beta',
                  kickoffAt: '2026-11-23T19:00:00Z',
                  state: 'not_started',
                  homeSide: H2hCupBoardSideDto(
                    revealed: true,
                    pick: H2hPickDto(
                      homeGoals: 0,
                      awayGoals: 0,
                      isDouble: false,
                      exact: false,
                    ),
                  ),
                  awaySide: H2hCupBoardSideDto.hidden(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Opens the tab; every request path is appended to the returned list.
/// [board] answers `/me/h2h-cup/board`, null makes it fail with 404.
Future<List<String>> _open(
  WidgetTester tester,
  MyH2hLeagueDto league, {
  H2hCupBoardDto? board = _board,
  int section = 0,
  double width = 1080,
  double textScale = 1,
}) async {
  final List<String> paths = <String>[];
  Future<http.Response> handle(http.Request request) async {
    paths.add(request.url.path);
    if (request.url.path == '/me/h2h-league') return _json(league.toJson());
    if (request.url.path == '/me/h2h-cup/board' && board != null) {
      return _json(board.toJson());
    }
    return http.Response('not found', 404);
  }

  final AuthHarness harness = buildAuthHarness(handle, seedToken: 'jwt');
  addTearDown(harness.dispose);
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: H2hScreen(
          initialSection: section,
          now: () => DateTime.utc(2026, 11, 4, 10),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return paths;
}

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

void main() {
  testWidgets('a seated month has the cup as its fifth section', (
    WidgetTester tester,
  ) async {
    final List<String> paths = await _open(tester, _seated);

    expect(find.byKey(const Key('h2h.section.4')), findsOneWidget);
    expect(find.byKey(const Key('h2h.section.5')), findsNothing);
    // The board is asked for only once its section is chosen.
    expect(paths, isNot(contains('/me/h2h-cup/board')));
    expect(find.byKey(const Key('h2h.cupBoard')), findsNothing);

    await tester.tap(find.byKey(const Key('h2h.section.4')));
    await tester.pumpAndSettle();

    expect(paths.where((String p) => p == '/me/h2h-cup/board'), hasLength(1));
    expect(find.byKey(const Key('h2h.cupBoard')), findsOneWidget);
    expect(_text(tester, 'h2h.cupBoard.month'), 'نوفمبر 2026');
    // The hidden side says only that it appears after the kickoff.
    expect(
      _text(tester, 'h2h.cupBoard.pair.1.semi.1.fixture.f-next.away.hidden'),
      'تظهر بعد انطلاق المباراة',
    );
  });

  testWidgets('initialSection 4 opens on the cup, a larger one too', (
    WidgetTester tester,
  ) async {
    await _open(tester, _seated, section: 4);
    expect(find.byKey(const Key('h2h.cupBoard')), findsOneWidget);
    await _open(tester, _seated, section: 9);
    expect(find.byKey(const Key('h2h.cupBoard')), findsOneWidget);
  });

  testWidgets('no cup yet: the section says so', (WidgetTester tester) async {
    await _open(tester, _seated, board: const H2hCupBoardDto(), section: 4);

    expect(find.byKey(const Key('h2h.cupBoard.empty')), findsOneWidget);
    expect(find.byKey(const Key('h2h.cupBoard')), findsNothing);
  });

  testWidgets('a failing board shows a retry and leaves the tab working', (
    WidgetTester tester,
  ) async {
    final List<String> paths = await _open(
      tester,
      _seated,
      board: null,
      section: 4,
    );

    expect(find.byKey(const Key('h2h.cupBoard.error')), findsOneWidget);
    expect(find.byKey(const Key('h2h.cupBoard.retry')), findsOneWidget);
    // The other sections are one tap away and still draw.
    expect(find.byKey(const Key('h2h.sections')), findsOneWidget);
    await tester.tap(find.byKey(const Key('h2h.cupBoard.retry')));
    await tester.pumpAndSettle();
    expect(paths.where((String p) => p == '/me/h2h-cup/board'), hasLength(2));
  });

  testWidgets('without a seat the board sits under the state card', (
    WidgetTester tester,
  ) async {
    await _open(tester, _noSeat);

    expect(find.byKey(const Key('h2h.sections')), findsNothing);
    expect(find.byKey(const Key('h2h.state.not_started')), findsOneWidget);
    expect(find.byKey(const Key('h2h.cupBoard')), findsOneWidget);
    expect(find.byKey(const Key('h2h.rules')), findsOneWidget);
    final double state = tester
        .getTopLeft(find.byKey(const Key('h2h.state.not_started')))
        .dy;
    final double board = tester
        .getTopLeft(find.byKey(const Key('h2h.cupBoard')))
        .dy;
    final double rules = tester
        .getTopLeft(find.byKey(const Key('h2h.rules')))
        .dy;
    expect(state, lessThan(board));
    expect(board, lessThan(rules));
  });

  testWidgets('at 360px and text x2 the cup section draws without overflow', (
    WidgetTester tester,
  ) async {
    await _open(tester, _seated, section: 4, width: 360, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('h2h.cupBoard')), findsOneWidget);
  });
}
