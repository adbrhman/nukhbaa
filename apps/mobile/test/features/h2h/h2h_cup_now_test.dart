// NK332_03
/// «مواجهتك الآن» و«مباريات المواجهة» بـ AppTheme الحقيقي وعلى لوحة كأس
/// حقيقية: نقاط الزوج من الخادم أو «ضد» حين لا تصل، توقع الخصم المحجوب عبارة
/// الحجب وحدها بلا شريط ولا مسافة، الشريط والمسافة حين يظهر التوقعان،
/// وصاحب الأرض على يمين الضيف، ولا شيء لمن يشاهد أو يتأهل مباشرة، وعند 360px
/// ونص x2 بلا فيض. الودجة لا تقرأ الساعة، فلا حاجة لساعة ثابتة هنا.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/h2h_cup_texts.dart';
import 'package:mobile/features/h2h/widgets/h2h_cup_now.dart';
import 'package:mobile/l10n/app_localizations.dart';

H2hCupPlayerDto _p(String id, String name, {bool me = false}) =>
    H2hCupPlayerDto(userId: id, displayName: name, groupNumber: 1, isMe: me);

final H2hCupPlayerDto _me = _p('u-me', 'سامي', me: true);
final H2hCupPlayerDto _noura = _p('u-n', 'نورة');
final H2hCupPlayerDto _omar = _p('u-o', 'عمر');
final H2hCupPlayerDto _huda = _p('u-h', 'هدى');

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
  H2hCupPlayerDto home,
  H2hCupPlayerDto away,
  List<H2hCupBoardFixtureDto> fixtures, {
  int? homePoints,
  int? awayPoints,
}) => H2hCupBoardPairDto(
  slot: 1,
  home: home,
  away: away,
  decided: false,
  homePoints: homePoints,
  awayPoints: awayPoints,
  fixtures: fixtures,
);

H2hCupBoardStageDto _stage(
  String round,
  String phase,
  List<H2hCupBoardPairDto> pairs, {
  H2hCupPlayerDto? bye,
}) => H2hCupBoardStageDto(
  round: round,
  cupDay: round == 'semi' ? 1 : 2,
  phase: phase,
  attempt: 1,
  pairs: pairs,
  bye: bye,
);

/// لوحة بمسار واحد (الثاني) فيه نصف نهائي جارٍ، وزوجه [pair].
H2hCupBoardDto _board(H2hCupBoardPairDto pair) => H2hCupBoardDto(
  monthStart: '2026-11-01',
  paths: <H2hCupBoardPathDto>[
    H2hCupBoardPathDto(
      place: 2,
      stages: <H2hCupBoardStageDto>[
        _stage('semi', 'live', <H2hCupBoardPairDto>[
          pair,
          _pair(_omar, _huda, const <H2hCupBoardFixtureDto>[]),
        ]),
        _stage('final', 'waiting', const <H2hCupBoardPairDto>[]),
      ],
    ),
  ],
);

/// زوج اللاعب: مباراة منتهية، ثم جارية، ثم لم تبدأ.
H2hCupBoardPairDto _livePair() => _pair(
  _me,
  _noura,
  <H2hCupBoardFixtureDto>[
    _fixture(
      'f-done',
      state: 'finished',
      homeGoals: 2,
      awayGoals: 1,
      homeSide: _shown(_pick(2, 1, exact: true, points: 9)),
      awaySide: _shown(_pick(0, 0, points: 0)),
    ),
    _fixture(
      'f-live',
      state: 'live',
      homeSide: _shown(_pick(1, 3)),
      awaySide: _shown(_pick(2, 3)),
    ),
    _fixture(
      'f-next',
      state: 'not_started',
      kickoffAt: '2026-11-23T19:00:00Z',
      homeSide: _shown(_pick(0, 0)),
      awaySide: _hidden,
    ),
  ],
  homePoints: 4,
  awayPoints: 2,
);

