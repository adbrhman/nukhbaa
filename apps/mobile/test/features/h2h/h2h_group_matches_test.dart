/// The fourth section of the head-to-head tab (المواجهات): every match of a
/// round in the caller's group, over the real [AuthApi] with only the
/// socket faked. It opens on the round that matters now, switches rounds
/// from its list, puts the caller's match first and opens it, and shows
/// names and points only.
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

/// Round 1 settled, round 2 live (the one that matters now), round 3 next.
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
  daysLeft: 20,
  standings: <H2hStandingDto>[],
  rounds: <H2hRoundViewDto>[
    H2hRoundViewDto(
      round: 1,
      day: '2026-11-04',
      status: 'settled',
      fixtureCount: 6,
    ),
    H2hRoundViewDto(
      round: 2,
      day: '2026-11-07',
      status: 'live',
      fixtureCount: 7,
    ),
    H2hRoundViewDto(
      round: 3,
      day: '2026-11-10',
      status: 'open',
      fixtureCount: 8,
    ),
  ],
);

H2hGroupRoundDto _group(int round) => switch (round) {
  1 => const H2hGroupRoundDto(
    round: 1,
    day: '2026-11-04',
    status: 'settled',
    matches: <H2hGroupMatchDto>[
      H2hGroupMatchDto(
        homeUserId: 'u-me',
        homeName: 'سامي',
        homeIsMe: true,
        homePoints: 9,
        awayUserId: 'u-2',
        awayName: 'نورة',
        awayPoints: 4,
        winner: 'home',
      ),
      H2hGroupMatchDto(
        homeUserId: 'u-3',
        homeName: 'عمر',
        homePoints: 0,
        awayUserId: 'u-4',
        awayName: 'خالد',
        awayPoints: 0,
        winner: 'none',
      ),
    ],
  ),
  2 => const H2hGroupRoundDto(
    round: 2,
    day: '2026-11-07',
    status: 'live',
    matches: <H2hGroupMatchDto>[
      H2hGroupMatchDto(
        homeUserId: 'u-me',
        homeName: 'سامي',
        homeIsMe: true,
        homePoints: 3,
        awayUserId: 'u-3',
        awayName: 'عمر',
        awayPoints: 6,
        winner: 'away',
      ),
      H2hGroupMatchDto(
        homeUserId: 'u-2',
        homeName: 'نورة',
        homePoints: 5,
        awayPoints: 4.5,
        winner: 'home',
      ),
    ],
  ),
  _ => const H2hGroupRoundDto(
    round: 3,
    day: '2026-11-10',
    status: 'open',
    matches: <H2hGroupMatchDto>[
      H2hGroupMatchDto(
        homeUserId: 'u-me',
        homeName: 'سامي',
        homeIsMe: true,
        awayUserId: 'u-4',
        awayName: 'خالد',
      ),
    ],
  ),
};

