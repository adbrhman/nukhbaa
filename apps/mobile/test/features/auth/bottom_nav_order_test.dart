/// The bottom bar's order (2026-10-10, the owner's choice): home, the
/// head-to-head league, matches, leaders, account -- read from the start,
/// the right edge in Arabic. Each item still opens its own page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/nukhbaa_shell.dart';
import 'package:mobile/features/auth/sign_in_screen.dart' show kBrandLogoAsset;

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

  for (final (String name, ThemeData theme) in <(String, ThemeData)>[
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
  ]) {
    testWidgets('$name: every glyph wears the brand mark; the open tab is '
        'underlined; labels read at 4.5:1', (tester) async {
      final List<int> opened = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              bottomNavigationBar: NukhbaaBottomNav(
                index: 1,
                onChanged: opened.add,
              ),
            ),
          ),
        ),
      );

      for (final String tab in <String>[
        'home',
        'h2h',
        'fixtures',
        'leaders',
        'account',
      ]) {
        final Finder badge = find.descendant(
          of: find.byKey(Key('nav.item.$tab')),
          matching: find.byKey(Key('nav.badge.$tab')),
        );
        expect(badge, findsOneWidget, reason: tab);
        final Image logo = tester.widget<Image>(
          find.descendant(of: badge, matching: find.byType(Image)),
        );
        expect((logo.image as AssetImage).assetName, kBrandLogoAsset);
      }
      // The ball sits in the middle item, inside the bar: no longer raised.
      final Finder brand = find.byKey(const Key('nav.brand'));
      expect(
        find.descendant(
          of: find.byKey(const Key('nav.item.fixtures')),
          matching: brand,
        ),
        findsOneWidget,
      );
      final Rect bar = tester.getRect(find.byType(NukhbaaBottomNav));
      expect(tester.getRect(brand).top, greaterThanOrEqualTo(bar.top));
      // One underline, under the open tab.
      expect(find.byKey(const Key('nav.indicator')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('nav.item.fixtures')),
          matching: find.byKey(const Key('nav.indicator')),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byKey(const Key('nav.item.fixtures'))),
        isSemantics(isSelected: true, isButton: true),
      );

      // The bar is see-through (script 157): every label, open or not,
      // must hold 4.5:1 over the page and over the worst content that can
      // scroll under it -- white in the dark theme, black in the light one.
      final Color tint = tester
          .widget<Material>(
            find
                .ancestor(
                  of: find.text('الحساب'),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color!;
      expect(tint.a, lessThan(1.0));
      expect(
        find.ancestor(
          of: find.text('الحساب'),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
      final bool dark = theme.brightness == Brightness.dark;
      for (final Color behind in <Color>[
        theme.scaffoldBackgroundColor,
        dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      ]) {
        final Color under = Color.alphaBlend(tint, behind);
        for (final String label in <String>[
          'الرئيسية',
          'المواجهات',
          'المباريات',
          'المتصدرون',
          'الحساب',
        ]) {
          final Color fg = tester.widget<Text>(find.text(label)).style!.color!;
          expect(
            _contrast(fg, under),
            greaterThanOrEqualTo(4.5),
            reason: '$label over $behind',
          );
        }
      }

      await tester.tap(find.byKey(const Key('nav.item.fixtures')));
      expect(opened, <int>[1]);
    });
  }
}

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
