import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/rules_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

void main() {
  testWidgets('the rules page states the knockout rule', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const RulesScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rules.knockout')), findsOneWidget);
    expect(find.textContaining('الأشواط الإضافية'), findsWidgets);
    expect(find.textContaining('ركلات الترجيح'), findsWidgets);
  });

  // Audit M-07: only the exact score earns points, and the page must say
  // it in those words -- "التوقع الصحيح" read as "I called the winner".
  testWidgets('the rules page says only the exact score scores', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const RulesScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // The last row is built, so every findsNothing below is meaningful.
    expect(find.byKey(const Key('rules.tieBreak')), findsOneWidget);

    expect(find.text('النتيجة الدقيقة (مثل 2-1): 3 نقاط'), findsOneWidget);
    expect(
      find.text('أي توقع آخر: 0 نقطة، حتى لو أصبت الاتجاه (الفائز أو التعادل)'),
      findsOneWidget,
    );
    expect(
      find.text('الدبل يضاعف النقاط: النتيجة الدقيقة فيه 6 نقاط'),
      findsOneWidget,
    );
    expect(find.textContaining('التوقع الصحيح'), findsNothing);

    // The three rules the page left out.
    expect(
      find.descendant(
        of: find.byKey(const Key('rules.oneDouble')),
        matching: find.textContaining('دبل واحد فقط في اليوم'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('rules.lock')),
        matching: find.textContaining('حتى انطلاق المباراة'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('rules.month')),
        matching: find.textContaining('من الصفر'),
      ),
      findsOneWidget,
    );
  });

  // Batch 129: a tie on points goes down the whole chain, so every player
  // has a place of his own.
  testWidgets('the rules page states the whole tie-break chain', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const RulesScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final Finder rule = find.byKey(const Key('rules.tieBreak'));
    // The invitations were removed (2026-10-26): no step names them.
    expect(
      find.descendant(of: rule, matching: find.textContaining('الدعوة')),
      findsNothing,
    );
    for (final String step in <String>[
      'التوقعات الدقيقة الأكثر',
      'الاتجاهات الصحيحة الأكثر',
      'الأسبق انضماماً',
    ]) {
      expect(
        find.descendant(of: rule, matching: find.textContaining(step)),
        findsOneWidget,
        reason: step,
      );
    }
  });
}
