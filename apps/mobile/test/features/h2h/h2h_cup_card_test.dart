/// بطاقة كأس النخبة للاعب المتأهل عبر الشاشة الحقيقية و`AuthApi` الحقيقي
/// فوق خادم الاختبار: مساره ومواجهته ومن سيواجه ويوم المرحلة ونتيجتها
/// واللقب؛ ومن لم يتأهل أو فشل طلب الكأس لا يرى البطاقة وتبقى الشاشة.
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

MyH2hLeagueDto _league() => MyH2hLeagueDto(
  state: 'open',
  monthStart: '2026-11-01',
  startsOn: '2026-11-01',
  isPilot: false,
  division: 1,
  groupIndex: 0,
  myRank: 1,
  promotionZone: 3,
  relegationZone: 0,
  standings: const <H2hStandingDto>[],
  rounds: const <H2hRoundViewDto>[],
);

H2hCupPlayerDto _p(String id, String name, int group, {bool me = false}) =>
    H2hCupPlayerDto(
      userId: id,
      displayName: name,
      groupNumber: group,
      isMe: me,
    );

final H2hCupPlayerDto _me = _p('u-me', 'سامي', 1, me: true);
final H2hCupPlayerDto _noura = _p('u-n', 'نورة', 3);
final H2hCupPlayerDto _omar = _p('u-o', 'عمر', 2);
final H2hCupPlayerDto _huda = _p('u-h', 'هدى', 4);

H2hCupPairDto _pair(
  int slot,
  H2hCupPlayerDto home,
  H2hCupPlayerDto away, {
  String? winner,
  String? outcome,
  int? homePoints,
  int? awayPoints,
}) => H2hCupPairDto(
  slot: slot,
  home: home,
  away: away,
  isMine: home.isMe || away.isMe,
  decided: winner != null || outcome != null,
  outcome: outcome,
  winnerUserId: winner,
  homePoints: homePoints,
  awayPoints: awayPoints,
);

/// اللاعب (`u-me`) من أوائل المجموعات؛ نصف النهائي مجدول بيوم والنهائي ينتظر.
MyH2hCupDto _qualified({List<H2hCupStageDto>? stages, H2hCupTitleDto? title}) =>
    MyH2hCupDto(
      state: 'qualified',
      monthStart: '2026-11-01',
      place: 1,
      groupNumber: 1,
      entrants: <H2hCupPlayerDto>[_me, _omar, _noura, _huda],
      stages:
          stages ??
          <H2hCupStageDto>[
            H2hCupStageDto(
              round: 'semi',
              cupDay: 1,
              expectedDay: 20,
              phase: 'scheduled',
              attempt: 1,
              day: '2026-11-23',
              fixtureCount: 8,
              pairs: <H2hCupPairDto>[
                _pair(1, _me, _noura),
                _pair(2, _omar, _huda),
              ],
            ),
            const H2hCupStageDto(
              round: 'final',
              cupDay: 2,
              expectedDay: 21,
              phase: 'waiting',
              attempt: 1,
              pairs: <H2hCupPairDto>[],
            ),
          ],
      title: title,
    );

Future<void> _open(
  WidgetTester tester, {
  MyH2hCupDto? cup,
  bool cupFails = false,
  double width = 1080,
  double textScale = 1,
}) async {
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/me/h2h-league') return _json(_league().toJson());
    if (request.url.path == '/me/h2h-cup') {
      if (cupFails || cup == null) return http.Response('not found', 404);
      return _json(cup.toJson());
    }
    return http.Response('not found', 404);
  }

  final AuthHarness harness = buildAuthHarness(handle, seedToken: 'jwt');
  addTearDown(harness.dispose);
  tester.view.physicalSize = Size(width, 6000);
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

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

