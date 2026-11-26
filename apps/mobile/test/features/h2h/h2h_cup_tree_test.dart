// NK334_03
/// «شجرة الأدوار» بـ AppTheme الحقيقي وعلى لوحة كأس حقيقية: تبويب لكل مسار
/// يفتح على مسار اللاعب، ومربعا نصف النهائي بفائزيهما بعد الحسم فقط، والنهائي
/// المتقطع «بانتظار الفائز»، والبطل أو حلقته، ومن تأهل مباشرة، ومرحلة لا
/// تُلعب، والضغط على مربع يفتح مباريات زوجه (وتوقع الخصم قبل الانطلاق
/// محجوب)، والتبويب يمسح ما فُتح، وما اختاره اللاعب يبقى بين لوحتين وإن غاب
/// المسار رجع إلى مساره، وعند 360px ونص x2 بلا فيض. الودجة لا تقرأ الساعة،
/// فلا حاجة لساعة ثابتة هنا.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/h2h_cup_texts.dart';
import 'package:mobile/features/h2h/widgets/h2h_cup_tree.dart';
import 'package:mobile/l10n/app_localizations.dart';

H2hCupPlayerDto _p(String id, String name, {bool me = false}) =>
    H2hCupPlayerDto(userId: id, displayName: name, groupNumber: 1, isMe: me);

final H2hCupPlayerDto _me = _p('u-me', 'سامي', me: true);
final H2hCupPlayerDto _noura = _p('u-n', 'نورة');
final H2hCupPlayerDto _omar = _p('u-o', 'عمر');
final H2hCupPlayerDto _huda = _p('u-h', 'هدى');
final H2hCupPlayerDto _talal = _p('u-t', 'طلال');

const H2hCupBoardSideDto _hidden = H2hCupBoardSideDto.hidden();

H2hCupBoardFixtureDto _fixture(String id) => H2hCupBoardFixtureDto(
  fixtureId: id,
  homeTeam: 'Alpha',
  awayTeam: 'Beta',
  kickoffAt: '2026-11-25T16:30:00Z',
  state: 'not_started',
  homeSide: _hidden,
  awaySide: _hidden,
);

