// NK362B_T1
/// شجرة الأدوار على كأس الشجرة الواحدة (سكربت 362b): أربعة أدوار وعمود
/// البطل أعرض من الهاتف، فتبقى أعمدتها بعرض ثابت وتتحرك البطاقة أفقياً بدل
/// أن تُسحق؛ ومربع الدور الذي لم يُسحب بعد يقول «بانتظار السحب» لدور الـ16
/// و«بانتظار الفائز» لما بعده؛ ومسارات نوفمبر بلا تمرير وبنصوصها. الودجة
/// بـ AppTheme الحقيقي وعلى لوحة كأس حقيقية، ولا تقرأ الساعة.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/h2h_cup_texts.dart';
import 'package:mobile/features/h2h/widgets/h2h_cup_tree.dart';
import 'package:mobile/l10n/app_localizations.dart';

H2hCupPlayerDto _p(int n) => H2hCupPlayerDto(
  userId: 'u$n',
  displayName: 'لاعب $n',
  groupNumber: 1,
  isMe: n == 1,
);

H2hCupBoardPairDto _pair(int slot, int home, int away) => H2hCupBoardPairDto(
  slot: slot,
  home: _p(home),
  away: _p(away),
  decided: false,
  fixtures: const <H2hCupBoardFixtureDto>[],
);

H2hCupBoardStageDto _stage(
  String round,
  int day,
  String phase, [
  List<H2hCupBoardPairDto> pairs = const <H2hCupBoardPairDto>[],
]) => H2hCupBoardStageDto(
  round: round,
  cupDay: day,
  phase: phase,
  attempt: 1,
  pairs: pairs,
);

/// كأس الشجرة: دور الـ16 جارٍ بثمانية أزواج، وما بعده لم يُسحب.
H2hCupBoardPathDto _bracket() => H2hCupBoardPathDto(
  place: 1,
  stages: <H2hCupBoardStageDto>[
    _stage('round16', 1, 'live', <H2hCupBoardPairDto>[
      for (int i = 0; i < 8; i++) _pair(i + 1, 2 * i + 1, 2 * i + 2),
    ]),
    _stage('quarter', 2, 'waiting'),
    _stage('semi', 3, 'waiting'),
    _stage('final', 4, 'waiting'),
  ],
);

/// مسار من مسارات نوفمبر: نصف نهائي جارٍ بزوجين، ونهائي لم يُسحب.
H2hCupBoardPathDto _classic() => H2hCupBoardPathDto(
  place: 1,
  stages: <H2hCupBoardStageDto>[
    _stage('semi', 1, 'live', <H2hCupBoardPairDto>[
      _pair(1, 1, 2),
      _pair(2, 3, 4),
    ]),
    _stage('final', 2, 'waiting'),
  ],
);

H2hCupBoardDto _board(H2hCupBoardPathDto path, String month) =>
    H2hCupBoardDto(monthStart: month, paths: <H2hCupBoardPathDto>[path]);

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

Finder _key(String key) => find.byKey(Key(key));

/// نص القطعة ذات المفتاح، وهي Text واحدة.
String _data(WidgetTester tester, String key) {
  final Finder found = _key(key);
  expect(found, findsOneWidget, reason: key);
  return tester.widget<Text>(found).data ?? '';
}

double _dx(WidgetTester tester, String key) => tester.getCenter(_key(key)).dx;

void main() {
  test('a box with no pair yet says what it is waiting for', () {
    expect(
      h2hCupTreeSlotText(_stage('round16', 1, 'waiting'), bracket: true),
      'بانتظار السحب',
    );
    for (final String round in <String>['quarter', 'semi', 'final']) {
      expect(
        h2hCupTreeSlotText(_stage(round, 2, 'waiting'), bracket: true),
        'بانتظار الفائز',
        reason: round,
      );
    }
    expect(
      h2hCupTreeSlotText(_stage('semi', 3, 'skipped'), bracket: true),
      'لا تُلعب',
    );
    // مسارات نوفمبر بلا معامل: النهائي وحده ينتظر الفائز.
    expect(h2hCupTreeSlotText(_stage('semi', 1, 'waiting')), 'بانتظار السحب');
    expect(h2hCupTreeSlotText(_stage('final', 2, 'waiting')), 'بانتظار الفائز');
  });

  testWidgets('the bracket shows its four rounds, first on the start edge', (
    WidgetTester tester,
  ) async {
    await _mount(tester, _board(_bracket(), '2026-12-01'));

    expect(_data(tester, 'h2h.cupTree.stage.0'), 'دور الـ16');
    expect(_data(tester, 'h2h.cupTree.stage.1'), 'ربع النهائي');
    expect(_data(tester, 'h2h.cupTree.stage.2'), 'نصف النهائي');
    expect(_data(tester, 'h2h.cupTree.stage.3'), 'النهائي');
    expect(_key('h2h.cupTree.box.0.8'), findsOneWidget);
    expect(_key('h2h.cupTree.scroll'), findsOneWidget);

    // ربع النهائي ونصفه ونهائيه ينتظرون الفائز، لا السحب.
    expect(_data(tester, 'h2h.cupTree.slot.1.0'), 'بانتظار الفائز');
    expect(_data(tester, 'h2h.cupTree.slot.2.0'), 'بانتظار الفائز');
    expect(_data(tester, 'h2h.cupTree.slot.3.0'), 'بانتظار الفائز');

    // الواجهة عربية: دور الـ16 على اليمين والبطل على اليسار.
    expect(
      _dx(tester, 'h2h.cupTree.stage.0'),
      greaterThan(_dx(tester, 'h2h.cupTree.stage.3')),
    );
    expect(
      _dx(tester, 'h2h.cupTree.champion.label'),
      lessThan(_dx(tester, 'h2h.cupTree.stage.3')),
    );

    // الضغط على مربع يفتح زوجه ولا مباريات مسجّلة له.
    await tester.tap(_key('h2h.cupTree.box.0.1'));
    await tester.pumpAndSettle();
    expect(_key('h2h.cupTree.noFixtures'), findsOneWidget);
  });

  testWidgets('the three paths of November keep the fixed layout', (
    WidgetTester tester,
  ) async {
    await _mount(tester, _board(_classic(), '2026-11-01'));

    expect(_key('h2h.cupTree.card'), findsOneWidget);
    expect(_key('h2h.cupTree.scroll'), findsNothing);
    expect(_data(tester, 'h2h.cupTree.stage.0'), 'نصف النهائي');
    expect(_data(tester, 'h2h.cupTree.slot.1.0'), 'بانتظار الفائز');
  });

  testWidgets('the bracket scrolls at 360px and text x2, no overflow', (
    WidgetTester tester,
  ) async {
    await _mount(
      tester,
      _board(_bracket(), '2026-12-01'),
      width: 360,
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    final ScrollableState scroll = tester.state<ScrollableState>(
      find.descendant(
        of: _key('h2h.cupTree.scroll'),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    for (int i = 0; i < 4; i++) {
      expect(_key('h2h.cupTree.stage.$i'), findsOneWidget, reason: '$i');
    }

    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_key('h2h.cupTree.champion.label'), findsOneWidget);
  });
}
