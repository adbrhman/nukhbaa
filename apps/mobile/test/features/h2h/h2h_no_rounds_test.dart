/// A seated month before its first round: the match section and the rounds
/// section each say "no round yet" once, and no empty match is drawn.
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

const MyH2hLeagueDto _league = MyH2hLeagueDto(
  state: 'open',
  monthStart: '2026-11-01',
  startsOn: '2026-11-01',
  isPilot: false,
  division: 1,
  groupIndex: 0,
  myRank: 1,
  promotionZone: 0,
  relegationZone: 3,
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
  rounds: <H2hRoundViewDto>[],
);

Future<void> _pump(WidgetTester tester, int section) async {
  final harness = buildAuthHarness((http.Request request) async {
    if (request.url.path == '/me/h2h-league') {
      return http.Response(
        jsonEncode(_league.toJson()),
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
        home: H2hScreen(initialSection: section, onOpenMatches: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the match section: no round yet, said once', (tester) async {
    await _pump(tester, 0);

    expect(find.byKey(const Key('h2h.banner')), findsOneWidget);
    expect(find.byKey(const Key('h2h.featured')), findsNothing);
    expect(find.byKey(const Key('h2h.goToMatches')), findsNothing);
    expect(find.byKey(const Key('h2h.noRounds')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('h2h.progress'))).data,
      'لا جولات بعد',
    );
  });

  testWidgets('the rounds section: no round yet, said once', (tester) async {
    await _pump(tester, 2);

    expect(find.byKey(const Key('h2h.noRounds')), findsOneWidget);
    expect(find.byKey(const Key('h2h.rounds.note')), findsNothing);
  });

  testWidgets('the first division has nowhere to go up', (tester) async {
    await _pump(tester, 1);

    expect(find.byKey(const Key('h2h.zone.up')), findsNothing);
    expect(find.text('يهبط آخر 3'), findsOneWidget);
  });
}
