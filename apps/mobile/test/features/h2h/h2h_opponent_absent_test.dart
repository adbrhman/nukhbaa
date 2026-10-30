/// The absent opponent (decided 2026-10-29, rules of December 2026) through
/// the real screens over the real [AuthApi] and transport, only the socket
/// faked. When the opponent was absent and the caller predicted, the server
/// sends `opponent_absent` with the group average as the opponent's points:
/// the match card, the round page and the group section must say so, name
/// the group average instead of the absent player, and say nothing when the
/// opponent came.
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

/// What the screens say under the match when the opponent was absent.
const String _absentLine = 'غاب خصمك: واجهت متوسط المجموعة (4.5 نقطة).';

const List<H2hStandingDto> _standings = <H2hStandingDto>[
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
];

/// December's round 2, being played. The server names the absent player
/// still; the screens must show the group average in his place.
MyH2hLeagueDto _month({required bool absent}) => MyH2hLeagueDto(
  state: 'open',
  monthStart: '2026-12-01',
  startsOn: '2026-12-01',
  isPilot: false,
  division: 2,
  groupIndex: 0,
  myRank: 1,
  promotionZone: 2,
  relegationZone: 2,
  daysLeft: 26,
  standings: _standings,
  rounds: <H2hRoundViewDto>[
    H2hRoundViewDto(
      round: 2,
      day: '2026-12-04',
      status: 'live',
      fixtureCount: 6,
      firstKickoff: '2026-12-04T12:00:00.000Z',
      opponentUserId: 'u-b',
      opponentName: 'نورة',
      myPoints: 6,
      opponentPoints: 4.5,
      result: 'win',
      opponentAbsent: absent,
    ),
  ],
);

MyH2hRoundDto _detail({required bool absent}) => MyH2hRoundDto(
  round: 2,
  day: '2026-12-04',
  status: 'live',
  fixtureCount: 1,
  firstKickoff: '2026-12-04T12:00:00.000Z',
  opponentUserId: 'u-b',
  opponentName: 'نورة',
  myPoints: 6,
  opponentPoints: 4.5,
  result: 'win',
  mine: const H2hSideTotalsDto(predicted: 1, exact: 1, doubles: 0),
  opponentAbsent: absent,
  fixtures: <H2hRoundFixtureDto>[
    H2hRoundFixtureDto(
      fixtureId: 'f1',
      homeTeam: 'الهلال',
      awayTeam: 'النصر',
      kickoffAt: '2026-12-04T12:00:00.000Z',
      state: 'finished',
      homeGoals: 2,
      awayGoals: 1,
      mine: const H2hPickDto(
        homeGoals: 2,
        awayGoals: 1,
        isDouble: false,
        points: 3,
        exact: true,
      ),
      theirs: absent
          ? null
          : const H2hPickDto(
              homeGoals: 0,
              awayGoals: 0,
              isDouble: false,
              points: 0,
            ),
      theirsHidden: false,
    ),
  ],
);

