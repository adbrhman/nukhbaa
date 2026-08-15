/// Widget tests for [RoundFixturesScreen], wired through the real screen +
/// providers over `buildCompetitionHarness` (a `MockClient` transport).
/// Asserts the round header + fixtures list on success, a legitimate-empty
/// fixtures list, and that a not-found round surfaces its "not found"
/// message via `ErrorPresenter` (never an empty list).
///
/// Split out of the removed `competition_browse_widgets_test.dart` when the
/// top-level competition catalogue screen (`CompetitionListScreen`) was
/// deleted; this screen itself is unchanged and still reachable via
/// `SeasonRoundsScreen`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/round_fixtures_screen.dart';

import 'package:mobile/l10n/app_localizations.dart';

import '../../support/competition_harness.dart';

Widget _host(CompetitionHarness harness, Widget child) => ProviderScope(
  overrides: harness.overrides,
  retry: (retryCount, error) => null,
  child: MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  ),
);

void main() {
  group('RoundFixturesScreen', () {
    testWidgets('round header + fixtures list on success', (tester) async {
      final harness = buildCompetitionHarness((request) async {
        final path = request.url.path;
        if (path == '/rounds/r-1') {
          return okJsonObject(sampleRound.toJson());
        }
        if (path == '/rounds/r-1/fixtures') {
          return okJsonList([sampleFixture.toJson()]);
        }
        return okJsonList(<Object>[]);
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        _host(harness, const RoundFixturesScreen(roundId: 'r-1')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fixtures.roundHeader')), findsOneWidget);
      // Ruleset *version* is shown; the opaque snapshot never is.
      expect(find.textContaining('Rules v3'), findsOneWidget);
      expect(find.byKey(const Key('fixtures.item.f-1')), findsOneWidget);
    });

    testWidgets('empty fixtures -> legitimate empty affordance', (
      tester,
    ) async {
      final harness = buildCompetitionHarness((request) async {
        final path = request.url.path;
        if (path == '/rounds/r-1') {
          return okJsonObject(sampleRound.toJson());
        }
        return okJsonList(<Object>[]); // no fixtures
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        _host(harness, const RoundFixturesScreen(roundId: 'r-1')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fixtures.roundHeader')), findsOneWidget);
      expect(find.byKey(const Key('browse.empty')), findsOneWidget);
    });

    testWidgets('unknown round (404) -> not-found message, no fixtures list', (
      tester,
    ) async {
      final harness = buildCompetitionHarness((request) async {
        final path = request.url.path;
        if (path == '/rounds/missing') {
          return errorEnvelope(
            404,
            'competition.round_not_found',
            'No such round.',
          );
        }
        return okJsonList(<Object>[]);
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        _host(harness, const RoundFixturesScreen(roundId: 'missing')),
      );
      await tester.pumpAndSettle();

      // The header read fails with the not-found error, rendered via
      // ErrorPresenter — distinct from an empty fixtures list.
      expect(find.byKey(const Key('browse.error')), findsOneWidget);
      expect(find.text('This round could not be found.'), findsOneWidget);
      // A not-found (invariant) failure is NOT retryable — no retry button.
      expect(find.byKey(const Key('browse.error.retry')), findsNothing);
    });
  });
}