void main() {
  testWidgets('a qualifier sees his path, who he faces and the day', (
    WidgetTester tester,
  ) async {
    await _open(tester, cup: _qualified());

    expect(find.byKey(const Key('h2h.cup')), findsOneWidget);
    expect(_text(tester, 'h2h.cup.title'), 'كأس النخبة');
    expect(_text(tester, 'h2h.cup.path'), contains('أوائل المجموعات'));
    expect(_text(tester, 'h2h.cup.path'), contains('نوفمبر 2026'));
    // مواجهته: الخصم باسمه ومجموعته، ويوم المرحلة.
    expect(_text(tester, 'h2h.cup.focus.line'), contains('نورة'));
    expect(_text(tester, 'h2h.cup.focus.line'), contains('مجموعة 3'));
    expect(_text(tester, 'h2h.cup.focus.when'), contains('23'));
    // مواجهتا نصف النهائي كلتاهما، والنهائي ينتظر.
    expect(find.byKey(const Key('h2h.cup.pair.semi.1')), findsOneWidget);
    expect(find.byKey(const Key('h2h.cup.pair.semi.2')), findsOneWidget);
    expect(_text(tester, 'h2h.cup.stage.final'), contains('بانتظار الجدولة'));
  });

  testWidgets('a decided pair shows its score, its winner and why', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      cup: _qualified(
        stages: <H2hCupStageDto>[
          H2hCupStageDto(
            round: 'semi',
            cupDay: 1,
            expectedDay: 20,
            phase: 'decided',
            attempt: 1,
            day: '2026-11-22',
            fixtureCount: 8,
            pairs: <H2hCupPairDto>[
              _pair(
                1,
                _me,
                _noura,
                winner: 'u-n',
                outcome: 'points',
                homePoints: 7,
                awayPoints: 9,
              ),
            ],
          ),
          H2hCupStageDto(
            round: 'final',
            cupDay: 2,
            expectedDay: 21,
            phase: 'scheduled',
            attempt: 1,
            day: '2026-11-24',
            fixtureCount: 8,
            pairs: <H2hCupPairDto>[_pair(1, _noura, _omar)],
          ),
        ],
      ),
    );

    expect(find.text('7 - 9'), findsOneWidget);
    expect(
      _text(tester, 'h2h.cup.outcome.semi.1'),
      allOf(contains('نورة'), contains('بفارق النقاط')),
    );
    // المرحلة التي تهمه الآن هي النهائي؛ ولست فيه.
    expect(_text(tester, 'h2h.cup.focus.line'), 'لست في هذه المرحلة');
  });

  testWidgets('three qualifiers: the bye is named', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      cup: _qualified(
        stages: <H2hCupStageDto>[
          H2hCupStageDto(
            round: 'semi',
            cupDay: 1,
            expectedDay: 20,
            phase: 'scheduled',
            attempt: 1,
            day: '2026-11-23',
            fixtureCount: 8,
            pairs: <H2hCupPairDto>[_pair(1, _omar, _noura)],
            bye: _me,
          ),
          const H2hCupStageDto(
            round: 'final',
            cupDay: 2,
            expectedDay: 21,
            phase: 'waiting',
            attempt: 1,
            pairs: <H2hCupPairDto>[],
          ),
        ],
      ),
    );

    expect(_text(tester, 'h2h.cup.focus.line'), contains('تأهلت مباشرة'));
    expect(_text(tester, 'h2h.cup.bye.semi'), contains('سامي'));
  });

  testWidgets('the title of the path is shown to its champion', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      cup: _qualified(
        title: H2hCupTitleDto(how: 'final', champion: _me, runnerUp: _noura),
      ),
    );

    expect(_text(tester, 'h2h.cup.titleLine'), contains('أنت بطل'));
  });

  testWidgets('a player outside the cup sees no card', (
    WidgetTester tester,
  ) async {
    await _open(tester, cup: const MyH2hCupDto(state: 'not_qualified'));

    expect(find.byKey(const Key('h2h.cup')), findsNothing);
    expect(find.byKey(const Key('h2h.title')), findsOneWidget);
  });

  testWidgets('a failed cup request leaves the league screen alone', (
    WidgetTester tester,
  ) async {
    await _open(tester, cupFails: true);

    expect(find.byKey(const Key('h2h.cup')), findsNothing);
    expect(find.byKey(const Key('h2h.list')), findsOneWidget);
  });

  testWidgets('the card fits a 360px phone at text x2', (
    WidgetTester tester,
  ) async {
    await _open(tester, cup: _qualified(), width: 360, textScale: 2);

    expect(find.byKey(const Key('h2h.cup')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
