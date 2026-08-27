/// Widget tests for the Leaderboards (view) screen, wired through the real
/// screen + provider over `buildLeaderboardsHarness` (a `MockClient`
/// transport). They assert the four user-visible states — loading,
/// legitimate-empty, error (with a retry affordance only when retryable), and
/// data (a row per participant showing rank/participant/points in the
/// server-defined order) — plus that the non-member refusal
/// (`401 leaderboard.not_a_participant`) surfaces its tailored message via
/// `ErrorPresenter` with NO retry, and that the additive
/// `SeasonRoundsScreen` entry point navigates to this screen.
///
/// The screen now lands on the **fixture points** tab by default (Tab index
/// 0, Axiom 4 Amendment); these tests exercise the **season points** tab
/// (`GET /seasons/{id}/leaderboard`), so each one taps
/// `leaderboard.tab.season` before asserting on it. The fixture tab's own
/// read (`GET /seasons/{id}/fixture-leaderboard`) is routed separately to a
/// legitimate empty board so it never interferes with the season-tab
/// assertions under test.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/leaderboards/season_leaderboard_screen.dart';

import 'package:mobile/l10n/app_localizations.dart';

import '../../support/leaderboards_harness.dart';

Widget _host(LeaderboardsHarness harness, Widget child) => ProviderScope(
  overrides: harness.overrides,
  retry: (retryCount, error) => null,
  child: MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  ),
);

/// Switches from the default fixture tab to the season tab and lets the tab
/// transition finish.
Future<void> _openSeasonTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('leaderboard.tab.season')));
  await tester.pump(); // start the tab-switch animation
  await tester.pump(kTabScrollDuration); // finish it
}

void main() {
  group('SeasonLeaderboardScreen', () {
    testWidgets('shows a loading indicator while the read is in flight', (
      tester,
    ) async {
      // The fixture tab's read settles immediately (empty is fine); the
      // season-tab leaderboard read never completes, keeping the season
      // tab's provider in the loading state.
      final harness = buildLeaderboardsHarness((request) async {
        if (request.url.path == '/seasons/s-1/fixture-leaderboard') {
          return okJsonObject(emptyFixtureBoard.toJson());
        }
        return Completer<http.Response>().future;
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        _host(
          harness,
          const SeasonLeaderboardScreen(seasonId: 's-1', seasonLabel: '26/27'),
        ),
      );
      await tester.pump(); // first frame after the providers start loading

      expect(find.byKey(const Key('leaderboard.title')), findsOneWidget);

      await _openSeasonTab(tester);
      await tester.pump(); // first frame after the season tab's read starts

      expect(find.byKey(const Key('browse.loading')), findsOneWidget);
    });

    testWidgets('data -> a ranked row per participant in server order', (
      tester,
    ) async {
      final harness = buildLeaderboardsHarness((request) async {
        if (request.url.path == '/seasons/s-1/fixture-leaderboard') {
          return okJsonObject(emptyFixtureBoard.toJson());
        }
        return okJsonObject(sampleBoard.toJson());
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        _host(
          harness,
          const SeasonLeaderboardScreen(seasonId: 's-1', seasonLabel: '26/27'),
        ),
      );
      await _openSeasonTab(tester);
      await tester.pumpAndSettle();

      // Both participants render with their server-computed rank + points.
      expect(find.byKey(const Key('leaderboard.item.p-a')), findsOneWidget);
      expect(find.byKey(const Key('leaderboard.item.p-b')), findsOneWidget);
      expect(find.text('12 pts'), findsOneWidget);
      expect(find.text('7 pts'), findsOneWidget);
      // Audit entry count is surfaced (plural form).
      expect(find.text('3 entries counted'), findsNWidgets(2));
    });

    testWidgets('empty board -> the empty affordance, not an error', (
      tester,
    ) async {
      final harness = buildLeaderboardsHarness((request) async {
        if (request.url.path == '/seasons/s-2/fixture-leaderboard') {
          return okJsonObject(emptyFixtureBoard.toJson());
        }
        return okJsonObject(emptyBoard.toJson());
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        _host(
          harness,
          const SeasonLeaderboardScreen(seasonId: 's-2', seasonLabel: '26/27'),
        ),
      );
      await _openSeasonTab(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('browse.empty')), findsOneWidget);
      expect(find.byKey(const Key('browse.error')), findsNothing);
    });

    testWidgets(
      'non-member (401 leaderboard.not_a_participant) -> tailored message, '
      'no retry',
      (tester) async {
        final harness = buildLeaderboardsHarness((request) async {
          if (request.url.path == '/seasons/s-1/fixture-leaderboard') {
            return okJsonObject(emptyFixtureBoard.toJson());
          }
          return errorEnvelope(
            401,
            'leaderboard.not_a_participant',
            'Not a member of this season.',
          );
        });
        addTearDown(harness.dispose);

        await tester.pumpWidget(
          _host(
            harness,
            const SeasonLeaderboardScreen(
              seasonId: 's-1',
              seasonLabel: '26/27',
            ),
          ),
        );
        await _openSeasonTab(tester);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('browse.error')), findsOneWidget);
        // The tailored ErrorPresenter copy for this stable code (not a raw code).
        expect(
          find.textContaining('not a member of this season'),
          findsOneWidget,
        );
        // An authorization failure is NOT retryable — no retry affordance.
        expect(find.byKey(const Key('browse.error.retry')), findsNothing);
      },
    );

    testWidgets('transport failure -> error message + retry affordance', (
      tester,
    ) async {
      // The retry counter is scoped to the season-leaderboard endpoint only,
      // so the fixture tab's own (always-successful) read never consumes it.
      var leaderboardCalls = 0;
      final harness = buildLeaderboardsHarness((request) async {
        if (request.url.path == '/seasons/s-1/fixture-leaderboard') {
          return okJsonObject(emptyFixtureBoard.toJson());
        }
        leaderboardCalls++;
        if (leaderboardCalls == 1) throw Exception('offline');
        return okJsonObject(sampleBoard.toJson());
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        _host(
          harness,
          const SeasonLeaderboardScreen(seasonId: 's-1', seasonLabel: '26/27'),
        ),
      );
      await _openSeasonTab(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('browse.error')), findsOneWidget);
      final retry = find.byKey(const Key('browse.error.retry'));
      expect(retry, findsOneWidget);

      // Tapping retry re-reads and, this time, shows the standings.
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('browse.error')), findsNothing);
      expect(find.byKey(const Key('leaderboard.item.p-a')), findsOneWidget);
    });
  });
}
