/// The rules text is chosen by the month a player is in, never by today's
/// date (decided 2026-10-29): November keeps its own eight rules, December
/// 2026 and every month after it read the December rules (the four-day cup
/// and the carry, NK276), and the sheet and the card draw the list of the
/// month they are given.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/h2h_screen.dart';
import 'package:mobile/features/h2h/h2h_texts.dart';
import 'package:mobile/l10n/app_localizations.dart';

Future<void> _pumpRules(WidgetTester tester, {String? monthStart}) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: SingleChildScrollView(
          child: H2hRulesList(monthStart: monthStart),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('h2hRulesForMonth', () {
    test('October keeps the ladder rules, eight of them', () {
      expect(h2hRulesForMonth('2026-10-01'), same(h2hRules));
      expect(h2hRules, hasLength(8));
      expect(h2hRules.join(' '), isNot(contains('متوسط نقاط')));
    });

    test('November reads the elite draw rules: groups, absence, the cup', () {
      expect(h2hRulesForMonth('2026-11-01'), same(h2hNovemberRules));
      expect(h2hNovemberRules, hasLength(8));
      final String all = h2hNovemberRules.join('\n');
      expect(all, contains('4 مجموعات من 20'));
      expect(all, contains('بعد الثالثة يُبدَّل مقعدك'));
      expect(all, contains('كأس النخبة'));
      expect(all, isNot(contains('درجة')));
      expect(
        h2hNovemberRules,
        contains('خصمك في كل جولة سري، ويُكشف عند انطلاق آخر مباراة فيها.'),
      );
    });

    test('December 2026 and every later month read the December rules', () {
      expect(h2hRulesForMonth('2026-12-01'), same(h2hDecemberRules));
      expect(h2hRulesForMonth('2027-01-01'), same(h2hDecemberRules));
      expect(h2hRulesForMonth('2028-06-01'), same(h2hDecemberRules));
    });

    test('a month that cannot be read keeps the rules it had', () {
      expect(h2hRulesForMonth(''), same(h2hRules));
      expect(h2hRulesForMonth('soon'), same(h2hRules));
    });

    test('December says how an absent opponent is faced', () {
      final String all = h2hDecemberRules.join('\n');
      // NK216_22: a walkover, not the group average.
      expect(all, contains('إذا غاب خصمك وأنت توقّعت'));
      expect(all, contains('توقّع صحيح واحد على الأقل'));
      expect(all, contains('نقطة واحدة فقط'));
      expect(all, isNot(contains('متوسط نقاط')));
      expect(all, contains('غيابك أنت يبقى خسارة'));
      expect(all, contains('إذا غاب الطرفان يخسران معًا'));
    });

    test('November says the walkover and the seat record from round 7', () {
      final String all = h2hNovemberRules.join('\n');
      expect(all, contains('ومن الجولة 7: إذا غاب خصمك وأنت توقّعت'));
      expect(all, contains('توقّع صحيح واحد على الأقل'));
      expect(all, contains('تبقى نقاط المقعد مع المقعد'));
      expect(all, isNot(contains('ويحتفظ كل لاعب بنقاطه.')));
    });

    // NK276: December tells the four-day cup and the carry (NK275).
    test('December says the Elite Cup in four days, paths 2 and 3 side by '
        'side', () {
      final String all = h2hDecemberRules.join('\n');
      expect(all, contains('في 4 أيام مباريات'));
      final List<int> at = <String>[
        'في اليوم الأول نصف نهائي أصحاب المركز الأول',
        'وفي اليوم الثاني نهائيهم ويُتوَّج بطل كأس النخبة',
        'في اليوم الثالث نصف نهائي أصحاب المركز الثاني فيما بينهم',
        'ونصف نهائي أصحاب المركز الثالث فيما بينهم، في اليوم نفسه',
        'وفي اليوم الرابع النهائيان معًا، ويُتوَّج ثاني الكأس وثالثها',
      ].map(all.indexOf).toList();
      expect(at.every((int i) => i >= 0), isTrue, reason: '$at');
      expect(at, orderedEquals(<int>[...at]..sort()));
      expect(all, contains('كأس منفصلة'));
      expect(all, isNot(contains('ثلاث كؤوس')));
    });

    test('December says how a cup pair is decided, in order', () {
      final String line = h2hDecemberRules.singleWhere(
        (String r) => r.startsWith('تُحسم مواجهة الكأس'),
      );
      final List<int> at = <String>[
        'من توقّع يفوز على من لم يتوقّع',
        'نقاط توقّع',
        'إصابات دقيقة',
        'الأفضل في الدوري',
        'إذا غاب الطرفان يخسران معًا',
      ].map(line.indexOf).toList();
      expect(at.every((int i) => i >= 0), isTrue, reason: '$at');
      expect(at, orderedEquals(<int>[...at]..sort()));
    });

    test('December says the carry of NK275: 3 down from each of the first '
        'four groups, the elite filled from groups 5 and 6, 5 and 5 below', () {
      final String all = h2hDecemberRules.join('\n');
      expect(
        all,
        contains('يهبط آخر 3 من كل مجموعة من 1 إلى 4 إلى المجموعة 5'),
      );
      expect(all, contains('بالأكثر التزامًا من المجموعتين 5 و6 معًا'));
      expect(all, contains('يهبط آخر 5 من كل مجموعة إلى التي تحتها'));
      expect(all, contains('أكثر 5 التزامًا من المجموعة التي تحتها'));
      expect(all, isNot(contains('درجة')));
      expect(all, isNot(contains('حتى 3 لاعبين')));
    });

    test('December ranks commitment in the owner\'s order', () {
      final String line = h2hDecemberRules.singleWhere(
        (String r) => r.startsWith('الالتزام:'),
      );
      final List<int> at = <String>[
        'الأقل غيابًا',
        'الأكثر توقّعات',
        'الأكثر إصابات دقيقة',
        'الأكثر نتائج صحيحة',
        'الأكثر نقاطًا',
      ].map(line.indexOf).toList();
      expect(at.every((int i) => i >= 0), isTrue, reason: '$at');
      expect(at, orderedEquals(<int>[...at]..sort()));
    });

    test('December ranks the eighty by the month, in order', () {
      final String line = h2hDecemberRules.singleWhere(
        (String r) => r.startsWith('في نهاية الشهر'),
      );
      final List<int> at = <String>[
        'المركز في المجموعة',
        'نقاط التوقع',
        'الإصابات الدقيقة',
        'نقاط الدوري',
      ].map(line.indexOf).toList();
      expect(at.every((int i) => i >= 0), isTrue, reason: '$at');
      expect(at, orderedEquals(<int>[...at]..sort()));
    });

    test('December says how a tie inside a group is broken, in order', () {
      final String line = h2hDecemberRules.singleWhere(
        (String r) => r.startsWith('داخل المجموعة'),
      );
      final List<int> at = <String>[
        'نقاط الدوري',
        'نقاط التوقع',
        'المواجهات بين المتعادلين',
        'الإصابات الدقيقة',
        'أسبقية المقعد',
      ].map(line.indexOf).toList();
      expect(at.every((int i) => i >= 0), isTrue);
      expect(at, orderedEquals(<int>[...at]..sort()));
    });
  });

  group('H2hRulesList', () {
    testWidgets('draws the eight November rules for a November month', (
      tester,
    ) async {
      await _pumpRules(tester, monthStart: '2026-11-01');

      expect(find.byKey(const Key('h2h.rule.8')), findsOneWidget);
      expect(find.byKey(const Key('h2h.rule.9')), findsNothing);
      expect(find.text(h2hNovemberRules.first), findsOneWidget);
      expect(find.text(h2hDecemberRules.first), findsNothing);
    });

    testWidgets('draws the December rules for a December month', (
      tester,
    ) async {
      await _pumpRules(tester, monthStart: '2026-12-01');

      final int last = h2hDecemberRules.length;
      expect(find.byKey(Key('h2h.rule.$last')), findsOneWidget);
      expect(find.byKey(Key('h2h.rule.${last + 1}')), findsNothing);
      for (final String rule in h2hDecemberRules) {
        expect(find.text(rule), findsOneWidget);
      }
    });

    testWidgets('with no month it draws the rules it always drew', (
      tester,
    ) async {
      await _pumpRules(tester);

      expect(find.byKey(const Key('h2h.rule.8')), findsOneWidget);
      expect(find.byKey(const Key('h2h.rule.9')), findsNothing);
    });
  });
}
