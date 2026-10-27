/// Gold sits on an opaque amber, never on a wash of itself. A 14-16% gold
/// wash over the navy came out a neutral grey in the dark theme (#353C3B,
/// hue 171): the owner's screenshots showed the H2H shield circle, the
/// first place badge and the "pilot month" badge grey (colour audit of
/// 2026-10-15, CA-19). Checked on the token and on the real gold badge, in
/// both themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/ui/app_badge.dart';

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Opaque, in gold's own hue (within 25 degrees of it) and tinted
/// enough to read as gold rather than grey.
void _expectAmber(Color ground, Color gold, String what) {
  final HSVColor g = HSVColor.fromColor(ground);
  final HSVColor ref = HSVColor.fromColor(gold);
  final double apart = (g.hue - ref.hue).abs();
  expect(ground.a, 1.0, reason: '$what is opaque');
  expect(
    apart > 180 ? 360 - apart : apart,
    lessThanOrEqualTo(25),
    reason: '$what: hue ${g.hue.toStringAsFixed(0)}, gold ${ref.hue}',
  );
  expect(g.saturation, greaterThanOrEqualTo(0.1), reason: '$what is not grey');
}

void main() {
  for (final (String name, ThemeData theme) in <(String, ThemeData)>[
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
  ]) {
    final AppTokens t = theme.extension<AppTokens>()!;

    test('$name: the gold container is amber; gold reads on it', () {
      _expectAmber(t.goldContainer, t.goldAccent, 'goldContainer');
      expect(
        _contrast(t.gold, t.goldContainer),
        greaterThanOrEqualTo(7),
        reason: '$name: gold text on its container',
      );
      expect(
        _contrast(t.goldAccent, t.goldContainer),
        greaterThanOrEqualTo(3),
        reason: '$name: the medal gold on its container',
      );
    });

    testWidgets('$name: the gold badge sits on the amber', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Center(
              child: AppBadge(label: 'شهر تجريبي', tone: AppBadgeTone.gold),
            ),
          ),
        ),
      );
      final BoxDecoration ground =
          tester
                  .widget<Container>(
                    find.descendant(
                      of: find.byType(AppBadge),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      final Color label = tester
          .widget<Text>(find.text('شهر تجريبي'))
          .style!
          .color!;
      _expectAmber(ground.color!, t.goldAccent, 'the gold badge');
      expect(
        _contrast(label, ground.color!),
        greaterThanOrEqualTo(7),
        reason: '$name: the gold badge label',
      );
    });
  }
}
