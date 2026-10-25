/// The secret opponent (script 147, decided 2026-10-25) through the real
/// screens over the real [AuthApi] and transport, only the socket faked:
/// until the round's last kickoff the server sends `opponent_hidden` with no
/// opponent, and every screen must say the opponent is secret -- never the
/// group average, which the same empty opponent meant before.
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

/// 20:00 UTC, the last kickoff of round 2: 23:00 on the Riyadh clock.
const String _revealsAt = '2026-11-04T20:00:00.000Z';

/// Round 2 is being played, its opponent still secret; round 3 is next.
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
      fixtureCount: 2,
      myPoints: 6,
      firstKickoff: '2026-11-04T12:00:00.000Z',
      opponentHidden: true,
      revealsAt: _revealsAt,
    ),
    H2hRoundViewDto(
      round: 3,
      day: '2026-11-06',
      status: 'open',
      fixtureCount: 7,
      firstKickoff: '2026-11-06T15:00:00.000Z',
      opponentHidden: true,
    ),
  ],
);

/// Round 2 in detail while its opponent is secret: f1 finished, f2 not
/// started; nothing of theirs on either.
const MyH2hRoundDto _detail = MyH2hRoundDto(
  round: 2,
  day: '2026-11-04',
  status: 'live',
  fixtureCount: 2,
  firstKickoff: '2026-11-04T12:00:00.000Z',
  myPoints: 6,
  opponentHidden: true,
  revealsAt: _revealsAt,
  mine: H2hSideTotalsDto(predicted: 2, exact: 1, doubles: 1),
  fixtures: <H2hRoundFixtureDto>[
    H2hRoundFixtureDto(
      fixtureId: 'f1',
      homeTeam: 'الهلال',
      awayTeam: 'النصر',
      kickoffAt: '2026-11-04T12:00:00.000Z',
      state: 'finished',
      homeGoals: 2,
      awayGoals: 1,
      mine: H2hPickDto(
        homeGoals: 2,
        awayGoals: 1,
        isDouble: true,
        points: 6,
        exact: true,
      ),
      theirsHidden: true,
    ),
    H2hRoundFixtureDto(
      fixtureId: 'f2',
      homeTeam: 'الاتحاد',
      awayTeam: 'الأهلي',
      kickoffAt: '2026-11-04T20:00:00.000Z',
      state: 'not_started',
      mine: H2hPickDto(homeGoals: 1, awayGoals: 0, isDouble: false),
      theirsHidden: true,
    ),
  ],
);

/// The pairs of the round chosen in the group section: secret.
const H2hGroupRoundDto _pairs = H2hGroupRoundDto(
  round: 2,
  day: '2026-11-04',
  status: 'live',
  matches: <H2hGroupMatchDto>[],
  matchesHidden: true,
  revealsAt: _revealsAt,
);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(1080, 4000),
  double textScale = 1,
}) async {
  final AuthHarness harness = buildAuthHarness((http.Request request) async {
    switch (request.url.path) {
      case '/me/h2h-league':
        return _okJson(_month.toJson());
      case '/me/h2h-league/rounds/2':
        return _okJson(_detail.toJson());
      case '/me/h2h-league/rounds/2/matches':
        return _okJson(_pairs.toJson());
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
}

Finder _inside(String key, Finder finder) =>
    find.descendant(of: find.byKey(Key(key)), matching: finder);

DateTime _now() => DateTime.utc(2026, 11, 4, 16);

void main() {
  testWidgets('the match card names nobody, shows my points, and when the '
      'opponent is named', (tester) async {
    await _pump(tester, H2hScreen(now: _now));

    expect(
      _inside('h2h.featured', find.text(h2hSecretOpponent)),
      findsOneWidget,
    );
    expect(find.byKey(const Key('h2h.side.secret')), findsOneWidget);
    expect(find.text(h2hAverageOpponent), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.featured.mine'))).data,
      '6',
    );
    expect(find.byKey(const Key('h2h.featured.theirs')), findsNothing);
    expect(
      _inside('h2h.featured.reveal', find.text('يُكشف الساعة 23:00')),
      findsOneWidget,
    );
  });

  testWidgets('the rounds list says secret, my points only, and when', (
    tester,
  ) async {
    await _pump(tester, H2hScreen(now: _now, initialSection: 2));

    expect(
      _inside('h2h.round.2', find.text('ضد $h2hSecretOpponent')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.round.2.score'))).data,
      'نقاطك 6',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.round.2.reveal'))).data,
      'يُكشف الساعة 23:00',
    );
    expect(
      _inside('h2h.round.3', find.text('ضد $h2hSecretOpponent')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.round.3.reveal'))).data,
      'يُكشف عند انطلاق آخر مباراة في الجولة',
    );
    expect(find.text(h2hAverageOpponent), findsNothing);
  });

  testWidgets('the round page withholds every pick of theirs, not as the '
      'group average', (tester) async {
    await _pump(tester, const H2hRoundScreen(round: 2));

    expect(
      _inside('h2h.detail.card', find.text(h2hSecretOpponent)),
      findsOneWidget,
    );
    expect(find.text(h2hAverageOpponent), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.detail.mine'))).data,
      '6',
    );
    expect(find.byKey(const Key('h2h.detail.theirs')), findsNothing);
    expect(
      _inside('h2h.detail.reveal', find.text('يُكشف الساعة 23:00')),
      findsOneWidget,
    );
    for (final String id in <String>['f1', 'f2']) {
      expect(
        _inside('h2h.fixture.$id.hidden', find.text(h2hSecretPick)),
        findsOneWidget,
        reason: id,
      );
      expect(find.byKey(Key('h2h.fixture.$id.theirs')), findsNothing);
    }
    expect(
      _inside('h2h.detail.totals', find.text(h2hSecretOpponent)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('h2h.detail.totals.predicted.theirs')),
          )
          .data,
      '—',
    );
  });

  testWidgets('the group section shows no pairs, only when they come', (
    tester,
  ) async {
    await _pump(tester, H2hScreen(now: _now, initialSection: 3));

    expect(
      _inside('h2h.matches.secret', find.text(h2hSecretPairs)),
      findsOneWidget,
    );
    expect(
      _inside('h2h.matches.secret', find.text('يُكشف الساعة 23:00')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('h2h.pair.mine')), findsNothing);
    expect(find.byKey(const Key('h2h.matches.note')), findsNothing);
  });

  testWidgets('the rules say the opponent is secret until the last kickoff', (
    tester,
  ) async {
    expect(
      h2hRules,
      contains('خصمك في كل جولة سري، ويُكشف عند انطلاق آخر مباراة فيها.'),
    );
  });

  for (final double scale in <double>[1.3, 2.0]) {
    testWidgets('a 360px phone at text x$scale draws every secret screen', (
      tester,
    ) async {
      for (final int section in <int>[0, 2, 3]) {
        // A fresh screen each time: the section is the state's first value.
        await tester.pumpWidget(const SizedBox());
        await _pump(
          tester,
          H2hScreen(now: _now, initialSection: section),
          size: const Size(360, 6000),
          textScale: scale,
        );
        expect(tester.takeException(), isNull, reason: 'section $section');
      }
      expect(find.byKey(const Key('h2h.matches.secret')), findsOneWidget);

      await _pump(
        tester,
        const H2hRoundScreen(round: 2),
        size: const Size(360, 6000),
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
      // Tall enough that the list builds its last item.
      expect(find.byKey(const Key('h2h.fixture.f2.hidden')), findsOneWidget);
      expect(find.byKey(const Key('h2h.detail.reveal')), findsOneWidget);
    });
  }
}
