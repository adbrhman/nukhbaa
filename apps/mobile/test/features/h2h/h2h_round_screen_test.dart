/// The round page (تفاصيل المواجهة) over the real [AuthApi] and transport,
/// only the socket faked. It asks `GET /me/h2h-league/rounds/{n}` and draws
/// what came back; the opponent's pick of a fixture that has not kicked
/// off is shown as hidden -- even if a broken server sent it anyway.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/h2h_round_screen.dart';
import 'package:mobile/features/h2h/h2h_screen.dart';
import 'package:mobile/features/h2h/h2h_texts.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _okJson(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

/// Round 2, being played: f1 finished (both picks shown), f2 not started
/// (the opponent's withheld -- and this server wrongly sends it anyway),
/// f3 moved off the day.
MyH2hRoundDto _detail({bool average = false}) => MyH2hRoundDto(
  round: 2,
  day: '2026-11-04',
  status: 'live',
  fixtureCount: 3,
  firstKickoff: '2026-11-04T12:00:00.000Z',
  opponentUserId: average ? null : 'u-b',
  opponentName: average ? null : 'نورة',
  myPoints: 6,
  opponentPoints: 0,
  result: 'win',
  mine: const H2hSideTotalsDto(predicted: 2, exact: 1, doubles: 1),
  theirs: average
      ? null
      : const H2hSideTotalsDto(predicted: 1, exact: 0, doubles: 0),
  fixtures: <H2hRoundFixtureDto>[
    H2hRoundFixtureDto(
      fixtureId: 'f1',
      homeTeam: 'الهلال',
      awayTeam: 'النصر',
      kickoffAt: '2026-11-04T12:00:00.000Z',
      state: 'finished',
      homeGoals: 2,
      awayGoals: 1,
      mine: const H2hPickDto(
        homeGoals: 2,
        awayGoals: 1,
        isDouble: true,
        points: 6,
        exact: true,
      ),
      theirs: average
          ? null
          : const H2hPickDto(
              homeGoals: 0,
              awayGoals: 3,
              isDouble: false,
              points: 0,
            ),
      theirsHidden: false,
    ),
    H2hRoundFixtureDto(
      fixtureId: 'f2',
      homeTeam: 'الاتحاد',
      awayTeam: 'الأهلي',
      kickoffAt: '2026-11-04T15:00:00.000Z',
      state: 'not_started',
      mine: const H2hPickDto(homeGoals: 1, awayGoals: 0, isDouble: false),
      theirs: average
          ? null
          : const H2hPickDto(homeGoals: 7, awayGoals: 7, isDouble: true),
      theirsHidden: !average,
    ),
    H2hRoundFixtureDto(
      fixtureId: 'f3',
      homeTeam: 'الشباب',
      awayTeam: 'الفتح',
      kickoffAt: '2026-11-05T18:00:00.000Z',
      state: 'void',
      theirsHidden: !average,
    ),
  ],
);

const MyH2hLeagueDto _month = MyH2hLeagueDto(
  state: 'open',
  monthStart: '2026-11-01',
  startsOn: '2026-11-01',
  isPilot: false,
  division: 2,
  groupIndex: 0,
  myRank: 1,
  promotionZone: 2,
  relegationZone: 2,
  daysLeft: 26,
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
      round: 2,
      day: '2026-11-04',
      status: 'live',
      fixtureCount: 3,
      opponentUserId: 'u-b',
      opponentName: 'نورة',
      myPoints: 6,
      opponentPoints: 0,
      result: 'win',
    ),
  ],
);

Future<List<String>> _pump(
  WidgetTester tester,
  Widget home, {
  MyH2hRoundDto? detail,
  Size size = const Size(1080, 4000),
  double textScale = 1,
}) async {
  final List<String> paths = <String>[];
  final AuthHarness harness = buildAuthHarness((http.Request request) async {
    paths.add(request.url.path);
    if (request.url.path == '/me/h2h-league/rounds/2') {
      return _okJson((detail ?? _detail()).toJson());
    }
    if (request.url.path == '/me/h2h-league') return _okJson(_month.toJson());
    return http.Response('not found', 404);
  }, seedToken: 'jwt');
  addTearDown(harness.dispose);
  tester.view.physicalSize = size;
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
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return paths;
}

Finder _inside(String key, Finder finder) =>
    find.descendant(of: find.byKey(Key(key)), matching: finder);