Future<List<String>> _pump(
  WidgetTester tester, {
  Size size = const Size(1080, 4000),
  double textScale = 1,
  bool failGroup = false,
  MyH2hLeagueDto month = _month,
}) async {
  final List<String> paths = <String>[];
  final AuthHarness harness = buildAuthHarness((http.Request request) async {
    paths.add(request.url.path);
    if (request.url.path == '/me/h2h-league') return _okJson(month.toJson());
    final RegExpMatch? m = RegExp(
      r'^/me/h2h-league/rounds/(\d+)/matches$',
    ).firstMatch(request.url.path);
    if (m != null) {
      if (failGroup) {
        return http.Response(
          jsonEncode(<String, Object?>{
            'schema_version': 1,
            'code': 'db.down',
            'message': 'down',
          }),
          503,
          headers: const {'content-type': 'application/json'},
        );
      }
      return _okJson(_group(int.parse(m.group(1)!)).toJson());
    }
    if (request.url.path == '/me/h2h-league/rounds/2') {
      return _okJson(
        const MyH2hRoundDto(
          round: 2,
          day: '2026-11-07',
          status: 'live',
          fixtureCount: 0,
          mine: H2hSideTotalsDto(predicted: 0, exact: 0, doubles: 0),
          fixtures: <H2hRoundFixtureDto>[],
        ).toJson(),
      );
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
        home: const H2hScreen(initialSection: 3),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return paths;
}

Finder _inside(String key, Finder finder) =>
    find.descendant(of: find.byKey(Key(key)), matching: finder);

String? _text(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).data;

void main() {
  test('the fourth section is the group matches', () {
    expect(h2hSectionLabels, <String>[
      'مواجهتي',
      'الترتيب',
      'الجولات',
      'المواجهات',
    ]);
  });

  testWidgets('opens on the live round, the caller first, points only', (
    tester,
  ) async {
    final List<String> paths = await _pump(tester);

    expect(paths, contains('/me/h2h-league/rounds/2/matches'));
    expect(
      _text(tester, find.byKey(const Key('h2h.matches.round.label'))),
      'الجولة 2 · 7 نوفمبر',
    );
    final double mineTop = tester
        .getTopLeft(find.byKey(const Key('h2h.pair.mine')))
        .dy;
    final double otherTop = tester
        .getTopLeft(find.byKey(const Key('h2h.pair.1')))
        .dy;
    expect(mineTop, lessThan(otherTop));

    expect(
      _text(
        tester,
        _inside('h2h.pair.mine', find.byKey(const Key('h2h.pair.home'))),
      ),
      '3',
    );
    expect(
      _text(
        tester,
        _inside('h2h.pair.mine', find.byKey(const Key('h2h.pair.away'))),
      ),
      '6',
    );
    expect(
      _text(
        tester,
        _inside('h2h.pair.mine', find.byKey(const Key('h2h.pair.state'))),
      ),
      'جارية · يتقدم عمر',
    );
    // The other pair plays the group average.
    expect(
      _inside('h2h.pair.1', find.text(h2hAverageOpponent)),
      findsOneWidget,
    );
    expect(
      _text(
        tester,
        _inside('h2h.pair.1', find.byKey(const Key('h2h.pair.away'))),
      ),
      '4.5',
    );
    expect(find.byKey(const Key('h2h.matches.note')), findsOneWidget);
  });

  testWidgets('another round from the list: the settled results', (
    tester,
  ) async {
    final List<String> paths = await _pump(tester);

    await tester.tap(find.byKey(const Key('h2h.matches.round')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('h2h.matches.pick.1')));
    await tester.pumpAndSettle();

    expect(paths, contains('/me/h2h-league/rounds/1/matches'));
    expect(
      _text(tester, find.byKey(const Key('h2h.matches.round.label'))),
      'الجولة 1 · 4 نوفمبر',
    );
    expect(
      _text(
        tester,
        _inside('h2h.pair.mine', find.byKey(const Key('h2h.pair.state'))),
      ),
      'فوز سامي',
    );
    expect(
      _text(
        tester,
        _inside('h2h.pair.1', find.byKey(const Key('h2h.pair.state'))),
      ),
      'خسارة للطرفين',
    );
  });

  testWidgets('a round ahead: the pairs, no points', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('h2h.matches.round')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('h2h.matches.pick.3')));
    await tester.pumpAndSettle();

    expect(
      _text(
        tester,
        _inside('h2h.pair.mine', find.byKey(const Key('h2h.pair.home'))),
      ),
      '–',
    );
    expect(
      _text(
        tester,
        _inside('h2h.pair.mine', find.byKey(const Key('h2h.pair.state'))),
      ),
      'لم تبدأ',
    );
    expect(_inside('h2h.pair.mine', find.text('خالد')), findsOneWidget);
  });

  testWidgets("the caller's match opens its round", (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('h2h.pair.mine')));
    await tester.pumpAndSettle();

    expect(find.byType(H2hRoundScreen), findsOneWidget);
  });

  testWidgets('a failed read says so and offers to try again', (tester) async {
    await _pump(tester, failGroup: true);

    expect(find.byKey(const Key('h2h.matches.error')), findsOneWidget);
    expect(find.byKey(const Key('h2h.matches.retry')), findsOneWidget);
    // The rest of the tab stands.
    expect(find.byKey(const Key('h2h.banner')), findsOneWidget);
  });

  testWidgets('no round yet: said once, nothing asked', (tester) async {
    final List<String> paths = await _pump(
      tester,
      month: const MyH2hLeagueDto(
        state: 'open',
        monthStart: '2026-11-01',
        startsOn: '2026-11-01',
        isPilot: false,
        division: 2,
        groupIndex: 0,
        myRank: 1,
        promotionZone: 2,
        relegationZone: 2,
        standings: <H2hStandingDto>[],
        rounds: <H2hRoundViewDto>[],
      ),
    );

    expect(find.byKey(const Key('h2h.noRounds')), findsOneWidget);
    expect(paths.where((p) => p.endsWith('/matches')), isEmpty);
  });

  for (final double scale in <double>[1.3, 2.0]) {
    testWidgets('a 360px phone at text x$scale draws every match', (
      tester,
    ) async {
      await _pump(tester, size: const Size(360, 6000), textScale: scale);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('h2h.pair.mine')), findsOneWidget);
      expect(find.byKey(const Key('h2h.pair.1')), findsOneWidget);
      expect(find.byKey(const Key('h2h.matches.note')), findsOneWidget);
    });
  }
}
