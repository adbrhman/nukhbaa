// NK362A_01
/// كأس الشجرة الواحدة (ديسمبر 2026 فصاعداً) في نصوص الكأس وقسم المسارات
/// وبطاقة «مواجهتك الآن»: الدوران الجديدان باسميهما، والمسار الواحد يُسمّى
/// «كأس النخبة» لا «مسار أوائل المجموعات»، وعنوان القسم للمشاهد «مسار
/// الكأس» لا «المسارات الثلاثة»، والبطل بطل الكأس. ونوفمبر وما قبله على
/// المسارات الثلاثة بلا تغيير. الودجتان بـ AppTheme الحقيقي، وعند 360px
/// ونص x2 بلا فيض.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/h2h_cup_texts.dart';
import 'package:mobile/features/h2h/widgets/h2h_cup_now.dart';
import 'package:mobile/features/h2h/widgets/h2h_cup_path.dart';
import 'package:mobile/l10n/app_localizations.dart';

H2hCupPlayerDto _p(String id, String name, {bool me = false}) =>
    H2hCupPlayerDto(userId: id, displayName: name, groupNumber: 1, isMe: me);

final H2hCupPlayerDto _me = _p('u-me', 'سامي', me: true);
final H2hCupPlayerDto _noura = _p('u-n', 'نورة');
final H2hCupPlayerDto _omar = _p('u-o', 'عمر');
final H2hCupPlayerDto _huda = _p('u-h', 'هدى');
final H2hCupPlayerDto _watcher = _p('u-w', 'مشاهد');

H2hCupBoardPairDto _pair(
  int slot,
  H2hCupPlayerDto home,
  H2hCupPlayerDto away,
) => H2hCupBoardPairDto(
  slot: slot,
  home: home,
  away: away,
  decided: false,
  fixtures: const <H2hCupBoardFixtureDto>[],
);

H2hCupBoardStageDto _stage(
  String round,
  int cupDay,
  String phase,
  List<H2hCupBoardPairDto> pairs, {
  String? day,
}) => H2hCupBoardStageDto(
  round: round,
  cupDay: cupDay,
  phase: phase,
  attempt: 1,
  day: day,
  pairs: pairs,
);

/// الشجرة: أربعة أدوار على مسار واحد، ودور الـ16 جارٍ بأول زوجين.
H2hCupBoardPathDto _bracket({
  required H2hCupPlayerDto first,
  H2hCupTitleDto? title,
}) => H2hCupBoardPathDto(
  place: 1,
  stages: <H2hCupBoardStageDto>[
    _stage('round16', 1, 'live', <H2hCupBoardPairDto>[
      _pair(1, first, _noura),
      _pair(2, _omar, _huda),
    ], day: '2026-12-21'),
    _stage('quarter', 2, 'waiting', const <H2hCupBoardPairDto>[]),
    _stage('semi', 3, 'waiting', const <H2hCupBoardPairDto>[]),
    _stage('final', 4, 'waiting', const <H2hCupBoardPairDto>[]),
  ],
  title: title,
);

/// مسار من مسارات نوفمبر: نصف نهائي ونهائي.
H2hCupBoardPathDto _classic(int place) => H2hCupBoardPathDto(
  place: place,
  stages: <H2hCupBoardStageDto>[
    _stage('semi', 1, 'live', <H2hCupBoardPairDto>[_pair(1, _omar, _huda)]),
    _stage('final', 2, 'waiting', const <H2hCupBoardPairDto>[]),
  ],
);

H2hCupBoardDto _board(H2hCupBoardPathDto path) =>
    H2hCupBoardDto(monthStart: '2026-12-01', paths: <H2hCupBoardPathDto>[path]);

Future<void> _open(
  WidgetTester tester,
  Widget section, {
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
      home: Scaffold(body: SingleChildScrollView(child: section)),
    ),
  );
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) {
  final Finder found = find.byKey(Key(key));
  expect(found, findsOneWidget, reason: key);
  return (tester.widget(found) as Text).data ?? '';
}

