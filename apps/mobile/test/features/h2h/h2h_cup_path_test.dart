// NK333_03
/// «مسارك» و«بقية المسارات» و«المسارات الثلاثة» بـ AppTheme الحقيقي وعلى لوحة
/// كأس حقيقية: خط المراحل بنقطة لكل حال، والخصم والفائز، والبطل أو حلقته
/// المتقطعة، وشارة «بطل» أو نقاط المراحل في صف كل مسار، ولا مسار للاعب في
/// صف المسارات الأخرى، وما يراه المشاهد، وعند 360px ونص x2 بلا فيض. الودجة لا
/// تقرأ الساعة، فلا حاجة لساعة ثابتة هنا.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/h2h_cup_texts.dart';
import 'package:mobile/features/h2h/widgets/h2h_cup_path.dart';
import 'package:mobile/l10n/app_localizations.dart';

H2hCupPlayerDto _p(String id, String name, {bool me = false}) =>
    H2hCupPlayerDto(userId: id, displayName: name, groupNumber: 1, isMe: me);

final H2hCupPlayerDto _me = _p('u-me', 'سامي', me: true);
final H2hCupPlayerDto _noura = _p('u-n', 'نورة');
final H2hCupPlayerDto _omar = _p('u-o', 'عمر');
final H2hCupPlayerDto _huda = _p('u-h', 'هدى');
final H2hCupPlayerDto _talal = _p('u-t', 'طلال');

