/// Regression: a score tapped while an earlier save is still out must reach
/// the server, however long that save takes.
///
/// Before the fix the card waited for the save in flight by rescheduling
/// itself every 250 ms, four times at most. A server slower than that (the
/// error log shows the web timing out) used the budget up: the card went on
/// showing 2-1 while the server kept 2-0, with no message. The controller
/// now keeps the newest submit and sends it when the one in flight lands.
library;

import 'dart:async';
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

const String _submitPath = '/seasons/s-1/fixtures/f-1/prediction';

void main() {
  testWidgets(
    'a tap made during a three-second save is the score the server keeps',
    (tester) async {
      final Completer<void> releaseFirstSave = Completer<void>();
      int submits = 0;
      Map<String, Object?>? stored;

      final harness = buildCurrentMonthFixturesHarness((request) async {
        final path = request.url.path;
        if (path == '/feed/current-month-fixtures') {
          return okJsonList([sampleFeedItem.toJson()]);
        }
        if (path == '/seasons/s-1/fixtures/f-1/prediction-distribution') {
          return okJsonObject(const {
            'schema_version': 1,
            'home_win_percentage': 50,
            'away_win_percentage': 50,
          });
        }
        if (path == '/me/fixture-predictions') {
          final Map<String, Object?>? current = stored;
          return okJsonList([?current]);
        }
        if (path == '/teams') {
          return okJsonList(const []);
        }
        if (path == _submitPath) {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          submits++;
          final Map<String, Object?> saved = {
            'schema_version': 1,
            'id': 'fp-1',
            'participant_id': 'part-1',
            'fixture_id': 'f-1',
            'submitted_at': '2026-09-04T10:00:00.000Z',
            'home_goals': body['home_goals'],
            'away_goals': body['away_goals'],
            'is_double': body['is_double'],
          };
          if (submits == 1) {
            await releaseFirstSave.future;
          }
          stored = saved;
          return okJsonObject(saved);
        }
        throw StateError('Unexpected request: ${request.method} $path');
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        _host(harness, const CurrentMonthFixturesScreen()),
      );
      await tester.pumpAndSettle();

      Finder increment(String side) =>
          find.byKey(Key('currentMonthFixtures.$side.increment.f-1'));
      String shown(String side) => tester
          .widget<Text>(find.byKey(Key('currentMonthFixtures.$side.value.f-1')))
          .data!;

      // A first tap turns "?" into 0: three home taps and one away tap
      // make 2-0.
      await tester.tap(increment('home'));
      await tester.pump();
      await tester.tap(increment('home'));
      await tester.pump();
      await tester.tap(increment('home'));
      await tester.pump();
      await tester.tap(increment('away'));
      await tester.pump();

      // The finger pauses: the 2-0 save starts and the server holds it.
      await tester.pump(const Duration(milliseconds: 300));
      expect(submits, 1);

      // 2-1 is tapped, and the server stays silent for three seconds --
      // three times the card's old retry budget.
      await tester.tap(increment('away'));
      await tester.pump();
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(submits, 1, reason: 'nothing more goes out while 2-0 is out');

      releaseFirstSave.complete();
      for (int i = 0; i < 4; i++) {
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.pumpAndSettle();

      expect(shown('home'), '2');
      expect(shown('away'), '1');
      expect(submits, 2, reason: '2-0, then the waiting 2-1, and no more');
      final Map<String, Object?> lastBody =
          jsonDecode(
                harness.captured
                    .lastWhere((c) => c.request.url.path == _submitPath)
                    .request
                    .body,
              )
              as Map<String, Object?>;
      expect(lastBody['home_goals'], 2);
      expect(lastBody['away_goals'], 1);
      expect(stored?['away_goals'], 1, reason: 'the server keeps 2-1');
    },
  );
}