void main() {
  group('the words of the bracket cup', () {
    test('the two new rounds have their names', () {
      expect(h2hCupRoundName('round16'), 'دور الـ16');
      expect(h2hCupRoundName('quarter'), 'ربع النهائي');
      expect(h2hCupRoundName('semi'), 'نصف النهائي');
      expect(h2hCupRoundName('final'), 'النهائي');
    });

    test(
      'only a path with a round of 16 or a quarter-final is the bracket',
      () {
        expect(h2hCupIsBracket(_bracket(first: _me)), isTrue);
        expect(h2hCupIsBracket(_classic(1)), isFalse);
        expect(
          h2hCupIsBracket(
            const H2hCupBoardPathDto(place: 1, stages: <H2hCupBoardStageDto>[]),
          ),
          isFalse,
        );
      },
    );

    test('the bracket path is the cup, a place path keeps its name', () {
      final H2hCupBoardPathDto bracket = _bracket(first: _me);
      expect(h2hCupBoardPathName(bracket), 'كأس النخبة');
      expect(h2hCupBoardPathShortName(bracket), 'كأس النخبة');
      expect(h2hCupBoardPathName(_classic(2)), 'مسار ثواني المجموعات');
      expect(h2hCupBoardPathShortName(_classic(3)), 'ثوالث المجموعات');
    });

    test('the title line names the cup, the old paths keep theirs', () {
      final H2hCupTitleDto mine = H2hCupTitleDto(how: 'final', champion: _me);
      final H2hCupTitleDto theirs = H2hCupTitleDto(
        how: 'final',
        champion: _noura,
      );
      const H2hCupTitleDto vacant = H2hCupTitleDto(how: 'vacant');
      expect(h2hCupBoardTitleLine(mine, bracket: true), 'أنت بطل كأس النخبة');
      expect(
        h2hCupBoardTitleLine(theirs, bracket: true),
        'بطل كأس النخبة: نورة',
      );
      expect(h2hCupBoardTitleLine(vacant, bracket: true), 'اللقب شاغر');
      expect(h2hCupBoardTitleLine(theirs), 'بطل المسار: نورة');
      expect(h2hCupBoardTitleLine(vacant), 'اللقب شاغر في هذا المسار');
    });

    test('the status and the champion line of the bracket', () {
      final H2hCupBoardPathDto live = _bracket(first: _me);
      expect(h2hCupBoardPathStatus(live), 'دور الـ16 · جارية');
      expect(h2hCupBoardChampionLine(live), 'بطل كأس النخبة');
      final H2hCupBoardPathDto crowned = _bracket(
        first: _me,
        title: H2hCupTitleDto(how: 'final', champion: _omar),
      );
      expect(h2hCupBoardPathStatus(crowned), 'بطل كأس النخبة: عمر');
      expect(h2hCupBoardChampionLine(crowned), 'بطل كأس النخبة: عمر');
      expect(h2hCupBoardChampionLine(_classic(2)), 'بطل مسار ثواني المجموعات');
    });

    test('the heading over the paths follows the cup the board holds', () {
      final List<H2hCupBoardPathDto> bracket = <H2hCupBoardPathDto>[
        _bracket(first: _me),
      ];
      final List<H2hCupBoardPathDto> classic = <H2hCupBoardPathDto>[
        _classic(1),
        _classic(2),
        _classic(3),
      ];
      expect(h2hCupPathsHeading(bracket, mine: false), 'مسار الكأس');
      expect(h2hCupPathsHeading(classic, mine: false), 'المسارات الثلاثة');
      expect(h2hCupPathsHeading(classic, mine: true), 'بقية المسارات');
    });

    test('a day lists the bracket as the cup, then its round', () {
      final H2hCupBoardPathDto path = _bracket(first: _me);
      expect(
        h2hCupDaySlotTitle((path: path, stage: path.stages[1])),
        'كأس النخبة · ربع النهائي',
      );
    });
  });

  group('the paths section on a bracket board', () {
    testWidgets('a player in the cup reads his path as the cup', (
      WidgetTester tester,
    ) async {
      await _open(tester, H2hCupPathsView(board: _board(_bracket(first: _me))));

      expect(tester.takeException(), isNull);
      expect(_text(tester, 'h2h.cupPath.heading'), 'مسارك · كأس النخبة');
      expect(find.byKey(const Key('h2h.cupPaths.heading')), findsNothing);
      expect(
        _text(tester, 'h2h.cupPath.stage.0').startsWith('دور الـ16'),
        isTrue,
      );
      expect(
        _text(tester, 'h2h.cupPath.stage.1').startsWith('ربع النهائي'),
        isTrue,
      );
      expect(
        _text(tester, 'h2h.cupPath.stage.2').startsWith('نصف النهائي'),
        isTrue,
      );
      expect(
        _text(tester, 'h2h.cupPath.stage.3').startsWith('النهائي'),
        isTrue,
      );
      expect(_text(tester, 'h2h.cupPath.champion'), 'بطل كأس النخبة');
    });

    testWidgets('a player who only watches reads one path of the cup', (
      WidgetTester tester,
    ) async {
      await _open(
        tester,
        H2hCupPathsView(board: _board(_bracket(first: _watcher))),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('h2h.cupPath.heading')), findsNothing);
      expect(_text(tester, 'h2h.cupPaths.heading'), 'مسار الكأس');
      expect(_text(tester, 'h2h.cupPaths.row.1.name'), 'كأس النخبة');
      expect(_text(tester, 'h2h.cupPaths.row.1.status'), 'دور الـ16 · جارية');
      expect(find.byKey(const Key('h2h.cupPaths.row.1.dots')), findsOneWidget);
      expect(find.textContaining('المسارات الثلاثة'), findsNothing);
      expect(find.textContaining('أوائل المجموعات'), findsNothing);
    });

    testWidgets('both read well at 360px and text x2', (
      WidgetTester tester,
    ) async {
      await _open(
        tester,
        H2hCupPathsView(board: _board(_bracket(first: _me))),
        width: 360,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('h2h.cupPath.champion')), findsOneWidget);

      await _open(
        tester,
        H2hCupPathsView(board: _board(_bracket(first: _watcher))),
        width: 360,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('h2h.cupPaths.row.1')), findsOneWidget);
    });
  });

  group('the duel card on a bracket board', () {
    testWidgets('names the round of 16 and the cup', (
      WidgetTester tester,
    ) async {
      await _open(tester, H2hCupNowView(board: _board(_bracket(first: _me))));

      expect(tester.takeException(), isNull);
      expect(_text(tester, 'h2h.cupNow.stage'), 'دور الـ16 · كأس النخبة');
    });

    testWidgets('reads well at 360px and text x2', (WidgetTester tester) async {
      await _open(
        tester,
        H2hCupNowView(board: _board(_bracket(first: _me))),
        width: 360,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('h2h.cupNow.card')), findsOneWidget);
    });
  });
}
