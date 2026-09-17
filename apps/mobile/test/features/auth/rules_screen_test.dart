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
}
