/// Widget tests for [PredictionHistoryScreen], wired through the real screen +
/// providers over [buildPredictionHarness] (a `MockClient` transport, already
/// used by the Prediction-submit tests — it overrides both
/// `predictionApiProvider`, for `GET /me/predictions`, and
/// `competitionApiProvider`, for the per-card
/// `GET /rounds/{id}/fixtures` reads this screen issues).
///
/// Asserts the fix for the "raw fixture id" defect: a score line renders the
/// resolved team names (from `GET /rounds/{id}/fixtures`) instead of the
/// opaque fixture id, and still falls back to the id when that read has not
/// resolved a name for the fixture.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
    testWidgets('renders team names + crests instead of the raw fixture id', (
      tester,
    ) async {
      final harness = buildPredictionHarness((request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path == '/me/predictions') {
          return okJsonList([storedPrediction.toJson()]);
        }
        if (request.method == 'GET' && path == '/rounds/r-1/fixtures') {
          return okJsonList([fixtureA.toJson(), fixtureB.toJson()]);
        }
        return okJsonList(<Object>[]);
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const PredictionHistoryScreen()));
      await tester.pumpAndSettle();

      // fixtureA resolves to named teams — rendered via `teamDisplayName`
      // (the Arabic brand name, matching PredictionScreen's own team
      // rendering) — the raw id must not appear.
      expect(find.text('الهلال'), findsOneWidget);
      expect(find.text('النصر'), findsOneWidget);
      expect(find.text('2 - 1'), findsOneWidget);
      expect(find.textContaining('f-a:'), findsNothing);

      // fixtureB has no team names on the DTO — falls back to the raw-id line
      // rather than disappearing or crashing the card.
      expect(find.textContaining('f-b'), findsOneWidget);
    });

    testWidgets('falls back to the raw fixture id while fixtures are loading', (
      tester,
    ) async {
      final harness = buildPredictionHarness((request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path == '/me/predictions') {
          return okJsonList([storedPrediction.toJson()]);
        }
        if (request.method == 'GET' && path == '/rounds/r-1/fixtures') {
          // Never resolves within this test — asserts the loading fallback.
          // Uses a bare Completer (no real Timer) so no pending timer
          // remains after the widget tree is disposed.
          return Completer<http.Response>().future;
        }
        return okJsonList(<Object>[]);
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const PredictionHistoryScreen()));
      // Enough pumps for the quick `/me/predictions` read to resolve and the
      // card to build, without waiting on the perpetually-pending fixtures
      // read (a `pumpAndSettle` would hang on it).
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('f-a:'), findsOneWidget);
      expect(find.textContaining('f-b:'), findsOneWidget);
    });
  });
}
