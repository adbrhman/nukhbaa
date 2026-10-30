/// The rules text is chosen by the month a player is in, never by today's
/// date (decided 2026-10-29): November keeps its own eight rules, December
/// 2026 and every month after it read the December rules, and the sheet and
/// the card draw the list of the month they are given.
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
    test('November keeps its own eight rules', () {
      expect(h2hRulesForMonth('2026-11-01'), same(h2hRules));
      expect(h2hRulesForMonth('2026-10-01'), same(h2hRules));
      expect(h2hRules, hasLength(8));
      expect(h2hRules.join(' '), isNot(contains('متوسط نقاط')));
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
      expect(all, contains('إذا غاب خصمك وأنت توقّعت'));
      expect(all, contains('متوسط نقاط كل أعضاء المجموعة'));
      expect(all, contains('الغائب بصفر وأنت ضمن المتوسط'));
      expect(all, contains('غيابك أنت يبقى خسارة'));
      expect(all, contains('إذا غاب الطرفان يخسران معًا'));
    });

    test('December says how groups of one division are compared', () {
      final String line = h2hDecemberRules.singleWhere(
        (String r) => r.startsWith('بين مجموعات الدرجة الواحدة'),
      );
      final List<int> at = <String>[
        'المركز في المجموعة',
        'نقاط التوقع',
        'الإصابات الدقيقة',
        'نقاط الدوري',
      ].map(line.indexOf).toList();
      expect(at.every((int i) => i >= 0), isTrue);
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
      expect(find.text(h2hRules.first), findsOneWidget);
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
