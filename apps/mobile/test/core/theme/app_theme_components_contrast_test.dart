/// The colours Material picks by itself -- a tonal button's label, the
/// selected tab, a focused field's label and its error line, a selected
/// list tile, the snack bar's action, today in the date picker -- and every
/// text token on every surface, read from the real [AppTheme] in both
/// themes. Each must reach WCAG AAA (7:1; AA's 4.5:1 until script 162).
/// Before the colour audit of
/// 2026-10-15 the tonal buttons read 3.3:1 in the dark theme, the selected
/// tab and a focused label 3.4-4.1:1 there, and the snack bar's "copy the
/// code" action was white on the light bar (1.3:1).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/core/theme/app_theme.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Color _textColor(TextStyle? style, Set<WidgetState> states) =>
    WidgetStateProperty.resolveAs<TextStyle?>(style, states)!.color!;

void main() {
  for (final (String name, ThemeData theme) in <(String, ThemeData)>[
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
  ]) {
    group('$name theme', () {
      final AppTokens t = theme.extension<AppTokens>()!;
      final ColorScheme scheme = theme.colorScheme;
      final Map<String, Color> surfaces = <String, Color>{
        'background': t.background,
        'surface': t.surface,
        'surfaceElevated': t.surfaceElevated,
        'surfaceHigh': t.surfaceHigh,
      };

      void expectAA(Color fg, Color bg, String what) {
        expect(
          _contrast(fg, bg),
          greaterThanOrEqualTo(7),
          reason: '$name: $what is ${_contrast(fg, bg).toStringAsFixed(2)}:1',
        );
      }

      test('every text token reaches 7:1 on every surface', () {
        final Map<String, Color> texts = <String, Color>{
          'textPrimary': t.textPrimary,
          'textSecondary': t.textSecondary,
          'textMuted': t.textMuted,
          'primaryText': t.primaryText,
          'successText': t.successText,
          'errorText': t.errorText,
          'gold': t.gold,
        };
        for (final MapEntry<String, Color> text in texts.entries) {
          for (final MapEntry<String, Color> under in surfaces.entries) {
            expectAA(text.value, under.value, '${text.key} on ${under.key}');
          }
        }
      });

      test('every content colour reaches 7:1 on its own fill', () {
        expectAA(scheme.onPrimary, scheme.primary, 'onPrimary on primary');
        expectAA(
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
          'onPrimaryContainer on primaryContainer',
        );
        expectAA(
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
          'a tonal button or selected chip label on its fill',
        );
        expectAA(t.onGold, t.gold, 'onGold on gold');
        expectAA(scheme.onError, t.errorFill, 'white on the red badge');
        expectAA(t.errorText, t.errorContainer, 'errorText on its container');
        expectAA(
          t.successText,
          t.successContainer,
          'successText on its container',
        );
      });

      testWidgets('a tonal button label reaches 7:1 (FilledButton.tonal)', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: FilledButton.tonal(
                  key: const Key('tonal'),
                  onPressed: () {},
                  child: const Text('حاول مرة أخرى'),
                ),
              ),
            ),
          ),
        );
        final Material fill = tester.widget<Material>(
          find
              .descendant(
                of: find.byKey(const Key('tonal')),
                matching: find.byType(Material),
              )
              .first,
        );
        final Color label = DefaultTextStyle.of(
          tester.element(find.text('حاول مرة أخرى')),
        ).style.color!;
        expectAA(label, fill.color!, 'tonal button label');
      });

      test('the selected tab label reaches 7:1 on the app bar', () {
        expectAA(
          theme.tabBarTheme.labelColor!,
          theme.appBarTheme.backgroundColor!,
          'selected tab',
        );
        expectAA(
          theme.tabBarTheme.unselectedLabelColor!,
          theme.appBarTheme.backgroundColor!,
          'unselected tab',
        );
      });

      test('a field label, focused or in error, and its error line', () {
        final fields = theme.inputDecorationTheme;
        final Color fill = fields.fillColor!;
        for (final Color under in <Color>[fill, t.background, t.surface]) {
          expectAA(
            _textColor(fields.floatingLabelStyle, <WidgetState>{
              WidgetState.focused,
            }),
            under,
            'focused field label',
          );
          expectAA(
            _textColor(fields.floatingLabelStyle, <WidgetState>{
              WidgetState.error,
            }),
            under,
            'field label in error',
          );
          expectAA(
            _textColor(fields.floatingLabelStyle, <WidgetState>{}),
            under,
            'field label',
          );
          expectAA(fields.errorStyle!.color!, under, 'field error line');
        }
      });

      test('the medal gold of icons and rims reaches 3:1 on every surface', () {
        // The trophy, the H2H shield, the crown, the double button's rim
        // (script 77): goldAccent, not the text gold that reads olive in
        // the light theme.
        for (final MapEntry<String, Color> under in surfaces.entries) {
          expect(
            _contrast(t.goldAccent, under.value),
            greaterThanOrEqualTo(3),
            reason: '$name: goldAccent on ${under.key}',
          );
        }
      });

      test('a selected list tile, the snack bar action, today, links', () {
        expectAA(theme.listTileTheme.selectedColor!, t.surface, 'tile');
        expectAA(
          theme.snackBarTheme.actionTextColor!,
          theme.snackBarTheme.backgroundColor!,
          'snack bar action',
        );
        expectAA(
          theme.datePickerTheme.todayForegroundColor!.resolve(<WidgetState>{})!,
          t.surface,
          'today in the date picker',
        );
        expectAA(
          theme.datePickerTheme.todayForegroundColor!.resolve(<WidgetState>{
            WidgetState.selected,
          })!,
          scheme.primary,
          'today, selected',
        );
        final Color link = theme.textButtonTheme.style!.foregroundColor!
            .resolve(<WidgetState>{})!;
        for (final MapEntry<String, Color> under in surfaces.entries) {
          expectAA(link, under.value, 'a text button on ${under.key}');
        }
      });
    });
  }
}
