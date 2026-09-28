/// Widget test covering the FotMob-style card's double toggle
/// (`_DoubleGlowButton` in `widgets/fotmob_match_card.dart`), independent of
/// any live device/emulator: pumps the real screen against a faked
/// transport, taps the score steppers and the double button by their actual
/// `Key`s, and asserts both the visual toggle and that the flag is actually
/// carried through to the submitted request body — so a pass here proves
/// the tap-to-state-to-submit path is sound at the framework level,
/// regardless of what a specific device/browser shows.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
    'tapping the double button toggles its icon and auto-save carries isDouble:true',
    (tester) async {
      final harness = buildCurrentMonthFixturesHarness((request) async {
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
        reason: 'the double button must be visible without any extra step',
      );

      // Before: unselected — the outline bolt icon, not the filled one.
      expect(
        find.descendant(
          of: doubleKey,
          matching: find.byIcon(Icons.bolt_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: doubleKey,
          matching: find.byIcon(Icons.bolt_rounded),
        ),
        findsNothing,
      );

      await tester.tap(doubleKey);
      await tester.pump();

      // After one tap: selected — the filled bolt icon, not the outline one.
      expect(
        find.descendant(
          of: doubleKey,
          matching: find.byIcon(Icons.bolt_rounded),
        ),
        findsOneWidget,
        reason: 'a single tap must flip the button to its selected state',
      );
      expect(
        find.descendant(
          of: doubleKey,
          matching: find.byIcon(Icons.bolt_outlined),
        ),
        findsNothing,
      );

      // Pick a score on both steppers; auto-save sends the current score
      // and double flag after the debounce window.
      await tester.tap(
        find.byKey(const Key('currentMonthFixtures.home.increment.f-1')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('currentMonthFixtures.away.increment.f-1')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      final submitRequest = harness.captured.firstWhere(
        (c) => c.request.url.path == '/seasons/s-1/fixtures/f-1/prediction',
      );
      final body =
          jsonDecode(submitRequest.request.body) as Map<String, Object?>;
      expect(
        body['is_double'],
        true,
        reason: 'the toggled double flag must be carried through to auto-save',
      );
      expect(body['home_goals'], 0);
      expect(body['away_goals'], 0);

      // Tap again: back to unselected.
      await tester.tap(doubleKey);
      await tester.pump();
      expect(
        find.descendant(
          of: doubleKey,
          matching: find.byIcon(Icons.bolt_outlined),
        ),
        findsOneWidget,
        reason: 'a second tap must flip the button back off',
      );
    },
  );

  testWidgets(
    'a second double on the same day is turned off and the score still saves',
    (tester) async {
      final harness = buildCurrentMonthFixturesHarness((request) async {
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
        if (path == '/me/fixture-predictions' || path == '/teams') {
          return okJsonList(const []);
        }
        if (path == '/seasons/s-1/fixtures/f-1/prediction') {
          final decoded = jsonDecode(request.body) as Map<String, Object?>;
          if (decoded['is_double'] == true) {
            return http.Response(
              jsonEncode(const <String, Object?>{
                'schema_version': 1,
                'code': 'prediction.daily_double_exceeded',
                'message': 'daily double already used',
              }),
              409,
              headers: const {'content-type': 'application/json'},
            );
          }
          return okJsonObject({
            'schema_version': 1,
            'id': 'fp-1',
            'participant_id': 'part-1',
            'fixture_id': 'f-1',
            'submitted_at': '2026-09-04T10:00:00.000Z',
            'home_goals': decoded['home_goals'],
            'away_goals': decoded['away_goals'],
            'is_double': false,
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
      await tester.tap(doubleKey);
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('currentMonthFixtures.home.increment.f-1')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('currentMonthFixtures.away.increment.f-1')),
      );
      await tester.pump();
      // The refused save, then the retry without the double.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: doubleKey,
          matching: find.byIcon(Icons.bolt_outlined),
        ),
        findsOneWidget,
        reason: 'the refused double must not stay lit',
      );
      expect(
        find.text('يمكنك مضاعفة النقاط في مباراة واحدة فقط كل يوم.'),
        findsWidgets,
        reason: 'the player is told why',
      );
      final posts = harness.captured
          .where(
            (c) => c.request.url.path == '/seasons/s-1/fixtures/f-1/prediction',
          )
          .toList();
      expect(posts, isNotEmpty);
      final last = jsonDecode(posts.last.request.body) as Map<String, Object?>;
      expect(last['is_double'], false);
      expect(last['home_goals'], 0);
      expect(last['away_goals'], 0);
    },
  );
}