Future<void> _open(
  WidgetTester tester,
  H2hCupBoardDto board, {
  double width = 1080,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
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
      home: Scaffold(
        body: SingleChildScrollView(child: H2hCupNowView(board: board)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// نص القطعة ذات المفتاح: نصها إن كانت نصاً، وإلا نصوص أبنائها متصلة.
String _text(WidgetTester tester, String key) {
  final Finder found = find.byKey(Key(key));
  expect(found, findsOneWidget, reason: key);
  final Widget widget = tester.widget(found);
  if (widget is Text) return widget.data ?? '';
  return tester
      .widgetList<Text>(find.descendant(of: found, matching: find.byType(Text)))
      .map((Text t) => t.data ?? '')
      .join();
}

Finder _key(String key) => find.byKey(Key(key));

double _dx(WidgetTester tester, String key) => tester.getCenter(_key(key)).dx;

const String _row = 'h2h.cupFixtures.row';

void main() {
  test('the gap between two picks is counted in goals and worded', () {
    expect(h2hCupPickGap(_pick(1, 3), _pick(2, 3)), 1);
    expect(h2hCupPickGap(_pick(0, 0), _pick(3, 2)), 5);
    expect(h2hCupPickGapLine(0), 'التوقعان متطابقان');
    expect(h2hCupPickGapLine(2), 'المسافة بين التوقعين هدفان');
    expect(h2hCupPickGapLine(5), 'المسافة بين التوقعين 5 أهداف');
    expect(h2hCupPickGapLine(11), 'المسافة بين التوقعين 11 هدفاً');
  });

  testWidgets('the duel card names the stage, the badge, the players, points', (
    WidgetTester tester,
  ) async {
    await _open(tester, _board(_livePair()));

    expect(_text(tester, 'h2h.cupNow.heading'), 'مواجهتك الآن');
    expect(
      _text(tester, 'h2h.cupNow.stage'),
      'نصف النهائي · مسار ثواني المجموعات',
    );
    expect(_text(tester, 'h2h.cupNow.badge'), 'مباشر الآن');
    expect(_text(tester, 'h2h.cupNow.home.name'), 'سامي');
    expect(_text(tester, 'h2h.cupNow.away.name'), 'نورة');
    expect(_text(tester, 'h2h.cupNow.you'), 'أنت');
    expect(_text(tester, 'h2h.cupNow.homePoints'), '4');
    expect(_text(tester, 'h2h.cupNow.awayPoints'), '2');
    expect(_text(tester, 'h2h.cupNow.pointsLabel'), 'نقاط المواجهة');
    // صاحب الأرض ونقاطه على يمين الضيف ونقاطه.
    expect(
      _dx(tester, 'h2h.cupNow.home.name'),
      greaterThan(_dx(tester, 'h2h.cupNow.away.name')),
    );
    expect(
      _dx(tester, 'h2h.cupNow.homePoints'),
      greaterThan(_dx(tester, 'h2h.cupNow.awayPoints')),
    );
  });

  testWidgets('the live fixture shows both picks, the bar and the distance', (
    WidgetTester tester,
  ) async {
    await _open(tester, _board(_livePair()));

    expect(_text(tester, 'h2h.cupNow.fixture.teams'), 'Alpha – Beta');
    // 16:30 بتوقيت UTC هي 19:30 في الرياض.
    expect(_text(tester, 'h2h.cupNow.fixture.when'), '19:30 · جارية');
    expect(_text(tester, 'h2h.cupNow.fixture.home.label'), 'توقعك');
    expect(_text(tester, 'h2h.cupNow.fixture.home.pick'), '1 - 3');
    expect(_text(tester, 'h2h.cupNow.fixture.away.label'), 'توقعه');
    expect(_text(tester, 'h2h.cupNow.fixture.away.pick'), '2 - 3');
    expect(_key('h2h.cupNow.fixture.bar'), findsOneWidget);
    expect(
      _text(tester, 'h2h.cupNow.fixture.distance'),
      'المسافة بين التوقعين هدف واحد · تُحسم بعد صافرة النهاية',
    );
  });

  testWidgets('a fixture not started hides his pick: no bar, no distance', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardPairDto pair = _pair(
      _me,
      _noura,
      <H2hCupBoardFixtureDto>[
        _fixture(
          'f-done',
          state: 'finished',
          homeGoals: 1,
          awayGoals: 0,
          homeSide: _shown(_pick(1, 0, points: 3)),
          awaySide: _shown(_pick(0, 1, points: 0)),
        ),
        _fixture(
          'f-next',
          state: 'not_started',
          kickoffAt: '2026-11-23T16:00:00Z',
          homeSide: _shown(_pick(2, 2)),
          awaySide: _hidden,
        ),
      ],
      homePoints: 3,
      awayPoints: 0,
    );
    await _open(tester, _board(pair));

    expect(_key('h2h.cupNow.badge'), findsNothing);
    expect(_text(tester, 'h2h.cupNow.fixture.when'), '19:00 · لم تبدأ');
    expect(_text(tester, 'h2h.cupNow.fixture.home.pick'), '2 - 2');
    expect(
      _text(tester, 'h2h.cupNow.fixture.away.hidden'),
      'تظهر بعد انطلاق المباراة',
    );
    expect(_key('h2h.cupNow.fixture.away.pick'), findsNothing);
    expect(_key('h2h.cupNow.fixture.away.none'), findsNothing);
    expect(_key('h2h.cupNow.fixture.bar'), findsNothing);
    expect(_key('h2h.cupNow.fixture.distance'), findsNothing);
  });

  testWidgets('the grid lists every fixture: picks, points, words, order', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardPairDto pair = _pair(
      _me,
      _noura,
      <H2hCupBoardFixtureDto>[
        ..._livePair().fixtures,
        _fixture(
          'f-void',
          state: 'void',
          homeSide: _shown(),
          awaySide: _shown(),
        ),
      ],
      homePoints: 4,
      awayPoints: 2,
    );
    await _open(tester, _board(pair));

    expect(_text(tester, 'h2h.cupFixtures.heading'), 'مباريات المواجهة');
    // مباراة منتهية: النتيجة الحقيقية وتوقع كل جانب مع نقاطه.
    expect(_text(tester, '$_row.f-done.match.score'), '2 - 1');
    expect(_text(tester, '$_row.f-done.match.state'), 'انتهت');
    expect(_text(tester, '$_row.f-done.home.pick'), '2 - 1');
    expect(_text(tester, '$_row.f-done.home.extras'), 'دقيقة · +9 ن');
    expect(_text(tester, '$_row.f-done.away.pick'), '0 - 0');
    expect(_text(tester, '$_row.f-done.away.extras'), '+0 ن');
    // مباراة جارية: الموعد والحالة وتوقع الجانبين.
    expect(_text(tester, '$_row.f-live.match.kickoff'), '19:30');
    expect(_text(tester, '$_row.f-live.match.state'), 'جارية');
    expect(_text(tester, '$_row.f-live.away.pick'), '2 - 3');
    // لم تبدأ: توقع الخصم محجوب بالعبارة وحدها.
    expect(
      _text(tester, '$_row.f-next.away.hidden'),
      'تظهر بعد انطلاق المباراة',
    );
    expect(_key('$_row.f-next.away.none'), findsNothing);
    // ملغاة: جانبان ظاهران بلا توقع، كلٌّ بصيغته، والملاحظة مكتوبة.
    expect(_text(tester, '$_row.f-void.home.none'), 'لم تتوقع');
    expect(_text(tester, '$_row.f-void.away.none'), 'لم يتوقع');
    expect(_text(tester, '$_row.f-void.match.state'), 'لا تُحتسب');
    expect(
      _text(tester, 'h2h.cupFixtures.void'),
      'لا تُحتسب: أُجّلت أو خرجت من يوم المرحلة أو تأخّرت نتيجتها.',
    );
    // الترتيب كما أرسله الخادم، وصاحب الأرض على يمين الضيف.
    expect(
      tester.getTopLeft(_key('$_row.f-done')).dy,
      lessThan(tester.getTopLeft(_key('$_row.f-live')).dy),
    );
    expect(
      tester.getTopLeft(_key('$_row.f-live')).dy,
      lessThan(tester.getTopLeft(_key('$_row.f-next')).dy),
    );
    expect(
      _dx(tester, '$_row.f-done.home.pick'),
      greaterThan(_dx(tester, '$_row.f-done.away.pick')),
    );
  });

  testWidgets('no points from the server read as versus, never a number', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardPairDto pair = _pair(_me, _noura, _livePair().fixtures);
    await _open(tester, _board(pair));

    expect(_text(tester, 'h2h.cupNow.versus'), 'ضد');
    expect(_key('h2h.cupNow.homePoints'), findsNothing);
    expect(_key('h2h.cupNow.awayPoints'), findsNothing);
  });

  testWidgets('the caller as the away player keeps his own label and side', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardPairDto pair = _pair(
      _noura,
      _me,
      <H2hCupBoardFixtureDto>[
        _fixture(
          'f-live',
          state: 'live',
          homeSide: _shown(_pick(1, 1)),
          awaySide: _shown(_pick(1, 0)),
        ),
      ],
      homePoints: 0,
      awayPoints: 5,
    );
    await _open(tester, _board(pair));

    expect(_text(tester, 'h2h.cupNow.home.name'), 'نورة');
    expect(_text(tester, 'h2h.cupNow.away.name'), 'سامي');
    expect(_text(tester, 'h2h.cupNow.fixture.home.label'), 'توقعه');
    expect(_text(tester, 'h2h.cupNow.fixture.away.label'), 'توقعك');
    expect(
      _text(tester, 'h2h.cupNow.fixture.distance'),
      'المسافة بين التوقعين هدف واحد · تُحسم بعد صافرة النهاية',
    );
  });

  testWidgets('a watcher, or a qualifier on a bye, gets nothing', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      _board(_pair(_omar, _huda, const <H2hCupBoardFixtureDto>[])),
    );
    expect(_key('h2h.cupNow'), findsNothing);
    expect(_key('h2h.cupFixtures'), findsNothing);

    final H2hCupBoardDto onBye = H2hCupBoardDto(
      monthStart: '2026-11-01',
      paths: <H2hCupBoardPathDto>[
        H2hCupBoardPathDto(
          place: 1,
          stages: <H2hCupBoardStageDto>[
            _stage('semi', 'live', <H2hCupBoardPairDto>[
              _pair(_omar, _huda, const <H2hCupBoardFixtureDto>[]),
            ], bye: _me),
          ],
        ),
      ],
    );
    await _open(tester, onBye);
    expect(_key('h2h.cupNow'), findsNothing);
  });

  testWidgets('it holds at 360px and text x2 with long names, no overflow', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardPairDto pair = _pair(
      _p('u-me', 'عبدالملك السفياني الطويل جدا', me: true),
      _p('u-n', 'عبدالرحمن بن محمد الشهابي الكبير'),
      <H2hCupBoardFixtureDto>[
        _fixture(
          'f-live',
          state: 'live',
          home: 'Paris Saint-Germain',
          away: 'Roma',
          homeSide: _shown(_pick(10, 3, double: true, exact: true, points: 12)),
          awaySide: _hidden,
        ),
      ],
      homePoints: 120,
      awayPoints: 118,
    );
    await _open(tester, _board(pair), width: 360, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(_key('$_row.f-live.away.hidden'), findsOneWidget);
    expect(_key('$_row.f-live.home.extras'), findsOneWidget);
    expect(_key('h2h.cupNow.fixture.away.hidden'), findsOneWidget);
  });
}
