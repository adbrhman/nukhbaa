/// Widget tests for [PredictionHistoryScreen], wired through the real screen
/// + providers over [buildPredictionHarness] (a `MockClient` transport,
/// already used by the Prediction-submit tests — it overrides
/// `predictionApiProvider`, for `GET /me/fixture-predictions`).
///
/// Round-scoped prediction history (`GET /me/predictions`) was dropped from
/// this screen (docs/project-context.md, "Legacy `Round` predictions in
/// `prediction_history_screen.dart`") — the app has not launched yet, so
/// there was no external history to preserve.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/history/prediction_history_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/prediction_harness.dart';

Widget _host(PredictionHarness harness, Widget child) => ProviderScope(
  overrides: harness.overrides,
  child: MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  ),
);

void main() {
  group('PredictionHistoryScreen', () {
    testWidgets(
      'renders a fixture prediction, falling back to the raw fixture id',
      (tester) async {
        final harness = buildPredictionHarness((request) async {
          final path = request.url.path;
          if (request.method == 'GET' && path == '/me/fixture-predictions') {
            return okJsonList([storedFixturePrediction.toJson()]);
          }
          return okJsonList(<Object>[]);
        });
        addTearDown(harness.dispose);

        await tester.pumpWidget(
          _host(harness, const PredictionHistoryScreen()),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('history.item.fp-1')), findsOneWidget);
        // storedFixturePrediction has no known team names (no round
        // context), so it falls back to the raw fixture id.
        expect(find.textContaining('f-c'), findsOneWidget);
        expect(find.text('3 - 3'), findsOneWidget);
      },
    );

    testWidgets('shows the empty message when there is no history', (
      tester,
    ) async {
      final harness = buildPredictionHarness((request) async {
        return okJsonList(<Object>[]);
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const PredictionHistoryScreen()));
      await tester.pumpAndSettle();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(PredictionHistoryScreen)),
      );
      expect(find.text(l10n.predictionHistoryEmpty), findsOneWidget);
    });
  });
}
