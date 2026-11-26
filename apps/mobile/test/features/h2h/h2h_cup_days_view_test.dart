// NK335_03
/// «جدول الأيام» بـ AppTheme الحقيقي وعلى لوحة كأس حقيقية: شريط الأيام
/// بتواريخها (اليوم الأول على اليمين)، ويفتح على اليوم الذي فيه مرحلة جارية،
/// والضغط على يوم يبدّل أزواجه، وكل زوج بصاحب أرضه على اليمين ونقاطه من
/// الخادم أو «ضد» حين لا تصل، والمحسوم بفائزه، ومرحلة بلا أزواج مربع متقطع،
/// ومن تأهل مباشرة بسطر، وما اختاره اللاعب يبقى بين لوحتين وإن غاب اليوم رجع
/// اليوم الافتراضي، وعند 360px ونص x2 بلا فيض. الودجة لا تقرأ الساعة، فلا
/// حاجة لساعة ثابتة هنا.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/h2h_cup_texts.dart';
import 'package:mobile/features/h2h/widgets/h2h_cup_days.dart';
import 'package:mobile/l10n/app_localizations.dart';

H2hCupPlayerDto _p(String id, String name, {bool me = false}) =>
    H2hCupPlayerDto(userId: id, displayName: name, groupNumber: 1, isMe: me);

final H2hCupPlayerDto _me = _p('u-me', 'سامي', me: true);
final H2hCupPlayerDto _noura = _p('u-n', 'نورة');
final H2hCupPlayerDto _omar = _p('u-o', 'عمر');
final H2hCupPlayerDto _huda = _p('u-h', 'هدى');
final H2hCupPlayerDto _talal = _p('u-t', 'طلال');

H2hCupBoardPairDto _pair(
  int slot,
  H2hCupPlayerDto home,
  H2hCupPlayerDto away, {
  bool decided = false,
  String? winner,
  int? homePoints,
  int? awayPoints,
}) => H2hCupBoardPairDto(
  slot: slot,
  home: home,
  away: away,
  decided: decided,
  winnerUserId: winner,
  homePoints: homePoints,
  awayPoints: awayPoints,
  fixtures: const <H2hCupBoardFixtureDto>[],
);

H2hCupBoardStageDto _stage(
  String round,
  String phase,
  List<H2hCupBoardPairDto> pairs, {
  required int cupDay,
  String? day,
  H2hCupPlayerDto? bye,
}) => H2hCupBoardStageDto(
  round: round,
  cupDay: cupDay,
  phase: phase,
  attempt: 1,
  day: day,
  pairs: pairs,
  bye: bye,
);

H2hCupBoardPathDto _path(
  int place,
  List<H2hCupBoardStageDto> stages, {
  H2hCupTitleDto? title,
}) => H2hCupBoardPathDto(place: place, stages: stages, title: title);

/// الأول انتهى (يومان)، والثاني والثالث نصف نهائيهما جارٍ في اليوم 3 ونهائياهما
/// ينتظران السحب في اليوم 4. اللاعب في زوج الثاني الأول.
H2hCupBoardDto _board() => H2hCupBoardDto(
  monthStart: '2026-11-01',
  paths: <H2hCupBoardPathDto>[
    _path(1, <H2hCupBoardStageDto>[
      _stage(
        'semi',
        'decided',
        <H2hCupBoardPairDto>[
          _pair(
            1,
            _omar,
            _huda,
            decided: true,
            winner: 'u-o',
            homePoints: 12,
            awayPoints: 7,
          ),
        ],
        cupDay: 1,
        day: '2026-11-23',
      ),
      _stage(
        'final',
        'decided',
        <H2hCupBoardPairDto>[
          _pair(
            1,
            _omar,
            _talal,
            decided: true,
            winner: 'u-o',
            homePoints: 10,
            awayPoints: 8,
          ),
        ],
        cupDay: 2,
        day: '2026-11-24',
      ),
    ], title: H2hCupTitleDto(how: 'final', champion: _omar)),
    _path(2, <H2hCupBoardStageDto>[
      _stage(
        'semi',
        'live',
        <H2hCupBoardPairDto>[
          _pair(1, _me, _noura, homePoints: 3, awayPoints: 5),
          _pair(2, _omar, _huda),
        ],
        cupDay: 3,
        day: '2026-11-25',
      ),
      _stage(
        'final',
        'waiting',
        const <H2hCupBoardPairDto>[],
        cupDay: 4,
        day: '2026-11-26',
      ),
    ]),
    _path(3, <H2hCupBoardStageDto>[
      _stage(
        'semi',
        'live',
        <H2hCupBoardPairDto>[_pair(1, _talal, _noura)],
        cupDay: 3,
        day: '2026-11-25',
      ),
      _stage(
        'final',
        'waiting',
        const <H2hCupBoardPairDto>[],
        cupDay: 4,
        day: '2026-11-26',
      ),
    ]),
  ],
);

