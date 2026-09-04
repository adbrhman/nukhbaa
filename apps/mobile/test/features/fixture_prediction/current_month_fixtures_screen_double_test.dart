/// Widget test isolating the reported "double chip doesn't respond to
/// taps" issue on [CurrentMonthFixturesScreen], independent of any live
/// device/emulator: pumps the real screen against a faked transport, taps
/// the chip by its actual `Key`, and asserts both the visual toggle and
/// that the flag is actually carried through to the submitted request body
/// — so a pass here proves the tap-to-state-to-submit path is sound at the
/// framework level, regardless of what a specific device/browser shows.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

Widget _host(CurrentMonthFixturesHarness harness, Widget child) =>
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: child,
      ),
    );

void main() {
  testWidgets(
    'tapping the double chip toggles its icon and the submit body carries isDouble:true',
    (tester) async {
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
        if (path == '/seasons/s-1/fixtures/f-1/prediction') {
          final decoded = jsonDecode(request.body) as Map<String, Object?>;
          return okJsonObject({
            'schema_version': 1,
            'id': 'fp-1',
            'participant_id': 'part-1',
            'fixture_id': 'f-1',
            'submitted_at': '2026-09-04T10:00:00.000Z',
            'home_goals': decoded['home_goals'],
            'away_goals': decoded['away_goals'],
            'is_double': decoded['is_double'],
          });
        }
        throw StateError('Unexpected request: ${request.method} $path');
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        _host(harness, const CurrentMonthFixturesScreen()),
      );
      await tester.pumpAndSettle();

      final doubleKey = find.byKey(
        const Key('currentMonthFixtures.double.f-1'),
      );
      expect(
        doubleKey,
        findsOneWidget,
        reason:
            'the double chip must be visible without any expand/collapse step',
      );

      // Before: unselected — the outline icon, not the filled one.
      expect(
        find.descendant(
          of: doubleKey,
          matching: find.byIcon(Icons.circle_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: doubleKey,
          matching: find.byIcon(Icons.check_circle),
        ),
        findsNothing,
      );

      await tester.tap(doubleKey);
      await tester.pump();

      // After one tap: selected — the filled icon, not the outline one.
      expect(
        find.descendant(
          of: doubleKey,
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
        reason: 'a single tap must flip the chip to its selected state',
      );
      expect(
        find.descendant(
          of: doubleKey,
          matching: find.byIcon(Icons.circle_outlined),
        ),
        findsNothing,
      );

      // Pick an outcome (required before submit is enabled) then submit,
      // and confirm the toggled flag actually reaches the request body —
      // closing the loop from tap to network payload.
      await tester.tap(
        find.byKey(const Key('currentMonthFixtures.quickFill1.f-1')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('currentMonthFixtures.submit.f-1')),
      );
      await tester.pumpAndSettle();

      final submitRequest = harness.captured.firstWhere(
        (c) => c.request.url.path == '/seasons/s-1/fixtures/f-1/prediction',
      );
      final body =
          jsonDecode(submitRequest.request.body) as Map<String, Object?>;
      expect(
        body['is_double'],
        true,
        reason: 'the toggled double flag must be carried through to submit',
      );

      // Tap again: back to unselected.
      await tester.tap(doubleKey);
      await tester.pump();
      expect(
        find.descendant(
          of: doubleKey,
          matching: find.byIcon(Icons.circle_outlined),
        ),
        findsOneWidget,
        reason: 'a second tap must flip the chip back off',
      );
    },
  );
}