void main() {
  testWidgets('asks for its round and draws the match', (tester) async {
    final List<String> paths = await _pump(
      tester,
      const H2hRoundScreen(round: 2),
    );

    expect(paths, contains('/me/h2h-league/rounds/2'));
    expect(find.byKey(const Key('h2h.detail.title')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.detail.heading'))).data,
      'الجولة 2 · 4 نوفمبر',
    );
    expect(_inside('h2h.detail.status', find.text('جارية')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.detail.mine'))).data,
      '6',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.detail.theirs'))).data,
      '0',
    );
    expect(find.text('فوز حتى الآن'), findsOneWidget);
    expect(_inside('h2h.detail.card', find.text('نورة')), findsOneWidget);
  });

  testWidgets('a pick not kicked off stays hidden, even if it was sent', (
    tester,
  ) async {
    await _pump(tester, const H2hRoundScreen(round: 2));

    expect(find.byKey(const Key('h2h.fixture.f2.hidden')), findsOneWidget);
    expect(
      _inside('h2h.fixture.f2.hidden', find.text(h2hHiddenPick)),
      findsOneWidget,
    );
    expect(find.byKey(const Key('h2h.fixture.f2.theirs')), findsNothing);
    expect(find.text('7 - 7'), findsNothing);
    expect(find.byKey(const Key('h2h.detail.hiddenNote')), findsOneWidget);
    // The caller's own pick is theirs to see.
    expect(_inside('h2h.fixture.f2.mine', find.text('1 - 0')), findsOneWidget);
  });

  testWidgets('a kicked-off fixture shows both picks, points and result', (
    tester,
  ) async {
    await _pump(tester, const H2hRoundScreen(round: 2));

    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.fixture.f1.middle'))).data,
      '2 - 1',
    );
    expect(_inside('h2h.fixture.f1.mine', find.text('2 - 1')), findsOneWidget);
    expect(
      _inside('h2h.fixture.f1.mine', find.text('مضاعفة · دقيقة · +6 ن')),
      findsOneWidget,
    );
    expect(
      _inside('h2h.fixture.f1.theirs', find.text('0 - 3')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.fixture.f1.state'))).data,
      'انتهت',
    );
  });

  testWidgets('kickoff on the Riyadh clock; a moved fixture does not count', (
    tester,
  ) async {
    await _pump(tester, const H2hRoundScreen(round: 2));

    // 15:00 UTC is 18:00 in Riyadh, whatever the device's zone.
    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.fixture.f2.middle'))).data,
      '18:00',
    );
    expect(find.byKey(const Key('h2h.fixture.f3.void')), findsOneWidget);
    expect(find.byKey(const Key('h2h.detail.voidNote')), findsOneWidget);
    expect(
      _inside('h2h.fixture.f3.mine', find.text('لم تتوقع')),
      findsOneWidget,
    );
  });

  testWidgets('both sides counted; the opponent over kicked-off fixtures', (
    tester,
  ) async {
    await _pump(tester, const H2hRoundScreen(round: 2));

    String? cell(String key) => tester.widget<Text>(find.byKey(Key(key))).data;
    expect(cell('h2h.detail.totals.predicted.mine'), '2');
    expect(cell('h2h.detail.totals.predicted.theirs'), '1');
    expect(cell('h2h.detail.totals.doubles.mine'), '1');
    expect(cell('h2h.detail.totals.doubles.theirs'), '0');
    expect(cell('h2h.detail.totals.exact.mine'), '1');
  });

  testWidgets('against the group average there is no opponent pick', (
    tester,
  ) async {
    await _pump(
      tester,
      const H2hRoundScreen(round: 2),
      detail: _detail(average: true),
    );

    expect(find.text(h2hAverageOpponent), findsWidgets);
    expect(find.byKey(const Key('h2h.fixture.f1.theirs')), findsNothing);
    expect(find.byKey(const Key('h2h.fixture.f2.hidden')), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('h2h.detail.totals.predicted.theirs')),
          )
          .data,
      '—',
    );
  });

  testWidgets('a round of the list opens its page', (tester) async {
    final List<String> paths = await _pump(
      tester,
      const H2hScreen(initialSection: 2),
    );

    await tester.tap(find.byKey(const Key('h2h.round.2')));
    await tester.pumpAndSettle();

    expect(find.byType(H2hRoundScreen), findsOneWidget);
    expect(paths, contains('/me/h2h-league/rounds/2'));
  });

  testWidgets('the match card opens its round', (tester) async {
    await _pump(tester, const H2hScreen());

    await tester.tap(find.byKey(const Key('h2h.openRound')));
    await tester.pumpAndSettle();

    expect(find.byType(H2hRoundScreen), findsOneWidget);
    expect(find.byKey(const Key('h2h.detail.card')), findsOneWidget);
  });

  testWidgets('a refusal shows the error state', (tester) async {
    final AuthHarness harness = buildAuthHarness(
      (http.Request request) async => http.Response(
        jsonEncode(<String, Object?>{
          'schema_version': 1,
          'code': 'h2h.not_seated',
          'message': 'no seat',
        }),
        409,
        headers: const {'content-type': 'application/json'},
      ),
      seedToken: 'jwt',
    );
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        retry: (retryCount, error) => null,
        child: MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const H2hRoundScreen(round: 2),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('h2h.detail.title')), findsOneWidget);
    expect(find.byKey(const Key('browse.error')), findsOneWidget);
  });

  for (final double scale in <double>[1.3, 2.0]) {
    testWidgets('a 360px phone at text x$scale draws the whole page', (
      tester,
    ) async {
      await _pump(
        tester,
        const H2hRoundScreen(round: 2),
        size: const Size(360, 6000),
        textScale: scale,
      );

      expect(tester.takeException(), isNull);
      // Tall enough that the list builds its last item.
      expect(find.byKey(const Key('h2h.fixture.f3')), findsOneWidget);
      expect(find.byKey(const Key('h2h.detail.voidNote')), findsOneWidget);
    });
  }
}