Future<void> _mount(
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
        body: SingleChildScrollView(child: H2hCupDaysView(board: board)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Finder _key(String key) => find.byKey(Key(key));

/// نص القطعة ذات المفتاح.
String _text(WidgetTester tester, String key) {
  final Finder found = _key(key);
  expect(found, findsOneWidget, reason: key);
  return tester.widget<Text>(found).data ?? '';
}

double _dx(WidgetTester tester, String key) => tester.getCenter(_key(key)).dx;

/// أقرب Material فوق القطعة ذات المفتاح: ما يرسم لون التبويب.
Material _material(WidgetTester tester, String key) => tester.widget<Material>(
  find.ancestor(of: _key(key), matching: find.byType(Material)).first,
);

Color? _tabColor(WidgetTester tester, int day) =>
    _material(tester, 'h2h.cupDays.tab.$day').color;

/// علامة قارئ الشاشة لأقرب Semantics فوق القطعة ذات المفتاح.
String? _label(WidgetTester tester, String key) {
  for (final Semantics s in tester.widgetList<Semantics>(
    find.ancestor(of: _key(key), matching: find.byType(Semantics)),
  )) {
    final String? label = s.properties.label;
    if (label != null) return label;
  }
  return null;
}

Color? _textColor(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).style?.color;

FontWeight? _weight(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).style?.fontWeight;

Color _borderColor(WidgetTester tester, String key) {
  final Container box = tester.widget<Container>(_key(key));
  return ((box.decoration! as BoxDecoration).border! as Border).top.color;
}

void main() {
  test('the days are laid out by cup day, the first places first', () {
    final List<H2hCupDayEntry> days = h2hCupBoardDays(_board());
    expect(days.map((H2hCupDayEntry d) => d.cupDay).toList(), <int>[
      1,
      2,
      3,
      4,
    ]);
    expect(days[0].date, '2026-11-23');
    expect(days[3].date, '2026-11-26');
    expect(days[2].slots.map((H2hCupDaySlot s) => s.path.place).toList(), <int>[
      2,
      3,
    ]);
    expect(h2hCupBoardDays(const H2hCupBoardDto()), isEmpty);

    expect(h2hCupDayTabLabel(days[2]), 'اليوم الثالث · 25 نوفمبر');
    expect(
      h2hCupDayTabLabel((cupDay: 4, date: null, slots: <H2hCupDaySlot>[])),
      'اليوم الرابع',
    );
    expect(
      h2hCupDaySlotTitle(days[2].slots.first),
      'ثواني المجموعات · نصف النهائي',
    );
    expect(h2hCupDaySlotTitle(days[3].slots.last), 'ثوالث المجموعات · النهائي');
  });

  test(
    'the table opens on the live day, else the next to play, else the last',
    () {
      expect(h2hCupBoardDefaultDay(h2hCupBoardDays(_board())), 3);
      expect(h2hCupBoardDefaultDay(const <H2hCupDayEntry>[]), isNull);

      final H2hCupBoardDto scheduled = H2hCupBoardDto(
        paths: <H2hCupBoardPathDto>[
          _path(1, <H2hCupBoardStageDto>[
            _stage('semi', 'decided', <H2hCupBoardPairDto>[
              _pair(1, _omar, _huda, decided: true),
            ], cupDay: 1),
            _stage('final', 'scheduled', <H2hCupBoardPairDto>[
              _pair(1, _omar, _talal),
            ], cupDay: 2),
          ]),
        ],
      );
      expect(h2hCupBoardDefaultDay(h2hCupBoardDays(scheduled)), 2);

      final H2hCupBoardDto finished = H2hCupBoardDto(
        paths: <H2hCupBoardPathDto>[
          _path(1, <H2hCupBoardStageDto>[
            _stage('semi', 'decided', <H2hCupBoardPairDto>[
              _pair(1, _omar, _huda, decided: true),
            ], cupDay: 1),
            _stage('final', 'skipped', const <H2hCupBoardPairDto>[], cupDay: 2),
          ]),
        ],
      );
      expect(h2hCupBoardDefaultDay(h2hCupBoardDays(finished)), 2);
    },
  );

  test('a pair says where it stands and what the server sent', () {
    final H2hCupBoardStageDto live = _stage(
      'semi',
      'live',
      const <H2hCupBoardPairDto>[],
      cupDay: 3,
    );
    final H2hCupBoardPairDto scored = _pair(
      1,
      _me,
      _noura,
      homePoints: 3,
      awayPoints: 5,
    );
    final H2hCupBoardPairDto plain = _pair(2, _omar, _huda);
    expect(h2hCupPairStatus(live, plain), 'جارية');
    expect(
      h2hCupPairStatus(live, _pair(2, _omar, _huda, decided: true)),
      'انتهت',
    );
    expect(
      h2hCupPairStatus(
        _stage('final', 'waiting', const <H2hCupBoardPairDto>[], cupDay: 4),
        plain,
      ),
      'بانتظار الجدولة',
    );
    expect(h2hCupDayPairLabel(live, scored), 'سامي ضد نورة · 3 : 5 · جارية');
    expect(h2hCupDayPairLabel(live, plain), 'عمر ضد هدى · جارية');
  });

  testWidgets('it opens on the live day, the strip and the pairs drawn', (
    WidgetTester tester,
  ) async {
    await _mount(tester, _board());
    final AppTokens t = tester.element(_key('h2h.cupDays')).tokens;

    expect(_text(tester, 'h2h.cupDays.heading'), 'جدول الأيام');
    for (final int day in <int>[1, 2, 3, 4]) {
      expect(_text(tester, 'h2h.cupDays.tab.$day.number'), '$day');
    }
    expect(_text(tester, 'h2h.cupDays.tab.1.date'), '23 نوفمبر');
    expect(_text(tester, 'h2h.cupDays.tab.3.date'), '25 نوفمبر');
    expect(_text(tester, 'h2h.cupDays.tab.4.date'), '26 نوفمبر');
    expect(_tabColor(tester, 3), t.primary);
    expect(_tabColor(tester, 1), t.surfaceHigh);
    expect(_tabColor(tester, 4), t.surfaceHigh);
    expect(_label(tester, 'h2h.cupDays.tab.3'), 'اليوم الثالث · 25 نوفمبر');
    // اليوم الأول على اليمين في الواجهة العربية.
    expect(
      _dx(tester, 'h2h.cupDays.tab.1'),
      greaterThan(_dx(tester, 'h2h.cupDays.tab.4')),
    );

    expect(_text(tester, 'h2h.cupDays.day'), 'اليوم الثالث');
    expect(
      _text(tester, 'h2h.cupDays.slot.3.2'),
      'ثواني المجموعات · نصف النهائي',
    );
    expect(
      _text(tester, 'h2h.cupDays.slot.3.3'),
      'ثوالث المجموعات · نصف النهائي',
    );
    // أيام أخرى لا تظهر أزواجها.
    expect(_key('h2h.cupDays.pair.1.semi.1'), findsNothing);

    // زوج اللاعب: نقاط من الخادم، وصاحب الأرض على يمين الضيف.
    const String mine = 'h2h.cupDays.pair.2.semi.1';
    expect(_text(tester, '$mine.home'), 'سامي');
    expect(_text(tester, '$mine.away'), 'نورة');
    expect(_text(tester, '$mine.homePoints'), '3');
    expect(_text(tester, '$mine.awayPoints'), '5');
    expect(_text(tester, '$mine.status'), 'جارية');
    expect(_textColor(tester, '$mine.status'), t.primary);
    expect(_key('$mine.versus'), findsNothing);
    expect(_dx(tester, '$mine.home'), greaterThan(_dx(tester, '$mine.away')));
    expect(_textColor(tester, '$mine.home'), t.gold);
    expect(_borderColor(tester, mine), t.primary);
    expect(_label(tester, mine), 'سامي ضد نورة · 3 : 5 · جارية');

    // زوج لم تصل نقاطه: «ضد» ولا رقم مخترع، وحدّه عادي.
    const String other = 'h2h.cupDays.pair.2.semi.2';
    expect(_text(tester, '$other.versus'), 'ضد');
    expect(_key('$other.homePoints'), findsNothing);
    expect(_key('$other.awayPoints'), findsNothing);
    expect(_borderColor(tester, other), t.border);
    expect(_label(tester, other), 'عمر ضد هدى · جارية');
    expect(_key('h2h.cupDays.pair.3.semi.1'), findsOneWidget);
  });

  testWidgets('a day opens on tap, a decided pair marks its winner', (
    WidgetTester tester,
  ) async {
    await _mount(tester, _board());
    final AppTokens t = tester.element(_key('h2h.cupDays')).tokens;

    await _tap(tester, 'h2h.cupDays.tab.1');
    expect(_tabColor(tester, 1), t.primary);
    expect(_tabColor(tester, 3), t.surfaceHigh);
    expect(_text(tester, 'h2h.cupDays.day'), 'اليوم الأول');
    expect(_key('h2h.cupDays.pair.2.semi.1'), findsNothing);

    const String done = 'h2h.cupDays.pair.1.semi.1';
    expect(_text(tester, '$done.homePoints'), '12');
    expect(_text(tester, '$done.awayPoints'), '7');
    expect(_text(tester, '$done.status'), 'انتهت');
    expect(_textColor(tester, '$done.status'), t.textSecondary);
    expect(_textColor(tester, '$done.home'), t.textPrimary);
    expect(_weight(tester, '$done.home'), FontWeight.w800);
    expect(_textColor(tester, '$done.away'), t.textSecondary);
    expect(_weight(tester, '$done.away'), FontWeight.w600);
    expect(_label(tester, done), 'عمر ضد هدى · 12 : 7 · انتهت');
    expect(_borderColor(tester, done), t.border);
  });

  testWidgets('a stage with no pair is a dashed box that says why', (
    WidgetTester tester,
  ) async {
    await _mount(tester, _board());
    await _tap(tester, 'h2h.cupDays.tab.4');

    expect(_text(tester, 'h2h.cupDays.day'), 'اليوم الرابع');
    expect(_text(tester, 'h2h.cupDays.slot.4.2'), 'ثواني المجموعات · النهائي');
    expect(_key('h2h.cupDays.empty.4.2'), findsOneWidget);
    expect(
      _text(tester, 'h2h.cupDays.empty.4.2.text'),
      'تُسحب المواجهات عند جدولة المرحلة',
    );
    expect(
      _text(tester, 'h2h.cupDays.empty.4.3.text'),
      'تُسحب المواجهات عند جدولة المرحلة',
    );
    expect(_key('h2h.cupDays.pair.2.semi.1'), findsNothing);

    final H2hCupBoardDto skipped = H2hCupBoardDto(
      paths: <H2hCupBoardPathDto>[
        _path(1, <H2hCupBoardStageDto>[
          _stage('semi', 'skipped', const <H2hCupBoardPairDto>[], cupDay: 1),
        ]),
      ],
    );
    await _mount(tester, skipped);
    expect(
      _text(tester, 'h2h.cupDays.empty.1.1.text'),
      'لا تُلعب هذه المرحلة في هذا المسار',
    );
  });

  testWidgets('a qualifier on a bye is named under his stage', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardDto bye = H2hCupBoardDto(
      paths: <H2hCupBoardPathDto>[
        _path(1, <H2hCupBoardStageDto>[
          _stage(
            'semi',
            'scheduled',
            <H2hCupBoardPairDto>[_pair(1, _omar, _huda)],
            cupDay: 1,
            day: '2026-11-23',
            bye: _me,
          ),
        ]),
      ],
    );
    await _mount(tester, bye);
    final AppTokens t = tester.element(_key('h2h.cupDays')).tokens;

    expect(_text(tester, 'h2h.cupDays.bye.1.1'), 'تأهل مباشرة: سامي');
    expect(_textColor(tester, 'h2h.cupDays.bye.1.1'), t.gold);
    expect(_key('h2h.cupDays.empty.1.1'), findsNothing);
    expect(_key('h2h.cupDays.pair.1.semi.1'), findsOneWidget);
  });

  testWidgets('a fresh board keeps his day, or falls back when it is gone', (
    WidgetTester tester,
  ) async {
    await _mount(tester, _board());
    final AppTokens t = tester.element(_key('h2h.cupDays')).tokens;
    await _tap(tester, 'h2h.cupDays.tab.4');
    expect(_tabColor(tester, 4), t.primary);

    // لوحة جديدة فيها اليوم نفسه: يبقى مختاراً.
    await _mount(tester, _board());
    expect(_tabColor(tester, 4), t.primary);
    expect(_tabColor(tester, 3), t.surfaceHigh);

    // لوحة بلا اليوم الرابع: يرجع إلى يوم الفتح.
    final H2hCupBoardDto shorter = H2hCupBoardDto(
      paths: <H2hCupBoardPathDto>[
        _path(2, <H2hCupBoardStageDto>[
          _stage(
            'semi',
            'live',
            <H2hCupBoardPairDto>[_pair(1, _me, _noura)],
            cupDay: 3,
            day: '2026-11-25',
          ),
        ]),
      ],
    );
    await _mount(tester, shorter);
    expect(_key('h2h.cupDays.tab.4'), findsNothing);
    expect(_tabColor(tester, 3), t.primary);
  });

  testWidgets('a day with no date shows no date line', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardDto undated = H2hCupBoardDto(
      paths: <H2hCupBoardPathDto>[
        _path(1, <H2hCupBoardStageDto>[
          _stage('semi', 'waiting', const <H2hCupBoardPairDto>[], cupDay: 1),
        ]),
      ],
    );
    await _mount(tester, undated);
    expect(_text(tester, 'h2h.cupDays.tab.1.number'), '1');
    expect(_key('h2h.cupDays.tab.1.date'), findsNothing);
    expect(_label(tester, 'h2h.cupDays.tab.1'), 'اليوم الأول');
  });

  testWidgets('before the cup stands, nothing is drawn', (
    WidgetTester tester,
  ) async {
    await _mount(tester, const H2hCupBoardDto());
    expect(_key('h2h.cupDays'), findsNothing);
    expect(_key('h2h.cupDays.heading'), findsNothing);
  });

  testWidgets('it holds at 360px and text x2 with long names, no overflow', (
    WidgetTester tester,
  ) async {
    final H2hCupPlayerDto longMe = _p(
      'u-me',
      'عبدالملك السفياني الطويل جدا',
      me: true,
    );
    final H2hCupPlayerDto longOther = _p(
      'u-n',
      'عبدالرحمن بن محمد الشهابي الكبير',
    );
    final H2hCupBoardDto board = H2hCupBoardDto(
      monthStart: '2026-11-01',
      paths: <H2hCupBoardPathDto>[
        _path(2, <H2hCupBoardStageDto>[
          _stage(
            'semi',
            'live',
            <H2hCupBoardPairDto>[
              _pair(1, longMe, longOther, homePoints: 128, awayPoints: 117),
              _pair(2, _omar, _huda),
            ],
            cupDay: 3,
            day: '2026-11-25',
          ),
          _stage(
            'final',
            'waiting',
            const <H2hCupBoardPairDto>[],
            cupDay: 4,
            day: '2026-11-26',
          ),
        ]),
        _path(1, <H2hCupBoardStageDto>[
          _stage(
            'semi',
            'decided',
            <H2hCupBoardPairDto>[
              _pair(
                1,
                longOther,
                longMe,
                decided: true,
                winner: 'u-n',
                homePoints: 12,
                awayPoints: 7,
              ),
            ],
            cupDay: 1,
            day: '2026-11-23',
          ),
        ]),
      ],
    );
    await _mount(tester, board, width: 360, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(_key('h2h.cupDays.pair.2.semi.1'), findsOneWidget);
    expect(_text(tester, 'h2h.cupDays.pair.2.semi.1.homePoints'), '128');

    await _tap(tester, 'h2h.cupDays.tab.4');
    expect(tester.takeException(), isNull);
    expect(_key('h2h.cupDays.empty.4.2'), findsOneWidget);

    await _tap(tester, 'h2h.cupDays.tab.1');
    expect(tester.takeException(), isNull);
    expect(_key('h2h.cupDays.pair.1.semi.1'), findsOneWidget);
  });
}
