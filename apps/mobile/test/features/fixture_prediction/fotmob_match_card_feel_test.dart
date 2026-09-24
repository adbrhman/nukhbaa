/// How the match card feels, pumped through the real
/// [CurrentMonthFixturesScreen]: a stepper tap and the double toggle answer
/// with a selection tick, a save the server accepted answers with one light
/// tap, and the selected double button keeps its white label at WCAG AA.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

const String _selection = 'HapticFeedbackType.selectionClick';
const String _light = 'HapticFeedbackType.lightImpact';

CurrentMonthFixturesHarness _harness() =>
    buildCurrentMonthFixturesHarness((request) async {
      final path = request.url.path;
      if (path == '/feed/current-month-fixtures') {
        return okJsonList([sampleFeedItem.toJson()]);
      }
      if (path == '/seasons/s-1/fixtures/f-1/prediction-distribution') {
        return okJsonObject(const {
          'schema_version': 1,
          'home_win_percentage': 68,
          'away_win_percentage': 32,
        });
      }
      if (path == '/seasons/s-1/fixtures/f-1/prediction') {
        return okJsonObject({
          'schema_version': 1,
          'id': 'fp-1',
          'participant_id': 'part-1',
          'fixture_id': 'f-1',
          'submitted_at': '2026-09-12T20:00:00.000Z',
          'home_goals': 0,
          'away_goals': 0,
          'is_double': false,
        });
      }
      if (path == '/me/fixture-predictions') {
        return okJsonList(const []);
      }
      if (path == '/seasons/s-1/fixtures/f-1/scores') {
        return okJsonObject(const {
          'schema_version': 1,
          'fixture_id': 'f-1',
          'scores': <Object?>[],
        });
      }
      if (path == '/teams') {
        return okJsonList(const []);
      }
      throw StateError('Unexpected request: ${request.method} $path');
    });

/// Records every haptic the app asks the platform for.
List<String?> _recordHaptics(WidgetTester tester) {
  final List<String?> calls = <String?>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String?);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

Future<void> _pump(WidgetTester tester, CurrentMonthFixturesHarness h) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const CurrentMonthFixturesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  testWidgets('a stepper tap ticks; the accepted save taps once', (
    tester,
  ) async {
    final List<String?> haptics = _recordHaptics(tester);
    final harness = _harness();
    addTearDown(harness.dispose);
    await _pump(tester, harness);

    await tester.tap(
      find.byKey(const Key('currentMonthFixtures.home.increment.f-1')),
    );
    expect(haptics, <String?>[_selection]);

    await tester.tap(
      find.byKey(const Key('currentMonthFixtures.away.increment.f-1')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(haptics, <String?>[_selection, _selection, _light]);
  });

  testWidgets('the double toggle ticks and its selected label stays AA', (
    tester,
  ) async {
    final List<String?> haptics = _recordHaptics(tester);
    final harness = _harness();
    addTearDown(harness.dispose);
    await _pump(tester, harness);

    final Finder toggle = find.byKey(
      const Key('currentMonthFixtures.double.f-1'),
    );
    await tester.tap(toggle);
    await tester.pump();
    expect(haptics.first, _selection);

    final AnimatedContainer box = tester.widget<AnimatedContainer>(
      find.descendant(of: toggle, matching: find.byType(AnimatedContainer)),
    );
    final Gradient? gradient = (box.decoration! as BoxDecoration).gradient;
    expect(gradient, isNotNull, reason: 'selected state paints a gradient');
    for (final Color stop in gradient!.colors) {
      expect(
        _contrast(AppTokens.dark.onPrimary, stop),
        greaterThanOrEqualTo(4.5),
        reason: stop.toString(),
      );
    }
    await tester.pumpAndSettle();
  });
}
