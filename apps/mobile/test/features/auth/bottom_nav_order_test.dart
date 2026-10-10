/// The bottom bar's order (2026-10-10, the owner's choice): home, the
/// head-to-head league, matches, leaders, account -- read from the start,
/// the right edge in Arabic. Each item still opens its own page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/nukhbaa_shell.dart';

void main() {
  testWidgets('home, the league, matches, leaders, account; each its page', (
    tester,
  ) async {
    final List<int> opened = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            bottomNavigationBar: NukhbaaBottomNav(
              index: 0,
              onChanged: opened.add,
            ),
          ),
        ),
      ),
    );

    const List<String> keys = <String>[
      'nav.item.home',
      'nav.item.h2h',
      'nav.item.fixtures',
      'nav.item.leaders',
      'nav.item.account',
    ];
    final List<double> centres = <double>[
      for (final String key in keys) tester.getCenter(find.byKey(Key(key))).dx,
    ];
    // Right to left: each item sits left of the one before it.
    for (int i = 1; i < centres.length; i++) {
      expect(centres[i], lessThan(centres[i - 1]), reason: keys[i]);
    }

    for (final String key in keys) {
      await tester.tap(find.byKey(Key(key)));
    }
    // The pages keep their indexes: home 0, matches 1, league 2,
    // leaders 3, account 4.
    expect(opened, <int>[0, 2, 1, 3, 4]);
  });
}
