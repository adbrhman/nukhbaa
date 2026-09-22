import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
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
    group('$name theme', () {
      final Color background = theme.scaffoldBackgroundColor;

      test('text buttons and links reach 4.5:1 on the background', () {
        final Color link = theme.textButtonTheme.style!.foregroundColor!
            .resolve(<WidgetState>{})!;
        expect(_contrast(link, background), greaterThanOrEqualTo(4.5));
      });

      test('a text field outline reaches 3:1 on the background and on the '
          'field fill', () {
        final Color outline =
            theme.inputDecorationTheme.enabledBorder!.borderSide.color;
        final Color fill = theme.inputDecorationTheme.fillColor!;
        expect(
          _contrast(Color.alphaBlend(outline, background), background),
          greaterThanOrEqualTo(3),
        );
        expect(
          _contrast(Color.alphaBlend(outline, fill), fill),
          greaterThanOrEqualTo(3),
        );
      });
    });
  }
}
