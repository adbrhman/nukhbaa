/// A filled button's label -- white on the action blue -- reaches WCAG AA
/// (4.5:1) in both themes. The sheet's `#2F6BFF` measured 4.499:1, a hair
/// under, which is why the dark primary sits one step deeper.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final (String name, ThemeData theme) in <(String, ThemeData)>[
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
  ]) {
    test('$name: a filled button label reaches 4.5:1 on its fill', () {
      final ButtonStyle style = theme.filledButtonTheme.style!;
      final Color fill = style.backgroundColor!.resolve(<WidgetState>{})!;
      final Color label = style.foregroundColor!.resolve(<WidgetState>{})!;
      expect(_contrast(label, fill), greaterThanOrEqualTo(4.5));
    });
  }
}
