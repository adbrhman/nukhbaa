/// Widget tests for [H2hScreen] over the real [AuthApi] and the real
/// [ApiTransport], with only the socket faked ([buildAuthHarness]'s
/// `MockClient`). The tab asks `GET /me/h2h-league` through
/// `myH2hLeagueProvider` and draws what came back, so a tab that stopped
/// asking, asked the wrong path, or re-decided the server's table, zones or
/// results fails here.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/h2h_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _okJson(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

Future<http.Response> Function(http.Request) _serve(MyH2hLeagueDto league) {
  return (http.Request request) async {
    if (request.url.path == '/me/h2h-league') return _okJson(league.toJson());
    return http.Response('not found', 404);
  };
}

MyH2hLeagueDto _waiting(String state) => MyH2hLeagueDto(
  state: state,
  monthStart: '2026-10-01',
  startsOn: '2026-11-01',
  isPilot: false,
  myRank: 0,
  promotionZone: 0,
  relegationZone: 0,
  standings: const <H2hStandingDto>[],
  rounds: const <H2hRoundViewDto>[],
);

H2hStandingDto _line(
  int rank,
  String id,
  String name,
  int points, {
  bool me = false,
  List<String> form = const <String>[],
}) => H2hStandingDto(
  rank: rank,
  userId: id,
  displayName: name,
  played: form.length,
  won: form.where((r) => r == 'win').length,
  drawn: form.where((r) => r == 'draw').length,
  lost: form.where((r) => r == 'loss').length,
  leaguePoints: points,
  pointsFor: 10 * points,
  exactCount: 0,
  form: form,
  isMe: me,
);