H2hCupBoardPairDto _pair(
  int slot,
  H2hCupPlayerDto home,
  H2hCupPlayerDto away, {
  bool decided = false,
  String? winner,
  List<H2hCupBoardFixtureDto> fixtures = const <H2hCupBoardFixtureDto>[],
}) => H2hCupBoardPairDto(
  slot: slot,
  home: home,
  away: away,
  decided: decided,
  winnerUserId: winner,
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

H2hCupBoardPathDto _path(
  int place,
  List<H2hCupBoardStageDto> stages, {
  H2hCupTitleDto? title,
}) => H2hCupBoardPathDto(place: place, stages: stages, title: title);

/// مسار انتهى: بطله عمر.
H2hCupBoardPathDto _donePath() => _path(1, <H2hCupBoardStageDto>[
  _stage('semi', 'decided', <H2hCupBoardPairDto>[
    _pair(1, _omar, _huda, decided: true, winner: 'u-o'),
    _pair(2, _talal, _noura, decided: true, winner: 'u-n'),
  ]),
  _stage('final', 'decided', <H2hCupBoardPairDto>[
    _pair(1, _omar, _talal, decided: true, winner: 'u-o'),
  ]),
], title: H2hCupTitleDto(how: 'final', champion: _omar));

/// مسار اللاعب: نصف نهائي جارٍ بزوجين (الأول زوجه، وله مباراة)، ونهائي لم
/// يُسحب.
H2hCupBoardPathDto _myPath() => _path(2, <H2hCupBoardStageDto>[
  _stage('semi', 'live', <H2hCupBoardPairDto>[
    _pair(1, _me, _noura, fixtures: <H2hCupBoardFixtureDto>[_fixture('f1')]),
    _pair(2, _omar, _huda),
  ]),
  _stage('final', 'waiting', const <H2hCupBoardPairDto>[]),
]);

/// مسار آخر لم يُحسم: نصف نهائي جارٍ بزوج واحد.
H2hCupBoardPathDto _livePath() => _path(3, <H2hCupBoardStageDto>[
  _stage('semi', 'live', <H2hCupBoardPairDto>[_pair(1, _omar, _huda)]),
  _stage('final', 'waiting', const <H2hCupBoardPairDto>[]),
]);

/// المسارات الثلاثة، ومسار اللاعب هو الثاني.
H2hCupBoardDto _board() => H2hCupBoardDto(
  monthStart: '2026-11-01',
  paths: <H2hCupBoardPathDto>[_donePath(), _myPath(), _livePath()],
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
        body: SingleChildScrollView(child: H2hCupTreeView(board: board)),
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
  final Widget widget = tester.widget(found);
  if (widget is Text) return widget.data ?? '';
  return tester
      .widgetList<Text>(find.descendant(of: found, matching: find.byType(Text)))
      .map((Text t) => t.data ?? '')
      .join();
}

double _dx(WidgetTester tester, String key) => tester.getCenter(_key(key)).dx;

double _dy(WidgetTester tester, String key) => tester.getCenter(_key(key)).dy;

/// أقرب Material فوق القطعة ذات المفتاح: ما يرسم لون التبويب وحدّ المربع.
Material _material(WidgetTester tester, String key) => tester.widget<Material>(
  find.ancestor(of: _key(key), matching: find.byType(Material)).first,
);

Color? _tabColor(WidgetTester tester, int place) =>
    _material(tester, 'h2h.cupTree.tab.$place').color;

BorderSide _side(WidgetTester tester, String key) =>
    (_material(tester, key).shape! as RoundedRectangleBorder).side;

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

void main() {
  test('the tree words and pure helpers say what the server sent', () {
    final H2hCupBoardPairDto done = _pair(
      1,
      _omar,
      _huda,
      decided: true,
      winner: 'u-o',
    );
    expect(h2hCupPairWon(done, _omar), isTrue);
    expect(h2hCupPairWon(done, _huda), isFalse);
    // قبل الحسم لا فائز ولو وصل اسم.
    expect(
      h2hCupPairWon(_pair(1, _omar, _huda, winner: 'u-o'), _omar),
      isFalse,
    );
    // حُسم بلا فائز: لم يفز أحد.
    expect(
      h2hCupPairWon(_pair(1, _omar, _huda, decided: true), _omar),
      isFalse,
    );

    expect(h2hCupTreeBoxLabel(_pair(1, _me, _noura)), 'سامي ضد نورة');
    expect(h2hCupTreeBoxLabel(done), 'عمر ضد هدى · الفائز: عمر');

    expect(
      h2hCupTreeSlotText(_stage('final', 'waiting', const [])),
      'بانتظار الفائز',
    );
    expect(
      h2hCupTreeSlotText(_stage('semi', 'waiting', const [])),
      'بانتظار السحب',
    );
    expect(h2hCupTreeSlotText(_stage('semi', 'skipped', const [])), 'لا تُلعب');
    expect(
      h2hCupTreeSlotText(_stage('final', 'skipped', const [])),
      'لا تُلعب',
    );

    expect(h2hCupTreeChampionText(_myPath()), '؟');
    expect(h2hCupTreeChampionText(_donePath()), 'عمر');
    expect(
      h2hCupTreeChampionText(
        _path(
          1,
          const <H2hCupBoardStageDto>[],
          title: const H2hCupTitleDto(how: 'vacant'),
        ),
      ),
      'شاغر',
    );
    expect(h2hCupTreeChampionSemantics(_myPath()), 'البطل: لم يُحسم بعد');
    expect(h2hCupTreeChampionSemantics(_donePath()), 'البطل: عمر');
  });

  testWidgets('a participant opens on his own path, boxes and ring drawn', (
    WidgetTester tester,
  ) async {
    await _mount(tester, _board());
    final AppTokens t = tester.element(_key('h2h.cupTree')).tokens;

    expect(_text(tester, 'h2h.cupTree.heading'), 'شجرة الأدوار');
    for (final int place in <int>[1, 2, 3]) {
      expect(_key('h2h.cupTree.tab.$place'), findsOneWidget);
    }
    expect(_text(tester, 'h2h.cupTree.tab.2'), 'ثواني المجموعات');
    expect(_tabColor(tester, 2), t.primary);
    expect(_tabColor(tester, 1), t.surfaceHigh);
    expect(_tabColor(tester, 3), t.surfaceHigh);

    expect(_text(tester, 'h2h.cupTree.stage.0'), 'نصف النهائي');
    expect(_text(tester, 'h2h.cupTree.stage.1'), 'النهائي');
    expect(_text(tester, 'h2h.cupTree.box.0.1.home'), 'سامي');
    expect(_text(tester, 'h2h.cupTree.box.0.1.away'), 'نورة');
    expect(_text(tester, 'h2h.cupTree.box.0.2.home'), 'عمر');
    expect(_text(tester, 'h2h.cupTree.box.0.2.away'), 'هدى');
    // قبل الحسم لا علامة فائز.
    expect(_key('h2h.cupTree.box.0.1.home.winner'), findsNothing);
    expect(_key('h2h.cupTree.box.0.2.home.winner'), findsNothing);
    // حدّ مربع اللاعب بلون الأساس، وحدّ غيره عادي.
    expect(_side(tester, 'h2h.cupTree.box.0.1').color, t.primary);
    expect(_side(tester, 'h2h.cupTree.box.0.2').color, t.border);

    // النهائي لم يُسحب: مربع متقطع بصفين.
    expect(_text(tester, 'h2h.cupTree.slot.1.0'), 'بانتظار الفائز');
    expect(_text(tester, 'h2h.cupTree.slot.1.1'), 'بانتظار الفائز');
    // البطل مجهول: حلقة فيها علامة استفهام، ولا اسم.
    expect(_text(tester, 'h2h.cupTree.champion.label'), 'البطل');
    expect(_text(tester, 'h2h.cupTree.champion.text'), '؟');
    expect(_key('h2h.cupTree.champion.name'), findsNothing);
    expect(_text(tester, 'h2h.cupTree.hint'), 'اضغط أي مربع لترى مبارياته');

    // الترتيب في الواجهة العربية: نصف النهائي على اليمين، ثم النهائي، ثم
    // البطل على اليسار؛ والزوج الأول فوق الثاني.
    expect(
      _dx(tester, 'h2h.cupTree.box.0.1'),
      greaterThan(_dx(tester, 'h2h.cupTree.slot.1')),
    );
    expect(
      _dx(tester, 'h2h.cupTree.slot.1'),
      greaterThan(_dx(tester, 'h2h.cupTree.champion.circle')),
    );
    expect(
      _dy(tester, 'h2h.cupTree.box.0.1'),
      lessThan(_dy(tester, 'h2h.cupTree.box.0.2')),
    );

    // لقارئ الشاشة: التبويب والمربع والبطل جملة واحدة لكل منها.
    expect(_label(tester, 'h2h.cupTree.tab.2'), 'ثواني المجموعات');
    expect(_label(tester, 'h2h.cupTree.box.0.1'), 'سامي ضد نورة');
    expect(
      _label(tester, 'h2h.cupTree.champion.circle'),
      'البطل: لم يُحسم بعد',
    );
  });

  testWidgets('a decided path marks its winners and crowns its champion', (
    WidgetTester tester,
  ) async {
    await _mount(tester, _board());
    final AppTokens t = tester.element(_key('h2h.cupTree')).tokens;

    await _tap(tester, 'h2h.cupTree.tab.1');
    expect(_tabColor(tester, 1), t.primary);
    expect(_tabColor(tester, 2), t.surfaceHigh);

    // الفائز بنقطة خضراء، والخاسر باهت.
    expect(_key('h2h.cupTree.box.0.1.home.winner'), findsOneWidget);
    expect(_key('h2h.cupTree.box.0.1.away.winner'), findsNothing);
    expect(_key('h2h.cupTree.box.0.2.away.winner'), findsOneWidget);
    expect(_key('h2h.cupTree.box.0.2.home.winner'), findsNothing);
    expect(_textColor(tester, 'h2h.cupTree.box.0.1.away'), t.textSecondary);
    expect(_textColor(tester, 'h2h.cupTree.box.0.1.home'), t.textPrimary);
    final Container dot = tester.widget<Container>(
      _key('h2h.cupTree.box.0.1.home.winner'),
    );
    expect((dot.decoration! as BoxDecoration).color, t.success);
    expect(_label(tester, 'h2h.cupTree.box.0.1'), 'عمر ضد هدى · الفائز: عمر');

    // النهائي مسحوب بزوجه، فلا مربع متقطع.
    expect(_key('h2h.cupTree.slot.1'), findsNothing);
    expect(_text(tester, 'h2h.cupTree.box.1.1.home'), 'عمر');
    expect(_text(tester, 'h2h.cupTree.box.1.1.away'), 'طلال');
    expect(_key('h2h.cupTree.box.1.1.home.winner'), findsOneWidget);
    // لا لاعب من هذا المسار هو اللاعب نفسه: حدّ عادي.
    expect(_side(tester, 'h2h.cupTree.box.0.1').color, t.border);

    // البطل: دائرة ذهبية فيها كأس واسمه تحتها.
    expect(_text(tester, 'h2h.cupTree.champion.name'), 'عمر');
    expect(_key('h2h.cupTree.champion.text'), findsNothing);
    final Container circle = tester.widget<Container>(
      _key('h2h.cupTree.champion.circle'),
    );
    expect((circle.decoration! as BoxDecoration).color, t.goldAccent);
    expect(
      find.descendant(
        of: _key('h2h.cupTree.champion.circle'),
        matching: find.byIcon(Icons.emoji_events),
      ),
      findsOneWidget,
    );
    expect(_label(tester, 'h2h.cupTree.champion.circle'), 'البطل: عمر');
  });

  testWidgets('a box opens the fixtures of its pair, and closes again', (
    WidgetTester tester,
  ) async {
    await _mount(tester, _board());
    final AppTokens t = tester.element(_key('h2h.cupTree')).tokens;
    expect(_key('h2h.cupTree.fixtures'), findsNothing);

    await _tap(tester, 'h2h.cupTree.box.0.1');
    expect(_key('h2h.cupTree.hint'), findsNothing);
    expect(_key('h2h.cupTree.fixtures'), findsOneWidget);
    expect(_text(tester, 'h2h.cupTree.fixtures.heading'), 'مباريات المواجهة');
    expect(_key('h2h.cupTree.fixtures.row.f1'), findsOneWidget);
    // توقع الخصم قبل الانطلاق محجوب كما في بطاقة المباريات.
    expect(
      _text(tester, 'h2h.cupTree.fixtures.row.f1.away.hidden'),
      'تظهر بعد انطلاق المباراة',
    );
    expect(_side(tester, 'h2h.cupTree.box.0.1').width, 2);
    expect(_side(tester, 'h2h.cupTree.box.0.1').color, t.primary);

    // الضغط ثانية يغلقها ويعيد التلميح.
    await _tap(tester, 'h2h.cupTree.box.0.1');
    expect(_key('h2h.cupTree.fixtures'), findsNothing);
    expect(_key('h2h.cupTree.hint'), findsOneWidget);
    expect(_side(tester, 'h2h.cupTree.box.0.1').width, 1);

    // زوج بلا مباريات مسجلة يقول ذلك.
    await _tap(tester, 'h2h.cupTree.box.0.2');
    expect(_key('h2h.cupTree.fixtures'), findsNothing);
    expect(
      _text(tester, 'h2h.cupTree.noFixtures'),
      'لا مباريات مسجّلة لهذه المواجهة بعد',
    );

    // مربع آخر يحل محله، والتبويب يمسح ما فُتح.
    await _tap(tester, 'h2h.cupTree.box.0.1');
    expect(_key('h2h.cupTree.noFixtures'), findsNothing);
    expect(_key('h2h.cupTree.fixtures'), findsOneWidget);
    await _tap(tester, 'h2h.cupTree.tab.3');
    expect(_key('h2h.cupTree.fixtures'), findsNothing);
    expect(_key('h2h.cupTree.noFixtures'), findsNothing);
    expect(_key('h2h.cupTree.hint'), findsOneWidget);
  });

  testWidgets('a qualifier on a bye is named, and his box opens nothing', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardPathDto bye = _path(1, <H2hCupBoardStageDto>[
      _stage('semi', 'scheduled', <H2hCupBoardPairDto>[
        _pair(1, _omar, _huda),
      ], bye: _me),
      _stage('final', 'waiting', const <H2hCupBoardPairDto>[]),
    ]);
    await _mount(tester, H2hCupBoardDto(paths: <H2hCupBoardPathDto>[bye]));
    final AppTokens t = tester.element(_key('h2h.cupTree')).tokens;

    expect(_text(tester, 'h2h.cupTree.bye.0.name'), 'سامي');
    expect(_text(tester, 'h2h.cupTree.bye.0.note'), 'تأهل مباشرة');
    expect(_label(tester, 'h2h.cupTree.bye.0'), 'سامي · تأهل مباشرة');
    final Container box = tester.widget<Container>(_key('h2h.cupTree.bye.0'));
    expect(
      ((box.decoration! as BoxDecoration).border! as Border).top.color,
      t.primary,
    );

    await _tap(tester, 'h2h.cupTree.bye.0');
    expect(_key('h2h.cupTree.fixtures'), findsNothing);
    expect(_key('h2h.cupTree.noFixtures'), findsNothing);
    expect(_key('h2h.cupTree.hint'), findsOneWidget);
  });

  testWidgets('a stage left out of the path is a box that says so', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardPathDto skipped = _path(2, <H2hCupBoardStageDto>[
      _stage('semi', 'skipped', const <H2hCupBoardPairDto>[]),
      _stage('final', 'live', <H2hCupBoardPairDto>[_pair(1, _me, _noura)]),
    ]);
    await _mount(tester, H2hCupBoardDto(paths: <H2hCupBoardPathDto>[skipped]));

    expect(_text(tester, 'h2h.cupTree.slot.0.0'), 'لا تُلعب');
    expect(_key('h2h.cupTree.slot.0.1'), findsNothing);
    expect(_text(tester, 'h2h.cupTree.box.1.1.home'), 'سامي');
    expect(_key('h2h.cupTree.hint'), findsOneWidget);
  });

  testWidgets('a path with no pair yet shows its boxes empty, no hint', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardPathDto waiting = _path(1, <H2hCupBoardStageDto>[
      _stage('semi', 'waiting', const <H2hCupBoardPairDto>[]),
      _stage('final', 'waiting', const <H2hCupBoardPairDto>[]),
    ]);
    await _mount(tester, H2hCupBoardDto(paths: <H2hCupBoardPathDto>[waiting]));

    expect(_text(tester, 'h2h.cupTree.slot.0.0'), 'بانتظار السحب');
    expect(_text(tester, 'h2h.cupTree.slot.1.0'), 'بانتظار الفائز');
    expect(_text(tester, 'h2h.cupTree.champion.text'), '؟');
    expect(_key('h2h.cupTree.hint'), findsNothing);
  });

  testWidgets('a path that ended with the title vacant says so in the ring', (
    WidgetTester tester,
  ) async {
    final H2hCupBoardPathDto vacant = _path(1, <H2hCupBoardStageDto>[
      _stage('semi', 'decided', <H2hCupBoardPairDto>[
        _pair(1, _omar, _huda, decided: true),
      ]),
      _stage('final', 'skipped', const <H2hCupBoardPairDto>[]),
    ], title: const H2hCupTitleDto(how: 'vacant'));
    await _mount(tester, H2hCupBoardDto(paths: <H2hCupBoardPathDto>[vacant]));

    expect(_text(tester, 'h2h.cupTree.champion.text'), 'شاغر');
    expect(_key('h2h.cupTree.champion.name'), findsNothing);
    expect(_key('h2h.cupTree.box.0.1.home.winner'), findsNothing);
    expect(_key('h2h.cupTree.box.0.1.away.winner'), findsNothing);
  });

  testWidgets('a watcher opens on the first path, and a fresh board keeps '
      'his choice or falls back', (WidgetTester tester) async {
    final H2hCupBoardPathDto other = _path(2, <H2hCupBoardStageDto>[
      _stage('semi', 'live', <H2hCupBoardPairDto>[_pair(1, _talal, _noura)]),
      _stage('final', 'waiting', const <H2hCupBoardPairDto>[]),
    ]);
    H2hCupBoardDto watcher(List<H2hCupBoardPathDto> paths) =>
        H2hCupBoardDto(monthStart: '2026-11-01', paths: paths);
    await _mount(
      tester,
      watcher(<H2hCupBoardPathDto>[_donePath(), other, _livePath()]),
    );
    final AppTokens t = tester.element(_key('h2h.cupTree')).tokens;
    expect(_tabColor(tester, 1), t.primary);

    // اختار المسار الثالث؛ لوحة جديدة بالمسارات نفسها تُبقيه.
    await _tap(tester, 'h2h.cupTree.tab.3');
    expect(_tabColor(tester, 3), t.primary);
    await _mount(
      tester,
      watcher(<H2hCupBoardPathDto>[_donePath(), other, _livePath()]),
    );
    expect(_tabColor(tester, 3), t.primary);
    expect(_tabColor(tester, 1), t.surfaceHigh);

    // لوحة بلا المسار الثالث: يرجع إلى الأول.
    await _mount(tester, watcher(<H2hCupBoardPathDto>[_donePath(), other]));
    expect(_key('h2h.cupTree.tab.3'), findsNothing);
    expect(_tabColor(tester, 1), t.primary);
    expect(_tabColor(tester, 2), t.surfaceHigh);
  });

  testWidgets('before the cup stands, nothing is drawn', (
    WidgetTester tester,
  ) async {
    await _mount(tester, const H2hCupBoardDto());
    expect(_key('h2h.cupTree'), findsNothing);
    expect(_key('h2h.cupTree.card'), findsNothing);
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
    final H2hCupBoardPathDto mine = _path(2, <H2hCupBoardStageDto>[
      _stage('semi', 'live', <H2hCupBoardPairDto>[
        _pair(
          1,
          longMe,
          longOther,
          fixtures: <H2hCupBoardFixtureDto>[_fixture('f-long')],
        ),
        _pair(2, _omar, _huda),
      ]),
      _stage('final', 'waiting', const <H2hCupBoardPairDto>[]),
    ]);
    final H2hCupPlayerDto longChampion = _p(
      'u-c',
      'محمد عبدالعزيز السليمان الغامدي',
    );
    final H2hCupBoardPathDto crowned = _path(1, <H2hCupBoardStageDto>[
      _stage('semi', 'decided', <H2hCupBoardPairDto>[
        _pair(1, longChampion, _huda, decided: true, winner: 'u-c'),
      ]),
      _stage('final', 'decided', <H2hCupBoardPairDto>[
        _pair(1, longChampion, longOther, decided: true, winner: 'u-c'),
      ]),
    ], title: H2hCupTitleDto(how: 'final', champion: longChampion));
    await _mount(
      tester,
      H2hCupBoardDto(
        monthStart: '2026-11-01',
        paths: <H2hCupBoardPathDto>[crowned, mine, _livePath()],
      ),
      width: 360,
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(_key('h2h.cupTree.box.0.1'), findsOneWidget);
    expect(_key('h2h.cupTree.slot.1'), findsOneWidget);
    await _tap(tester, 'h2h.cupTree.box.0.1');
    expect(tester.takeException(), isNull);
    expect(_key('h2h.cupTree.fixtures.row.f-long'), findsOneWidget);

    await _tap(tester, 'h2h.cupTree.tab.1');
    expect(tester.takeException(), isNull);
    expect(_key('h2h.cupTree.champion.name'), findsOneWidget);
    expect(_key('h2h.cupTree.box.1.1.home.winner'), findsOneWidget);
  });
}
