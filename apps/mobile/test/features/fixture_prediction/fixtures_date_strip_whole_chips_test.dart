/// The day strip shows whole chips only (script 214): no chip is cut by the
/// edge of the screen, at rest or after a swipe. A cut chip was a 20 dp touch
/// target to the Accessibility Scanner on every matches screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/fixture_prediction/widgets/fixtures_date_bar.dart';
import 'package:mobile/l10n/app_localizations.dart';

const double _width = 384;

Future<void> _pump(WidgetTester tester, {double scale = 1}) async {
  tester.view.physicalSize = const Size(_width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: FixturesDateStrip(
          selectedDay: DateTime(2026, 11, 5),
          onDaySelected: (DateTime day) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every chip's rect is wholly inside the screen or wholly outside it.
void _expectNoCutChip(WidgetTester tester) {
  final Finder chips = find.descendant(
    of: find.byKey(const Key('currentMonthFixtures.dayStrip')),
    matching: find.byType(InkWell),
  );
  expect(chips, findsWidgets);
  int shown = 0;
  for (final Element chip in chips.evaluate()) {
    final Rect rect = tester.getRect(find.byWidget(chip.widget));
    final bool cutLeft = rect.left < -0.5 && rect.right > 0.5;
    final bool cutRight = rect.left < _width - 0.5 && rect.right > _width + 0.5;
    expect(cutLeft || cutRight, isFalse, reason: 'chip at $rect is cut');
    if (rect.left >= -0.5 && rect.right <= _width + 0.5) shown++;
  }
  expect(shown, greaterThanOrEqualTo(2));
}

void main() {
  testWidgets('at rest no chip is cut by the screen edge', (tester) async {
    await _pump(tester);
    _expectNoCutChip(tester);
  });

  testWidgets('after a swipe the strip rests on whole chips', (tester) async {
    await _pump(tester);
    await tester.drag(
      find.byKey(const Key('currentMonthFixtures.dayStrip')),
      const Offset(-101, 0),
    );
    await tester.pumpAndSettle();
    _expectNoCutChip(tester);
  });

  testWidgets('at large text the chips stay whole, fewer to a view', (
    tester,
  ) async {
    await _pump(tester, scale: 2);
    expect(tester.takeException(), isNull);
    _expectNoCutChip(tester);
  });
}
