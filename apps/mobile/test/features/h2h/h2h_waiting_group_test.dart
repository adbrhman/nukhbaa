/// The waiting group on the player's screen (NK277, December 2026 on):
/// the server's `waiting_for` and `group_start` reach the card through the
/// real screen and its JSON; a group drawn at the start, or a payload from
/// a server before script 277, shows nothing new; the line fits a 360px
/// phone at text x2; and December's rules tell it.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/h2h_screen.dart';
import 'package:mobile/features/h2h/h2h_texts.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

MyH2hLeagueDto _league({int groupStart = 1, int? waitingFor}) => MyH2hLeagueDto(
  state: 'open',
  monthStart: '2026-12-01',
  startsOn: '2026-11-01',
  isPilot: false,
  division: 2,
  groupIndex: 2,
  myRank: 1,
  promotionZone: 0,
  relegationZone: 0,
  daysLeft: 20,
  groupStart: groupStart,
  waitingFor: waitingFor,
  standings: const <H2hStandingDto>[
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
  rounds: const <H2hRoundViewDto>[],
);

Future<void> _pump(
  WidgetTester tester,
  Map<String, Object?> json, {
  Size size = const Size(1080, 4000),
  double textScale = 1,
}) async {
  final harness = buildAuthHarness((http.Request request) async {
    if (request.url.path == '/me/h2h-league') {
      return http.Response(
        jsonEncode(json),
        200,
        headers: const {'content-type': 'application/json'},
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
        home: H2hScreen(initialSection: 0, onOpenMatches: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String? _note(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('h2h.waiting.text'))).data;

void main() {
  testWidgets('a waiting group: the card says how many it still needs', (
    tester,
  ) async {
    await _pump(tester, _league(groupStart: 20, waitingFor: 15).toJson());

    expect(find.byKey(const Key('h2h.waiting')), findsOneWidget);
    expect(_note(tester), h2hWaitingLabel(15));
    expect(_note(tester), contains('15 لاعبًا'));
  });

  testWidgets('a group that started at round 15: results kept, nobody up or '
      'down', (tester) async {
    await _pump(tester, _league(groupStart: 15).toJson());

    expect(_note(tester), h2hGroupStartLabel(15));
    expect(_note(tester), contains('لا صعود منها'));
  });

  testWidgets('a group that started at round 8 takes part: only its round', (
    tester,
  ) async {
    await _pump(tester, _league(groupStart: 8).toJson());

    expect(_note(tester), 'بدأت مجموعتك من الجولة 8.');
  });

  testWidgets('a group drawn at the start, and a server before 277: nothing '
      'new', (tester) async {
    await _pump(tester, _league().toJson());
    expect(find.byKey(const Key('h2h.banner')), findsOneWidget);
    expect(find.byKey(const Key('h2h.waiting')), findsNothing);

    final old = _league().toJson()
      ..remove('group_start')
      ..remove('waiting_for');
    await _pump(tester, old);
    expect(find.byKey(const Key('h2h.banner')), findsOneWidget);
    expect(find.byKey(const Key('h2h.waiting')), findsNothing);
  });

  testWidgets('the waiting line fits a 360px phone at text x2', (tester) async {
    await _pump(
      tester,
      _league(groupStart: 20, waitingFor: 2).toJson(),
      size: const Size(360, 3000),
      textScale: 2,
    );

    expect(find.byKey(const Key('h2h.waiting')), findsOneWidget);
    expect(_note(tester), contains('لاعبان'));
    expect(tester.takeException(), isNull);
  });

  test('players in words', () {
    expect(h2hPlayersWords(1), 'لاعب واحد');
    expect(h2hPlayersWords(2), 'لاعبان');
    expect(h2hPlayersWords(7), '7 لاعبين');
    expect(h2hPlayersWords(19), '19 لاعبًا');
  });

  test('December\'s rules tell the waiting group and the late group', () {
    final String all = h2hDecemberRules.join('\n');
    expect(all, contains('عند أول توقّع له مجموعة الانتظار'));
    expect(all, contains('حتى يكتمل 20 لاعبًا'));
    expect(all, contains('ولا تتأثر المجموعات الأخرى'));
    expect(all, contains('أقل من 7 جولات'));
    expect(all, isNot(contains('يدخل القرعة التالية في آخر المجموعات')));
    expect(
      h2hRulesForMonth('2026-11-01'),
      isNot(contains(h2hDecemberRules.last)),
    );
  });
}
