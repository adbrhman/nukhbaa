/// The app's button is read by its name once (Accessibility Scanner,
/// 2026-10-28): its Semantics names it, and its drawn text read again
/// doubled the name ("sign in sign in").
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/ui/app_button.dart';

Future<void> _pump(WidgetTester tester, Widget button) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: Center(child: button)),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a button is read by its name once, with or without an icon', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      await _pump(
        tester,
        AppButton(key: const Key('b'), label: 'Sign in', onPressed: () {}),
      );
      expect(tester.getSemantics(find.byKey(const Key('b'))).label, 'Sign in');

      await _pump(
        tester,
        AppButton(
          key: const Key('b'),
          label: 'Sign out',
          icon: Icons.logout_rounded,
          variant: AppButtonVariant.danger,
          onPressed: () {},
        ),
      );
      expect(tester.getSemantics(find.byKey(const Key('b'))).label, 'Sign out');
    } finally {
      handle.dispose();
    }
  });
}
