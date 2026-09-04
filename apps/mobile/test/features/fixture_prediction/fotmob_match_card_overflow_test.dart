/// Confirms `FotmobMatchCard` renders with no overflow at a narrow
/// (320-logical-pixel-wide) viewport in both the light and dark theme
/// (spec §10 acceptance criterion) — a card that overflows throws a
/// `FlutterError` during the pump, which `tester.takeException()` would
/// surface here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

Future<void> _pumpAtNarrowWidth(
  WidgetTester tester,
  CurrentMonthFixturesHarness harness,
  ThemeData theme,
) async {
  await tester.binding.setSurfaceSize(const Size(320, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        theme: theme,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const CurrentMonthFixturesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final entry in <String, ThemeData>{
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    testWidgets('no overflow at 320px width (${entry.key} theme)', (
      tester,
    ) async {
      final harness = buildCurrentMonthFixturesHarness((request) async {
        final path = request.url.path;
        if (path == '/feed/current-month-fixtures') {
          return okJsonList([sampleFeedItem.toJson()]);
        }
        if (path == '/me/fixture-predictions') {
          return okJsonList(const []);
        }
        if (path == '/teams') {
          return okJsonList(const []);
        }
        throw StateError('Unexpected request: ${request.method} $path');
      });
      addTearDown(harness.dispose);

      await _pumpAtNarrowWidth(tester, harness, entry.value);

      expect(tester.takeException(), isNull);
    });
  }
}
