// NK336_03
/// لوحة كأس النخبة بعد التركيب (سكربت 336)، عبر `AuthApi` الحقيقي فوق خادم
/// الاختبار وAppTheme الحقيقي: المشارك يقرأ مواجهته الآن ثم مساره ثم الشجرة
/// ثم الأيام بهذا الترتيب، والمشاهد الترتيب نفسه بلا «مواجهتك الآن» وبـ
/// «المسارات الثلاثة»، والجانب المحجوب يقول «تظهر بعد انطلاق المباراة» لا
/// غير، والحالة الفارغة والفشل مع الإعادة، وعند 360px ونص x2 بلا فيض. تفاصيل
/// كل قسم في اختبارات ودجاته. القطعة لا تقرأ الساعة، فلا حاجة لساعة ثابتة.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/widgets/h2h_cup_board.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
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
final H2hCupPlayerDto _majed = _p('u-m', 'ماجد', 1);

const H2hCupBoardSideDto _hidden = H2hCupBoardSideDto.hidden();

H2hCupBoardSideDto _shown([H2hPickDto? pick]) =>
    H2hCupBoardSideDto(revealed: true, pick: pick);

H2hPickDto _pick(
  int home,
  int away, {
  bool double = false,
  bool exact = false,
  int? points,
}) => H2hPickDto(
  homeGoals: home,
  awayGoals: away,
  isDouble: double,
  exact: exact,
  points: points,
);

H2hCupBoardFixtureDto _fixture(
  String id, {
  required String state,
  required H2hCupBoardSideDto homeSide,
  required H2hCupBoardSideDto awaySide,
  String home = 'Alpha',
  String away = 'Beta',
  String? kickoffAt = '2026-11-23T16:30:00Z',
  int? homeGoals,
  int? awayGoals,
}) => H2hCupBoardFixtureDto(
  fixtureId: id,
  homeTeam: home,
  awayTeam: away,
  kickoffAt: kickoffAt,
  state: state,
  homeGoals: homeGoals,
  awayGoals: awayGoals,
  homeSide: homeSide,
  awaySide: awaySide,
);

H2hCupBoardPairDto _pair(
  int slot,
  H2hCupPlayerDto home,
  H2hCupPlayerDto away,
  List<H2hCupBoardFixtureDto> fixtures, {
  String? winner,
  bool decided = false,
}) => H2hCupBoardPairDto(
  slot: slot,
  home: home,
  away: away,
  decided: decided || winner != null,
  winnerUserId: winner,
  fixtures: fixtures,
);

H2hCupBoardStageDto _stage(
  String round,
  String phase,
  List<H2hCupBoardPairDto> pairs, {
  String? day,
  H2hCupPlayerDto? bye,
}) => H2hCupBoardStageDto(
  round: round,
  cupDay: round == 'semi' ? 1 : 2,
  phase: phase,
  attempt: 1,
  day: day,
  pairs: pairs,
  bye: bye,
);

/// مساران: الأول (أوائل المجموعات) فيه مباراتان، واحدة انطلقت وأخرى لا.
H2hCupBoardDto _board() => H2hCupBoardDto(
  monthStart: '2026-11-01',
  paths: <H2hCupBoardPathDto>[
    H2hCupBoardPathDto(
      place: 1,
      stages: <H2hCupBoardStageDto>[
        _stage('semi', 'live', <H2hCupBoardPairDto>[
          _pair(1, _me, _noura, <H2hCupBoardFixtureDto>[
            _fixture(
              'f-live',
              state: 'live',
              homeSide: _shown(_pick(2, 1, double: true)),
              awaySide: _shown(_pick(1, 1)),
            ),
            _fixture(
              'f-next',
              state: 'not_started',
              kickoffAt: '2026-11-23T19:00:00Z',
              homeSide: _shown(_pick(0, 0)),
              awaySide: _hidden,
            ),
          ]),
          _pair(2, _omar, _huda, <H2hCupBoardFixtureDto>[
            _fixture(
              'f-live',
              state: 'live',
              homeSide: _shown(_pick(3, 0, exact: true, points: 9)),
              awaySide: _shown(),
            ),
          ]),
        ], day: '2026-11-23'),
        _stage('final', 'waiting', const <H2hCupBoardPairDto>[]),
      ],
    ),
    H2hCupBoardPathDto(
      place: 2,
      stages: <H2hCupBoardStageDto>[
        _stage('semi', 'decided', <H2hCupBoardPairDto>[
          _pair(1, _omar, _huda, <H2hCupBoardFixtureDto>[
            _fixture(
              'f-live',
              state: 'finished',
              homeGoals: 2,
              awayGoals: 0,
              homeSide: _shown(_pick(2, 0)),
              awaySide: _shown(_pick(1, 0)),
            ),
          ], winner: 'u-o'),
        ], day: '2026-11-22'),
        _stage('final', 'decided', const <H2hCupBoardPairDto>[], bye: _noura),
      ],
      title: H2hCupTitleDto(how: 'final', champion: _omar),
    ),
  ],
);