/// My match, and another pair of the group; both against an absent player
/// when [absent].
H2hGroupRoundDto _pairs({required bool absent}) => H2hGroupRoundDto(
  round: 2,
  day: '2026-12-04',
  status: 'live',
  matches: <H2hGroupMatchDto>[
    H2hGroupMatchDto(
      homeUserId: 'u-me',
      homeName: 'سامي',
      homeIsMe: true,
      homePoints: 6,
      awayUserId: 'u-b',
      awayName: 'نورة',
      awayPoints: 4.5,
      winner: 'home',
      awayAbsent: absent,
    ),
    H2hGroupMatchDto(
      homeUserId: 'u-3',
      homeName: 'عمر',
      homePoints: 5,
      awayUserId: 'u-4',
      awayName: 'خالد',
      awayPoints: 3.5,
      winner: 'home',
      awayAbsent: absent,
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required bool absent,
  Size size = const Size(1080, 4000),
}) async {
  final AuthHarness harness = buildAuthHarness((http.Request request) async {
    switch (request.url.path) {
      case '/me/h2h-league':
        return _okJson(_month(absent: absent).toJson());
      case '/me/h2h-league/rounds/2':
        return _okJson(_detail(absent: absent).toJson());
      case '/me/h2h-league/rounds/2/matches':
        return _okJson(_pairs(absent: absent).toJson());
    }
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
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inside(String key, Finder finder) =>
    find.descendant(of: find.byKey(Key(key)), matching: finder);

DateTime _now() => DateTime.utc(2026, 12, 4, 16);

void main() {
  group('the match card of the first section', () {
    testWidgets('says the opponent was absent and names the group average', (
      tester,
    ) async {
      await _pump(tester, H2hScreen(now: _now), absent: true);

      expect(
        tester
            .widget<Text>(find.byKey(const Key('h2h.featured.opponentAbsent')))
            .data,
        _absentLine,
      );
      expect(
        _inside('h2h.featured', find.text(h2hAverageOpponent)),
        findsOneWidget,
      );
      expect(_inside('h2h.featured', find.text('نورة')), findsNothing);
    });

    testWidgets('says nothing when the opponent came', (tester) async {
      await _pump(tester, H2hScreen(now: _now), absent: false);

      expect(
        find.byKey(const Key('h2h.featured.opponentAbsent')),
        findsNothing,
      );
      expect(_inside('h2h.featured', find.text('نورة')), findsOneWidget);
      expect(find.text(h2hAverageOpponent), findsNothing);
    });
  });

  group('the round page', () {
    testWidgets('says the opponent was absent and names the group average', (
      tester,
    ) async {
      await _pump(tester, const H2hRoundScreen(round: 2), absent: true);

      expect(
        tester
            .widget<Text>(find.byKey(const Key('h2h.detail.opponentAbsent')))
            .data,
        _absentLine,
      );
      expect(
        _inside('h2h.detail.card', find.text(h2hAverageOpponent)),
        findsOneWidget,
      );
      expect(_inside('h2h.detail.card', find.text('نورة')), findsNothing);
      expect(find.byKey(const Key('h2h.fixture.f1.theirs')), findsNothing);
    });

    testWidgets('says nothing when the opponent came', (tester) async {
      await _pump(tester, const H2hRoundScreen(round: 2), absent: false);

      expect(find.byKey(const Key('h2h.detail.opponentAbsent')), findsNothing);
      expect(_inside('h2h.detail.card', find.text('نورة')), findsOneWidget);
      expect(find.byKey(const Key('h2h.fixture.f1.theirs')), findsOneWidget);
    });
  });

  group('the group section', () {
    testWidgets('says it for my match and for the other pairs', (tester) async {
      await _pump(
        tester,
        H2hScreen(now: _now, initialSection: 3),
        absent: true,
      );

      expect(
        find.byKey(const Key('h2h.pair.opponentAbsent')),
        findsNWidgets(2),
      );
      expect(find.text(_absentLine), findsOneWidget);
      expect(
        find.text('غاب أحد طرفي المواجهة؛ احتُسب متوسط المجموعة (3.5 نقطة).'),
        findsOneWidget,
      );
    });

    testWidgets('says nothing when everybody came', (tester) async {
      await _pump(
        tester,
        H2hScreen(now: _now, initialSection: 3),
        absent: false,
      );

      expect(find.byKey(const Key('h2h.pair.opponentAbsent')), findsNothing);
      expect(find.text('نورة'), findsWidgets);
    });
  });

  for (final double scale in <double>[1.3, 2.0]) {
    testWidgets('a 360px phone at text x$scale draws the absent screens', (
      tester,
    ) async {
      for (final Widget home in <Widget>[
        H2hScreen(now: _now),
        const H2hRoundScreen(round: 2),
        H2hScreen(now: _now, initialSection: 3),
      ]) {
        await tester.pumpWidget(const SizedBox());
        final AuthHarness harness = buildAuthHarness((
          http.Request request,
        ) async {
          switch (request.url.path) {
            case '/me/h2h-league':
              return _okJson(_month(absent: true).toJson());
            case '/me/h2h-league/rounds/2':
              return _okJson(_detail(absent: true).toJson());
            case '/me/h2h-league/rounds/2/matches':
              return _okJson(_pairs(absent: true).toJson());
          }
          return http.Response('not found', 404);
        }, seedToken: 'jwt');
        addTearDown(harness.dispose);
        tester.view.physicalSize = const Size(360, 6000);
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
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: home,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('غاب'), findsWidgets);
      }
    });
  }
}
