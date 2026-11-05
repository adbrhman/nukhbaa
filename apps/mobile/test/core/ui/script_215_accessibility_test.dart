/// Accessibility Scanner findings of 2026-11-05 after the update (script 215):
/// the date dialog's day columns are 48 dp or more on a 384 dp phone (script
/// 214 raised the text scale, but the dialog's own side margin cut its width
/// back), a confirm dialog stacks two 48 dp buttons, every AppButton is 48 dp
/// tall at least, and two password fields name their own eye button.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/ui/accessible_date_picker.dart';
import 'package:mobile/core/ui/app_button.dart';
import 'package:mobile/core/ui/app_dialog.dart';
import 'package:mobile/core/ui/app_text_field.dart';
import 'package:mobile/l10n/app_localizations.dart';

Widget _app(Widget home) => MaterialApp(
  theme: AppTheme.dark,
  locale: const Locale('ar'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: home,
);

/// A phone [width] dp wide (device pixel ratio 3).
void _phone(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width * 3, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<double> _dateDialogWidth(WidgetTester tester, double screen) async {
  _phone(tester, screen);
  await tester.pumpWidget(
    _app(
      Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showAccessibleDatePicker(
              context: context,
              initialDate: DateTime(2026, 11, 5),
              firstDate: DateTime(2026),
              lastDate: DateTime(2027),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  final Finder box = find
      .descendant(
        of: find.byType(DatePickerDialog),
        matching: find.byType(AnimatedContainer),
      )
      .first;
  return tester.getSize(box).width;
}

void main() {
  test('the date dialog keeps the margin it can spare', () {
    expect(datePickerSideMargin(500), 16);
    expect(datePickerSideMargin(384), closeTo(1.2, 0.01));
    expect(datePickerSideMargin(360), 0);
    expect(datePickerSideMargin(320), 0);
  });

  testWidgets(
    'on a 384 dp phone the date dialog is wide enough for 48 dp days',
    (tester) async {
      final double width = await _dateDialogWidth(tester, 384);
      // The grid is padded 12 dp each side; seven columns share the rest.
      expect((width - 24) / 7, greaterThanOrEqualTo(48));
      expect(width, closeTo(datePickerDialogWidth, 0.5));
    },
  );

  testWidgets('on a 360 dp phone the date dialog is the screen, 48 dp days', (
    tester,
  ) async {
    final double width = await _dateDialogWidth(tester, 360);
    expect(width, closeTo(360, 0.5));
    expect((width - 24) / 7, greaterThanOrEqualTo(47.99));
  });

  testWidgets('a confirm dialog stacks the confirm over the cancel at 48 dp', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      _phone(tester, 384);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => AppDialog.confirm(
                  context,
                  title: 'خروج',
                  message: 'هل تريد الخروج من حسابك؟',
                  confirmLabel: 'تسجيل الخروج',
                  cancelLabel: 'إلغاء',
                  destructive: true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final Finder buttons = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(AppButton),
      );
      expect(buttons, findsNWidgets(2));
      for (int i = 0; i < 2; i++) {
        expect(tester.getSize(buttons.at(i)).height, greaterThanOrEqualTo(48));
      }
      // The confirm is the upper one, and both are as wide as each other.
      expect(
        tester.getTopLeft(find.text('تسجيل الخروج')).dy,
        lessThan(tester.getTopLeft(find.text('إلغاء')).dy),
      );
      expect(
        tester.getSize(buttons.at(0)).width,
        tester.getSize(buttons.at(1)).width,
      );

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      handle.dispose();
    }
  });

  testWidgets('every AppButton size is a 48 dp target at least', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Column(
            children: <Widget>[
              for (final AppButtonSize size in AppButtonSize.values)
                AppButton(label: 'x', size: size, onPressed: () {}),
            ],
          ),
        ),
      ),
    );
    final Finder buttons = find.byType(AppButton);
    expect(buttons, findsNWidgets(3));
    for (int i = 0; i < 3; i++) {
      expect(tester.getSize(buttons.at(i)).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('two password fields: each eye button names its own field', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: Column(
            children: <Widget>[
              AppTextField(label: 'كلمة المرور', obscure: true),
              AppTextField(label: 'تأكيد كلمة المرور', obscure: true),
            ],
          ),
        ),
      ),
    );
    expect(find.byTooltip('إظهار كلمة المرور (كلمة المرور)'), findsOneWidget);
    expect(
      find.byTooltip('إظهار كلمة المرور (تأكيد كلمة المرور)'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('إظهار كلمة المرور (كلمة المرور)'));
    await tester.pump();
    expect(find.byTooltip('إخفاء كلمة المرور (كلمة المرور)'), findsOneWidget);
    expect(
      find.byTooltip('إظهار كلمة المرور (تأكيد كلمة المرور)'),
      findsOneWidget,
    );
  });
}