/// يفتح القطعة؛ [responses] تُخدَم بالترتيب (الأخيرة تتكرر).
Future<List<http.Request>> _open(
  WidgetTester tester, {
  required List<http.Response Function()> responses,
  double width = 1080,
  double textScale = 1,
}) async {
  final List<http.Request> seen = <http.Request>[];
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path != '/me/h2h-cup/board') {
      return http.Response('not found', 404);
    }
    seen.add(request);
    final int i = seen.length - 1 < responses.length
        ? seen.length - 1
        : responses.length - 1;
    return responses[i]();
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
        home: const Scaffold(
          body: SingleChildScrollView(child: H2hCupBoardView()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return seen;
}

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

/// أول كل قسم من أقسام اللوحة بالترتيب الذي يُكتب به للمشارك.
const List<String> _participantOrder = <String>[
  'h2h.cupNow',
  'h2h.cupFixtures',
  'h2h.cupPath.heading',
  'h2h.cupPaths.heading',
  'h2h.cupTree',
  'h2h.cupDays',
];

/// الأقسام نفسها للمشاهد: بلا «مواجهتك الآن» ولا «مسارك».
const List<String> _spectatorOrder = <String>[
  'h2h.cupPaths.heading',
  'h2h.cupTree',
  'h2h.cupDays',
];

/// لوحة لا يظهر فيها اللاعب: مساران بلا `isMe`، والثاني محسوم بلقب.
H2hCupBoardDto _spectatorBoard() => H2hCupBoardDto(
  monthStart: '2026-11-01',
  paths: <H2hCupBoardPathDto>[
    H2hCupBoardPathDto(
      place: 1,
      stages: <H2hCupBoardStageDto>[
        _stage('semi', 'live', <H2hCupBoardPairDto>[
          _pair(1, _majed, _noura, <H2hCupBoardFixtureDto>[
            _fixture(
              'f-live',
              state: 'live',
              homeSide: _shown(_pick(2, 1)),
              awaySide: _shown(_pick(1, 1)),
            ),
          ]),
          _pair(2, _omar, _huda, <H2hCupBoardFixtureDto>[
            _fixture(
              'f-next',
              state: 'not_started',
              homeSide: _shown(_pick(0, 0)),
              awaySide: _hidden,
            ),
          ]),
        ], day: '2026-11-23'),
        _stage('final', 'waiting', const <H2hCupBoardPairDto>[]),
      ],
    ),
    H2hCupBoardPathDto(
      place: 2,
      stages: <H2hCupBoardStageDto>[
        _stage('semi', 'decided', <H2hCupBoardPairDto>[
          _pair(1, _omar, _huda, <H2hCupBoardFixtureDto>[
            _fixture(
              'f-done',
              state: 'finished',
              homeGoals: 2,
              awayGoals: 0,
              homeSide: _shown(_pick(2, 0)),
              awaySide: _shown(_pick(1, 0)),
            ),
          ], winner: 'u-o'),
        ], day: '2026-11-22'),
        _stage('final', 'decided', const <H2hCupBoardPairDto>[], bye: _noura),
      ],
      title: H2hCupTitleDto(how: 'final', champion: _omar),
    ),
  ],
);

void main() {
  testWidgets('a player in the cup reads now, path, tree and days in order', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      responses: <http.Response Function()>[() => _json(_board().toJson())],
    );

    expect(find.byKey(const Key('h2h.cupBoard')), findsOneWidget);
    expect(_text(tester, 'h2h.cupBoard.month'), 'نوفمبر 2026');
    final List<double> tops = <double>[];
    for (final String key in _participantOrder) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      tops.add(tester.getTopLeft(find.byKey(Key(key))).dy);
    }
    for (int i = 1; i < tops.length; i++) {
      expect(
        tops[i],
        greaterThan(tops[i - 1]),
        reason:
            '${_participantOrder[i]} must sit under '
            '${_participantOrder[i - 1]}',
      );
    }
    // The old per-path list is gone; the opponent's pick is still withheld.
    expect(find.byKey(const Key('h2h.cupBoard.pair.1.semi.1')), findsNothing);
    expect(
      _text(tester, 'h2h.cupFixtures.row.f-next.away.hidden'),
      'تظهر بعد انطلاق المباراة',
    );
  });

  testWidgets('a spectator reads the three paths, the tree and the days', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      responses: <http.Response Function()>[
        () => _json(_spectatorBoard().toJson()),
      ],
    );

    expect(find.byKey(const Key('h2h.cupBoard')), findsOneWidget);
    expect(find.byKey(const Key('h2h.cupNow')), findsNothing);
    expect(find.byKey(const Key('h2h.cupFixtures')), findsNothing);
    expect(find.byKey(const Key('h2h.cupPath.heading')), findsNothing);
    final List<double> tops = <double>[];
    for (final String key in _spectatorOrder) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      tops.add(tester.getTopLeft(find.byKey(Key(key))).dy);
    }
    for (int i = 1; i < tops.length; i++) {
      expect(
        tops[i],
        greaterThan(tops[i - 1]),
        reason:
            '${_spectatorOrder[i]} must sit under '
            '${_spectatorOrder[i - 1]}',
      );
    }
  });

  testWidgets('before the cup stands the board says so', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      responses: <http.Response Function()>[
        () => _json(const H2hCupBoardDto().toJson()),
      ],
    );

    expect(find.byKey(const Key('h2h.cupBoard.empty')), findsOneWidget);
    expect(find.byKey(const Key('h2h.cupBoard')), findsNothing);
    expect(find.byKey(const Key('h2h.cupNow')), findsNothing);
    expect(
      find.text(
        'لم يقم كأس النخبة بعد. تظهر هنا مبارياته وتوقعات الخصوم حين يبدأ.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed read offers a retry that reads again', (
    WidgetTester tester,
  ) async {
    final List<http.Request> seen = await _open(
      tester,
      responses: <http.Response Function()>[
        () => http.Response('boom', 500),
        () => _json(_board().toJson()),
      ],
    );

    expect(seen, hasLength(1));
    expect(find.byKey(const Key('h2h.cupBoard.error')), findsOneWidget);
    expect(find.text('تعذّر تحميل لوحة الكأس'), findsOneWidget);
    expect(find.byKey(const Key('h2h.cupBoard')), findsNothing);

    await tester.tap(find.byKey(const Key('h2h.cupBoard.retry')));
    await tester.pumpAndSettle();

    expect(seen, hasLength(2));
    expect(find.byKey(const Key('h2h.cupBoard.error')), findsNothing);
    expect(find.byKey(const Key('h2h.cupBoard')), findsOneWidget);
    expect(find.byKey(const Key('h2h.cupNow')), findsOneWidget);
  });

  testWidgets('a 360px phone at text x2 shows long names without overflow', (
    WidgetTester tester,
  ) async {
    final H2hCupPlayerDto longMe = _p(
      'u-me',
      'عبدالرحمن بن محمد بن عبدالله المغربي',
      1,
      me: true,
    );
    final H2hCupPlayerDto longOther = _p(
      'u-n',
      'نورة بنت عبدالعزيز بن سعود الفيصل',
      3,
    );
    final H2hCupBoardDto board = H2hCupBoardDto(
      monthStart: '2026-11-01',
      paths: <H2hCupBoardPathDto>[
        H2hCupBoardPathDto(
          place: 1,
          stages: <H2hCupBoardStageDto>[
            _stage('semi', 'live', <H2hCupBoardPairDto>[
              _pair(1, longMe, longOther, <H2hCupBoardFixtureDto>[
                _fixture(
                  'f-a',
                  state: 'live',
                  home: 'Paris Saint-Germain Football Club',
                  away: 'Borussia Monchengladbach Aktiengesellschaft',
                  homeSide: _shown(
                    _pick(2, 1, double: true, exact: true, points: 12),
                  ),
                  awaySide: _shown(_pick(1, 1, points: 3)),
                ),
                _fixture(
                  'f-b',
                  state: 'not_started',
                  home: 'Paris Saint-Germain Football Club',
                  away: 'Borussia Monchengladbach Aktiengesellschaft',
                  homeSide: _shown(_pick(2, 1)),
                  awaySide: _hidden,
                ),
                _fixture(
                  'f-c',
                  state: 'not_started',
                  kickoffAt: null,
                  homeSide: _shown(),
                  awaySide: _hidden,
                ),
              ]),
            ], day: '2026-11-23'),
            _stage('final', 'waiting', const <H2hCupBoardPairDto>[]),
          ],
        ),
      ],
    );
    await _open(
      tester,
      responses: <http.Response Function()>[() => _json(board.toJson())],
      width: 360,
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    const String p = 'h2h.cupFixtures.row';
    expect(find.byKey(const Key('$p.f-a.home.pick')), findsOneWidget);
    expect(find.byKey(const Key('$p.f-b.away.hidden')), findsOneWidget);
    expect(find.byKey(const Key('$p.f-c.match.kickoff')), findsOneWidget);
  });
}