H2hCupBoardPairDto _pair(
  H2hCupPlayerDto home,
  H2hCupPlayerDto away, {
  bool decided = false,
  String? winner,
}) => H2hCupBoardPairDto(
  slot: 1,
  home: home,
  away: away,
  decided: decided,
  winnerUserId: winner,
  fixtures: const <H2hCupBoardFixtureDto>[],
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

H2hCupBoardPathDto _path(
  int place,
  List<H2hCupBoardStageDto> stages, {
  H2hCupTitleDto? title,
}) => H2hCupBoardPathDto(place: place, stages: stages, title: title);

/// مسار انتهى: بطله عمر.
H2hCupBoardPathDto _donePath() => _path(1, <H2hCupBoardStageDto>[
  _stage('semi', 'decided', <H2hCupBoardPairDto>[
    _pair(_omar, _huda, decided: true, winner: 'u-o'),
  ], day: '2026-11-23'),
  _stage('final', 'decided', <H2hCupBoardPairDto>[
    _pair(_omar, _talal, decided: true, winner: 'u-o'),
  ], day: '2026-11-24'),
], title: H2hCupTitleDto(how: 'final', champion: _omar));

/// مسار اللاعب: نصف نهائي جارٍ ضد نورة، ونهائي لم يُجدول.
H2hCupBoardPathDto _myPath() => _path(2, <H2hCupBoardStageDto>[
  _stage('semi', 'live', <H2hCupBoardPairDto>[
    _pair(_me, _noura),
    _pair(_omar, _huda),
  ], day: '2026-11-25'),
  _stage('final', 'waiting', const <H2hCupBoardPairDto>[]),
]);

/// مسار آخر لم يُحسم: نصف نهائي جارٍ.
H2hCupBoardPathDto _livePath() => _path(3, <H2hCupBoardStageDto>[
  _stage('semi', 'live', <H2hCupBoardPairDto>[
    _pair(_omar, _huda),
  ], day: '2026-11-25'),
  _stage('final', 'waiting', const <H2hCupBoardPairDto>[]),
]);

/// المسارات الثلاثة، ومسار اللاعب هو الثاني.
H2hCupBoardDto _participantBoard() => H2hCupBoardDto(
  monthStart: '2026-11-01',
  paths: <H2hCupBoardPathDto>[_donePath(), _myPath(), _livePath()],
);

/// المسارات الثلاثة كما يراها من لا مسار له: اللاعب ليس في أحدها.
H2hCupBoardDto _watcherBoard() {
  final H2hCupBoardPathDto other = _path(2, <H2hCupBoardStageDto>[
    _stage('semi', 'live', <H2hCupBoardPairDto>[
      _pair(_talal, _noura),
    ], day: '2026-11-25'),
    _stage('final', 'waiting', const <H2hCupBoardPairDto>[]),
  ]);
  return H2hCupBoardDto(
    monthStart: '2026-11-01',
    paths: <H2hCupBoardPathDto>[_donePath(), other, _livePath()],
  );
}

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
        body: SingleChildScrollView(child: H2hCupPathsView(board: board)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// نص القطعة ذات المفتاح.
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

double _dy(WidgetTester tester, String key) => tester.getCenter(_key(key)).dy;

/// زخرفة النقطة ذات المفتاح: المفتاح على الـContainer نفسه، أو على ودجة
/// تبنيه.
BoxDecoration _decoration(WidgetTester tester, String key) {
  final Finder found = _key(key);
  final Widget widget = tester.widget(found);
  final Container box = widget is Container
      ? widget
      : tester.widget<Container>(
          find.descendant(of: found, matching: find.byType(Container)).first,
        );
  return box.decoration! as BoxDecoration;
}

void main() {
  test('a path is named short, and its step is counted and worded', () {
    expect(h2hCupPathShortName(1), 'أوائل المجموعات');
    expect(h2hCupPathShortName(2), 'ثواني المجموعات');
    expect(h2hCupPathShortName(3), 'ثوالث المجموعات');
    expect(h2hCupPathShortName(9), 'الكأس');
    expect(h2hCupPathStepLabel(1, 3), 'المرحلة الأولى من ثلاث');
    expect(h2hCupPathStepLabel(2, 3), 'المرحلة الثانية من ثلاث');
    expect(h2hCupPathStepLabel(3, 3), 'المرحلة الثالثة من ثلاث');
    expect(h2hCupPathStepLabel(4, 5), 'المرحلة 4 من 5');

    expect(h2hCupBoardPathStep(_myPath()), 1);
    expect(h2hCupBoardPathStep(_donePath()), 2);
    final H2hCupBoardPathDto second = _path(1, <H2hCupBoardStageDto>[
      _stage('semi', 'decided', const <H2hCupBoardPairDto>[]),
      _stage('final', 'live', const <H2hCupBoardPairDto>[]),
    ]);
    expect(h2hCupBoardPathStep(second), 2);
    expect(h2hCupBoardPathStep(_path(1, const <H2hCupBoardStageDto>[])), 0);
  });

  test('the stage title and the caller line say what the server sent', () {
    expect(
      h2hCupBoardStageTitle(
        _stage('semi', 'live', const [], day: '2026-11-25'),
      ),
      'نصف النهائي · 25 نوفمبر',
    );
    expect(
      h2hCupBoardStageTitle(_stage('final', 'waiting', const [])),
      'النهائي',
    );
    expect(
      h2hCupMyStageLine(
        _stage('semi', 'live', <H2hCupBoardPairDto>[_pair(_me, _noura)]),
      ),
      'جارية · ضد نورة',
    );
    expect(
      h2hCupMyStageLine(
        _stage('semi', 'live', <H2hCupBoardPairDto>[_pair(_noura, _me)]),
      ),
      'جارية · ضد نورة',
    );
    expect(
      h2hCupMyStageLine(
        _stage('final', 'decided', <H2hCupBoardPairDto>[
          _pair(_me, _omar, decided: true, winner: 'u-me'),
        ]),
      ),
      'انتهت · ضد عمر · الفائز: سامي',
    );
    expect(
      h2hCupMyStageLine(
        _stage('final', 'decided', <H2hCupBoardPairDto>[
          _pair(_me, _omar, decided: true),
        ]),
      ),
      'انتهت · ضد عمر · انتهت بلا فائز',
    );
    expect(
      h2hCupMyStageLine(_stage('semi', 'scheduled', const [], bye: _me)),
      'مجدولة · تأهلت مباشرة',
    );
    expect(
      h2hCupMyStageLine(_stage('final', 'waiting', const [])),
      'بانتظار الجدولة',
    );
  });

  test(
    'the champion line is the title once decided, else who it waits for',
    () {
      expect(h2hCupBoardChampionLine(_myPath()), 'بطل مسار ثواني المجموعات');
      expect(h2hCupBoardChampionLine(_donePath()), 'بطل المسار: عمر');
      expect(
        h2hCupBoardChampionLine(
          _path(
            2,
            const <H2hCupBoardStageDto>[],
            title: H2hCupTitleDto(how: 'final', champion: _me),
          ),
        ),
        'أنت بطل هذا المسار',
      );
      expect(
        h2hCupBoardChampionLine(
          _path(
            2,
            const <H2hCupBoardStageDto>[],
            title: const H2hCupTitleDto(how: 'vacant'),
          ),
        ),
        'اللقب شاغر في هذا المسار',
      );
    },
  );

  testWidgets('a player in the cup reads his path as a timeline', (
    WidgetTester tester,
  ) async {
    await _open(tester, _participantBoard());
    final AppTokens t = tester.element(_key('h2h.cupPaths')).tokens;

    expect(_text(tester, 'h2h.cupPath.heading'), 'مسارك · ثواني المجموعات');
    expect(_text(tester, 'h2h.cupPath.stage.0'), 'نصف النهائي · 25 نوفمبر');
    expect(_text(tester, 'h2h.cupPath.stage.0.line'), 'جارية · ضد نورة');
    expect(_text(tester, 'h2h.cupPath.stage.1'), 'النهائي');
    expect(_text(tester, 'h2h.cupPath.stage.1.line'), 'بانتظار الجدولة');
    expect(_text(tester, 'h2h.cupPath.champion'), 'بطل مسار ثواني المجموعات');

    // المرحلة الجارية ممتلئة بالأساسي، والقادمة مفرغة، والبطل حلقة متقطعة.
    expect(_decoration(tester, 'h2h.cupPath.dot.0').color, t.primary);
    expect(_decoration(tester, 'h2h.cupPath.dot.1').color, isNull);
    expect(_key('h2h.cupPath.champion.dot'), findsOneWidget);
    expect(
      find.descendant(
        of: _key('h2h.cupPath.champion.dot'),
        matching: find.byIcon(Icons.emoji_events),
      ),
      findsNothing,
    );

    // الخط من الأعلى: مرحلة، فمرحلة، فالبطل؛ والنقطة على يمين النص.
    expect(
      _dy(tester, 'h2h.cupPath.stage.0'),
      lessThan(_dy(tester, 'h2h.cupPath.stage.1')),
    );
    expect(
      _dy(tester, 'h2h.cupPath.stage.1'),
      lessThan(_dy(tester, 'h2h.cupPath.champion')),
    );
    expect(
      _dx(tester, 'h2h.cupPath.dot.0'),
      greaterThan(_dx(tester, 'h2h.cupPath.stage.0')),
    );
  });

  testWidgets('the other paths skip his own: a crowned one and one live', (
    WidgetTester tester,
  ) async {
    await _open(tester, _participantBoard());

    expect(_text(tester, 'h2h.cupPaths.heading'), 'بقية المسارات');
    expect(_key('h2h.cupPaths.row.2'), findsNothing);

    // مسار حُسم: البطل في سطر الحال وشارة «بطل» بلا نقاط.
    expect(_text(tester, 'h2h.cupPaths.row.1.name'), 'أوائل المجموعات');
    expect(_text(tester, 'h2h.cupPaths.row.1.status'), 'بطل المسار: عمر');
    expect(_text(tester, 'h2h.cupPaths.row.1.badge'), 'بطل');
    expect(_key('h2h.cupPaths.row.1.dots'), findsNothing);

    // مسار جارٍ: مرحلته وحالها ونقطة من ثلاث، بلا شارة.
    expect(_text(tester, 'h2h.cupPaths.row.3.name'), 'ثوالث المجموعات');
    expect(_text(tester, 'h2h.cupPaths.row.3.status'), 'نصف النهائي · جارية');
    expect(_key('h2h.cupPaths.row.3.badge'), findsNothing);
    final Semantics dots = tester.widget<Semantics>(
      find
          .descendant(
            of: _key('h2h.cupPaths.row.3.dots'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(dots.properties.label, 'المرحلة الأولى من ثلاث');

    // الأول فوق الثالث كما أرسلهما الخادم.
    expect(
      _dy(tester, 'h2h.cupPaths.row.1'),
      lessThan(_dy(tester, 'h2h.cupPaths.row.3')),
    );
  });

  testWidgets('a watcher reads the three paths and no path of his own', (
    WidgetTester tester,
  ) async {
    await _open(tester, _watcherBoard());

    expect(_text(tester, 'h2h.cupPaths.heading'), 'المسارات الثلاثة');
    expect(_key('h2h.cupPath.heading'), findsNothing);
    expect(_key('h2h.cupPath.card'), findsNothing);
    expect(_key('h2h.cupPaths.row.1'), findsOneWidget);
    expect(_key('h2h.cupPaths.row.2'), findsOneWidget);
    expect(_key('h2h.cupPaths.row.3'), findsOneWidget);
    expect(_text(tester, 'h2h.cupPaths.row.2.status'), 'نصف النهائي · جارية');
  });

  testWidgets('a path he won ends in the crown, every stage done', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardPathDto won = _path(2, <H2hCupBoardStageDto>[
      _stage('semi', 'decided', <H2hCupBoardPairDto>[
        _pair(_me, _noura, decided: true, winner: 'u-me'),
      ], day: '2026-11-23'),
      _stage('final', 'decided', <H2hCupBoardPairDto>[
        _pair(_me, _omar, decided: true, winner: 'u-me'),
      ], day: '2026-11-24'),
    ], title: H2hCupTitleDto(how: 'final', champion: _me));
    await _open(tester, H2hCupBoardDto(paths: <H2hCupBoardPathDto>[won]));
    final AppTokens t = tester.element(_key('h2h.cupPaths')).tokens;

    expect(_text(tester, 'h2h.cupPath.stage.0.line'), contains('الفائز: سامي'));
    expect(_text(tester, 'h2h.cupPath.stage.1.line'), contains('ضد عمر'));
    for (final String dot in <String>[
      'h2h.cupPath.dot.0',
      'h2h.cupPath.dot.1',
    ]) {
      expect(_decoration(tester, dot).color, t.success);
      expect(
        find.descendant(of: _key(dot), matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
    }
    expect(_text(tester, 'h2h.cupPath.champion'), 'أنت بطل هذا المسار');
    expect(_decoration(tester, 'h2h.cupPath.champion.dot').color, t.goldAccent);
    expect(
      find.descendant(
        of: _key('h2h.cupPath.champion.dot'),
        matching: find.byIcon(Icons.emoji_events),
      ),
      findsOneWidget,
    );
    // لا مسار آخر: لا عنوان ولا صفوف.
    expect(_key('h2h.cupPaths.heading'), findsNothing);
  });

  testWidgets('a qualifier on a bye reads that he is through', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardPathDto bye = _path(1, <H2hCupBoardStageDto>[
      _stage('semi', 'scheduled', <H2hCupBoardPairDto>[
        _pair(_omar, _huda),
      ], bye: _me),
      _stage('final', 'waiting', const <H2hCupBoardPairDto>[]),
    ]);
    await _open(tester, H2hCupBoardDto(paths: <H2hCupBoardPathDto>[bye]));

    expect(_text(tester, 'h2h.cupPath.heading'), 'مسارك · أوائل المجموعات');
    expect(_text(tester, 'h2h.cupPath.stage.0.line'), 'مجدولة · تأهلت مباشرة');
  });

  testWidgets('a stage left out of the path is not the one that stands', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardPathDto skipped = _path(2, <H2hCupBoardStageDto>[
      _stage('semi', 'skipped', const <H2hCupBoardPairDto>[]),
      _stage('final', 'live', <H2hCupBoardPairDto>[_pair(_me, _noura)]),
    ]);
    await _open(tester, H2hCupBoardDto(paths: <H2hCupBoardPathDto>[skipped]));
    final AppTokens t = tester.element(_key('h2h.cupPaths')).tokens;

    expect(_text(tester, 'h2h.cupPath.stage.0.line'), 'لا تُلعب');
    expect(_decoration(tester, 'h2h.cupPath.dot.0').color, isNull);
    expect(_decoration(tester, 'h2h.cupPath.dot.1').color, t.primary);
    expect(_text(tester, 'h2h.cupPath.stage.1.line'), 'جارية · ضد نورة');
  });

  testWidgets('before the cup stands, nothing is drawn', (
    WidgetTester tester,
  ) async {
    await _open(tester, const H2hCupBoardDto());
    expect(_key('h2h.cupPaths'), findsNothing);
    expect(_key('h2h.cupPath.card'), findsNothing);
  });

  testWidgets('it holds at 360px and text x2 with long names, no overflow', (
    WidgetTester tester,
  ) async {
    final H2hCupPlayerDto longName = _p(
      'u-l',
      'عبدالرحمن بن محمد الشهابي الكبير جدا',
    );
    final H2hCupBoardPathDto mine = _path(2, <H2hCupBoardStageDto>[
      _stage('semi', 'live', <H2hCupBoardPairDto>[
        _pair(_me, longName),
      ], day: '2026-11-25'),
      _stage('final', 'waiting', const <H2hCupBoardPairDto>[]),
    ]);
    await _open(
      tester,
      H2hCupBoardDto(
        paths: <H2hCupBoardPathDto>[_donePath(), mine, _livePath()],
      ),
      width: 360,
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(_key('h2h.cupPath.stage.0.line'), findsOneWidget);
    expect(_key('h2h.cupPaths.row.1.badge'), findsOneWidget);
    expect(_key('h2h.cupPaths.row.3.dots'), findsOneWidget);
  });
}
