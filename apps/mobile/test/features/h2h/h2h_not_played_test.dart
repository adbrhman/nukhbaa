/// Before the month's first settled round every line of the table is level:
/// the tab shows no place (an order by seat time read as "you are last") and
/// says the order comes after the first round. Once a round is settled the
/// place returns. At larger text the record line spells its words out.
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

H2hStandingDto _line(int rank, String id, {required bool me, int won = 0}) =>
    H2hStandingDto(
      rank: rank,
      userId: id,
      displayName: 'لاعب $rank',
      played: won,
      won: won,
      drawn: 0,
      lost: 0,
      leaguePoints: 3 * won,
      pointsFor: 7 * won,
      exactCount: 0,
      form: <String>[for (int i = 0; i < won; i++) 'win'],
      isMe: me,
    );

MyH2hLeagueDto _league({required bool played}) => MyH2hLeagueDto(
  state: 'open',
  monthStart: '2026-10-01',
  startsOn: '2026-11-01',
  isPilot: true,
  division: 1,
  groupIndex: 0,
  myRank: 2,
  promotionZone: 0,
  relegationZone: 3,
  daysLeft: 21,
  standings: <H2hStandingDto>[
    _line(1, 'u-a', me: false, won: played ? 1 : 0),
    _line(2, 'u-me', me: true),
  ],
  rounds: const <H2hRoundViewDto>[
    H2hRoundViewDto(
      round: 1,
      day: '2026-10-10',
      status: 'open',
      fixtureCount: 22,
      opponentUserId: 'u-a',
      opponentName: 'لاعب 1',
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  MyH2hLeagueDto league, {
  int section = 0,
  double textScale = 1,
}) async {
  final harness = buildAuthHarness((http.Request request) async {
    if (request.url.path == '/me/h2h-league') {
      return http.Response(
        jsonEncode(league.toJson()),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }
    return http.Response('not found', 404);
  }, seedToken: 'jwt');
  addTearDown(harness.dispose);
  tester.view.physicalSize = const Size(1080, 4000);
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
        home: H2hScreen(initialSection: section),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

void main() {
  testWidgets('before any settled round: no place, and a note why', (
    tester,
  ) async {
    await _pump(tester, _league(played: false));

    expect(find.byKey(const Key('h2h.banner')), findsOneWidget);
    expect(find.byKey(const Key('h2h.myRank')), findsNothing);
    expect(_text(tester, 'h2h.myRank.none'), '—');

    await tester.tap(find.byKey(const Key('h2h.section.1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('h2h.table.notPlayed')), findsOneWidget);
    expect(_text(tester, 'h2h.standing.u-me.rank'), '—');
    expect(_text(tester, 'h2h.table.me.rank'), 'لم يتحدد الترتيب بعد');
  });

  testWidgets('after a settled round: the place, and no note', (tester) async {
    await _pump(tester, _league(played: true), section: 1);

    expect(_text(tester, 'h2h.myRank'), '2 من 2');
    expect(find.byKey(const Key('h2h.table.notPlayed')), findsNothing);
    expect(_text(tester, 'h2h.standing.u-me.rank'), '2');
    expect(_text(tester, 'h2h.table.me.rank'), 'المركز 2 من 2');
  });

  testWidgets('at larger text the record line spells its words out', (
    tester,
  ) async {
    await _pump(tester, _league(played: true), section: 1, textScale: 1.3);

    expect(
      _text(tester, 'h2h.standing.u-a.record'),
      'لعب 1 · فوز 1 · تعادل 0 · خسارة 0 · نقاط التوقع 7',
    );
  });
}
