// NK315_04
/// لوحة كأس النخبة عبر `AuthApi` الحقيقي فوق خادم الاختبار وAppTheme الحقيقي:
/// توقع الخصم لا يظهر إلا في مباراة انطلقت، والجانب المحجوب يقول «تظهر بعد
/// انطلاق المباراة» لا غير، والمباراة بلا موعد لا تُكتب بشرطة، والموعد بتوقيت
/// الرياض، والحالة الفارغة والفشل مع الإعادة، وعند 360px ونص x2 بلا فيض.
/// القطعة لا تقرأ الساعة، فلا حاجة لساعة ثابتة هنا.
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

const String _live = 'h2h.cupBoard.pair.1.semi.1.fixture.f-live';
const String _next = 'h2h.cupBoard.pair.1.semi.1.fixture.f-next';

void main() {
  testWidgets('a pick shows once its fixture kicked off, not before', (
    WidgetTester tester,
  ) async {
    final List<http.Request> seen = await _open(
      tester,
      responses: <http.Response Function()>[() => _json(_board().toJson())],
    );

    expect(seen, hasLength(1));
    expect(find.byKey(const Key('h2h.cupBoard')), findsOneWidget);
    expect(_text(tester, 'h2h.cupBoard.month'), 'نوفمبر 2026');
    // مباراة انطلقت: توقع الجانبين ظاهر، والمضاعفة مكتوبة.
    expect(_text(tester, '$_live.home.pick'), '2 - 1');
    expect(_text(tester, '$_live.home.extras'), 'مضاعفة');
    expect(_text(tester, '$_live.away.pick'), '1 - 1');
    expect(_text(tester, '$_live.state'), 'جارية');
    // مباراة لم تنطلق: توقعه ظاهر لصاحبه، وتوقع الخصم عبارة الحجب وحدها.
    expect(_text(tester, '$_next.home.pick'), '0 - 0');
    expect(_text(tester, '$_next.away.hidden'), 'تظهر بعد انطلاق المباراة');
    expect(find.byKey(const Key('$_next.away.pick')), findsNothing);
    expect(find.byKey(const Key('$_next.away.none')), findsNothing);
    expect(_text(tester, '$_next.state'), 'لم تبدأ');
  });

  testWidgets('a side that kicked off with no pick says he did not predict', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      responses: <http.Response Function()>[() => _json(_board().toJson())],
    );

    const String other = 'h2h.cupBoard.pair.1.semi.2.fixture.f-live';
    expect(_text(tester, '$other.home.pick'), '3 - 0');
    expect(_text(tester, '$other.home.extras'), 'دقيقة · +9 ن');
    expect(_text(tester, '$other.away.none'), 'لم يتوقع');
  });

  testWidgets('the caller who did not predict reads it in the second person', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardDto board = H2hCupBoardDto(
      monthStart: '2026-11-01',
      paths: <H2hCupBoardPathDto>[
        H2hCupBoardPathDto(
          place: 1,
          stages: <H2hCupBoardStageDto>[
            _stage('semi', 'live', <H2hCupBoardPairDto>[
              _pair(1, _me, _noura, <H2hCupBoardFixtureDto>[
                _fixture(
                  'f-1',
                  state: 'live',
                  homeSide: _shown(),
                  awaySide: _shown(_pick(1, 0)),
                ),
              ]),
            ]),
          ],
        ),
      ],
    );
    await _open(
      tester,
      responses: <http.Response Function()>[() => _json(board.toJson())],
    );

    const String f = 'h2h.cupBoard.pair.1.semi.1.fixture.f-1';
    expect(_text(tester, '$f.home.none'), 'لم تتوقع');
    expect(_text(tester, '$f.away.pick'), '1 - 0');
  });

  testWidgets('the kickoff is on the Riyadh clock, a missing one is a word', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardDto board = H2hCupBoardDto(
      monthStart: '2026-11-01',
      paths: <H2hCupBoardPathDto>[
        H2hCupBoardPathDto(
          place: 1,
          stages: <H2hCupBoardStageDto>[
            _stage('semi', 'scheduled', <H2hCupBoardPairDto>[
              _pair(1, _me, _noura, <H2hCupBoardFixtureDto>[
                _fixture(
                  'f-1',
                  state: 'not_started',
                  kickoffAt: '2026-11-23T16:30:00Z',
                  homeSide: _shown(),
                  awaySide: _hidden,
                ),
                _fixture(
                  'f-2',
                  state: 'not_started',
                  kickoffAt: null,
                  homeSide: _shown(),
                  awaySide: _hidden,
                ),
                _fixture(
                  'f-3',
                  state: 'finished',
                  homeGoals: 2,
                  awayGoals: 0,
                  homeSide: _shown(_pick(2, 0)),
                  awaySide: _shown(_pick(0, 2)),
                ),
                _fixture(
                  'f-4',
                  state: 'void',
                  homeSide: _shown(),
                  awaySide: _shown(),
                ),
              ]),
            ]),
          ],
        ),
      ],
    );
    await _open(
      tester,
      responses: <http.Response Function()>[() => _json(board.toJson())],
    );

    const String p = 'h2h.cupBoard.pair.1.semi.1.fixture';
    expect(_text(tester, '$p.f-1.middle'), '19:30');
    expect(_text(tester, '$p.f-2.middle'), 'بلا موعد');
    expect(_text(tester, '$p.f-2.state'), 'لم تبدأ');
    expect(_text(tester, '$p.f-3.middle'), '2 - 0');
    expect(_text(tester, '$p.f-3.state'), 'انتهت');
    expect(_text(tester, '$p.f-4.state'), 'لا تُحتسب');
    expect(find.byKey(const Key('$p.f-4.void')), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('paths, stages, the winner, the bye and the title read right', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      responses: <http.Response Function()>[() => _json(_board().toJson())],
    );

    expect(_text(tester, 'h2h.cupBoard.path.1'), 'مسار أوائل المجموعات');
    expect(_text(tester, 'h2h.cupBoard.path.2'), 'مسار ثواني المجموعات');
    expect(_text(tester, 'h2h.cupBoard.stage.1.semi'), contains('جارية'));
    expect(_text(tester, 'h2h.cupBoard.stage.1.semi'), contains('23'));
    expect(
      _text(tester, 'h2h.cupBoard.stage.1.final'),
      contains('بانتظار الجدولة'),
    );
    expect(
      _text(tester, 'h2h.cupBoard.stage.1.final.empty'),
      'تُسحب المواجهات عند جدولة المرحلة',
    );
    expect(_text(tester, 'h2h.cupBoard.pair.2.semi.1.result'), 'الفائز: عمر');
    expect(_text(tester, 'h2h.cupBoard.bye.2.final'), 'تأهل مباشرة: نورة');
    expect(_text(tester, 'h2h.cupBoard.title.2'), 'بطل المسار: عمر');
    expect(find.byKey(const Key('h2h.cupBoard.title.1')), findsNothing);
  });

  testWidgets('the same fixture in two paths keeps its own keys', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      responses: <http.Response Function()>[() => _json(_board().toJson())],
    );

    // `f-live` يظهر في ثلاثة أزواج؛ لكل زوج مفتاحه، ولا مفتاح مشترك.
    for (final String pair in <String>[
      'h2h.cupBoard.pair.1.semi.1',
      'h2h.cupBoard.pair.1.semi.2',
      'h2h.cupBoard.pair.2.semi.1',
    ]) {
      expect(find.byKey(Key('$pair.fixture.f-live')), findsOneWidget);
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
    const String p = 'h2h.cupBoard.pair.1.semi.1.fixture';
    expect(find.byKey(const Key('$p.f-a.home.pick')), findsOneWidget);
    expect(find.byKey(const Key('$p.f-b.away.hidden')), findsOneWidget);
    expect(find.byKey(const Key('$p.f-c.middle')), findsOneWidget);
  });
}