/// A group of four in the second division: two go up, two go down. Round 1
/// was won, round 2 is being played, round 3 was void, round 4 is ahead.
MyH2hLeagueDto _open({bool pilot = false}) => MyH2hLeagueDto(
  state: 'open',
  monthStart: '2026-11-01',
  startsOn: '2026-11-01',
  isPilot: pilot,
  division: 2,
  groupIndex: 0,
  myRank: 1,
  promotionZone: 2,
  relegationZone: 2,
  standings: <H2hStandingDto>[
    _line(1, 'u-me', 'سامي', 3, me: true, form: const <String>['win']),
    _line(2, 'u-b', 'نورة', 1, form: const <String>['draw']),
    _line(3, 'u-c', '', 1, form: const <String>['draw']),
    _line(4, 'u-d', 'عمر', 0, form: const <String>['loss']),
  ],
  rounds: const <H2hRoundViewDto>[
    H2hRoundViewDto(
      round: 1,
      day: '2026-11-01',
      status: 'settled',
      fixtureCount: 7,
      opponentUserId: 'u-d',
      opponentName: 'عمر',
      myPoints: 10,
      opponentPoints: 6,
      result: 'win',
    ),
    H2hRoundViewDto(
      round: 2,
      day: '2026-11-04',
      status: 'live',
      fixtureCount: 8,
      opponentUserId: 'u-b',
      opponentName: 'نورة',
      myPoints: 3,
      opponentPoints: 5,
      result: 'loss',
    ),
    H2hRoundViewDto(
      round: 3,
      day: '2026-11-07',
      status: 'voided',
      fixtureCount: 0,
    ),
    H2hRoundViewDto(
      round: 4,
      day: '2026-11-12',
      status: 'upcoming',
      fixtureCount: 9,
      opponentUserId: 'u-d',
      opponentName: 'عمر',
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  AuthHarness harness, {
  Size size = const Size(1080, 4000),
  double textScale = 1,
}) async {
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
        home: const H2hScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inside(String key, Finder finder) =>
    find.descendant(of: find.byKey(Key(key)), matching: finder);

void main() {
  testWidgets('before the league opens: the date and the rules', (
    tester,
  ) async {
    final harness = buildAuthHarness(
      _serve(_waiting('not_started')),
      seedToken: 'jwt',
    );
    addTearDown(harness.dispose);
    await _pump(tester, harness);

    expect(find.byKey(const Key('h2h.title')), findsOneWidget);
    expect(find.byKey(const Key('h2h.state.not_started')), findsOneWidget);
    expect(find.text('ينطلق 1 نوفمبر'), findsOneWidget);
    expect(find.byKey(const Key('h2h.rules')), findsOneWidget);
    expect(find.byKey(const Key('h2h.banner')), findsNothing);
  });

  testWidgets('outside the draw: says why', (tester) async {
    final harness = buildAuthHarness(
      _serve(_waiting('not_in_draw')),
      seedToken: 'jwt',
    );
    addTearDown(harness.dispose);
    await _pump(tester, harness);

    expect(find.byKey(const Key('h2h.state.not_in_draw')), findsOneWidget);
    expect(find.text('لست في قرعة هذا الشهر'), findsOneWidget);
  });

  testWidgets('the open month: division, zones and the live match', (
    tester,
  ) async {
    final harness = buildAuthHarness(_serve(_open()), seedToken: 'jwt');
    addTearDown(harness.dispose);
    await _pump(tester, harness);

    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.division'))).data,
      'الدرجة الثانية',
    );
    expect(find.text('ترتيبك 1'), findsOneWidget);
    expect(find.text('يصعد أول 2'), findsOneWidget);
    expect(find.text('يهبط آخر 2'), findsOneWidget);
    expect(find.byKey(const Key('h2h.pilot')), findsNothing);

    // The round being played leads, with its score so far.
    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.featured.heading'))).data,
      'الجولة 2 · مواجهة اليوم · جارية',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.featured.mine'))).data,
      '3',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.featured.theirs'))).data,
      '5',
    );
    expect(
      _inside('h2h.featured', find.text('خسارة حتى الآن')),
      findsOneWidget,
    );
  });

  testWidgets('the table keeps the server order and marks both zones', (
    tester,
  ) async {
    final harness = buildAuthHarness(_serve(_open()), seedToken: 'jwt');
    addTearDown(harness.dispose);
    await _pump(tester, harness);

    final List<double> tops = <double>[
      for (final String id in <String>['u-me', 'u-b', 'u-c', 'u-d'])
        tester.getTopLeft(find.byKey(Key('h2h.standing.$id'))).dy,
    ];
    expect(tops, orderedEquals(<double>[...tops]..sort()));

    final AppTokens t = tester.element(find.byType(H2hScreen)).tokens;
    Color? zone(String id) =>
        (tester
                    .widget<Container>(find.byKey(Key('h2h.standing.$id.zone')))
                    .decoration!
                as BoxDecoration)
            .color;
    expect(zone('u-me'), t.success);
    expect(zone('u-b'), t.success);
    expect(zone('u-c'), t.error);
    expect(zone('u-d'), t.error);

    expect(
      tester
          .widget<Text>(find.byKey(const Key('h2h.standing.u-me.points')))
          .data,
      '3',
    );
    // A member without a name is still a line, never a blank.
    expect(_inside('h2h.standing.u-c', find.text('لاعب')), findsOneWidget);
  });

  testWidgets('every round: score, result, void and upcoming', (tester) async {
    final harness = buildAuthHarness(_serve(_open()), seedToken: 'jwt');
    addTearDown(harness.dispose);
    await _pump(tester, harness);

    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.round.1.score'))).data,
      '10 مقابل 6',
    );
    expect(_inside('h2h.round.1', find.text('فوز')), findsOneWidget);
    expect(_inside('h2h.round.2', find.text('جارية')), findsOneWidget);
    expect(_inside('h2h.round.3', find.text('أُلغيت')), findsOneWidget);
    expect(find.byKey(const Key('h2h.round.3.score')), findsNothing);
    expect(_inside('h2h.round.4', find.text('لم تبدأ')), findsOneWidget);
    expect(_inside('h2h.round.4', find.text('ضد عمر')), findsOneWidget);
  });

  testWidgets('a pilot month says its results do not count', (tester) async {
    final harness = buildAuthHarness(
      _serve(_open(pilot: true)),
      seedToken: 'jwt',
    );
    addTearDown(harness.dispose);
    await _pump(tester, harness);

    expect(find.byKey(const Key('h2h.pilot')), findsOneWidget);
  });

  testWidgets('a 360px phone at text x2 draws every line without overflow', (
    tester,
  ) async {
    final harness = buildAuthHarness(_serve(_open()), seedToken: 'jwt');
    addTearDown(harness.dispose);
    // Tall enough that the list builds its last item.
    await _pump(tester, harness, size: const Size(360, 9000), textScale: 2);

    expect(tester.takeException(), isNull);
    // The rounds are listed newest first: round 1 is the list's last item.
    expect(find.byKey(const Key('h2h.round.1')), findsOneWidget);
    expect(find.byKey(const Key('h2h.standing.u-d')), findsOneWidget);
  });

  testWidgets('a failed read shows the error under the tab header', (
    tester,
  ) async {
    final harness = buildAuthHarness(
      (http.Request request) async => http.Response(
        jsonEncode(<String, Object?>{
          'schema_version': 1,
          'code': 'db.down',
          'message': 'down',
        }),
        503,
        headers: const {'content-type': 'application/json'},
      ),
      seedToken: 'jwt',
    );
    addTearDown(harness.dispose);
    await _pump(tester, harness);

    expect(find.byKey(const Key('h2h.title')), findsOneWidget);
    expect(find.byKey(const Key('browse.error')), findsOneWidget);
  });
}
