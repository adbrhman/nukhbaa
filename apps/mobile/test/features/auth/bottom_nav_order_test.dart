/// The bottom bar's order (2026-10-10, the owner's choice): home, the
/// head-to-head league, matches, leaders, account -- read from the start,
/// the right edge in Arabic. Each item still opens its own page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/ui/brand_mark.dart';
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
        // The mark is drawn as a vector (script 160), never the 512 px
        // picture scaled down to a blur.
        expect(
          find.descendant(
            of: find.byKey(Key('nav.item.$tab')),
            matching: find.byType(BrandMark),
          ),
          findsOneWidget,
          reason: tab,
        );
        expect(
          find.descendant(
            of: find.byKey(Key('nav.item.$tab')),
            matching: find.byType(Image),
          ),
          findsNothing,
          reason: tab,
        );
      }
      // The side tabs wear the mark at the same corner, the same size.
      final List<Rect> marks = <Rect>[
        for (final String tab in <String>['home', 'h2h', 'leaders', 'account'])
          tester.getRect(find.byKey(Key('nav.badge.$tab'))),
      ];
      for (final Rect mark in marks.skip(1)) {
        expect(mark.size, marks.first.size);
        expect(mark.top, marks.first.top);
      }
      final Rect homeItem = tester.getRect(
        find.byKey(const Key('nav.item.home')),
      );
      // Arabic reads from the right: the mark sits on the icon's left top.
      expect(marks.first.center.dx, lessThan(homeItem.center.dx));
      // The middle disc carries the mark alone, inside the bar: no ball.
      expect(find.byIcon(Icons.sports_soccer), findsNothing);
      final Finder brand = find.byKey(const Key('nav.brand'));
      expect(
        find.descendant(
          of: find.byKey(const Key('nav.item.fixtures')),
          matching: brand,
        ),
        findsOneWidget,
      );
      final Rect navRect = tester.getRect(find.byType(NukhbaaBottomNav));
      expect(tester.getRect(brand).top, greaterThanOrEqualTo(navRect.top));
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

      // No bar (script 158): no colour, rim or blur of its own -- only a
      // fade into the page colour, clear at the top.
      expect(
        find.ancestor(
          of: find.text('الحساب'),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      final LinearGradient fade =
          (tester
                          .widget<DecoratedBox>(
                            find.byKey(const Key('nav.fade')),
                          )
                          .decoration
                      as BoxDecoration)
                  .gradient!
              as LinearGradient;
      expect(fade.colors.first.a, 0);
      final Rect bar = tester.getRect(find.byKey(const Key('nav.fade')));
      // The fade's opacity where a label starts, from its stops.
      double alphaAt(double y) {
        final double f = ((y - bar.top) / bar.height).clamp(0.0, 1.0);
        final List<double> stops = fade.stops!;
        for (int i = 1; i < stops.length; i++) {
          if (f <= stops[i]) {
            final double t = (f - stops[i - 1]) / (stops[i] - stops[i - 1]);
            final double a0 = fade.colors[i - 1].a;
            final double a1 = fade.colors[i].a;
            return a0 + (a1 - a0) * t;
          }
        }
        return fade.colors.last.a;
      }

      // Every label, open or not, holds 4.5:1 over the page and over the
      // worst content that can scroll under it -- white in the dark theme,
      // black in the light one -- through the fade where it sits.
      final bool dark = theme.brightness == Brightness.dark;
      for (final String label in <String>[
        'الرئيسية',
        'المواجهات',
        'المباريات',
        'المتصدرون',
        'الحساب',
      ]) {
        final Finder text = find.text(label);
        final Color fg = tester.widget<Text>(text).style!.color!;
        final Color tint = fade.colors.last.withValues(
          alpha: alphaAt(tester.getRect(text).top),
        );
        for (final Color behind in <Color>[
          theme.scaffoldBackgroundColor,
          dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
        ]) {
          expect(
            _contrast(fg, Color.alphaBlend(tint, behind)),
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
